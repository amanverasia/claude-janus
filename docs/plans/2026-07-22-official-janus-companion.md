# Official Janus Claude Code Companion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `claude-janus` into the official Claude Code → Janus companion: first-run setup, live `/v1/models` mapping, clearer health checks, and Janus docs/dashboard wiring.

**Architecture:** Keep the bash launcher. Extract catalog/health helpers into a sourced `lib/` module for testability. The launcher still owns TUI and exec. Janus repo gets a docs/dashboard PR that recommends this tool.

**Tech Stack:** Bash 4+, curl, jq, Claude Code CLI; smoke tests via `./tests/run.sh`; Janus docs are Markdown + Jinja dashboard templates.

**Spec:** `docs/2026-07-22-official-janus-companion-design.md`

## Global Constraints

- Stay bash; do not rewrite in Python/Go.
- Do not fold into Janus CLI.
- Launch contract unchanged: set `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, blank `ANTHROPIC_API_KEY`, set `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU}_MODEL`, leave `ANTHROPIC_MODEL` unset, start with `--model opus|sonnet|haiku`.
- `router.conf` mode `600`; never overwrite a non-placeholder config without confirmation.
- Env vars override config file.
- Catalog fetch uses a non–Claude Code User-Agent (e.g. `claude-janus/1.x`) so Janus returns OpenAI-shaped `/v1/models` by default; still parse both shapes.
- Preserve existing `~/.config/claude-janus/mappings.conf` on upgrade.
- Janus product wiring lives in `/home/amanverasia/Projects/Janus` (separate commits).

## File map

| Path | Responsibility |
| --- | --- |
| `lib/janus_api.sh` | Pure-ish helpers: normalize base URL, parse model ids from catalog JSON, health/catalog curl wrappers |
| `bin/claude-janus` | Source lib; first-run wizard; TUI; launch |
| `tests/fixtures/models_openai.json` | OpenAI-shaped catalog fixture |
| `tests/fixtures/models_anthropic.json` | Anthropic/Claude-shaped catalog fixture |
| `tests/test_janus_api.sh` | Unit tests for `lib/janus_api.sh` |
| `tests/smoke.sh` | Existing + first-run / health messaging coverage |
| `tests/run.sh` | Run unit + smoke |
| `README.md` | Companion positioning |
| Janus `docs/client-setup.md` | Recommend claude-janus |
| Janus `src/janus/dashboard/templates/tools.html` | Claude Code card → companion |

---

### Task 1: Catalog parse helpers + unit tests

**Files:**
- Create: `lib/janus_api.sh`
- Create: `tests/fixtures/models_openai.json`
- Create: `tests/fixtures/models_anthropic.json`
- Create: `tests/test_janus_api.sh`
- Modify: `tests/run.sh`

**Interfaces:**
- Produces:
  - `janus_normalize_base_url(url)` → stdout, strip trailing slash and optional trailing `/v1`
  - `janus_extract_model_ids(json)` → stdout, one id per line
  - `janus_catalog_contains(json, id)` → exit 0 if id present
- Consumes: jq, bash

- [ ] **Step 1: Write fixtures**

`tests/fixtures/models_openai.json`:

```json
{
  "object": "list",
  "data": [
    {"id": "openrouter/anthropic/claude-sonnet-4", "object": "model"},
    {"id": "deepseek/deepseek-v4-pro", "object": "model"},
    {"id": "combo-fast", "object": "model"}
  ]
}
```

`tests/fixtures/models_anthropic.json`:

```json
{
  "data": [
    {"id": "claude-sonnet-4", "type": "model", "display_name": "claude-sonnet-4"},
    {"id": "combo-fast", "type": "model", "display_name": "combo-fast"}
  ],
  "has_more": false
}
```

- [ ] **Step 2: Write failing unit tests**

`tests/test_janus_api.sh`:

```bash
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

