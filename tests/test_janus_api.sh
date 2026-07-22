#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/janus_api.sh
source "$ROOT/lib/janus_api.sh"

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

[[ "$(janus_normalize_base_url 'http://localhost:20128/v1/')" == 'http://localhost:20128' ]] \
  || fail "normalize strips /v1/"
pass "normalize strips /v1/"

ids="$(janus_extract_model_ids "$(cat "$ROOT/tests/fixtures/models_openai.json")")"
printf '%s\n' "$ids" | grep -qx 'deepseek/deepseek-v4-pro' || fail "openai extract"
pass "openai extract"

ids="$(janus_extract_model_ids "$(cat "$ROOT/tests/fixtures/models_anthropic.json")")"
printf '%s\n' "$ids" | grep -qx 'claude-sonnet-4' || fail "anthropic extract"
pass "anthropic extract"

janus_catalog_contains "$(cat "$ROOT/tests/fixtures/models_openai.json")" 'combo-fast' \
  || fail "contains combo"
! janus_catalog_contains "$(cat "$ROOT/tests/fixtures/models_openai.json")" 'missing/x' \
  || fail "missing should fail"
pass "catalog contains"

json="$(cat "$ROOT/tests/fixtures/models_openai.json")"
janus_catalog_contains "$json" 'deepseek/deepseek-v4-pro' || fail "preset in fixture"
pass "preset intersection helper"

printf 'All janus_api unit tests passed.\n'
