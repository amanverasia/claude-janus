# Independent Subagent Model Mapping Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `CLAUDE_CODE_SUBAGENT_MODEL` its own catalog-backed, persisted Janus model mapping while preserving the effective Sonnet mapping for existing installations.

**Architecture:** Extend the launcher's existing flat `mappings.conf` state with `SUBAGENT_MODEL`, falling back only after existing configuration has loaded so customized Sonnet routes remain backward compatible. Reuse the current mapping selector for a fourth mapping role, but keep startup tier validation and `--model` emission strictly limited to `opus|sonnet|haiku`. Verify noninteractive state/export behavior in Bash smoke tests and interactive save behavior in a dedicated pseudo-TTY regression test.

**Tech Stack:** Bash 4+, `curl`, `jq`, Python 3 pseudo-TTY tests, shell smoke tests, GitHub Actions via `./tests/run.sh`.

## Global Constraints

- Keep `claude-janus` a standalone Bash tool; do not move behavior into a Janus CLI or another language.
- Preserve existing `OPUS_MODEL`, `SONNET_MODEL`, `HAIKU_MODEL`, `DEFAULT_TIER`, `/model`, and primary launch behavior.
- `subagent` is a mapping role only; never accept `CLAUDE_JANUS_TIER=subagent` or emit `--model subagent`.
- A missing or invalid persisted `SUBAGENT_MODEL` must resolve to the effective `SONNET_MODEL` after `load_config` has applied valid legacy values.
- A newly created `mappings.conf` must include `SUBAGENT_MODEL` on its first write.
- Reuse existing live-catalog, offline-preset, custom-ID validation, and warning behavior; do not duplicate `lib/janus_api.sh` logic.
- Keep dry-run token redaction unchanged.
- Preserve the separately created, currently uncommitted root `CLAUDE.md`; do not reset, overwrite, or omit it from the final documentation commit.

---

## File Structure

- Modify `bin/claude-janus`: own the fourth mapping's state, fallback, persistence, UI, and child-process export.
- Modify `tests/smoke.sh`: cover first-save schema, exact four-variable export, legacy fallback, and primary-tier rejection.
- Create `tests/subagent_mapping.py`: drive the interactive configuration menu through a pseudo-TTY and verify the selected model is persisted and exported without becoming a primary tier.
- Modify `tests/run.sh`: include the new pseudo-TTY regression test in the CI entry point.
- Modify `README.md`: document the independent subagent mapping and legacy behavior for users.
- Modify `docs/2026-07-22-official-janus-companion-design.md`: correct the stale Haiku statement.
- Modify `CLAUDE.md`: make repository guidance accurately describe the four persisted mappings while preserving its existing content.

---

### Task 1: Persist and export an independent subagent mapping

**Files:**
- Modify: `tests/smoke.sh:35-102`
- Modify: `bin/claude-janus:161-206`
- Modify: `bin/claude-janus:803-813`

**Interfaces:**
- Consumes: existing `valid_model_value`, `load_config`, `save_config`, and the flat `$XDG_CONFIG_HOME/claude-janus/mappings.conf` format.
- Produces: shell variable `SUBAGENT_MODEL`, persisted key `SUBAGENT_MODEL=<model-id>`, and child environment variable `CLAUDE_CODE_SUBAGENT_MODEL="$SUBAGENT_MODEL"`.

- [ ] **Step 1: Extend the fake Claude probe and add failing first-save/export tests**

Update the fake `claude` block in `tests/smoke.sh` so it exposes all four mapping variables:

```bash
cat > "$TMP/fake-bin/claude" <<'SH'
#!/usr/bin/env bash
printf 'ARGS:'; printf ' <%s>' "$@"; printf '\n'
printf 'BASE=%s\nTOKEN=%s\nOPUS=%s\nSONNET=%s\nHAIKU=%s\nSUBAGENT=%s\nMODEL=%s\n' \
  "$ANTHROPIC_BASE_URL" "$ANTHROPIC_AUTH_TOKEN" \
  "$ANTHROPIC_DEFAULT_OPUS_MODEL" "$ANTHROPIC_DEFAULT_SONNET_MODEL" \
  "$ANTHROPIC_DEFAULT_HAIKU_MODEL" "$CLAUDE_CODE_SUBAGENT_MODEL" \
  "${ANTHROPIC_MODEL-<unset>}"
SH
```

After the existing first-run `router.conf` assertions, require the initial mapping file and its backward-compatible subagent value:

```bash
first_mappings="$TMP/config-firstrun/claude-janus/mappings.conf"
[[ -f "$first_mappings" ]] || fail "first-run wrote mappings.conf"
grep -Fxq 'SUBAGENT_MODEL=deepseek/deepseek-v4-pro' "$first_mappings" \
  || fail "first-run wrote Sonnet-compatible subagent mapping"
pass "first-run mapping schema includes subagent"
```

Before the existing noninteractive `output` invocation, create distinct persisted values:

```bash
cat > "$TMP/config/claude-janus/mappings.conf" <<'EOF'
OPUS_MODEL=test/opus-route
SONNET_MODEL=test/sonnet-route
HAIKU_MODEL=test/haiku-route
SUBAGENT_MODEL=test/subagent-route
DEFAULT_TIER=sonnet
EOF
chmod 600 "$TMP/config/claude-janus/mappings.conf"
```

Add exact assertions after the current environment-precedence assertion:

```bash
[[ "$output" == *"OPUS=test/opus-route"* ]] || fail "Opus mapping export"
[[ "$output" == *"SONNET=test/sonnet-route"* ]] || fail "Sonnet mapping export"
[[ "$output" == *"HAIKU=test/haiku-route"* ]] || fail "Haiku mapping export"
[[ "$output" == *"SUBAGENT=test/subagent-route"* ]] || fail "subagent mapping export"
[[ "$output" != *"SUBAGENT=test/sonnet-route"* ]] || fail "subagent mapping remains independent"
pass "all persisted mappings exported independently"
```

Add a legacy-file case before the dry-run test:

```bash
mkdir -p "$TMP/config-legacy/claude-janus"
cat > "$TMP/config-legacy/claude-janus/mappings.conf" <<'EOF'
OPUS_MODEL=legacy/opus
SONNET_MODEL=legacy/custom-sonnet
HAIKU_MODEL=legacy/haiku
DEFAULT_TIER=sonnet
EOF
legacy="$(
  PATH="$TMP/fake-bin:/usr/bin:/bin" \
  XDG_CONFIG_HOME="$TMP/config-legacy" \
  JANUS_BASE_URL="https://legacy.example" \
  JANUS_API_KEY="legacy-key" \
  CLAUDE_JANUS_SKIP_CHECK=1 \
  CLAUDE_JANUS_TIER=sonnet \
  "$WRAPPER" -p legacy 2>&1
)"
[[ "$legacy" == *"SONNET=legacy/custom-sonnet"* ]] || fail "legacy Sonnet mapping loaded"
[[ "$legacy" == *"SUBAGENT=legacy/custom-sonnet"* ]] || fail "legacy subagent inherits effective Sonnet"
pass "legacy mappings default subagent to effective Sonnet"
```

- [ ] **Step 2: Run smoke tests and confirm they fail for the missing feature**

Run:

```bash
bash tests/smoke.sh
```

Expected: `FAIL first-run wrote Sonnet-compatible subagent mapping` because current `save_config` does not write `SUBAGENT_MODEL`. If that assertion is temporarily bypassed, the distinct export assertion must fail because current code exports Sonnet.

- [ ] **Step 3: Add the minimal state, fallback, persistence, and export implementation**

In `bin/claude-janus`, initialize an empty optional value beside the existing defaults:

```bash
OPUS_MODEL="$CLAUDE_OPUS"
SONNET_MODEL="$DEEPSEEK_PRO"
HAIKU_MODEL="$GLM_47"
SUBAGENT_MODEL=""
DEFAULT_TIER="sonnet"
```

Extend `load_config`:

```bash
case "$key" in
  OPUS_MODEL)     valid_model_value "$value" && OPUS_MODEL="$value" ;;
  SONNET_MODEL)   valid_model_value "$value" && SONNET_MODEL="$value" ;;
  HAIKU_MODEL)    valid_model_value "$value" && HAIKU_MODEL="$value" ;;
  SUBAGENT_MODEL) valid_model_value "$value" && SUBAGENT_MODEL="$value" ;;
  DEFAULT_TIER)   valid_tier "$value" && DEFAULT_TIER="$value" ;;
esac
```

Extend `save_config`:

```bash
save_config() {
  {
    printf 'OPUS_MODEL=%s\n' "$OPUS_MODEL"
    printf 'SONNET_MODEL=%s\n' "$SONNET_MODEL"
    printf 'HAIKU_MODEL=%s\n' "$HAIKU_MODEL"
    printf 'SUBAGENT_MODEL=%s\n' "$SUBAGENT_MODEL"
    printf 'DEFAULT_TIER=%s\n' "$DEFAULT_TIER"
  } > "$CONFIG_FILE"
  chmod 600 "$CONFIG_FILE" 2>/dev/null || true
}
```

Apply the compatibility fallback after loading and before the existing first-save branch:

```bash
load_config
[[ -n "$SUBAGENT_MODEL" ]] || SUBAGENT_MODEL="$SONNET_MODEL"
[[ -f "$CONFIG_FILE" ]] || save_config
```

Replace the hardwired export:

```bash
export CLAUDE_CODE_SUBAGENT_MODEL="$SUBAGENT_MODEL"
```

- [ ] **Step 4: Run focused tests and syntax validation**

Run:

```bash
bash -n bin/claude-janus
bash -n tests/smoke.sh
bash tests/smoke.sh
```

Expected: both syntax checks exit `0`; smoke output ends with `All smoke tests passed.` and includes the new pass lines for first-save schema, independent exports, and legacy fallback.

- [ ] **Step 5: Commit the persisted state and export contract**

```bash
git add bin/claude-janus tests/smoke.sh
git commit -m "Add independent subagent model state

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: Add catalog-backed subagent mapping configuration

**Files:**
- Create: `tests/subagent_mapping.py`
- Modify: `tests/run.sh:1-7`
- Modify: `bin/claude-janus:397-427`
- Modify: `bin/claude-janus:598-661`
- Modify: `bin/claude-janus:695-728`

**Interfaces:**
- Consumes: `SUBAGENT_MODEL` from Task 1; existing `build_tier_model_menu`, `tier_menu_select_reply`, `pick_custom_model`, `save_config`, and `menu_navigate` behavior.
- Produces: `mapping_label <role>`, `configure_mapping <role>`, a five-entry configuration menu, a subagent mapping row without a default-tier marker, and a pseudo-TTY persistence test.

- [ ] **Step 1: Add a failing pseudo-TTY configuration test**

Create `tests/subagent_mapping.py` with a dedicated interactive flow. Use this complete structure:

```python
#!/usr/bin/env python3
"""Pseudo-TTY regression test for independent subagent mapping configuration."""
import os
import pty
import re
import select
import sys
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tmp = Path(tempfile.mkdtemp(prefix="claude-janus-subagent-test-"))
(tmp / "bin").mkdir()
(tmp / "config").mkdir()

fake_claude = tmp / "bin" / "claude"
fake_claude.write_text(
    "#!/usr/bin/env bash\n"
    "printf 'ARGS:'; printf ' <%s>' \"$@\"; echo\n"
    "printf 'SUBAGENT=%s\\n' \"$CLAUDE_CODE_SUBAGENT_MODEL\"\n"
)
fake_claude.chmod(0o755)

