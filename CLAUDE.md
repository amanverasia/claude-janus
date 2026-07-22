# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`claude-janus` is the official Claude Code companion for a Janus router. It is a Bash 4+ launcher that routes Claude Code through Janus's Anthropic-compatible API while preserving Claude Code's Opus, Sonnet, and Haiku tier interface.

The project deliberately remains a standalone Bash tool. Do not fold it into a Janus CLI or rewrite it in another language without an explicit change in project direction.

## Requirements

Development and runtime paths assume:

- Bash 4+
- `curl`
- `jq` for Janus catalog parsing and custom model validation
- Python 3 for the pseudo-TTY arrow-key regression test
- A `claude` executable on `PATH` when running the actual launcher

The test suite does not contact a real Janus server. It creates temporary fake `claude` and `curl` executables and uses catalog fixtures.

## Commands

Run all checks exactly as CI does:

```bash
./tests/run.sh
```

Run focused test layers:

```bash
# Unit tests for URL normalization, catalog parsing, membership, and empty-catalog health checks
bash tests/test_janus_api.sh

# End-to-end launcher, setup, installer, environment, and health-check smoke coverage
bash tests/smoke.sh

# Pseudo-terminal regression test for arrow-key menu navigation
python3 tests/arrow_keys.py
```

Run Bash syntax checks. There is no separately configured lint framework:

```bash
bash -n bin/claude-janus
bash -n lib/janus_api.sh
bash -n install.sh
bash -n tests/test_janus_api.sh
bash -n tests/smoke.sh
```

Install the launcher locally from a checkout:

```bash
./install.sh
```

Exercise launch construction without invoking Claude Code:

```bash
JANUS_BASE_URL=https://router.example \
JANUS_API_KEY=example-key \
CLAUDE_JANUS_TIER=sonnet \
CLAUDE_JANUS_SKIP_CHECK=1 \
CLAUDE_JANUS_DRYRUN=1 \
bin/claude-janus
```

Use `CLAUDE_JANUS_TIER=opus|sonnet|haiku` for scriptable, non-interactive launches. The normal launcher menu is enabled only on an interactive terminal; dry-run mode and non-TTY invocations remain scroll-safe.

## Architecture

### Launcher and child-process contract

`bin/claude-janus` is the main executable. It owns:

1. Reading router credentials from `router.conf`, with `JANUS_BASE_URL` and `JANUS_API_KEY` environment variables taking precedence.
2. First-run configuration, including optional localhost Janus detection.
3. Persistent per-tier mappings and the terminal menu used to edit them.
4. Optional health validation before launch.
5. Constructing and `exec`ing the real `claude` process.

The launcher is intentionally isolated: it does not alter the user's shell profile or replace the ordinary `claude` command. It sets Janus-specific environment variables only on the child Claude Code process.

Preserve the launch contract as one unit:

- Set `ANTHROPIC_BASE_URL` to the normalized Janus base URL, without a trailing `/v1`.
- Set `ANTHROPIC_AUTH_TOKEN` to the Janus API key.
- Explicitly blank `ANTHROPIC_API_KEY` and unset `ANTHROPIC_MODEL` so unrelated Anthropic credentials or a raw model override cannot bypass tier selection.
- Set `ANTHROPIC_DEFAULT_OPUS_MODEL`, `ANTHROPIC_DEFAULT_SONNET_MODEL`, and `ANTHROPIC_DEFAULT_HAIKU_MODEL` from saved mappings.
- Set `CLAUDE_CODE_SUBAGENT_MODEL` from the independently persisted `SUBAGENT_MODEL`; legacy files without that key inherit the effective Sonnet mapping.
- Invoke Claude Code with `--model opus`, `--model sonnet`, or `--model haiku`, rather than passing a raw Janus model ID as `--model`.

This preserves Claude Code's internal `/model` tier selector while allowing each tier to map to an arbitrary Janus model.

### Router config and persisted state

The router config path is:

```text
${CLAUDE_JANUS_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-janus/router.conf}
```

