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

ids="$(janus_extract_model_ids "$(cat "$ROOT/tests/fixtures/models_empty.json")")"
[[ -z "$ids" ]] || fail "empty catalog extract"
pass "empty catalog extract"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/fake-bin"
cat > "$TMP/fake-bin/curl" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  [[ "$arg" == */v1/health ]] && exit 0
  [[ "$arg" == */v1/models ]] && {
    cat <<'JSON'
{"object":"list","data":[]}
JSON
    exit 0
  }
done
exit 7
SH
chmod +x "$TMP/fake-bin/curl"
set +e
PATH="$TMP/fake-bin:/usr/bin:/bin" janus_check_health 'http://empty.example' 'k'
empty_rc=$?
set -e
[[ $empty_rc -eq 2 ]] || fail "empty models health check"
pass "empty models health check"

printf 'All janus_api unit tests passed.\n'