fake_curl = tmp / "bin" / "curl"
fake_curl.write_text("#!/usr/bin/env bash\nexit 7\n")
fake_curl.chmod(0o755)

env = os.environ.copy()
env.update(
    PATH=f"{tmp / 'bin'}:/usr/bin:/bin",
    XDG_CONFIG_HOME=str(tmp / "config"),
    JANUS_BASE_URL="https://router.example",
    JANUS_API_KEY="test-key",
    CLAUDE_JANUS_SKIP_CHECK="1",
    TERM="xterm-256color",
)

pid, fd = pty.fork()
if pid == 0:
    os.execve(str(root / "bin" / "claude-janus"), ["claude-janus"], env)

buffer = bytearray()


def wait_for(needle: bytes, timeout: float = 8) -> None:
    end = time.time() + timeout
    while time.time() < end:
        if needle in buffer:
            return
        ready, _, _ = select.select([fd], [], [], 0.1)
        if ready:
            try:
                data = os.read(fd, 65536)
            except OSError:
                data = b""
            if not data:
                break
            buffer.extend(data)
    raise RuntimeError(f"did not see {needle!r}")


def press(key: bytes, pause: float = 0.15) -> None:
    os.write(fd, key)
    time.sleep(pause)


wait_for(b"Esc/Q cancel")
press(b"c")
wait_for(b"Change subagent mapping")
press(b"a")
wait_for(b"Enter another exact Janus model ID")
press(b"f")
wait_for(b"Mapping saved")
press(b" ")
wait_for(b"Change subagent mapping")
press(b"\x1b")
wait_for(b"Esc/Q cancel")
press(b"\r")

end = time.time() + 8
status = None
while time.time() < end:
    got, status = os.waitpid(pid, os.WNOHANG)
    if got:
        break
    ready, _, _ = select.select([fd], [], [], 0.1)
    if ready:
        try:
            buffer.extend(os.read(fd, 65536))
        except OSError:
            pass
if status is None:
    os.kill(pid, 9)
    _, status = os.waitpid(pid, 0)

for _ in range(20):
    ready, _, _ = select.select([fd], [], [], 0.05)
    if not ready:
        break
    try:
        buffer.extend(os.read(fd, 65536))
    except OSError:
        break

raw = bytes(buffer)
text = re.sub(rb"\x1b\[[0-9;?]*[ -/]*[@-~]", b"", raw).decode("utf-8", "replace")
mappings = tmp / "config" / "claude-janus" / "mappings.conf"
mapping_text = mappings.read_text() if mappings.exists() else ""
checks = {
    "configuration action": "Change subagent mapping" in text,
    "primary launch remains Sonnet": "ARGS: <--model> <sonnet>" in text,
    "selected subagent exported": "SUBAGENT=deepseek/deepseek-v4-flash" in text,
    "selected subagent persisted": "SUBAGENT_MODEL=deepseek/deepseek-v4-flash\n" in mapping_text,
    "all mappings persisted": all(
        f"{key}=" in mapping_text
        for key in ("OPUS_MODEL", "SONNET_MODEL", "HAIKU_MODEL", "DEFAULT_TIER")
    ),
    "never launches subagent tier": "<--model> <subagent>" not in text,
    "no escaped arrows": all(token not in text for token in ("^[[A", "^[[B", "^[[C", "^[[D")),
    "success": os.waitstatus_to_exitcode(status) == 0,
}
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)
if not all(checks.values()):
    print(text)
    print(mapping_text)
    sys.exit(1)
