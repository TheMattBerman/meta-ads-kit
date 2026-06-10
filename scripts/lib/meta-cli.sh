#!/usr/bin/env bash

mk_snapshot_json() {
  local label="$1"
  local json_payload="$2"
  local output_dir ts out_file

  output_dir="$(mk_readonly_output_dir)"
  mkdir -p "$output_dir"
  ts="$(date -u +"%Y-%m-%dT%H%M%SZ")"
  out_file="${output_dir}/${ts}-${label}.json"

  printf '%s\n' "$json_payload" > "$out_file"
  printf '%s\n' "$out_file"
}

mk_meta_base_cmd() {
  # Prefer an installed `meta` binary. Fall back to uvx so the kit can inspect/run
  # the official PyPI package without forcing a global install.
  if command -v meta >/dev/null 2>&1; then
    META_BASE_CMD=(meta)
  elif command -v uvx >/dev/null 2>&1; then
    META_BASE_CMD=(uvx --python 3.12 --from meta-ads meta)
  else
    echo "ERROR: Meta CLI not installed and uvx is unavailable. Install with: pip install meta-ads" >&2
    return 1
  fi
}

mk_meta_cli_command_for() {
  local op="$1"

  # Official Ads CLI uses singular resources and noun-verb pattern:
  # meta ads <resource> <action> [options]
  # Docs: /documentation/ads-commerce/ads-ai-connectors/ads-cli/command-reference
  case "$op" in
    campaigns_list) META_CMD=(meta ads campaign list) ;;
    adsets_list) META_CMD=(meta ads adset list) ;;
    ads_list) META_CMD=(meta ads ad list) ;;
    insights_campaign_last_7d) META_CMD=(meta ads insights get --date-preset last_7d --fields spend,impressions,clicks,ctr,cpc,reach) ;;
    insights_ad_last_7d) META_CMD=(meta ads insights get --date-preset last_7d --fields spend,impressions,clicks,ctr,cpc,reach,frequency) ;;
    insights_ad_daily_last_7d) META_CMD=(meta ads insights get --date-preset last_7d --time-increment daily --fields spend,impressions,clicks,ctr,cpc,reach,frequency) ;;
    *)
      echo "ERROR: unknown operation mapping: $op" >&2
      return 1
      ;;
  esac
}

mk_meta_cli_doctor() {
  local mode output
  mode="$(mk_mode)"
  output="$(mk_output_format)"

  echo "meta-kit doctor"
  echo "mode=$mode output=$output"

  if command -v meta >/dev/null 2>&1; then
    echo "meta_binary=found"
    if meta --help >/dev/null 2>&1; then
      echo "meta_help=ok"
    else
      echo "meta_help=failed"
    fi
    if meta ads --help >/dev/null 2>&1; then
      echo "meta_ads_help=ok"
    else
      echo "meta_ads_help=failed"
    fi
    if meta ads campaign list --help >/dev/null 2>&1; then
      echo "meta_campaign_list_help=ok"
    else
      echo "meta_campaign_list_help=failed"
    fi
    if meta ads insights get --help >/dev/null 2>&1; then
      echo "meta_insights_get_help=ok"
    else
      echo "meta_insights_get_help=failed"
    fi
    if meta ads adaccount list --help >/dev/null 2>&1; then
      echo "meta_adaccount_list_help=ok"
    else
      echo "meta_adaccount_list_help=failed"
    fi
  else
    echo "meta_binary=missing"
    echo "note=official Meta Ads CLI not found in PATH"
    if command -v uvx >/dev/null 2>&1; then
      echo "uvx=found"
      if uvx --python 3.12 --from meta-ads meta --help >/dev/null 2>&1; then
        echo "uvx_meta_help=ok"
      else
        echo "uvx_meta_help=failed"
      fi
      if uvx --python 3.12 --from meta-ads meta ads campaign list --help >/dev/null 2>&1; then
        echo "uvx_meta_campaign_list_help=ok"
      else
        echo "uvx_meta_campaign_list_help=failed"
      fi
      if uvx --python 3.12 --from meta-ads meta ads insights get --help >/dev/null 2>&1; then
        echo "uvx_meta_insights_get_help=ok"
      else
        echo "uvx_meta_insights_get_help=failed"
      fi
      if uvx --python 3.12 --from meta-ads meta ads adaccount list --help >/dev/null 2>&1; then
        echo "uvx_meta_adaccount_list_help=ok"
      else
        echo "uvx_meta_adaccount_list_help=failed"
      fi
    else
      echo "uvx=missing"
    fi
  fi

  if command -v jq >/dev/null 2>&1; then
    echo "jq=found"
  else
    echo "jq=missing"
  fi

  if [[ -n "${AD_ACCOUNT_ID:-${META_AD_ACCOUNT:-}}" ]]; then
    echo "ad_account_id=$(mk_normalize_account "${AD_ACCOUNT_ID:-$META_AD_ACCOUNT}")"
  else
    echo "ad_account_id=missing"
  fi

  if [[ -n "${ACCESS_TOKEN:-${META_SYSTEM_USER_ACCESS_TOKEN:-}}" ]]; then
    echo "access_token=present"
  else
    echo "access_token=missing"
  fi

  if [[ "$mode" == "mock" ]]; then
    echo "doctor_status=ok_mock_mode"
  else
    echo "doctor_status=ok_non_mock"
  fi
}

