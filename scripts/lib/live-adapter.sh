#!/usr/bin/env bash

# Live adapter: turns raw Meta Marketing API (Graph) responses into the kit's
# internal report schema (the same shape as scripts/fixtures/insights.last_7d.json).
#
# Why the Graph API and not the official `meta` CLI here:
# the official Ads CLI exposes only account-level `insights get` (no --level),
# so it cannot return per-campaign or per-ad breakdowns in one call. Winners,
# bleeders, pacing-by-campaign and fatigue are all level-based. The Graph API
# (same ACCESS_TOKEN the CLI uses) returns level=campaign / level=ad in a single
# call, which is the only thing that scales past a handful of ads.
#
# The transform (mk_assemble_insights) is a PURE jq function over recorded raw
# responses, so it is unit-testable offline. The fetch layer (mk_build_live_insights)
# is the only part that touches the network.

GRAPH_API_VERSION="${GRAPH_API_VERSION:-v21.0}"
GRAPH_API_BASE="${GRAPH_API_BASE:-https://graph.facebook.com}"

# mk_graph_get <edge> <key=value>...
# Returns the raw JSON body for GET {base}/{version}/{account}/{edge}?...
# Follows .paging.next up to a bounded number of pages and merges .data arrays.
mk_graph_get() {
  local edge="$1"; shift
  local account token body merged pages next
  account="$(mk_normalize_account "${AD_ACCOUNT_ID:-${META_AD_ACCOUNT:-}}")"
  token="${ACCESS_TOKEN:-${META_SYSTEM_USER_ACCESS_TOKEN:-}}"

  local curl_args=(-sG "${GRAPH_API_BASE}/${GRAPH_API_VERSION}/${account}/${edge}"
    --data-urlencode "access_token=${token}")
  local kv
  for kv in "$@"; do
    curl_args+=(--data-urlencode "$kv")
  done

  body="$(curl "${curl_args[@]}" 2>/dev/null)"

  # If there is no pagination, return the body unchanged so single-object
  # responses (e.g. the account node) pass through untouched.
  next="$(jq -r '.paging.next // empty' <<<"$body" 2>/dev/null)"
  if [[ -z "$next" ]]; then
    printf '%s\n' "$body"
    return 0
  fi

  merged="$body"
  pages=1
  while [[ -n "$next" && "$pages" -lt 25 ]]; do
    body="$(curl -s "$next" 2>/dev/null)"
    merged="$(jq -s '{data: ((.[0].data // []) + (.[1].data // []))}' \
      <(printf '%s' "$merged") <(printf '%s' "$body") 2>/dev/null)"
    next="$(jq -r '.paging.next // empty' <<<"$body" 2>/dev/null)"
    pages=$((pages + 1))
  done
  printf '%s\n' "$merged"
}