printf 'All janus_api unit tests passed.\n'
```

- [ ] **Step 3: Run tests — expect fail**

Run: `bash tests/test_janus_api.sh`  
Expected: fail sourcing missing `lib/janus_api.sh`

- [ ] **Step 4: Implement `lib/janus_api.sh`**

```bash
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
  local base="$1" key="$2"
  base="$(janus_normalize_base_url "$base")"
  curl -fsS -o /dev/null --max-time 3 \
    -A 'claude-janus/1.0' \
    "$base/v1/health" || return 1
  curl -fsS -o /dev/null --max-time 8 \
    -A 'claude-janus/1.0' \
    -H "Authorization: Bearer $key" \
    "$base/v1/models" || return 2
  return 0
}
```

- [ ] **Step 5: Wire `tests/run.sh` and verify pass**

Update `tests/run.sh` to:

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/tests/test_janus_api.sh"
"$ROOT/tests/smoke.sh"
"$ROOT/tests/arrow_keys.py"
```

Run: `./tests/run.sh`  
Expected: unit tests PASS; smoke still PASS (arrow_keys as before).

- [ ] **Step 6: Commit**

```bash
git add lib/janus_api.sh tests/fixtures tests/test_janus_api.sh tests/run.sh
git commit -m "Add Janus catalog helpers and unit tests."
```

---

### Task 2: First-run router setup wizard

**Files:**
- Modify: `bin/claude-janus` (config load / missing-config block near lines 17–56)
- Modify: `tests/smoke.sh`

**Interfaces:**
- Consumes: `janus_normalize_base_url`, `janus_check_health` from `lib/janus_api.sh`
- Produces: `run_first_run_setup` writes `router.conf`; may set `JANUS_BASE_URL` / `JANUS_API_KEY` in-process

- [ ] **Step 1: Add failing smoke coverage for interactive setup via env-file write helper**

Append to `tests/smoke.sh` (after placeholder test):

```bash
# First-run: when CLAUDE_JANUS_SETUP_BASE_URL + CLAUDE_JANUS_SETUP_API_KEY are set,
# missing config is created non-interactively (test hook).
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
```

Note: `fake-bin/claude` must already exist from earlier smoke steps — move the fake-bin creation above this block if needed, or create a minimal fake-bin before this section.

- [ ] **Step 2: Run smoke — expect fail**

Run: `./tests/smoke.sh`  
Expected: FAIL `first-run setup dry-run` (hook not implemented).

- [ ] **Step 3: Source lib and implement setup in `bin/claude-janus`**

Near the top of `bin/claude-janus`, after `umask 077`:

```bash
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# When installed to ~/.local/bin, lib lives next to the repo only during dev;
# prefer adjacent lib, then XDG data, then same-dir.
if [[ -f "$ROOT_DIR/lib/janus_api.sh" ]]; then
  # shellcheck source=lib/janus_api.sh
  source "$ROOT_DIR/lib/janus_api.sh"
elif [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/claude-janus/lib/janus_api.sh" ]]; then
  # shellcheck disable=SC1091
  source "${XDG_DATA_HOME:-$HOME/.local/share}/claude-janus/lib/janus_api.sh"
else
  # Inline fallback only if install forgot lib — prefer install.sh shipping lib.
  :
fi
```

Update `install.sh` to also install `lib/`:

```bash
LIB_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-janus"
mkdir -p "$LIB_DIR"
cp -a "$ROOT_DIR/lib/." "$LIB_DIR/lib/" 2>/dev/null || {
  mkdir -p "$LIB_DIR/lib"
  install -m 0644 "$ROOT_DIR/lib/janus_api.sh" "$LIB_DIR/lib/janus_api.sh"
}
```

And in the launcher, when sourced from installed binary (`dirname` is `~/.local/bin`), set:

```bash
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/../lib/janus_api.sh" ]]; then
  source "$SCRIPT_DIR/../lib/janus_api.sh"
elif [[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/claude-janus/lib/janus_api.sh" ]]; then
  source "${XDG_DATA_HOME:-$HOME/.local/share}/claude-janus/lib/janus_api.sh"
fi
```

Replace the hard `exit 2` missing-config block with:

