#!/usr/bin/env bash
# Meta Ads Copilot command router (local adapter)

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
CMD="${1:-daily-check}"
shift || true

case "$CMD" in
  daily-check|daily|check|5questions|overview|campaigns|top-creatives|creatives|bleeders|losers|winners|tops|fatigue|fatigue-check|efficiency|recommend|optimize|pacing|social-pulse|doctor)
    exec "$ROOT_DIR/scripts/meta-kit.sh" "$CMD" "$@"
    ;;
  *)
    cat <<USAGE
Meta Ads Copilot

Usage: ./run.sh <command> [options]

Reports:
  daily-check    The 5 Daily Questions (start here)
  overview       Account overview with campaign breakdown
  campaigns      List campaigns (filter with --status ACTIVE)
  bleeders       Find ads bleeding money
  winners        Find top performing ads
  fatigue        Creative fatigue scan
  efficiency     Budget efficiency ranking
  pacing         Spend pacing check
  social-pulse   Read public X wording for copy research
  doctor         Local adapter + CLI diagnostics

Options:
  --account act_123    Override ad account
  --preset last_7d     Date range preset
  --output json        Output format
  --query "..."       Bounded X query for social-pulse
  --query-type Latest  Latest or Top X results
  --limit 10           Maximum results per X query

Quick start (mock): META_KIT_MODE=mock ./run.sh daily-check
USAGE
    exit 1
    ;;
esac