```

Add the test to `tests/run.sh` after the existing arrow-key test:

```bash
python3 "$ROOT/tests/subagent_mapping.py"
```

Also add a smoke regression proving the environment variable cannot become a startup tier:

```bash
set +e
bad_tier="$(
  PATH="$TMP/fake-bin:/usr/bin:/bin" \
  XDG_CONFIG_HOME="$TMP/config" \
  JANUS_BASE_URL="https://env.example" \
  JANUS_API_KEY="env-key" \
  CLAUDE_JANUS_SKIP_CHECK=1 \
  CLAUDE_JANUS_TIER=subagent \
  "$WRAPPER" 2>&1
)"
bad_tier_rc=$?
set -e
[[ $bad_tier_rc -eq 2 && "$bad_tier" == *"must be opus, sonnet, or haiku"* ]] \
  || fail "subagent rejected as startup tier"
pass "subagent remains outside primary tiers"
```

- [ ] **Step 2: Run the new test and confirm it fails at the missing menu action**

Run:

```bash
python3 tests/subagent_mapping.py
```

Expected: failure from `wait_for(b"Change subagent mapping")` because the configuration menu currently has only Opus, Sonnet, Haiku, and default-tier actions.

- [ ] **Step 3: Generalize mapping labels and rows without widening valid tiers**

Replace the role label helper and mapping row logic with:

```bash
mapping_label() {
  case "$1" in
    opus) printf 'Opus' ;;
    sonnet) printf 'Sonnet' ;;
    haiku) printf 'Haiku' ;;
    subagent) printf 'Subagent' ;;
  esac
}

tier_label() {
  mapping_label "$1"
}

print_mapping_row() {
  local role="$1" model="$2" marker=' '
  [[ "$role" == subagent || "$role" != "$DEFAULT_TIER" ]] || marker='●'
  printf '  %s%s %-9s%s  %s%-26s%s  [%s]\n' \
    "$CYAN" "$marker" "$(mapping_label "$role")" "$RESET" \
    "$BOLD" "$(model_label "$model")" "$RESET" "$(model_badge "$model")" >&2
  printf '      %s%s%s\n' "$DIM" "$model" "$RESET" >&2
}