```bash
is_placeholder_config() {
  [[ -z "$JANUS_BASE_URL" || -z "$JANUS_API_KEY" ||
    "$JANUS_BASE_URL" == *'your-janus-router.example'* ||
    "$JANUS_API_KEY" == 'replace-with-your-key' ]]
}

write_router_config() {
  local base key dest
  base="$(janus_normalize_base_url "$1")"
  key="$2"
  dest="$3"
  mkdir -p "$(dirname -- "$dest")"
  umask 077
  printf 'JANUS_BASE_URL=%s\nJANUS_API_KEY=%s\n' "$base" "$key" > "$dest"
  chmod 600 "$dest" 2>/dev/null || true
}

run_first_run_setup() {
  local base key probe
  # Test / automation hook
  if [[ -n "${CLAUDE_JANUS_SETUP_BASE_URL:-}" && -n "${CLAUDE_JANUS_SETUP_API_KEY:-}" ]]; then
    write_router_config "$CLAUDE_JANUS_SETUP_BASE_URL" "$CLAUDE_JANUS_SETUP_API_KEY" "$ROUTER_CONFIG"
    JANUS_BASE_URL="$(janus_normalize_base_url "$CLAUDE_JANUS_SETUP_BASE_URL")"
    JANUS_API_KEY="$CLAUDE_JANUS_SETUP_API_KEY"
    return 0
  fi
  if [[ ! -t 0 || ! -t 2 ]]; then
    printf 'claude-janus: router configuration is missing or still uses placeholders\n' >&2
    printf 'Create %s or export JANUS_BASE_URL and JANUS_API_KEY.\n' "$ROUTER_CONFIG" >&2
    exit 2
  fi
  printf '%sFirst-run setup%s\n\n' "$BOLD" "$RESET" >&2
  for probe in 'http://127.0.0.1:20128' 'http://localhost:20128'; do
    if curl -fsS -o /dev/null --max-time 1 -A 'claude-janus/1.0' "$probe/v1/health" 2>/dev/null; then
      printf 'Detected local Janus at %s\n' "$probe" >&2
      printf 'Use it? [Y/n]: ' >&2
      reply="$(read_reply)"
      case "$reply" in ''|y|Y|yes|Yes)
        base="$probe"
        break
        ;;
      esac
    fi
  done
  if [[ -z "${base:-}" ]]; then
    printf 'Janus base URL (no /v1 required): ' >&2
    base="$(read_reply)"
  fi
  printf 'Janus API key: ' >&2
  key="$(read_reply)"
  if [[ -z "$base" || -z "$key" ]]; then
    printf 'claude-janus: setup cancelled (empty URL or key)\n' >&2
    exit 2
  fi
  write_router_config "$base" "$key" "$ROUTER_CONFIG"
  JANUS_BASE_URL="$(janus_normalize_base_url "$base")"
  JANUS_API_KEY="$key"
  printf 'Wrote %s\n' "$ROUTER_CONFIG" >&2
}

if [[ $BYPASS_ROUTER_CONFIG -eq 0 ]] && is_placeholder_config; then
  run_first_run_setup
fi
# Re-normalize after setup/load
JANUS_BASE_URL="$(janus_normalize_base_url "$JANUS_BASE_URL")"
```

- [ ] **Step 4: Run smoke — expect pass**

Run: `./tests/smoke.sh`  
Expected: includes `PASS first-run non-interactive setup hook`

- [ ] **Step 5: Commit**

```bash
git add bin/claude-janus install.sh tests/smoke.sh
git commit -m "Add first-run Janus router setup wizard."
```

---

### Task 3: Health check messaging

**Files:**
- Modify: `bin/claude-janus` (reachability block ~653–660)
- Modify: `tests/smoke.sh`

**Interfaces:**
- Consumes: `janus_check_health`
- Produces: clearer stderr warnings; still non-fatal (warn and launch) unless `CLAUDE_JANUS_STRICT_CHECK=1`

- [ ] **Step 1: Add smoke for strict check failure**

```bash
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
[[ $strict_rc -ne 0 && "$strict" == *"Could not reach"* ]] || fail "strict health check"
pass "strict health check fails closed"
```

- [ ] **Step 2: Run — expect fail**

Expected: FAIL until strict mode implemented.

- [ ] **Step 3: Replace soft check with `janus_check_health`**

