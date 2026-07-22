# claude-janus

**Official [Claude Code](https://docs.anthropic.com/en/docs/claude-code) companion for [Janus](https://github.com/amanverasia/Janus)** — the multi-provider AI gateway.

`claude-janus` launches Claude Code through your Janus router's Anthropic-compatible Messages API. It keeps separate model mappings for Claude Code's **Opus**, **Sonnet**, and **Haiku** tiers, provides a keyboard-driven terminal UI, and leaves your shell profile untouched.

For Janus server setup and other client options, see the [Janus client-setup guide](https://amanverasia.github.io/Janus/client-setup/).

## Features

- Independent Opus, Sonnet, and Haiku model mappings
- **Live catalog** — tier menus query authenticated `GET /v1/models` and show models your Janus instance actually exposes
- Interactive first-run setup with localhost Janus detection
- Full-screen terminal menu with arrow-key navigation
- Number and letter shortcuts
- Saved default startup tier
- Authenticated `/v1/models` validation for custom model IDs
- Isolated environment: does not modify your shell profile
- Script-friendly dry-run and non-interactive modes
- Router credentials stored outside the executable

## Requirements

- Bash 4+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) available as `claude`
- `curl`
- `jq` (used to validate custom model IDs)
- A Janus router exposing:
  - `GET /v1/models`
  - `POST /v1/messages`
  - Bearer-token authentication

## Install

```bash
git clone https://github.com/amanverasia/claude-janus.git
cd claude-janus
./install.sh
```

The installer places the launcher at:

```text
~/.local/bin/claude-janus
```

and creates this private configuration file if it does not exist:

```text
~/.config/claude-janus/router.conf
```

Edit it:

```ini
JANUS_BASE_URL=https://your-janus-router.example
JANUS_API_KEY=replace-with-your-key
```

The base URL should normally omit `/v1`; Claude Code appends `/v1/messages`. If your URL already includes `/v1`, `claude-janus` normalizes it.

Make sure `~/.local/bin` is on your `PATH`.

## First-run setup

On the first launch, if `router.conf` is missing or still contains placeholders, `claude-janus` runs interactive setup:

1. Probes `http://127.0.0.1:20128` and `http://localhost:20128` for a local Janus `/v1/health` endpoint
2. Prompts for a Janus base URL and API key if needed
3. Writes `router.conf` at mode `600`

For CI or scripted installs, skip the prompts by exporting both setup variables before the first run:

```bash
export CLAUDE_JANUS_SETUP_BASE_URL='http://127.0.0.1:20128'
export CLAUDE_JANUS_SETUP_API_KEY='sk-janus-yourkey'
CLAUDE_JANUS_TIER=sonnet CLAUDE_JANUS_DRYRUN=1 CLAUDE_JANUS_SKIP_CHECK=1 claude-janus
```

This writes `router.conf` non-interactively. Environment variables (`JANUS_BASE_URL`, `JANUS_API_KEY`) still override the file on every run.

## Usage

```bash
claude-janus
```

### Keyboard controls

| Key | Action |
| --- | --- |
| `↑` / `↓` | Move selection |
| `Enter` | Select highlighted option |
| `Home` / `End` | Jump to first/last option |
| `Esc` | Back or cancel |
| `1`–`9` | Select by number |
| `o`, `s`, `h`, `c` | Contextual shortcuts |

Use **Configure mappings** to assign router models independently to Opus, Sonnet, Haiku, and Claude Code subagents. The menu loads your Janus **live catalog** when reachable: verified presets appear only if Janus advertises them, and additional models from `/v1/models` are listed as "From Janus" options. If the catalog is unavailable, the menu falls back to built-in presets.

Mappings are saved at:

```text
~/.config/claude-janus/mappings.conf
```

Existing mapping files without `SUBAGENT_MODEL` continue to work: the subagent route inherits the effective saved Sonnet mapping until a separate subagent mapping is chosen and saved. The subagent route is not a primary startup tier; `CLAUDE_JANUS_TIER` and Claude Code's `/model` selector remain `opus`, `sonnet`, or `haiku`.

Inside Claude Code, `/model` switches between the saved primary tier mappings.

## Non-interactive usage

Choose a tier without opening the menu:

```bash
CLAUDE_JANUS_TIER=sonnet claude-janus -p "Explain this repository"
```

Inspect the generated command and environment without launching Claude Code:

```bash
CLAUDE_JANUS_DRYRUN=1 CLAUDE_JANUS_TIER=haiku claude-janus
```

Override router configuration for one invocation:

```bash
JANUS_BASE_URL=https://router.example \
JANUS_API_KEY=your-key \
CLAUDE_JANUS_TIER=opus \
claude-janus
```

Skip the optional startup reachability check:

```bash
CLAUDE_JANUS_SKIP_CHECK=1 claude-janus
```

Fail instead of warning when the health check does not pass:

```bash
CLAUDE_JANUS_STRICT_CHECK=1 claude-janus
```

By default, a failed `/v1/health` or authenticated `/v1/models` check prints a warning and Claude Code still launches. With `CLAUDE_JANUS_STRICT_CHECK=1`, the launcher exits before starting Claude Code.

Use another configuration path:

```bash
CLAUDE_JANUS_CONFIG=/path/to/router.conf claude-janus
```

## How it works

The launcher sets these variables only for the child Claude Code process:

```text
ANTHROPIC_BASE_URL
ANTHROPIC_AUTH_TOKEN
ANTHROPIC_API_KEY=""
ANTHROPIC_DEFAULT_OPUS_MODEL
ANTHROPIC_DEFAULT_SONNET_MODEL
ANTHROPIC_DEFAULT_HAIKU_MODEL
CLAUDE_CODE_SUBAGENT_MODEL
```

`CLAUDE_CODE_SUBAGENT_MODEL` comes from the independently saved `SUBAGENT_MODEL` route. It does not change the primary `--model` argument.

It deliberately leaves `ANTHROPIC_MODEL` unset and starts Claude Code with `--model opus`, `--model sonnet`, or `--model haiku`. This avoids fighting Claude Code's internal model selector.

## Security

- Never commit a real API key.
- Keep `router.conf` at mode `600`.
- The installer does not overwrite an existing `router.conf`.
- Environment variables override the config file, which is useful for secret managers and CI.
- This launcher blanks `ANTHROPIC_API_KEY` to avoid accidental fallback to unrelated Anthropic credentials.

## Updating

```bash
cd claude-janus
git pull
./install.sh
```

Your existing router configuration and tier mappings are preserved.

## License

[MIT](LICENSE)
