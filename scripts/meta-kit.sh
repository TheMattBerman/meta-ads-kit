#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/config.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/mock.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/safety.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/meta-cli.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/live-adapter.sh"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/backend-social.sh"

mk_load_env
mk_require_jq

# The live adapter memoizes assembled insights to a per-process temp file so a
# single daily-check does not refetch the Graph API once per report. Clean it up
# when this process exits.
trap 'rm -f "${TMPDIR:-/tmp}"/meta-kit-insights-*-$$.json 2>/dev/null || true' EXIT

MODE="${1:-daily-check}"
shift || true

ACCOUNT="${AD_ACCOUNT_ID:-${META_AD_ACCOUNT:-}}"
PRESET="$(mk_default_preset)"
OUTPUT="$(mk_output_format)"
STATUS=""
LIMIT=10
PAYLOAD=""
DRY_RUN=false
FORCE_STATUS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --account)
      ACCOUNT="$2"
      shift 2
      ;;
    --preset)
      PRESET="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --status)
      STATUS="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
      ;;
    --payload)
      PAYLOAD="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 1
      ;;
  esac
done

ACCOUNT="$(mk_normalize_account "$ACCOUNT")"
export META_AD_ACCOUNT="$ACCOUNT"
export AD_ACCOUNT_ID="$ACCOUNT"
export META_KIT_OUTPUT="$OUTPUT"

MIN_CTR="$(mk_threshold_min_ctr)"
MAX_FREQ="$(mk_threshold_max_frequency)"
BLEEDER_SPEND="$(mk_threshold_bleeder_spend)"
FATIGUE_DROP_PCT="$(mk_threshold_fatigue_drop_pct)"

report_campaigns() {
  local raw
  raw="$(mk_meta_cli_read_json campaigns_list campaigns-list)"

  echo "Campaigns"
  echo "========="
  jq -r --arg status "$STATUS" '
    .data
    | (if $status == "" then . else map(select(.status == $status)) end)
    | if length == 0 then "No campaigns found" else .[] | "- \(.name) [\(.status)] (\(.id))" end
  ' <<<"$raw"
}

report_overview() {
  local insights
  insights="$(mk_meta_cli_read_json insights_campaign_last_7d overview)"

  echo "Overview"
  echo "========"
  echo "Preset: $PRESET"

  jq -r '
    .account_summary as $a |
    "Spend (7d): $\($a.spend_7d) | Spend (today): $\($a.spend_today) | Currency: \($a.currency)",
    "Active campaigns: \($a.active_campaigns) | Active ads: \($a.active_ads)",
    "",
    "Campaign performance:",
    (.campaign_insights[] | "- \(.campaign_name): spend $\(.spend), CTR \(.ctr)%, CPC $\(.cpc)")
  ' <<<"$insights"
}

report_bleeders() {
  local insights
  insights="$(mk_meta_cli_read_json insights_ad_last_7d bleeders)"

  echo "Bleeders"
  echo "========"

  jq -r --argjson min_ctr "$MIN_CTR" --argjson max_freq "$MAX_FREQ" --argjson min_spend "$BLEEDER_SPEND" '
    .ad_insights
    | map(select((.spend|tonumber) >= $min_spend and ((.ctr|tonumber) < $min_ctr or (.frequency|tonumber) > $max_freq)))
    | if length == 0 then "No bleeders detected" else
        .[] | "- \(.ad_name) | spend $\(.spend), CTR \(.ctr)%, freq \(.frequency), CPC $\(.cpc)"
      end
  ' <<<"$insights"
}

report_winners() {
  local insights
  insights="$(mk_meta_cli_read_json insights_ad_last_7d winners)"

  echo "Winners"
  echo "======="

  jq -r --argjson lim "$LIMIT" '
    .ad_insights
    | sort_by(-(.ctr|tonumber), (.cpc|tonumber))
    | .[0:$lim]
    | if length == 0 then "No winner candidates" else
        .[] | "- \(.ad_name) | CTR \(.ctr)%, CPC $\(.cpc), spend $\(.spend)"
      end
  ' <<<"$insights"
}

report_fatigue() {
  local insights
  insights="$(mk_meta_cli_read_json insights_ad_daily_last_7d fatigue)"

  echo "Fatigue"
  echo "======="

  jq -r --argjson drop_pct "$FATIGUE_DROP_PCT" --argjson max_freq "$MAX_FREQ" '
    .ad_daily
    | group_by(.ad_id)
    | map(sort_by(.date_start))
    | map(select(length >= 3))
    | map({
        ad_name: .[0].ad_name,
        ad_id: .[0].ad_id,
        start_ctr: (.[0].ctr|tonumber),
        end_ctr: (.[-1].ctr|tonumber),
        end_freq: (.[-1].frequency|tonumber),
        drop_pct: (if (.[0].ctr|tonumber) > 0 then (((.[0].ctr|tonumber) - (.[-1].ctr|tonumber)) / (.[0].ctr|tonumber) * 100) else 0 end)
      })
    | map(. + {status:
      (if .drop_pct >= $drop_pct then "FATIGUED"
       elif .end_freq > $max_freq then "HIGH_FREQUENCY"
       else "OK" end)
    })
    | if length == 0 then "No fatigue data" else
        .[] | "- [\(.status)] \(.ad_name) | CTR drop \(.drop_pct|round)% | freq \(.end_freq)"
      end
  ' <<<"$insights"
}