```bash
if [[ $BYPASS_ROUTER_CONFIG -eq 0 && -z "${CLAUDE_JANUS_SKIP_CHECK:-}" ]] && command -v curl >/dev/null 2>&1; then
  if ! janus_check_health "$JANUS_BASE_URL" "$JANUS_API_KEY"; then
    rc=$?
    case "$rc" in
      1) msg="Janus /v1/health unreachable at $JANUS_BASE_URL" ;;
      2) msg="Authenticated /v1/models failed (check JANUS_API_KEY / allowlist)" ;;
      *) msg="Could not reach Janus at $JANUS_BASE_URL" ;;
    esac
    if [[ -n "${CLAUDE_JANUS_STRICT_CHECK:-}" ]]; then
      printf '%s× %s%s\n' "$RED" "$msg" "$RESET" >&2
      exit 2
    fi
    printf '%s! %s — launching anyway.%s\n' "$YELLOW" "$msg" "$RESET" >&2
  fi
fi
```

- [ ] **Step 4: Run smoke — expect pass**

- [ ] **Step 5: Commit**

```bash
git add bin/claude-janus tests/smoke.sh
git commit -m "Improve Janus health check messaging and strict mode."
```

---

### Task 4: Live catalog in tier mapping UI

**Files:**
- Modify: `bin/claude-janus` (`model_exists`, `configure_tier`, `render_tier_model_menu`, `pick_custom_model`)

**Interfaces:**
- Consumes: `janus_fetch_catalog`, `janus_extract_model_ids`, `janus_catalog_contains`
- Produces: menus list live ids when catalog available; presets filtered to live set

- [ ] **Step 1: Cache catalog once per process**

```bash
CATALOG_JSON=""
CATALOG_STATUS=0  # 0 ok, 1 empty/unreachable

load_catalog() {
  if [[ -n "$CATALOG_JSON" || $CATALOG_STATUS -ne 0 ]]; then
    [[ -n "$CATALOG_JSON" ]]
    return $?
  fi
  if CATALOG_JSON="$(janus_fetch_catalog "$JANUS_BASE_URL" "$JANUS_API_KEY" 2>/dev/null)"; then
    if [[ -z "$(janus_extract_model_ids "$CATALOG_JSON")" ]]; then
      CATALOG_STATUS=1
      CATALOG_JSON=""
      return 1
    fi
    return 0
  fi
  CATALOG_STATUS=1
  CATALOG_JSON=""
  return 1
}
```

Replace `model_exists` body to use cache:

```bash
model_exists() {
  load_catalog || return 2
  janus_catalog_contains "$CATALOG_JSON" "$1"
}
```

- [ ] **Step 2: Build dynamic menu entries**

Keep presets as labeled shortcuts when present in catalog; append up to 20 other live ids under “From Janus”. Custom entry remains last.

Sketch for `configure_tier` selection list:

```bash
# PRESET_IDS and PRESET_LABELS arrays; filter with janus_catalog_contains when load_catalog succeeds
# EXTRA_IDS=($(janus_extract_model_ids "$CATALOG_JSON" | grep -vxF ...presets... | head -20))
```

When catalog unreachable, keep today’s hardcoded 6 presets + custom (current behavior).

- [ ] **Step 3: Manual dry verification**

Run against a live Janus if available:

```bash
CLAUDE_JANUS_SKIP_CHECK=0 claude-janus
# Configure mappings → confirm live models appear
```

If no live Janus: unit-test filtering with a sourced snippet in `tests/test_janus_api.sh` that asserts preset∩fixture ids.

Add to `tests/test_janus_api.sh`:

```bash
json="$(cat "$ROOT/tests/fixtures/models_openai.json")"
janus_catalog_contains "$json" 'deepseek/deepseek-v4-pro' || fail "preset in fixture"
pass "preset intersection helper"
```

- [ ] **Step 4: Commit**

```bash
git add bin/claude-janus tests/test_janus_api.sh
git commit -m "Map Claude tiers from live Janus /v1/models catalog."
```

---

### Task 5: Companion README + version banner

**Files:**
- Modify: `README.md`
- Modify: `bin/claude-janus` (header comment / startup banner subtitle)

- [ ] **Step 1: Rewrite README intro**

