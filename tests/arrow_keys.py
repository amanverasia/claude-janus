#!/usr/bin/env python3
"""Pseudo-TTY regression test for arrow-key navigation."""
import os
import pty
import re
import select
import sys
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
tmp = Path(tempfile.mkdtemp(prefix="claude-janus-arrow-test-"))
(tmp / "bin").mkdir()
(tmp / "config").mkdir()
fake = tmp / "bin" / "claude"
fake.write_text("#!/usr/bin/env bash\nprintf 'ARGS:'; printf ' <%s>' \"$@\"; echo\n")
fake.chmod(0o755)

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

wait_for(b"Esc/Q cancel")
# Default is Sonnet. Down selects Haiku; left/right are ignored; Enter launches.
for key in (b"\x1b[B", b"\x1b[D", b"\x1b[C", b"\r"):
    os.write(fd, key)
    time.sleep(0.12)

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
checks = {
    "Haiku launch": "ARGS: <--model> <haiku>" in text,
    "highlight": "❯" in text,
    "no escaped arrows": all(token not in text for token in ("^[[A", "^[[B", "^[[C", "^[[D")),
    "success": os.waitstatus_to_exitcode(status) == 0,
}
for name, ok in checks.items():
    print(("PASS" if ok else "FAIL"), name)
if not all(checks.values()):
    print(text)
    sys.exit(1)
