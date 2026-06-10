#!/usr/bin/env bash

# social-cli backend: routes live data through @vishalgojha/social-cli ("social").
#
# Why offer it alongside the default Graph backend: social-cli was the kit's
# ORIGINAL engine and natively supports `marketing insights --level campaign|ad
# --time-increment` (via async report runs) plus mutations (pause/resume/
# set-budget) and OAuth login. The official Ads CLI dropped --level, which is why
# the kit broke in live mode. This backend brings the richer surface back as an
# opt-in (META_KIT_BACKEND=social-cli).
#
# Trade-off: social-cli insights use async report jobs (slower, ~10s/poll) but
# are robust. The Graph backend is faster and dependency-free. Same internal
# schema either way — both feed the shared pure transform mk_assemble_insights.

# Strip social-cli's stdout preamble (banner note / progress lines) and emit JSON
# starting at the first line that begins with [ or {.
mk_social_strip() {
  awk 'f || /^[[{]/ { f=1; print }'
}

mk_social_installed() {
  command -v social >/dev/null 2>&1
}

# mk_social_list_json <social args...>  -> clean JSON (array/object) on stdout
mk_social_list_json() {
  social --no-banner "$@" --json 2>/dev/null | mk_social_strip
}

# mk_social_insights_data <account> <level> <preset> [time_increment]
# Uses --export to a temp file so progress lines never pollute the JSON.
# Returns {data: [...]} to match the bundle shape the transform expects.
mk_social_insights_data() {
  local acct="$1" level="$2" preset="$3" inc="${4:-}"
  local f out fields
  f="$(mktemp "${TMPDIR:-/tmp}/meta-kit-soc-XXXXXX.json")"

  case "$level" in
    campaign) fields="campaign_id,campaign_name,spend,ctr,cpc" ;;
    ad) if [[ -n "$inc" ]]; then fields="ad_id,ad_name,ctr,frequency"; else fields="ad_id,ad_name,spend,ctr,cpc,frequency"; fi ;;
    *) fields="spend,ctr,cpc" ;;
  esac

  local args=(--no-banner marketing insights "$acct" --level "$level" --preset "$preset" --fields "$fields" --export "$f" --export-format json)
  [[ -n "$inc" ]] && args+=(--time-increment "$inc")

  social "${args[@]}" >/dev/null 2>&1

  if [[ -s "$f" ]] && jq -e . "$f" >/dev/null 2>&1; then
    out="$(jq '{data: .}' "$f")"
  else
    out='{"data":[]}'
  fi
  rm -f "$f"
  printf '%s' "$out"
}

# mk_fetch_bundle_social -> the 9-key raw bundle consumed by mk_assemble_insights.
mk_fetch_bundle_social() {
  local acct status camps_raw camp7 camp_today ad7 ad_daily
  acct="$(mk_normalize_account "${AD_ACCOUNT_ID:-${META_AD_ACCOUNT:-}}")"

  status="$(social --no-banner marketing status "$acct" --json 2>/dev/null | mk_social_strip)"
  camps_raw="$(mk_social_list_json marketing campaigns "$acct")"
  camp7="$(mk_social_insights_data "$acct" campaign last_7d)"
  camp_today="$(mk_social_insights_data "$acct" campaign today)"
  ad7="$(mk_social_insights_data "$acct" ad last_7d)"
  ad_daily="$(mk_social_insights_data "$acct" ad last_7d 1)"

  # Campaigns: map social's `status` to effective_status; keep daily_budget for the target.
  local campaigns
  campaigns="$(jq '{data: [ (.[]? // empty) | {effective_status: .status, daily_budget: (.daily_budget // "0"), id: .id, name: .name, status: .status} ]}' <<<"${camps_raw:-[]}")"

  # Ad sets: social-cli only lists ad sets per-campaign (no account-level edge),
  # and those calls are rate-limit-prone. Rather than ship a pacing denominator
  # that swings between runs, the social backend computes daily_budget_target from
  # active CAMPAIGN budgets only (left empty here). This under-reports accounts
  # whose budgets live at the ad-set level (non-CBO). The graph backend, which has
  # an account-level adsets edge, includes ad-set budgets. Documented in SETUP.md.
  local adsets='{"data":[]}'

  # Account spend derived from campaign-level sums (saves two async jobs).
  local acct_7d acct_today acct_meta
  acct_7d="$(jq '{data:[{spend: (([(.data[]?.spend // "0")|tonumber]|add // 0) * 100 | round / 100 | tostring), account_currency: "USD"}]}' <<<"$camp7")"
  acct_today="$(jq '{data:[{spend: (([(.data[]?.spend // "0")|tonumber]|add // 0) * 100 | round / 100 | tostring)}]}' <<<"$camp_today")"
  local empty='{}'
  acct_meta="$(jq '{id: (.account.id // ""), currency: (.account.currency // "USD")}' <<<"${status:-$empty}")"

  jq -n \
    --argjson acct_meta "$acct_meta" \
    --argjson acct_7d "$acct_7d" \
    --argjson acct_today "$acct_today" \
    --argjson camp_7d "$camp7" \
    --argjson camp_today "$camp_today" \
    --argjson ad_7d "$ad7" \
    --argjson ad_daily "$ad_daily" \
    --argjson campaigns "$campaigns" \
    --argjson adsets "$adsets" \
    '{acct_meta:$acct_meta, acct_7d:$acct_7d, acct_today:$acct_today, camp_7d:$camp_7d, camp_today:$camp_today, ad_7d:$ad_7d, ad_daily:$ad_daily, campaigns:$campaigns, adsets:$adsets}'
}

# Campaign list for report_campaigns under the social backend.
mk_social_campaigns_list() {
  local acct
  acct="$(mk_normalize_account "${AD_ACCOUNT_ID:-${META_AD_ACCOUNT:-}}")"
  mk_social_list_json marketing campaigns "$acct" | mk_normalize_campaigns
}
