#!/usr/bin/env bash
# Offline unit tests for the live adapter's PURE transform (mk_assemble_insights)
# and campaign normalizer (mk_normalize_campaigns). No network.
#
# Run: ./scripts/test/test_live_adapter.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURES="$SCRIPT_DIR/fixtures"

# Minimal helper the adapter expects from config.sh.
mk_normalize_account() { local a="${1:-}"; [[ -z "$a" || "$a" == act_* ]] && echo "$a" || echo "act_${a}"; }

# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/live-adapter.sh"

PASS=0
FAIL=0
check() { # check <description> <actual> <expected>
  if [[ "$2" == "$3" ]]; then
    PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"
  else
    FAIL=$((FAIL + 1)); printf '  FAIL %s\n       expected [%s] got [%s]\n' "$1" "$3" "$2"
  fi
}

echo "== mk_assemble_insights (pure transform) =="
OUT="$(mk_assemble_insights < "$FIXTURES/raw-graph-bundle.json")"

# Schema keys present
for key in account_summary campaign_insights ad_insights ad_daily today_campaign_spend; do
  has="$(jq -r --arg k "$key" 'has($k)' <<<"$OUT")"
  check "schema has .$key" "$has" "true"
done

# account_summary fields
check "currency"        "$(jq -r '.account_summary.currency' <<<"$OUT")"        "USD"
check "spend_7d"        "$(jq -r '.account_summary.spend_7d' <<<"$OUT")"        "1640.25"
check "spend_today"     "$(jq -r '.account_summary.spend_today' <<<"$OUT")"     "241.10"
check "active_campaigns" "$(jq -r '.account_summary.active_campaigns' <<<"$OUT")" "2"
check "active_ads"      "$(jq -r '.account_summary.active_ads' <<<"$OUT")"      "3"
# daily_budget_target = (15000 + 8000)/100 ; paused 4000 excluded ; adset 0
check "daily_budget_target" "$(jq -r '.account_summary.daily_budget_target' <<<"$OUT")" "230"

# CTR/CPC rounded to 2dp (raw 1.434221 -> 1.43, 0.954381 -> 0.95)
check "campaign ctr rounded" "$(jq -r '.campaign_insights[0].ctr' <<<"$OUT")" "1.43"
check "campaign cpc rounded" "$(jq -r '.campaign_insights[0].cpc' <<<"$OUT")" "0.52"
check "ad freq rounded"      "$(jq -r '.ad_insights[0].frequency' <<<"$OUT")" "3.9"

# array counts
check "campaign_insights count" "$(jq -r '.campaign_insights|length' <<<"$OUT")" "2"
check "ad_insights count"       "$(jq -r '.ad_insights|length' <<<"$OUT")"       "3"
check "ad_daily count"          "$(jq -r '.ad_daily|length' <<<"$OUT")"          "3"
check "today_campaign_spend count" "$(jq -r '.today_campaign_spend|length' <<<"$OUT")" "2"

echo "== mk_normalize_campaigns =="
CAMP_RAW='[{"id":"1","name":"A","effective_status":"ACTIVE"},{"id":"2","name":"B","status":"PAUSED","effective_status":"PAUSED"}]'
CN="$(printf '%s' "$CAMP_RAW" | mk_normalize_campaigns)"
check "normalized wraps in .data"   "$(jq -r 'has("data")' <<<"$CN")"        "true"
check "status from effective_status" "$(jq -r '.data[0].status' <<<"$CN")"   "ACTIVE"
check "status prefers .status"       "$(jq -r '.data[1].status' <<<"$CN")"   "PAUSED"

echo "== reports render against assembled schema (no jq errors) =="
# Feed the assembled object through the same jq the reports use; assert no error
# and that a known value appears.
PACING="$(jq -r '
  .account_summary as $a |
  "Today spend: $\($a.spend_today) / daily target $\($a.daily_budget_target)"
' <<<"$OUT" 2>&1)"
check "pacing line renders" "$PACING" "Today spend: \$241.10 / daily target \$230"

WINNERS="$(jq -r '.ad_insights | sort_by(-(.ctr|tonumber)) | .[0].ad_name' <<<"$OUT" 2>&1)"
check "winners sorts by ctr" "$WINNERS" "UGC Retargeting - Testimonial"

echo
echo "RESULT: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
