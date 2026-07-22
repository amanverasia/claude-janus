#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$ROOT/bin/claude-janus"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1" >&2; exit 1; }

bash -n "$WRAPPER"
pass "wrapper syntax"
bash -n "$ROOT/install.sh"
pass "installer syntax"

set +e
missing="$(HOME="$TMP/home-missing" XDG_CONFIG_HOME="$TMP/config-missing" "$WRAPPER" -p hi 2>&1)"
missing_rc=$?
set -e
[[ $missing_rc -eq 2 && "$missing" == *"router configuration is missing"* ]] \
  || fail "missing config fails safely"
pass "missing config fails safely"

mkdir -p "$TMP/config-placeholder/claude-janus"
cp "$ROOT/config.example" "$TMP/config-placeholder/claude-janus/router.conf"
set +e
placeholder="$(XDG_CONFIG_HOME="$TMP/config-placeholder" "$WRAPPER" -p hi 2>&1)"
placeholder_rc=$?
set -e
[[ $placeholder_rc -eq 2 && "$placeholder" == *"still uses placeholders"* ]] \
  || fail "placeholder config fails safely"
pass "placeholder config fails safely"

mkdir -p "$TMP/fake-bin"
cat > "$TMP/fake-bin/claude" <<'SH'
#!/usr/bin/env bash
printf 'ARGS:'; printf ' <%s>' "$@"; printf '\n'
printf 'BASE=%s\nTOKEN=%s\nOPUS=%s\nSONNET=%s\nHAIKU=%s\nMODEL=%s\n' \
  "$ANTHROPIC_BASE_URL" "$ANTHROPIC_AUTH_TOKEN" \
  "$ANTHROPIC_DEFAULT_OPUS_MODEL" "$ANTHROPIC_DEFAULT_SONNET_MODEL" \
  "$ANTHROPIC_DEFAULT_HAIKU_MODEL" "${ANTHROPIC_MODEL-<unset>}"
SH
chmod +x "$TMP/fake-bin/claude"

mkdir -p "$TMP/config-firstrun"
set +e
firstrun="$(
  PATH="$TMP/fake-bin:/usr/bin:/bin" \
  XDG_CONFIG_HOME="$TMP/config-firstrun" \
  CLAUDE_JANUS_SETUP_BASE_URL='http://127.0.0.1:20128/v1' \
  CLAUDE_JANUS_SETUP_API_KEY='sk-janus-test' \
  CLAUDE_JANUS_SKIP_CHECK=1 \
  CLAUDE_JANUS_TIER=sonnet \
  CLAUDE_JANUS_DRYRUN=1 \
  "$WRAPPER" 2>&1
)"
firstrun_rc=$?
set -e
[[ $firstrun_rc -eq 0 ]] || fail "first-run setup dry-run"
[[ -f "$TMP/config-firstrun/claude-janus/router.conf" ]] || fail "first-run wrote router.conf"
grep -q 'JANUS_BASE_URL=http://127.0.0.1:20128' "$TMP/config-firstrun/claude-janus/router.conf" \
  || fail "first-run normalized base URL"
grep -q 'JANUS_API_KEY=sk-janus-test' "$TMP/config-firstrun/claude-janus/router.conf" \
  || fail "first-run wrote key"
pass "first-run non-interactive setup hook"

mkdir -p "$TMP/config/claude-janus"
cat > "$TMP/config/claude-janus/router.conf" <<'EOF'
JANUS_BASE_URL=https://config.example
JANUS_API_KEY=config-key
EOF
chmod 600 "$TMP/config/claude-janus/router.conf"

output="$(
  PATH="$TMP/fake-bin:/usr/bin:/bin" \
  XDG_CONFIG_HOME="$TMP/config" \
  JANUS_BASE_URL="https://env.example/" \
  JANUS_API_KEY="env-key" \
  CLAUDE_JANUS_SKIP_CHECK=1 \
  CLAUDE_JANUS_TIER=sonnet \
  "$WRAPPER" -p hello 2>&1
)"
[[ "$output" == *"ARGS: <--model> <sonnet> <-p> <hello>"* ]] || fail "tier alias"
[[ "$output" == *"BASE=https://env.example"* && "$output" == *"TOKEN=env-key"* ]] \
  || fail "environment precedence"