Lead with: official Claude Code companion for [Janus](https://github.com/amanverasia/Janus). Document first-run, live catalog, `CLAUDE_JANUS_STRICT_CHECK`, setup env hooks for CI, and link to Janus client-setup.

- [ ] **Step 2: Run `./tests/run.sh` — expect pass**

- [ ] **Step 3: Commit**

```bash
git add README.md bin/claude-janus
git commit -m "Position claude-janus as the official Janus companion."
```

---

### Task 6: Janus docs + dashboard wiring

**Files (Janus repo `/home/amanverasia/Projects/Janus`):**
- Modify: `docs/client-setup.md` (Claude Code section)
- Modify: `src/janus/dashboard/templates/tools.html` (Claude Code card)

**Interfaces:**
- Consumes: none from claude-janus runtime
- Produces: docs/UI pointing users at `https://github.com/amanverasia/claude-janus`

- [ ] **Step 1: Update `docs/client-setup.md`**

Replace the Claude Code section with preferred path:

```markdown
## Claude Code

**Recommended:** install [claude-janus](https://github.com/amanverasia/claude-janus), the official launcher that maps Opus/Sonnet/Haiku to your Janus models and sets the right env vars for each session.

```bash
git clone https://github.com/amanverasia/claude-janus.git
cd claude-janus && ./install.sh
claude-janus
```

### Manual env (advanced)

```bash
export ANTHROPIC_BASE_URL=http://localhost:20128
export ANTHROPIC_AUTH_TOKEN=sk-janus-yourkey
export ANTHROPIC_API_KEY=
```

Prefer `ANTHROPIC_AUTH_TOKEN` and a blank `ANTHROPIC_API_KEY` so Claude Code does not fall back to Anthropic cloud credentials. Base URL should omit `/v1` if you use Claude Code’s default path joining; if you already use `.../v1`, claude-janus normalizes it.
```

- [ ] **Step 2: Update dashboard Tools card**

In `tools.html` Claude Code block, add after the title:

```html
<p class="text-sm text-gray-400 mb-3">
  Recommended: <a class="text-cyan-400 underline" href="https://github.com/amanverasia/claude-janus" target="_blank" rel="noopener">claude-janus</a>
  maps Opus/Sonnet/Haiku to Janus and launches Claude Code for you.
</p>
```

Keep existing copy-paste exports for advanced users; note `ANTHROPIC_AUTH_TOKEN` if the template currently only shows `ANTHROPIC_API_KEY`.

- [ ] **Step 3: Verify docs build (Janus)**

Run: `cd /home/amanverasia/Projects/Janus && .venv/bin/mkdocs build --strict`  
Expected: success

- [ ] **Step 4: Commit in Janus**

```bash
cd /home/amanverasia/Projects/Janus
git add docs/client-setup.md src/janus/dashboard/templates/tools.html
git commit -m "Recommend claude-janus as the official Claude Code setup."
```

---

### Task 7: Final verification

- [ ] **Step 1: Run full claude-janus suite**

```bash
cd /home/amanverasia/claude-janus && ./tests/run.sh
```

Expected: all PASS

- [ ] **Step 2: Manual install smoke**

```bash
CLAUDE_JANUS_INSTALL_DIR=/tmp/cj-bin XDG_CONFIG_HOME=/tmp/cj-cfg ./install.sh
/tmp/cj-bin/claude-janus --help
```

Expected: help passthrough works; lib installed under XDG data.

- [ ] **Step 3: Commit any leftover fixes; push only if user asks**

---

## Spec coverage self-review

| Spec requirement | Task |
| --- | --- |
| First-run setup + localhost probe | Task 2 |
| Live `/v1/models` catalog + dual shapes | Tasks 1, 4 |
| Non-Claude UA for catalog | Task 1 (`-A claude-janus/1.0`) |
| Health check messaging | Task 3 |
| Launch contract unchanged | Constraints; Tasks 2–4 do not alter exec env block |
| Janus docs/dashboard wiring | Task 6 |
| Tests/CI | Tasks 1–3, 7; `tests/run.sh` |
| Preserve mappings on upgrade | No migration deletes mappings.conf |

## Placeholder scan

None intentional. Install/lib path resolution is fully specified in Task 2.

## Type/name consistency

- `janus_normalize_base_url`, `janus_extract_model_ids`, `janus_catalog_contains`, `janus_fetch_catalog`, `janus_check_health` used consistently across tasks.
- Setup hook env: `CLAUDE_JANUS_SETUP_BASE_URL`, `CLAUDE_JANUS_SETUP_API_KEY`.
- Strict mode: `CLAUDE_JANUS_STRICT_CHECK`.