print_mappings() {
  printf '%sSAVED MODEL MAP%s  %s● default startup tier%s\n\n' "$BOLD" "$RESET" "$DIM" "$RESET" >&2
  print_mapping_row opus "$OPUS_MODEL"
  print_mapping_row sonnet "$SONNET_MODEL"
  print_mapping_row haiku "$HAIKU_MODEL"
  print_mapping_row subagent "$SUBAGENT_MODEL"
}
```

Do not change `valid_tier`; it must remain:

```bash
valid_tier() {
  case "$1" in opus|sonnet|haiku) return 0 ;; *) return 1 ;; esac
}
```

- [ ] **Step 4: Generalize the existing selector to configure all four mapping roles**

Rename `render_tier_model_menu` to `render_mapping_model_menu` and use `mapping_label` in its header:

```bash
render_mapping_model_menu() {
  local cursor="$1" role="$2" current="$3" i number
  screen_header "Map the $(mapping_label "$role") model" "Current: $(model_label "$current") · $current"
  for i in "${!TIER_MENU_IDS[@]}"; do
    number="$((i + 1))"
    print_model_option "$cursor" "$number" "${TIER_MENU_LABELS[$i]}" "${TIER_MENU_IDS[$i]}" "${TIER_MENU_NOTES[$i]}"
  done
  menu_choice "$cursor" "$TIER_MENU_CUSTOM_INDEX" "$TIER_MENU_CUSTOM_INDEX" 'Enter another exact Janus model ID'
  printf '\n  %s↑/↓ move · Enter select · Esc back%s\n' "$DIM" "$RESET" >&2
}
```

Rename `configure_tier` to `configure_mapping`, add the fourth target, use the renamed renderer, and use `mapping_label` in success messages:

```bash
configure_mapping() {
  local role="$1" target_var current reply selected="" cursor=1 select_rc
  case "$role" in
    opus) target_var="OPUS_MODEL"; current="$OPUS_MODEL" ;;
    sonnet) target_var="SONNET_MODEL"; current="$SONNET_MODEL" ;;
    haiku) target_var="HAIKU_MODEL"; current="$HAIKU_MODEL" ;;
    subagent) target_var="SUBAGENT_MODEL"; current="$SUBAGENT_MODEL" ;;
  esac
  build_tier_model_menu
  cursor="$(tier_menu_cursor_for_model "$current")"

  while true; do
    if [[ $UI_ENABLED -eq 1 ]]; then
      menu_navigate "$TIER_MENU_COUNT" "$cursor" render_mapping_model_menu "$TIER_MENU_SHORTCUTS" "$role" "$current"
      reply="$MENU_RESULT"
      [[ "$reply" != back ]] || return 0
      cursor="$reply"
    else
      render_mapping_model_menu 0 "$role" "$current"
      printf 'Choice [Enter keeps current]: ' >&2
      reply="$(read_reply)"
    fi

    case "$reply" in
      ""|b|B) return 0 ;;
      *)
        if tier_menu_select_reply "$reply"; then
          select_rc=0
        else
          select_rc=$?
        fi
        case "$select_rc" in
          0) selected="$TIER_MENU_SELECTED" ;;
          1)
            if pick_custom_model "$target_var" "$current"; then
              save_config
              show_message success "Mapping saved" "$(mapping_label "$role") now uses $(model_label "${!target_var}")."
            fi
            return 0
            ;;
          *)
            show_message error "Unknown choice" "Choose a shown number, B, or press Enter."
            continue
            ;;
        esac
        ;;
    esac

    printf -v "$target_var" '%s' "$selected"
    save_config
    show_message success "Mapping saved" "$(mapping_label "$role") now uses $(model_label "$selected")."
    return 0
  done
}
```

Retain the internal `TIER_MENU_*` array names; renaming those implementation details adds churn without changing behavior.

- [ ] **Step 5: Add the fifth configuration action**

Replace `render_config_menu` and update `configure_menu` navigation/cases:

```bash
render_config_menu() {
  local cursor="$1"
  screen_header "Configure model mappings" "Changes are saved to $CONFIG_FILE"
  print_mappings
  printf '\n%sEDIT%s\n\n' "$BOLD" "$RESET" >&2
  menu_choice "$cursor" 1 1 'Change Opus mapping'
  menu_choice "$cursor" 2 2 'Change Sonnet mapping'
  menu_choice "$cursor" 3 3 'Change Haiku mapping'
  menu_choice "$cursor" 4 4 'Change subagent mapping'
  menu_choice "$cursor" 5 5 'Change default startup tier'
  printf '\n  %s↑/↓ move · Enter select · Esc back · 1–5 shortcut%s\n' "$DIM" "$RESET" >&2
}
```

Within `configure_menu`, use five rows and the non-conflicting `a` shortcut for the subagent action:

```bash
menu_navigate 5 "$cursor" render_config_menu 'oshad'
```

```bash
case "$reply" in
  1|o|O|opus|Opus) configure_mapping opus ;;
  2|s|S|sonnet|Sonnet) configure_mapping sonnet ;;
  3|h|H|haiku|Haiku) configure_mapping haiku ;;
  4|a|A|agent|Agent|subagent|Subagent) configure_mapping subagent ;;
  5|d|D|default|Default) configure_default_tier ;;
  ""|b|B) return 0 ;;
  *) show_message error "Unknown choice" "Choose 1–5 or B." ;;
esac
```

Update any remaining calls from `configure_tier` to `configure_mapping`. Do not alter the four-entry startup menu or `model_for_tier`.

- [ ] **Step 6: Run focused UI, smoke, and syntax tests**

Run:

```bash
bash -n bin/claude-janus
bash -n tests/smoke.sh
python3 tests/subagent_mapping.py
python3 tests/arrow_keys.py
bash tests/smoke.sh
```

Expected: all commands exit `0`; the new pseudo-TTY test reports `PASS` for configuration, persistence, export, primary Sonnet launch, and no `--model subagent`; the existing arrow test still reports `PASS Haiku launch`.

- [ ] **Step 7: Run the CI entry point**

Run:

```bash
./tests/run.sh
```

Expected: unit tests, smoke tests, existing arrow-key tests, and the new subagent mapping test all pass.

- [ ] **Step 8: Commit the interactive mapping feature**

```bash
git add bin/claude-janus tests/smoke.sh tests/subagent_mapping.py tests/run.sh
git commit -m "Add subagent mapping configuration

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: Document the fourth mapping and corrected compatibility contract