mk_meta_cli_read_json() {
  local op="$1"
  local label="$2"
  local mode json account

  mode="$(mk_mode)"
  account="$(mk_normalize_account "${AD_ACCOUNT_ID:-${META_AD_ACCOUNT:-}}")"

  if [[ "$mode" == "mock" ]]; then
    case "$op" in
      campaigns_list) json="$(mk_fixture_json campaigns.list.json)" ;;
      adsets_list) json="$(mk_fixture_json adsets.list.json)" ;;
      ads_list) json="$(mk_fixture_json ads.list.json)" ;;
      insights_campaign_last_7d|insights_ad_last_7d|insights_ad_daily_last_7d)
        json="$(mk_fixture_json insights.last_7d.json)"
        ;;
      *)
        echo "ERROR: no mock fixture mapping for op '$op'" >&2
        return 1
        ;;
    esac
    mk_snapshot_json "$label" "$json" >/dev/null
    printf '%s\n' "$json"
    return 0
  fi

  if [[ -z "$account" ]]; then
    echo "ERROR: META_AD_ACCOUNT is required outside mock mode." >&2
    return 1
  fi
  export AD_ACCOUNT_ID="$account"

  # Insights ops need level=campaign / level=ad breakdowns. The official Ads CLI
  # cannot do those (no --level), so the live adapter assembles them from the
  # Graph API into the kit's internal schema. See scripts/lib/live-adapter.sh.
  case "$op" in
    insights_campaign_last_7d|insights_ad_last_7d|insights_ad_daily_last_7d)
      json="$(mk_build_live_insights)"
      mk_snapshot_json "$label" "$json" >/dev/null
      printf '%s\n' "$json"
      return 0
      ;;
    campaigns_list)
      # The official CLI lists campaigns fine; normalize its array into {data:[...]}.
      mk_meta_base_cmd || return 1
      json="$("${META_BASE_CMD[@]}" --output "$(mk_output_format)" --no-input ads campaign list 2>/dev/null | mk_normalize_campaigns)"
      mk_snapshot_json "$label" "$json" >/dev/null
      printf '%s\n' "$json"
      return 0
      ;;
  esac

  mk_meta_base_cmd || return 1
  mk_meta_cli_command_for "$op"
  local cmd=("${META_BASE_CMD[@]}" --output "$(mk_output_format)" --no-input "${META_CMD[@]:1}")
  json="$("${cmd[@]}" 2>/dev/null)"
  mk_snapshot_json "$label" "$json" >/dev/null
  printf '%s\n' "$json"
}

mk_meta_cli_prepare_mutation() {
  local action="$1"
  local payload="$2"
  local desired_status="$3"
  local account

  account="$(mk_normalize_account "${AD_ACCOUNT_ID:-${META_AD_ACCOUNT:-}}")"

  desired_status="$(mk_enforce_paused_only "$desired_status")" || return 1

  local command_preview
  command_preview="AD_ACCOUNT_ID=${account:-<missing>} meta --no-input ads <resource> $action --status $desired_status --payload $payload"
  mk_write_dry_run_artifact "$action" "$account" "$command_preview" "$payload"
}
