#!/usr/bin/env bash
set -euo pipefail
umask 077

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${CLAUDE_JANUS_INSTALL_DIR:-$HOME/.local/bin}"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/claude-janus"
TARGET="$INSTALL_DIR/claude-janus"
ROUTER_CONFIG="$CONFIG_DIR/router.conf"

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR"
chmod 700 "$CONFIG_DIR" 2>/dev/null || true
install -m 0755 "$ROOT_DIR/bin/claude-janus" "$TARGET"

LIB_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-janus"
mkdir -p "$LIB_DIR"
cp -a "$ROOT_DIR/lib/." "$LIB_DIR/lib/" 2>/dev/null || {
  mkdir -p "$LIB_DIR/lib"
  install -m 0644 "$ROOT_DIR/lib/janus_api.sh" "$LIB_DIR/lib/janus_api.sh"
}

if [[ ! -f "$ROUTER_CONFIG" ]]; then
  install -m 0600 "$ROOT_DIR/config.example" "$ROUTER_CONFIG"
  created_config=1
else
  chmod 600 "$ROUTER_CONFIG" 2>/dev/null || true
  created_config=0
fi

printf 'Installed claude-janus → %s\n' "$TARGET"
if [[ $created_config -eq 1 ]]; then
  printf 'Created configuration → %s\n' "$ROUTER_CONFIG"
  printf 'Edit that file and replace the example URL and API key before launching.\n'
else
  printf 'Preserved existing configuration → %s\n' "$ROUTER_CONFIG"
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*) ;;
  *) printf 'Note: add %s to PATH to run claude-janus directly.\n' "$INSTALL_DIR" ;;
esac