**Files:**
- Modify: `README.md:99-107`
- Modify: `README.md:152-166`
- Modify: `docs/2026-07-22-official-janus-companion-design.md:75-90`
- Modify: `CLAUDE.md` sections `Launcher and child-process contract`, `Router config and persisted state`, and `Catalog, mappings, and interactive UI`

**Interfaces:**
- Consumes: final behavior from Tasks 1 and 2.
- Produces: user-facing and maintainer-facing documentation that consistently describes an independent subagent mapping with effective-Sonnet legacy fallback.

- [ ] **Step 1: Check documentation currently lacks or contradicts the new behavior**

Run:

```bash
grep -n "assign a router model independently" README.md
grep -n "CLAUDE_CODE_SUBAGENT_MODEL" README.md docs/2026-07-22-official-janus-companion-design.md CLAUDE.md
grep -n "typically Haiku mapping" docs/2026-07-22-official-janus-companion-design.md
```

Expected before editing:

- README says mappings are independent only for Opus, Sonnet, and Haiku.
- README lists `CLAUDE_CODE_SUBAGENT_MODEL` without explaining its source.
- The older design says the variable typically follows Haiku.
- `CLAUDE.md` describes mapping state generically but does not name `SUBAGENT_MODEL`.

- [ ] **Step 2: Update README configuration behavior**

Replace the mapping paragraph at `README.md:99` with:

```markdown
Use **Configure mappings** to assign router models independently to Opus, Sonnet, Haiku, and Claude Code subagents. The menu loads your Janus **live catalog** when reachable: verified presets appear only if Janus advertises them, and additional models from `/v1/models` are listed as "From Janus" options. If the catalog is unavailable, the menu falls back to built-in presets.

Mappings are saved at:

```text
~/.config/claude-janus/mappings.conf
```

Existing mapping files without `SUBAGENT_MODEL` continue to work: the subagent route inherits the effective saved Sonnet mapping until a separate subagent mapping is chosen and saved. The subagent route is not a primary startup tier; `CLAUDE_JANUS_TIER` and Claude Code's `/model` selector remain `opus`, `sonnet`, or `haiku`.

Inside Claude Code, `/model` switches between the saved primary tier mappings.
```

After the child environment variable list, add:

```markdown
`CLAUDE_CODE_SUBAGENT_MODEL` comes from the independently saved `SUBAGENT_MODEL` route. It does not change the primary `--model` argument.
```

- [ ] **Step 3: Correct the prior companion design**

Replace the stale row with:

```markdown
| `CLAUDE_CODE_SUBAGENT_MODEL` | Saved independent subagent mapping; legacy mapping files fall back to their effective Sonnet mapping |
```

Do not rewrite the rest of the historical design document.

- [ ] **Step 4: Update and preserve the root CLAUDE.md**

In `CLAUDE.md`, make the launch contract explicit:

```markdown
- Set `CLAUDE_CODE_SUBAGENT_MODEL` from the independently persisted `SUBAGENT_MODEL`; legacy files without that key inherit the effective Sonnet mapping.
```

Replace the generic mapping-state sentence with:

```markdown
`router.conf` contains `JANUS_BASE_URL` and `JANUS_API_KEY`. `mappings.conf` stores `OPUS_MODEL`, `SONNET_MODEL`, `HAIKU_MODEL`, `SUBAGENT_MODEL`, and `DEFAULT_TIER`. Legacy files without `SUBAGENT_MODEL` inherit their effective Sonnet route. Both files are private user state and are written with mode `600`; the containing configuration directory is kept at mode `700` when possible.
```