The mapping state is:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/claude-janus/mappings.conf
```

`router.conf` contains `JANUS_BASE_URL` and `JANUS_API_KEY`. `mappings.conf` stores `OPUS_MODEL`, `SONNET_MODEL`, `HAIKU_MODEL`, `SUBAGENT_MODEL`, and `DEFAULT_TIER`. Legacy files without `SUBAGENT_MODEL` inherit their effective Sonnet route. Both files are private user state and are written with mode `600`; the containing configuration directory is kept at mode `700` when possible.

The installer puts the executable in `${CLAUDE_JANUS_INSTALL_DIR:-$HOME/.local/bin}` and copies the shared library beneath `${XDG_DATA_HOME:-$HOME/.local/share}/claude-janus/lib`. It seeds `router.conf` only when one does not already exist, so upgrades must preserve user configuration.

### Janus API helper boundary

`lib/janus_api.sh` is safe to source and must remain side-effect free at load time. It centralizes reusable HTTP and catalog behavior:

- Normalize a base URL by removing a trailing slash and optional `/v1`.
- Fetch the authenticated `GET /v1/models` catalog using a non-Claude user agent.
- Extract model IDs and test exact catalog membership with `jq`.
- Check readiness by requiring both a reachable `GET /v1/health` and a non-empty authenticated `GET /v1/models` result.

Keep parsing, HTTP behavior, and exit-code meanings in this library when adding Janus API behavior. The launcher should consume these helpers rather than reimplementing them.

### Catalog, mappings, and interactive UI

The launcher has four persisted mapping roles—Opus, Sonnet, Haiku, and Claude Code subagents—while only Opus, Sonnet, and Haiku are primary startup tiers. It has curated model presets but uses the live authenticated Janus model catalog when available:

- If the catalog succeeds and is non-empty, only advertised presets are shown, followed by additional catalog models.
- If the catalog is unavailable, preset models are used as the offline fallback.
- A custom model ID is checked against the live catalog when possible; if the catalog cannot be reached, a syntactically valid value may still be saved with a warning.

The terminal UI lives in the launcher and is guarded by TTY detection. It switches the terminal to non-canonical/no-echo mode for the complete render-to-keypress cycle, restores it through exit/signal traps, and recognizes arrows, Home/End, Enter, Escape, numeric shortcuts, and contextual letter shortcuts. Changes to menu input or rendering need coverage from `tests/arrow_keys.py`, not only non-interactive smoke coverage.

### Health-check behavior

On ordinary launches, the wrapper checks Janus health and the authenticated model catalog before launching Claude Code. A failure is warning-only by default. `CLAUDE_JANUS_STRICT_CHECK=1` changes this to an exit before Claude Code starts; `CLAUDE_JANUS_SKIP_CHECK=1` disables the optional check.

Preserve the health helper's distinct results:

- exit status `1`: `/v1/health` was unreachable;
- exit status `2`: authenticated `/v1/models` failed or returned no model IDs.

These distinctions drive launcher diagnostics and smoke-test expectations.

## Testing conventions

- `tests/test_janus_api.sh` is the focused unit-test entry point for `lib/janus_api.sh`. Catalog fixtures cover OpenAI-style and Anthropic-style responses because both expose IDs under `.data[]`.
- `tests/smoke.sh` checks syntax, absent and placeholder configuration failure, first-run non-interactive setup, config/environment precedence, dry-run secret redaction, installation permissions, `--help` passthrough, and strict health-check failures.
- `tests/arrow_keys.py` uses a pseudo-TTY and fake `claude` executable to verify that arrow navigation selects the intended tier, renders a highlight, does not leak escape sequences, and exits successfully.
- CI runs `./tests/run.sh` on pushes and pull requests. Keep the complete suite self-contained and independent of a live Janus instance.

## Behavior to preserve

- Janus must provide authenticated `GET /v1/models`, `GET /v1/health`, and Anthropic-compatible `POST /v1/messages`.
- The configured base URL normally omits `/v1`; the launcher normalizes an already-suffixed URL.
- First run may probe `http://127.0.0.1:20128` and `http://localhost:20128`. For automation, `CLAUDE_JANUS_SETUP_BASE_URL` and `CLAUDE_JANUS_SETUP_API_KEY` provide non-interactive setup inputs.
- `CLAUDE_JANUS_DRYRUN=1` must not print the router token value; it reports only that `ANTHROPIC_AUTH_TOKEN` is set.
- `--help` and `--version` pass through to Claude Code without requiring router configuration or printing launcher startup status.
