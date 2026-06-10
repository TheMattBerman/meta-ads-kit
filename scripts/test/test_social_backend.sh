#!/usr/bin/env bash
# Offline unit tests for the social-cli backend helpers that are pure
# (preamble stripping + array->bundle wrapping + shared transform reuse).
# Does NOT call the `social` binary or the network.
#
# Run: ./scripts/test/test_social_backend.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

mk_normalize_account() { local a="${1:-}"; [[ -z "$a" || "$a" == act_* ]] && echo "$a" || echo "act_${a}"; }
mk_backend() { printf '%s\n' "${META_KIT_BACKEND:-graph}"; }

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/live-adapter.sh"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/backend-social.sh"

PASS=0; FAIL=0
check() { if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; else FAIL=$((FAIL+1)); printf '  FAIL %s\n       expected [%s] got [%s]\n' "$1" "$3" "$2"; fi; }

echo "== mk_social_strip drops the banner/version preamble =="
STRIPPED="$(mk_social_strip < "$FIXTURES/social-campaigns-with-preamble.txt")"
check "stripped output is valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$STRIPPED" && echo yes || echo no)" "yes"
check "stripped array length" "$(jq 'length' <<<"$STRIPPED")" "3"
check "no '! Note' leaks through" "$(grep -c '! Note' <<<"$STRIPPED")" "0"

echo "== mk_normalize_campaigns on social campaign array =="
CN="$(printf '%s' "$STRIPPED" | mk_normalize_campaigns)"
check "wrapped in .data"        "$(jq -r 'has("data")' <<<"$CN")"      "true"
check "status carried through"  "$(jq -r '.data[0].status' <<<"$CN")"  "ACTIVE"

echo "== social flat arrays wrap into the shared transform bundle =="
# Simulate social's flat insight arrays -> {data:[...]} -> shared transform.
CAMP7='[{"campaign_id":"111","campaign_name":"Prospecting - Broad","spend":"1120.40","ctr":"1.434221","cpc":"0.521988"}]'
AD7='[{"ad_id":"a1","ad_name":"Winner","spend":"300.00","ctr":"2.981004","cpc":"0.557777","frequency":"2.201991"}]'
CAMPS="$(printf '%s' "$STRIPPED" | jq '{data: [ .[] | {effective_status: .status, daily_budget, id, name, status} ]}')"
BUNDLE="$(jq -n \
  --argjson acct_meta '{"id":"act_999","currency":"USD"}' \
  --argjson acct_7d   "{\"data\":[{\"spend\":\"1120.40\"}]}" \
  --argjson acct_today '{"data":[{"spend":"50.00"}]}' \
  --argjson camp_7d   "{\"data\":$CAMP7}" \
  --argjson camp_today '{"data":[]}' \
  --argjson ad_7d     "{\"data\":$AD7}" \
  --argjson ad_daily  '{"data":[]}' \
  --argjson campaigns "$CAMPS" \
  --argjson adsets    '{"data":[]}' \
  '{acct_meta:$acct_meta,acct_7d:$acct_7d,acct_today:$acct_today,camp_7d:$camp_7d,camp_today:$camp_today,ad_7d:$ad_7d,ad_daily:$ad_daily,campaigns:$campaigns,adsets:$adsets}')"
OUT="$(printf '%s' "$BUNDLE" | mk_assemble_insights)"
check "currency"            "$(jq -r '.account_summary.currency' <<<"$OUT")"            "USD"
check "active_campaigns"    "$(jq -r '.account_summary.active_campaigns' <<<"$OUT")"    "2"
# target = (15000 + 8000)/100 ; paused 4000 excluded
check "daily_budget_target" "$(jq -r '.account_summary.daily_budget_target' <<<"$OUT")" "230"
check "campaign ctr rounded" "$(jq -r '.campaign_insights[0].ctr' <<<"$OUT")"           "1.43"
check "ad freq rounded"      "$(jq -r '.ad_insights[0].frequency' <<<"$OUT")"           "2.2"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
