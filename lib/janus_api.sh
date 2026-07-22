#!/usr/bin/env bash
# Shared Janus HTTP/catalog helpers for claude-janus.
# Safe to source; no side effects at load time.

janus_normalize_base_url() {
  local u="${1%/}"
  if [[ "$u" == */v1 ]]; then
    u="${u%/v1}"
  fi
  printf '%s' "$u"
}

janus_extract_model_ids() {
  local json="$1"
  command -v jq >/dev/null 2>&1 || return 2
  jq -r '.data[]? | .id // empty' <<<"$json" 2>/dev/null
}

janus_catalog_contains() {
  local json="$1" id="$2"
  command -v jq >/dev/null 2>&1 || return 2
  jq -e --arg id "$id" 'any(.data[]?; .id == $id)' >/dev/null 2>&1 <<<"$json"
}

janus_fetch_catalog() {
  local base="$1" key="$2"
  base="$(janus_normalize_base_url "$base")"
  curl -fsS --max-time 8 \
    -A 'claude-janus/1.0' \
    -H "Authorization: Bearer $key" \
    -H 'Accept: application/json' \
    "$base/v1/models"
}

janus_check_health() {
  local base="$1" key="$2" body
  base="$(janus_normalize_base_url "$base")"
  curl -fsS -o /dev/null --max-time 3 \
    -A 'claude-janus/1.0' \
    "$base/v1/health" || return 1
  body="$(curl -fsS --max-time 8 \
    -A 'claude-janus/1.0' \
    -H "Authorization: Bearer $key" \
    -H 'Accept: application/json' \
    "$base/v1/models")" || return 2
  [[ -n "$(janus_extract_model_ids "$body")" ]] || return 2
  return 0
}
