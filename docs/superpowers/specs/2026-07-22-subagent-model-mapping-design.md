# Independent Subagent Model Mapping Design

## Summary

`claude-janus` currently exports `CLAUDE_CODE_SUBAGENT_MODEL`, but always assigns it the effective Sonnet route. The launcher independently configures and persists Opus, Sonnet, and Haiku mappings, while the subagent model has no corresponding state, configuration UI, or direct test coverage.

Add `SUBAGENT_MODEL` as a fourth independent persisted model mapping. It will use the same live Janus catalog and custom-model selection flow as the existing mappings, while remaining separate from Claude Code's primary `opus|sonnet|haiku` startup tiers.

## Goals

- Allow users to map `CLAUDE_CODE_SUBAGENT_MODEL` to any advertised or custom Janus model.
- Configure the mapping through the existing interactive mapping menu.
- Persist the mapping in `mappings.conf`.
- Preserve current behavior for existing users by defaulting legacy configurations to their effective Sonnet mapping.
- Verify the exact model values exported to Claude Code.

## Non-goals

- Add `subagent` as a primary Claude Code tier.
- Allow `CLAUDE_JANUS_TIER=subagent` or launch Claude Code with `--model subagent`.
- Change the behavior of Opus, Sonnet, Haiku, `DEFAULT_TIER`, or `/model` switching.
- Change Janus catalog parsing or health-check behavior.
- Add an automatic rewrite or standalone migration command for existing mapping files.

## Current Behavior

The launcher maintains three in-memory model values:

- `OPUS_MODEL`
- `SONNET_MODEL`
- `HAIKU_MODEL`

It loads and saves them in `mappings.conf`, allows users to change them from the live Janus catalog, and exports them as:

- `ANTHROPIC_DEFAULT_OPUS_MODEL`
- `ANTHROPIC_DEFAULT_SONNET_MODEL`
- `ANTHROPIC_DEFAULT_HAIKU_MODEL`

Claude Code is then launched with a tier alias such as `--model sonnet`. This preserves Claude Code's internal tier selector while routing the tier through Janus.

The launcher also exports:

```bash
export CLAUDE_CODE_SUBAGENT_MODEL="$SONNET_MODEL"
```

That assignment is not independently configurable or persisted.

## Configuration Model

### New state

Add an in-memory `SUBAGENT_MODEL` value and a matching optional persisted key:

```text
OPUS_MODEL=...
SONNET_MODEL=...
HAIKU_MODEL=...
SUBAGENT_MODEL=...
DEFAULT_TIER=...
```

`SUBAGENT_MODEL` uses the same model-value validation as the existing model keys: it must be nonempty and contain neither a newline nor `=`.

### Backward compatibility

Existing `mappings.conf` files do not contain `SUBAGENT_MODEL`. Loading such a file must remain valid.

The compatibility fallback is the **effective Sonnet mapping after configuration loading**, not merely the built-in Sonnet default. This preserves current behavior for users who previously customized `SONNET_MODEL`:

1. Initialize the three existing model defaults.
2. Load valid existing keys from `mappings.conf`.
3. If no valid `SUBAGENT_MODEL` was loaded, assign `SUBAGENT_MODEL="$SONNET_MODEL"`.
4. Perform the existing first-save check only after that fallback assignment, so a newly created `mappings.conf` contains the new key immediately.

An explicitly present but invalid `SUBAGENT_MODEL` is ignored and therefore also falls back to the effective Sonnet mapping.

The next normal configuration save writes `SUBAGENT_MODEL` alongside the other keys. No eager file rewrite is required merely for launching with a legacy file.

## Interactive Configuration

### Mapping display

The mapping summary gains a fourth row for the subagent route. It must not show the primary-tier default marker, because `DEFAULT_TIER` applies only to `opus`, `sonnet`, and `haiku`.

### Configuration menu

Add a `Change subagent mapping` action beside the three existing mapping actions.

The subagent action reuses the existing model-selection behavior:

- When the authenticated Janus catalog is available and nonempty, show advertised curated presets and additional catalog models.
- When the catalog is unavailable, show the curated presets as an offline fallback.
- Permit a custom model ID.
- Validate custom membership exactly when the catalog is reachable.
- If catalog lookup is unavailable, permit a syntactically valid custom value with the existing warning behavior.

### Tier boundaries

Do not add `subagent` to:

- `valid_tier`
- `DEFAULT_TIER` choices
- `CLAUDE_JANUS_TIER` choices
- startup menus
- `model_for_tier`
- the primary `--model` argument

The subagent route is an exported mapping role, not a Claude Code top-level model alias.

### Internal organization

The current mapping editor is structured around the three primary tiers. The implementation may either generalize it into a role-oriented mapping function or add a thin subagent-specific wrapper, provided that:

- all four mappings use the same catalog/custom-selection rules;
- startup-tier validation remains limited to the three primary aliases;
- the change does not duplicate Janus catalog parsing or HTTP behavior.

Prefer the smallest refactor that makes the fourth mapping clear without introducing indirect shell metaprogramming.

## Launch Contract

