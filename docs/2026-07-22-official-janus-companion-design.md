# claude-janus as Official Janus Claude Code Companion

**Date:** 2026-07-22  
**Status:** Approved design (pending implementation plan)  
**Repo:** [amanverasia/claude-janus](https://github.com/amanverasia/claude-janus)  
**Related:** [amanverasia/Janus](https://github.com/amanverasia/Janus)

## Problem

Claude Code talks Anthropic Messages (`POST /v1/messages`) and expects Opus / Sonnet / Haiku tier aliases for `/model`. Janus is a local-first router that can serve those requests and map them to any configured upstream. Today, users must manually export `ANTHROPIC_*` env vars and invent model IDs. Mistakes (wrong base URL, leftover Anthropic API keys, raw model IDs fighting Claude Code’s selector) cause intermittent failures.

`claude-janus` already solves the core launch contract, but it is not yet the official product path: hardcoded curated models, weak first-run setup, and Janus docs still describe raw env exports.

## Goal

Make `claude-janus` the **official Claude Code → Janus onboarding companion**: one install, first-run wizard, live model mapping from Janus, launch Claude Code so `/model` keeps working.

## Non-goals

- Rewriting the launcher in Python/Go
- Folding into the Janus CLI (`janus claude`)
- Claude OAuth / subscription login (stays in Janus dashboard)
- Shell-profile rewriting or system HTTPS MITM
- Changing Janus’s canonical formats ↔ providers architecture

## Approach

**Hybrid companion:** keep `claude-janus` as a standalone bash tool, upgrade discovery and onboarding, and wire Janus docs/dashboard to recommend it as the preferred Claude Code setup.

## Product surface

```text
User installs claude-janus
        │
        ▼
First run: router.conf missing/placeholder?
        │ yes → wizard (URL + API key; probe localhost:20128)
        ▼
Health: GET /v1/health + GET /v1/models
        │
        ▼
Map Opus / Sonnet / Haiku from live catalog (fallback presets if unreachable)
        │
        ▼
Launch: ANTHROPIC_BASE_URL + ANTHROPIC_AUTH_TOKEN + DEFAULT_*_MODEL
         claude --model opus|sonnet|haiku
```

## Requirements

### 1. First-run setup

- If `~/.config/claude-janus/router.conf` is missing or still contains placeholders, run an interactive setup (skipped for `--help` / `--version` / dry-run with full env overrides).
- Prompt for `JANUS_BASE_URL` and `JANUS_API_KEY`.
- Optionally probe common local endpoints (`http://127.0.0.1:20128`, `http://localhost:20128`) and offer the first healthy one.
- Write `router.conf` mode `600`; never overwrite a non-placeholder existing file without confirmation.
- Environment variables continue to override the file.

### 2. Live model catalog

- Fetch authenticated `GET {base}/v1/models` with Bearer token.
- Parse both shapes:
  - OpenAI-style: `{ "object": "list", "data": [ { "id": "..." } ] }`
  - Anthropic-style: `{ "data": [ { "id": "..." } ], ... }` (ids may be bare or `prefix/model`)
- Prefer exact `id` match for validation; when Janus returns bare Anthropic ids, also accept matching `prefix/model` entries from the OpenAI list if both are present.
- Use a normal (non–Claude Code) User-Agent so Janus returns the OpenAI-shaped list by default; still tolerate the Claude-shaped response.
- Curated presets remain as labeled suggestions when the catalog is available (intersect with live ids) and as offline fallbacks when the catalog is unreachable.

### 3. Health check

- On interactive startup (unless `CLAUDE_JANUS_SKIP_CHECK=1`), call `/v1/health` and `/v1/models`.
- Fail with actionable messages for: connection refused, 401/403, empty model list, TLS/DNS errors.
- Non-interactive `CLAUDE_JANUS_TIER=...` keeps the same check unless skipped.

### 4. Launch contract (unchanged semantics)

For the child Claude Code process only:

| Variable | Behavior |
| --- | --- |
| `ANTHROPIC_BASE_URL` | Janus base URL without trailing `/v1` confusion documented; Claude appends `/v1/messages` |
| `ANTHROPIC_AUTH_TOKEN` | Janus API key |
| `ANTHROPIC_API_KEY` | Blanked to avoid accidental Anthropic cloud fallback |
| `ANTHROPIC_DEFAULT_OPUS_MODEL` | Saved Opus mapping |
| `ANTHROPIC_DEFAULT_SONNET_MODEL` | Saved Sonnet mapping |
| `ANTHROPIC_DEFAULT_HAIKU_MODEL` | Saved Haiku mapping |
| `CLAUDE_CODE_SUBAGENT_MODEL` | Follow existing behavior (typically Haiku mapping) |
| `ANTHROPIC_MODEL` | Left unset |

Start Claude Code with `--model opus|sonnet|haiku`, never a raw Janus model id as the primary `--model` flag.

### 5. Janus product wiring

In the Janus repo (separate change set / PR):

- Update `docs/client-setup.md` Claude Code section to recommend `claude-janus` install + link.
- Update dashboard Claude Code setup card copy to point at the companion.
- Optional README blurb under client setup.

### 6. Tests & CI

- Extend smoke tests for: first-run wizard (scripted), catalog parse helpers, placeholder vs live config, health failure messaging.
- Keep existing env-precedence, dry-run redaction, installer permission, and help-passthrough tests.
- CI continues to run `./tests/run.sh` on push/PR.

## File responsibilities (implementation guidance)

| Path | Role |
| --- | --- |
| `bin/claude-janus` | Launcher + TUI + setup/catalog/health (stay one script unless a clear split helps tests) |
| `config.example` | Example router.conf |
| `install.sh` | Install binary + seed config |
| `tests/smoke.sh` | End-to-end smoke |
| `tests/` helpers | Catalog/fixtures as needed |
| `README.md` | Companion positioning + Janus link |
| Janus `docs/client-setup.md` | Official recommendation |

## Success criteria

1. Fresh machine: `./install.sh` → enter URL/key (or accept localhost probe) → pick three tiers from live catalog → Claude Code chats and uses tools via Janus.
2. Existing users: `router.conf` and `mappings.conf` preserved on upgrade.
3. Janus docs/dashboard present `claude-janus` as the preferred Claude Code path.
4. Smoke tests pass in CI without a live Janus (mocked curl/jq fixtures where needed).

## Risks & mitigations

| Risk | Mitigation |
| --- | --- |
| Hardcoded presets drift from Janus catalog | Live catalog primary; presets are suggestions only |
| Claude UA changes `/v1/models` shape | Fixed non-Claude UA for catalog fetch; dual parsers |
| First-run prompts break automation | Env overrides + `CLAUDE_JANUS_TIER` skip menus; help bypasses config |
| Dual-repo doc drift | Ship Janus docs PR alongside companion release notes |

## Implementation order

1. Catalog fetch/parse + validation helpers + tests  
2. First-run wizard + localhost probe  
3. Health check messaging  
4. TUI: pick from live catalog (presets as shortcuts)  
5. README + Janus docs/dashboard wiring  
6. Smoke/CI polish  

---

## Spec self-review

- No unresolved placeholders.
- Scope limited to companion + Janus docs wiring; OAuth stays in Janus.
- Launch env contract matches current working behavior.
- Dual `/v1/models` shapes covered after Janus Claude Code capability responses.