report_efficiency() {
  local insights
  insights="$(mk_meta_cli_read_json insights_campaign_last_7d efficiency)"

  echo "Efficiency"
  echo "=========="

  jq -r '
    .campaign_insights
    | map(. + {score: ((.ctr|tonumber) / ((.cpc|tonumber) + 0.0001))})
    | sort_by(-.score)
    | .[]
    | "- \(.campaign_name) | score \(.score|floor), CTR \(.ctr)%, CPC $\(.cpc), spend $\(.spend)"
  ' <<<"$insights"
}

report_recommend() {
  local insights
  insights="$(mk_meta_cli_read_json insights_campaign_last_7d recommend)"

  echo "Budget Recommendations"
  echo "======================"

  jq -r '
    .campaign_insights
    | sort_by(-(.ctr|tonumber))
    | if length < 2 then
        "Not enough campaigns to compare."
      else
        "Increase budget candidates:",
        ("- " + .[0].campaign_name + " (CTR " + .[0].ctr + "%, CPC $" + .[0].cpc + ")"),
        "",
        "Decrease budget candidates:",
        ("- " + .[-1].campaign_name + " (CTR " + .[-1].ctr + "%, CPC $" + .[-1].cpc + ")"),
        "",
        "Approval gate: recommendations only; no budget mutation executed."
      end
  ' <<<"$insights"
}

report_pacing() {
  local insights
  insights="$(mk_meta_cli_read_json insights_campaign_last_7d pacing)"

  echo "Pacing"
  echo "======"

  jq -r '
    .account_summary as $a |
    "Today spend: $\($a.spend_today) / daily target $\($a.daily_budget_target)",
    (if ($a.spend_today|tonumber) > ($a.daily_budget_target|tonumber * 1.15)
      then "Status: OVERSPENDING"
      elif ($a.spend_today|tonumber) < ($a.daily_budget_target|tonumber * 0.85)
      then "Status: UNDERSPENDING"
      else "Status: ON PACE" end),
    "",
    "Today by campaign:",
    (.today_campaign_spend[] | "- \(.campaign_name): $\(.spend_today)")
  ' <<<"$insights"
}

report_daily_check() {
  echo "Meta Ads Daily Check"
  echo "===================="
  echo "Account: ${ACCOUNT:-not-set} | Mode: $(mk_mode) | Preset: $PRESET"
  echo ""

  echo "1) Spend / pacing"
  report_pacing
  echo ""

  echo "2) Active campaigns"
  report_campaigns
  echo ""

  echo "3) Last 7-day performance"
  report_overview
  echo ""

  echo "4) Winners and bleeders"
  report_winners
  report_bleeders
  echo ""

  echo "5) Fatigue"
  report_fatigue
}

prepare_create_ad() {
  local artifact
  if [[ -z "$PAYLOAD" ]]; then
    echo "ERROR: --payload is required for create-ad scaffolding." >&2
    return 1
  fi

  FORCE_STATUS="${STATUS:-PAUSED}"
  artifact="$(mk_meta_cli_prepare_mutation create-ad "$PAYLOAD" "$FORCE_STATUS")"
  echo "Dry-run artifact: $artifact"
  echo "Mutation execution is intentionally not implemented in this run."

  if [[ "$DRY_RUN" != true ]]; then
    echo "Use --dry-run for local proposal generation only." >&2
    return 1
  fi
}

usage() {
  cat <<USAGE
Meta Ads Copilot (local adapter)

Usage:
  ./scripts/meta-kit.sh <command> [options]

Commands:
  doctor
  daily-check
  overview
  campaigns
  bleeders
  winners
  fatigue
  efficiency
  recommend
  pacing
  create-ad --payload <json> --dry-run

Options:
  --account act_123
  --preset last_7d
  --output json|table|plain
  --status ACTIVE
  --limit 10
USAGE
}

case "$MODE" in
  doctor) mk_meta_cli_doctor ;;
  daily-check|daily|check|5questions) report_daily_check ;;
  overview) report_overview ;;
  campaigns) report_campaigns ;;
  bleeders|losers) report_bleeders ;;
  winners|tops|top-creatives|creatives) report_winners ;;
  fatigue|fatigue-check) report_fatigue ;;
  efficiency) report_efficiency ;;
  recommend|optimize) report_recommend ;;
  pacing) report_pacing ;;
  create-ad) prepare_create_ad ;;
  *)
    usage
    exit 1
    ;;
esac