[[ "$output" == *"MODEL=<unset>"* ]] || fail "ANTHROPIC_MODEL unset"
pass "non-interactive mapping and environment precedence"

dry="$(
  PATH="$TMP/fake-bin:/usr/bin:/bin" \
  XDG_CONFIG_HOME="$TMP/config" \
  JANUS_BASE_URL="https://env.example" \
  JANUS_API_KEY="super-secret-test-value" \
  CLAUDE_JANUS_SKIP_CHECK=1 \
  CLAUDE_JANUS_TIER=sonnet \
  CLAUDE_JANUS_DRYRUN=1 \
  "$WRAPPER" 2>&1
)"
[[ "$dry" == *"ANTHROPIC_AUTH_TOKEN=<set>"* && "$dry" != *"super-secret-test-value"* ]] \
  || fail "dry-run token redaction"
pass "dry-run token redaction"

install_root="$TMP/install"
HOME="$TMP/install-home" XDG_CONFIG_HOME="$TMP/install-config" \
  CLAUDE_JANUS_INSTALL_DIR="$install_root" "$ROOT/install.sh" >/dev/null
[[ -x "$install_root/claude-janus" ]] || fail "installer binary"
[[ -f "$TMP/install-config/claude-janus/router.conf" ]] || fail "installer config"
[[ "$(stat -c %a "$TMP/install-config/claude-janus/router.conf")" == "600" ]] \
  || fail "config permissions"
pass "installer and config permissions"

help_out="$(PATH="$TMP/fake-bin:/usr/bin:/bin" HOME="$TMP/help-home" XDG_CONFIG_HOME="$TMP/help-config" "$WRAPPER" --help 2>&1)"
[[ "$help_out" == *"ARGS: <--help>"* && "$help_out" != *"→ Janus"* && "$help_out" != *"router configuration"* ]] \
  || fail "help passthrough"
pass "help passthrough without router config"

mkdir -p "$TMP/config-strict/claude-janus" "$TMP/fake-bin-strict"
cat > "$TMP/fake-bin-strict/curl" <<'SH'
#!/usr/bin/env bash
exit 7
SH
chmod +x "$TMP/fake-bin-strict/curl"
cat > "$TMP/config-strict/claude-janus/router.conf" <<'EOF'
JANUS_BASE_URL=https://down.example
JANUS_API_KEY=k
EOF
set +e
strict="$(
  PATH="$TMP/fake-bin-strict:$TMP/fake-bin:/usr/bin:/bin" \
  XDG_CONFIG_HOME="$TMP/config-strict" \
  CLAUDE_JANUS_TIER=sonnet \
  CLAUDE_JANUS_STRICT_CHECK=1 \
  CLAUDE_JANUS_DRYRUN=1 \
  "$WRAPPER" 2>&1
)"
strict_rc=$?
set -e
[[ $strict_rc -ne 0 && "$strict" == *"/v1/health unreachable"* ]] || fail "strict health check"
pass "strict health check fails closed"

mkdir -p "$TMP/config-strict-models/claude-janus" "$TMP/fake-bin-strict-models"
cat > "$TMP/fake-bin-strict-models/curl" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  [[ "$arg" == */v1/health ]] && exit 0
done
exit 7
SH
chmod +x "$TMP/fake-bin-strict-models/curl"
cat > "$TMP/config-strict-models/claude-janus/router.conf" <<'EOF'
JANUS_BASE_URL=https://models-down.example
JANUS_API_KEY=k
EOF
set +e
strict_models="$(
  PATH="$TMP/fake-bin-strict-models:$TMP/fake-bin:/usr/bin:/bin" \
  XDG_CONFIG_HOME="$TMP/config-strict-models" \
  CLAUDE_JANUS_TIER=sonnet \
  CLAUDE_JANUS_STRICT_CHECK=1 \
  CLAUDE_JANUS_DRYRUN=1 \
  "$WRAPPER" 2>&1
)"
strict_models_rc=$?
set -e
[[ $strict_models_rc -ne 0 && "$strict_models" == *"/v1/models failed"* ]] \
  || fail "strict models check"
pass "strict models check fails closed"

printf 'All smoke tests passed.\n'
