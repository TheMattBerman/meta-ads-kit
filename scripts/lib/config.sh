#!/usr/bin/env bash

# Shared configuration loading for meta-kit scripts.

META_KIT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
META_KIT_ROOT_DIR="$(cd "$META_KIT_LIB_DIR/../.." && pwd)"

mk_require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: jq is required for reporting. Install jq and retry." >&2
    return 1
  fi
}

mk_load_env() {
  local env_file="${META_KIT_ROOT_DIR}/.env"

  if [[ -n "${META_KIT_ENV_FILE:-}" ]]; then
    env_file="${META_KIT_ENV_FILE}"
  fi

  if [[ -f "$env_file" ]]; then
    # Load .env WITHOUT clobbering variables already set in the environment, so a
    # command-line prefix wins over the file. This is what makes the documented
    # overrides work, e.g. `META_KIT_MODE=mock ./run.sh ...` even when .env pins a
    # mode. (A plain `set -a; source` would let the file overwrite the prefix.)
    local _line _key _val
    while IFS= read -r _line || [[ -n "$_line" ]]; do
      _line="${_line%%$'\r'}"
      _line="${_line#"${_line%%[![:space:]]*}"}"   # ltrim
      [[ -z "$_line" || "$_line" == \#* ]] && continue
      _line="${_line#export }"
      [[ "$_line" != *=* ]] && continue
      _key="${_line%%=*}"
      _val="${_line#*=}"
      _key="${_key//[[:space:]]/}"
      [[ -z "$_key" ]] && continue
      # Strip one layer of surrounding quotes from the value, if present.
      if [[ "$_val" == \"*\" || "$_val" == \'*\' ]]; then
        _val="${_val:1:${#_val}-2}"
      fi
      # Only set if not already provided by the caller's environment.
      if [[ -z "${!_key+x}" ]]; then
        export "$_key=$_val"
      fi
    done < "$env_file"
  fi

  # Official Ads CLI env vars are ACCESS_TOKEN, AD_ACCOUNT_ID, and BUSINESS_ID.
  # Keep META_* aliases working for the existing kit while exporting official names
  # before any live CLI invocation.
  if [[ -z "${ACCESS_TOKEN:-}" && -n "${META_SYSTEM_USER_ACCESS_TOKEN:-}" ]]; then
    export ACCESS_TOKEN="$META_SYSTEM_USER_ACCESS_TOKEN"
  fi
  if [[ -z "${AD_ACCOUNT_ID:-}" && -n "${META_AD_ACCOUNT:-}" ]]; then
    export AD_ACCOUNT_ID="$(mk_normalize_account "$META_AD_ACCOUNT")"
  fi
  if [[ -z "${BUSINESS_ID:-}" && -n "${META_BUSINESS_ID:-}" ]]; then
    export BUSINESS_ID="$META_BUSINESS_ID"
  fi
  if [[ -z "${META_AD_ACCOUNT:-}" && -n "${AD_ACCOUNT_ID:-}" ]]; then
    export META_AD_ACCOUNT="$(mk_normalize_account "$AD_ACCOUNT_ID")"
  fi
}

mk_normalize_account() {
  local account="$1"
  if [[ -n "$account" && "$account" != act_* ]]; then
    account="act_${account}"
  fi
  printf '%s\n' "$account"
}

mk_config_path() {
  if [[ -f "${META_KIT_ROOT_DIR}/ad-config.json" ]]; then
    printf '%s\n' "${META_KIT_ROOT_DIR}/ad-config.json"
  else
    printf '%s\n' "${META_KIT_ROOT_DIR}/ad-config.example.json"
  fi
}

mk_config_get() {
  local jq_expr="$1"
  local default_value="$2"
  local cfg

  cfg="$(mk_config_path)"
  if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' "$default_value"
    return 0
  fi

  if [[ -f "$cfg" ]]; then
    jq -r "$jq_expr // empty" "$cfg" 2>/dev/null || true
  fi | {
    local value
    read -r value || true
    if [[ -z "${value:-}" || "$value" == "null" ]]; then
      printf '%s\n' "$default_value"
    else
      printf '%s\n' "$value"
    fi
  }
}

mk_mode() {
  printf '%s\n' "${META_KIT_MODE:-mock}"
}

mk_output_format() {
  printf '%s\n' "${META_KIT_OUTPUT:-json}"
}

mk_default_preset() {
  local cfg_default
  cfg_default="$(mk_config_get '.reporting.default_preset' 'last_7d')"
  printf '%s\n' "${META_KIT_DEFAULT_PRESET:-$cfg_default}"
}

mk_threshold_min_ctr() {
  mk_config_get '.benchmarks.min_ctr' '1.0'
}

mk_threshold_max_frequency() {
  mk_config_get '.benchmarks.max_frequency' '3.5'
}

mk_threshold_bleeder_spend() {
  mk_config_get '.alerts.bleeder_spend_threshold' '10'
}

mk_threshold_fatigue_drop_pct() {
  local v
  v="$(mk_config_get '.alerts.fatigue_ctr_drop_pct' '20')"
  printf '%s\n' "$v"
}

mk_readonly_output_dir() {
  printf '%s\n' "${META_KIT_ROOT_DIR}/local/outputs/read-only"
}

mk_dry_run_dir() {
  printf '%s\n' "${META_KIT_DRY_RUN_DIR:-${META_KIT_ROOT_DIR}/local/dry-runs}"
}
