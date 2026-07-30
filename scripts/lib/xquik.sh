#!/usr/bin/env bash

# Optional read-only X research for ad-copy language and objections.

mk_xquik_base_url() {
  local base_url="${XQUIK_BASE_URL:-https://xquik.com/api/v1}"

  while [[ "$base_url" == */ ]]; do
    base_url="${base_url%/}"
  done

  case "$base_url" in
    https://xquik.com/api/v1|http://127.0.0.1:*|http://localhost:*)
      printf '%s\n' "$base_url"
      ;;
    *)
      echo "ERROR: XQUIK_BASE_URL must use the Xquik API or loopback HTTP." >&2
      return 1
      ;;
  esac
}

mk_xquik_requirements() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "ERROR: curl is required for Xquik research." >&2
    return 1
  fi

  if [[ -z "${XQUIK_API_KEY:-}" ]]; then
    echo "ERROR: XQUIK_API_KEY is required outside mock mode." >&2
    return 1
  fi
  case "$XQUIK_API_KEY" in
    *$'\r'*|*$'\n'*)
      echo "ERROR: XQUIK_API_KEY contains an invalid line break." >&2
      return 1
      ;;
  esac
}

mk_xquik_cursor_seen() {
  local needle="$1"
  shift
  local cursor

  for cursor in "$@"; do
    if [[ "$cursor" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

mk_xquik_normalize_page() {
  local payload="$1"
  local query="$2"

  jq -c --arg query "$query" '
    [
      .tweets[]
      | select(type == "object")
      | select((.id | type) == "string" and (.text | type) == "string")
      | (.author.username // null) as $username
      | (.url // null) as $source_url
      | {
          id,
          queries: [$query],
          author: (
            if ($username | type) == "string" then $username else null end
          ),
          created_at: (
            if (.createdAt | type) == "string" then .createdAt else null end
          ),
          text,
          url: (
            if
              ($source_url | type) == "string" and
              ($source_url | test("^https://(www\\.)?(x\\.com|twitter\\.com)/"))
            then
              $source_url
            elif
              ($username | type) == "string" and
              ($username | test("^[A-Za-z0-9_]{1,15}$")) and
              (.id | test("^[0-9]+$"))
            then
              "https://x.com/" + $username + "/status/" + .id
            else
              null
            end
          ),
          like_count: (
            if (.likeCount | type) == "number" then .likeCount else null end
          ),
          repost_count: (
            if (.retweetCount | type) == "number" then .retweetCount else null end
          ),
          reply_count: (
            if (.replyCount | type) == "number" then .replyCount else null end
          )
        }
    ]
  ' <<<"$payload"
}

mk_xquik_merge_tweets() {
  local existing="$1"
  local incoming="$2"

  jq -cn \
    --argjson existing "$existing" \
    --argjson incoming "$incoming" '
      reduce ($existing + $incoming)[] as $tweet ([];
        ([.[].id] | index($tweet.id)) as $index
        | if $index == null then
            . + [$tweet]
          else
            .[$index].queries = (
              (.[$index].queries + $tweet.queries) | unique
            )
          end
        )
    '
}

mk_xquik_request_page() {
  local query="$1"
  local query_type="$2"
  local limit="$3"
  local cursor="$4"
  local base_url
  local escaped_api_key
  local -a request

  base_url="$(mk_xquik_base_url)" || return 1
  escaped_api_key="${XQUIK_API_KEY//\\/\\\\}"
  escaped_api_key="${escaped_api_key//\"/\\\"}"
  request=(
    --fail-with-body
    --silent
    --show-error
    --get
    --connect-timeout "${XQUIK_CONNECT_TIMEOUT_SECONDS:-10}"
    --max-time "${XQUIK_REQUEST_TIMEOUT_SECONDS:-45}"
    --header "accept: application/json"
    --data-urlencode "q=${query}"
    --data-urlencode "queryType=${query_type}"
    --data-urlencode "limit=${limit}"
  )

  if [[ -n "$cursor" ]]; then
    request+=(--data-urlencode "cursor=${cursor}")
  fi

  printf 'header = "x-api-key: %s"\n' "$escaped_api_key" |
    curl --config - "${request[@]}" "${base_url}/x/tweets/search"
}

mk_xquik_search_query() {
  local query="$1"
  local query_type="$2"
  local limit="$3"
  local payload page has_next next_cursor remaining count page_count
  local cursor=""
  local collected="[]"
  local seen_cursors=()
  page_count=0

  while true; do
    page_count=$((page_count + 1))
    if (( page_count > 200 )); then
      echo "ERROR: Xquik search exceeded the pagination limit." >&2
      return 1
    fi

    count="$(jq -r 'length' <<<"$collected")"
    if (( count >= limit )); then
      break
    fi
    remaining=$((limit - count))

    if ! payload="$(mk_xquik_request_page "$query" "$query_type" "$remaining" "$cursor")"; then
      echo "ERROR: Xquik search failed for a bounded query." >&2
      return 1
    fi
    if ! jq -e '
      type == "object" and
      (.tweets | type) == "array" and
      all(.tweets[]; (
        type == "object" and
        (.id | type) == "string" and
        (.text | type) == "string"
      )) and
      (.has_next_page | type) == "boolean" and
      (.next_cursor | type) == "string"
    ' >/dev/null <<<"$payload"; then
      echo "ERROR: Xquik returned an unexpected search response." >&2
      return 1
    fi

    page="$(
      mk_xquik_normalize_page "$payload" "$query" |
        jq -c --argjson remaining "$remaining" '.[0:$remaining]'
    )"
    collected="$(mk_xquik_merge_tweets "$collected" "$page")"
    count="$(jq -r 'length' <<<"$collected")"
    has_next="$(jq -r '.has_next_page' <<<"$payload")"
    next_cursor="$(jq -r '.next_cursor' <<<"$payload")"

    if (( count >= limit )) || [[ "$has_next" != "true" ]]; then
      break
    fi
    if [[ -z "$next_cursor" ]]; then
      echo "ERROR: Xquik reported another page without a cursor." >&2
      return 1
    fi
    if mk_xquik_cursor_seen "$next_cursor" "${seen_cursors[@]}"; then
      echo "ERROR: Xquik repeated a pagination cursor." >&2
      return 1
    fi

    seen_cursors+=("$next_cursor")
    cursor="$next_cursor"
  done

  jq -c --argjson limit "$limit" '.[0:$limit]' <<<"$collected"
}

mk_xquik_social_pulse() {
  local limit="$1"
  local query_type="$2"
  shift 2
  local queries=("$@")
  local mode query payload query_tweets queries_json generated_at
  local tweets="[]"

  if ! [[ "$limit" =~ ^[0-9]+$ ]] || (( limit < 1 || limit > 200 )); then
    echo "ERROR: social-pulse --limit must be an integer from 1 to 200." >&2
    return 1
  fi
  if [[ "$query_type" != "Latest" && "$query_type" != "Top" ]]; then
    echo "ERROR: --query-type must be Latest or Top." >&2
    return 1
  fi
  if (( ${#queries[@]} == 0 )); then
    echo "ERROR: social-pulse requires at least 1 --query." >&2
    return 1
  fi
  if (( ${#queries[@]} > 10 )); then
    echo "ERROR: social-pulse accepts at most 10 queries." >&2
    return 1
  fi
  for query in "${queries[@]}"; do
    if [[ ! "$query" =~ [^[:space:]] ]]; then
      echo "ERROR: social-pulse queries cannot be blank." >&2
      return 1
    fi
    if (( ${#query} > 512 )); then
      echo "ERROR: social-pulse queries cannot exceed 512 characters." >&2
      return 1
    fi
    case "$query" in
      *$'\r'*|*$'\n'*)
        echo "ERROR: social-pulse queries must stay on one line." >&2
        return 1
        ;;
    esac
  done

  mode="$(mk_mode)"
  case "$mode" in
    mock) ;;
    read-only|live-approved)
      mk_xquik_requirements || return 1
      ;;
    *)
      echo "ERROR: META_KIT_MODE must be mock, read-only, or live-approved." >&2
      return 1
      ;;
  esac

  for query in "${queries[@]}"; do
    if [[ "$mode" == "mock" ]]; then
      payload="$(mk_fixture_json xquik.search.json)"
      query_tweets="$(
        mk_xquik_normalize_page "$payload" "$query" |
          jq -c --argjson limit "$limit" '.[0:$limit]'
      )"
    else
      query_tweets="$(mk_xquik_search_query "$query" "$query_type" "$limit")"
    fi
    tweets="$(mk_xquik_merge_tweets "$tweets" "$query_tweets")"
  done

  queries_json="$(printf '%s\n' "${queries[@]}" | jq -Rsc 'split("\n")[:-1]')"
  generated_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  jq -cn \
    --arg generated_at "$generated_at" \
    --arg mode "$mode" \
    --arg query_type "$query_type" \
    --argjson queries "$queries_json" \
    --argjson tweets "$tweets" '
      {
        source: "xquik",
        mode: $mode,
        generated_at: $generated_at,
        query_type: $query_type,
        queries: $queries,
        tweet_count: ($tweets | length),
        tweets: $tweets
      }
    '
}
