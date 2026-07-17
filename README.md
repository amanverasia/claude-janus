# claude-janus

An interactive launcher for running [Claude Code](https://docs.anthropic.com/en/docs/claude-code) through a Janus router that exposes the Anthropic Messages API.

`claude-janus` keeps separate router model mappings for Claude Code's **Opus**, **Sonnet**, and **Haiku** tiers. It provides a keyboard-driven terminal UI and launches Claude Code through its built-in tier aliases, so `/model` continues to work inside Claude Code.

## Features

- Independent Opus, Sonnet, and Haiku model mappings
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

The base URL should normally omit `/v1`; Claude Code appends `/v1/messages`.

Make sure `~/.local/bin` is on your `PATH`.

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

Use **Configure mappings** to assign a router model independently to Opus, Sonnet, and Haiku. Mappings are saved at:

```text
~/.config/claude-janus/mappings.conf
```

Inside Claude Code, `/model` switches between the saved tier mappings.

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