# mk_assemble_insights  (reads a combined raw bundle on stdin)
# Input: one JSON object keyed by raw Graph responses:
#   {acct_meta, acct_7d, acct_today, camp_7d, camp_today, ad_7d, ad_daily, campaigns, adsets}
# Output: the kit's internal insights schema.
# PURE: jq only, no network — this is the unit-tested seam.
mk_assemble_insights() {
  jq '
    def num: (try (tostring|tonumber) catch 0);
    def r2: (. as $n | ($n|num) * 100 | round / 100);
    def cents_to_dollars: (num / 100);

    .acct_meta as $meta
    | .acct_7d as $a7
    | .acct_today as $at
    | .camp_7d as $c7
    | .camp_today as $ct
    | .ad_7d as $a
    | .ad_daily as $ad
    | .campaigns as $camps
    | .adsets as $adsets

    | ( [ ($camps.data // [])[] | select(.effective_status == "ACTIVE") | (.daily_budget // "0" | cents_to_dollars) ] | add // 0 ) as $camp_budget
    | ( [ ($adsets.data // [])[] | select(.effective_status == "ACTIVE") | (.daily_budget // "0" | cents_to_dollars) ] | add // 0 ) as $adset_budget

    | {
        account_summary: {
          account_id: ($meta.id // ""),
          currency: ($meta.currency // ($a7.data[0].account_currency // "USD")),
          spend_7d: (($a7.data[0].spend // "0") | num | tostring),
          spend_today: (($at.data[0].spend // "0") | num | tostring),
          daily_budget_target: (($camp_budget + $adset_budget) | tostring),
          active_campaigns: ( [ ($camps.data // [])[] | select(.effective_status == "ACTIVE") ] | length ),
          active_ads: ( ($a.data // []) | length )
        },
        campaign_insights: [
          ($c7.data // [])[] | {
            campaign_id: (.campaign_id // ""),
            campaign_name: (.campaign_name // "(unknown)"),
            spend: ((.spend // "0") | num | tostring),
            ctr: ((.ctr // "0") | r2 | tostring),
            cpc: ((.cpc // "0") | r2 | tostring)
          }
        ],
        ad_insights: [
          ($a.data // [])[] | {
            ad_id: (.ad_id // ""),
            ad_name: (.ad_name // "(unknown)"),
            spend: ((.spend // "0") | num | tostring),
            ctr: ((.ctr // "0") | r2 | tostring),
            cpc: ((.cpc // "0") | r2 | tostring),
            frequency: ((.frequency // "0") | r2 | tostring)
          }
        ],
        ad_daily: [
          ($ad.data // [])[] | {
            ad_id: (.ad_id // ""),
            ad_name: (.ad_name // "(unknown)"),
            date_start: (.date_start // ""),
            ctr: ((.ctr // "0") | r2 | tostring),
            frequency: ((.frequency // "0") | r2 | tostring)
          }
        ],
        today_campaign_spend: [
          ($ct.data // [])[] | {
            campaign_id: (.campaign_id // ""),
            campaign_name: (.campaign_name // "(unknown)"),
            spend_today: ((.spend // "0") | num | tostring)
          }
        ]
      }
  '
}

# mk_normalize_campaigns  (reads raw `meta ads campaign list` array on stdin)
# Output: { data: [ {id, name, status} ] } — the shape report_campaigns expects.
mk_normalize_campaigns() {
  jq '{ data: [ .[] | { id: .id, name: .name, status: (.status // .effective_status // "UNKNOWN") } ] }'
}

# mk_build_live_insights  (network)
# Fetches the raw Graph responses for the account and assembles the internal
# schema. Memoized per process+account so daily-check does not refetch 5x.
mk_build_live_insights() {
  local account cache
  account="$(mk_normalize_account "${AD_ACCOUNT_ID:-${META_AD_ACCOUNT:-}}")"
  cache="${TMPDIR:-/tmp}/meta-kit-insights-${account}-$$.json"

  if [[ -f "$cache" ]]; then
    cat "$cache"
    return 0
  fi

  local acct_meta acct_7d acct_today camp_7d camp_today ad_7d ad_daily campaigns adsets bundle
  # Account node (currency); not an edge, so call it directly rather than via mk_graph_get.
  acct_meta="$(curl -sG "${GRAPH_API_BASE}/${GRAPH_API_VERSION}/${account}" \
    --data-urlencode "access_token=${ACCESS_TOKEN:-${META_SYSTEM_USER_ACCESS_TOKEN:-}}" \
    --data-urlencode "fields=currency,name" 2>/dev/null)"
  acct_7d="$(mk_graph_get insights "date_preset=last_7d" "fields=spend,account_currency")"
  acct_today="$(mk_graph_get insights "date_preset=today" "fields=spend")"
  camp_7d="$(mk_graph_get insights "level=campaign" "date_preset=last_7d" "fields=campaign_id,campaign_name,spend,ctr,cpc" "limit=200")"
  camp_today="$(mk_graph_get insights "level=campaign" "date_preset=today" "fields=campaign_id,campaign_name,spend" "limit=200")"
  ad_7d="$(mk_graph_get insights "level=ad" "date_preset=last_7d" "fields=ad_id,ad_name,spend,ctr,cpc,frequency" "limit=500")"
  ad_daily="$(mk_graph_get insights "level=ad" "date_preset=last_7d" "time_increment=1" "fields=ad_id,ad_name,ctr,frequency" "limit=500")"
  campaigns="$(mk_graph_get campaigns "fields=effective_status,daily_budget" "limit=500")"
  adsets="$(mk_graph_get adsets "fields=effective_status,daily_budget" "limit=500")"

  # NB: do not use "${var:-{}}" as a default here — bash parses the first "}"
  # as the end of the expansion and appends the trailing "}" literally,
  # corrupting otherwise-valid JSON. Use a named empty-object default.
  local empty='{}'
  bundle="$(jq -n \
    --argjson acct_meta "${acct_meta:-$empty}" \
    --argjson acct_7d "${acct_7d:-$empty}" \
    --argjson acct_today "${acct_today:-$empty}" \
    --argjson camp_7d "${camp_7d:-$empty}" \
    --argjson camp_today "${camp_today:-$empty}" \
    --argjson ad_7d "${ad_7d:-$empty}" \
    --argjson ad_daily "${ad_daily:-$empty}" \
    --argjson campaigns "${campaigns:-$empty}" \
    --argjson adsets "${adsets:-$empty}" \
    '{acct_meta:$acct_meta, acct_7d:$acct_7d, acct_today:$acct_today, camp_7d:$camp_7d, camp_today:$camp_today, ad_7d:$ad_7d, ad_daily:$ad_daily, campaigns:$campaigns, adsets:$adsets}')"

  printf '%s' "$bundle" | mk_assemble_insights | tee "$cache"
}