Replace the hardwired export with:

```bash
export CLAUDE_CODE_SUBAGENT_MODEL="$SUBAGENT_MODEL"
```

The remaining launch contract is unchanged:

- `ANTHROPIC_BASE_URL` points at the normalized Janus base URL.
- `ANTHROPIC_AUTH_TOKEN` contains the Janus token.
- `ANTHROPIC_API_KEY` is explicitly blank.
- `ANTHROPIC_MODEL` is unset.
- The three `ANTHROPIC_DEFAULT_*_MODEL` variables retain their current mappings.
- Claude Code receives `--model opus|sonnet|haiku`, unless the caller already supplied a model argument or requested help/version passthrough.

Dry-run output continues to display the resolved `CLAUDE_CODE_SUBAGENT_MODEL` value without exposing authentication material.

## Error Handling

- Missing `SUBAGENT_MODEL` is expected for legacy files and does not produce a warning or error.
- Invalid persisted `SUBAGENT_MODEL` is ignored using the same validation policy as invalid persisted primary model values; the effective Sonnet route is used.
- A catalog outage does not prevent selecting and saving a syntactically valid custom subagent model, matching existing mapping behavior.
- Persisted mappings are not revalidated against the live catalog on every launch; the subagent mapping follows the same policy as the primary mappings.
- The new mapping does not alter health-check exit codes or strict/warning behavior.

## Documentation

Update the README to explain that:

- the subagent route is independently configurable;
- it is persisted in `mappings.conf`;
- legacy configurations initialize it from their effective Sonnet mapping;
- it is not a primary startup tier or `/model` alias;
- `CLAUDE_CODE_SUBAGENT_MODEL` is exported from this mapping.

Correct `docs/2026-07-22-official-janus-companion-design.md`, whose launch-contract section says `CLAUDE_CODE_SUBAGENT_MODEL` typically follows the Haiku mapping. The executable has used Sonnet since the initial release, and this design deliberately preserves that behavior during migration.

Update the newly introduced root `CLAUDE.md` if implementation details make its launch-contract or mapping-state descriptions more specific. Keep it focused on stable repository guidance rather than duplicating the full user-facing README.

## Testing Strategy

### Export contract

Extend the fake `claude` executable in `tests/smoke.sh` to print `CLAUDE_CODE_SUBAGENT_MODEL` in addition to the existing model variables.

Before invoking the launcher, create a controlled `$XDG_CONFIG_HOME/claude-janus/mappings.conf` in which every route has a distinct value. Launch through the fake executable and assert:

- `ANTHROPIC_DEFAULT_OPUS_MODEL` equals `OPUS_MODEL`;
- `ANTHROPIC_DEFAULT_SONNET_MODEL` equals `SONNET_MODEL`;
- `ANTHROPIC_DEFAULT_HAIKU_MODEL` equals `HAIKU_MODEL`;
- `CLAUDE_CODE_SUBAGENT_MODEL` equals `SUBAGENT_MODEL`;
- the subagent value remains distinct from Sonnet when explicitly configured that way;
- the primary launch argument remains a valid `--model opus|sonnet|haiku` alias.

### Legacy configuration

Create a legacy mapping file containing customized Opus, Sonnet, and Haiku values but no `SUBAGENT_MODEL`. Assert that launch succeeds and `CLAUDE_CODE_SUBAGENT_MODEL` equals the customized Sonnet value.

### Persistence

Add a pseudo-TTY sequence that opens `Configure mappings`, selects `Change subagent mapping`, chooses a curated preset, and then exits. Assert that `$XDG_CONFIG_HOME/claude-janus/mappings.conf` contains the chosen `SUBAGENT_MODEL` plus all three primary mappings and `DEFAULT_TIER`.

The test may force catalog unavailability and use the offline preset list; catalog parsing is already covered separately. Do not expose private shell helpers solely to make persistence testing easier.

Also cover a first launch with no existing `mappings.conf` and assert that the file created by the existing first-save path already contains `SUBAGENT_MODEL` initialized from Sonnet.

### Interactive boundaries

Use pseudo-TTY coverage to verify that the configuration menu exposes the subagent mapping action. Retain coverage proving startup navigation emits only the three primary aliases. The subagent mapping must never result in `--model subagent`.

### Existing coverage

No Janus API helper changes are expected. `tests/test_janus_api.sh` should remain unchanged unless implementation reveals a genuinely shared helper requirement.

Run the complete suite:

```bash
./tests/run.sh
```

Also run Bash syntax checks for every modified shell file.

## Acceptance Criteria

- A user can independently choose and persist a subagent model using the existing mapping UI.
- `CLAUDE_CODE_SUBAGENT_MODEL` is exported from that independent mapping.
- Existing mapping files without the new key continue to launch and inherit their effective Sonnet route for subagents.
- Saving configuration adds the new key without discarding existing settings.
- `subagent` is not accepted or emitted as a primary tier alias.
- Catalog and custom-model behavior matches the three existing mappings.
- README and repository guidance accurately describe the behavior.
- The complete test suite passes with direct assertions over all four exported mappings.
