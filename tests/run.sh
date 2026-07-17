#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/tests/smoke.sh"
python3 "$ROOT/tests/arrow_keys.py"