Update the catalog/UI introduction to say the launcher has four persisted mapping roles, while only three are primary startup tiers. Preserve all other existing repository guidance; this file was created earlier in the session and is intentionally uncommitted until this documentation task.

- [ ] **Step 5: Verify documentation consistency**

Run:

```bash
! grep -R "typically Haiku mapping" README.md docs/2026-07-22-official-janus-companion-design.md CLAUDE.md
grep -n "SUBAGENT_MODEL" README.md docs/2026-07-22-official-janus-companion-design.md CLAUDE.md
grep -n "not a primary startup tier" README.md
```

Expected: the negative grep exits `0`; all three documents describe `SUBAGENT_MODEL`; README explicitly preserves the three-tier primary selector boundary.

- [ ] **Step 6: Run the full suite after documentation changes**

Run:

```bash
./tests/run.sh
git diff --check
```

Expected: all tests pass and `git diff --check` prints no whitespace errors.

- [ ] **Step 7: Commit documentation, including the previously uncommitted CLAUDE.md**

```bash
git add README.md docs/2026-07-22-official-janus-companion-design.md CLAUDE.md
git commit -m "Document subagent model mapping

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: Final verification against the approved specification

**Files:**
- Verify only: `bin/claude-janus`
- Verify only: `tests/smoke.sh`
- Verify only: `tests/arrow_keys.py`
- Verify only: `tests/subagent_mapping.py`
- Verify only: `README.md`
- Verify only: `CLAUDE.md`

**Interfaces:**
- Consumes: all implementation and documentation commits from Tasks 1–3.
- Produces: evidence that the complete feature meets the acceptance criteria with a clean, reviewable working tree.

- [ ] **Step 1: Run every syntax check documented for modified shell files**

```bash
bash -n bin/claude-janus
bash -n tests/smoke.sh
bash -n tests/run.sh
```

Expected: all commands exit `0` with no output.

- [ ] **Step 2: Run the complete CI suite**

```bash
./tests/run.sh
```

Expected: every unit, smoke, and pseudo-TTY check passes, including the new independent subagent mapping checks.

- [ ] **Step 3: Inspect the launch and persistence boundaries directly**

Run:

```bash
grep -nE '^(SUBAGENT_MODEL=|.*SUBAGENT_MODEL\)|.*CLAUDE_CODE_SUBAGENT_MODEL=)' bin/claude-janus
grep -nE 'valid_tier|--model subagent|CLAUDE_JANUS_TIER=subagent' bin/claude-janus tests/smoke.sh tests/subagent_mapping.py
git diff --check
git status --short
```

Expected:

- Launcher output shows initialization, load, save, fallback, and export sites for `SUBAGENT_MODEL`.
- `valid_tier` still lists only `opus|sonnet|haiku`.
- Any `subagent` primary-tier strings appear only in negative regression assertions, never launch code.
- `git diff --check` is clean.
- `git status --short` is empty after the three task commits, apart from the implementation plan itself if the plan has not yet been committed.

- [ ] **Step 4: Commit the implementation plan if it remains untracked**

```bash
git add docs/superpowers/plans/2026-07-22-subagent-model-mapping.md
git commit -m "Add subagent mapping implementation plan

Co-Authored-By: Claude <noreply@anthropic.com>"
```

If the plan was committed before execution, skip this step rather than creating an empty commit.

- [ ] **Step 5: Report verified outcomes**

Report all of the following with the exact commands run:

- independent subagent selection and persistence works;
- legacy files inherit effective Sonnet;
- first-save files include `SUBAGENT_MODEL`;
- primary tier selection still rejects `subagent`;
- dry-run redaction remains intact;
- `./tests/run.sh` passes;
- final `git status --short` state.
