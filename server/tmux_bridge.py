"""Safe async wrappers around tmux subprocess calls."""

from __future__ import annotations

import asyncio
import re
from dataclasses import dataclass

_TARGET_RE = re.compile(r"^[a-zA-Z0-9_:.\-%]+$")
_TIMEOUT = 5.0


def _validate_target(target: str | None) -> str | None:
    if target is None:
        return None
    if not _TARGET_RE.match(target):
        raise ValueError(f"Invalid tmux target: {target!r}")
    return target


async def _run(*args: str) -> str:
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=_TIMEOUT)
    if proc.returncode != 0:
        msg = stderr.decode().strip() if stderr else f"tmux exited {proc.returncode}"
        raise RuntimeError(msg)
    return stdout.decode()


@dataclass
class PaneInfo:
    session_name: str
    window_index: int
    window_name: str
    pane_id: str


async def capture_pane(lines: int = 80, target: str | None = None) -> str:
    """Capture the current tmux pane content with ANSI escapes preserved.

    Uses -S to capture the specified number of lines from the bottom of the
    visible region. -e preserves ANSI escapes, -J joins wrapped lines.
    """
    _validate_target(target)
    cmd = ["tmux", "capture-pane", "-e", "-p", "-J", "-S", f"-{lines}"]
    if target:
        cmd.extend(["-t", target])
    return await _run(*cmd)


async def get_pane_info(target: str | None = None) -> PaneInfo:
    """Get info about the current or specified tmux pane."""
    _validate_target(target)
    fmt = "#{session_name}|#{window_index}|#{window_name}|#{pane_id}"
    cmd = ["tmux", "display-message", "-p", fmt]
    if target:
        cmd.extend(["-t", target])
    out = (await _run(*cmd)).strip()
    parts = out.split("|", 3)
    if len(parts) < 4:
        raise RuntimeError(f"Unexpected tmux display-message output: {out!r}")
    try:
        win_idx = int(parts[1])
    except ValueError:
        win_idx = 0
    return PaneInfo(
        session_name=parts[0],
        window_index=win_idx,
        window_name=parts[2],
        pane_id=parts[3],
    )


@dataclass
class SessionInfo:
    name: str
    windows: int
    attached: bool


async def list_sessions() -> list[SessionInfo]:
    """List all tmux sessions."""
    fmt = "#{session_name}|#{session_windows}|#{session_attached}"
    out = await _run("tmux", "list-sessions", "-F", fmt)
    sessions: list[SessionInfo] = []
    for line in out.strip().split("\n"):
        if not line:
            continue
        parts = line.split("|", 2)
        if len(parts) < 3:
            continue
        try:
            win_count = int(parts[1])
        except ValueError:
            win_count = 0
        sessions.append(SessionInfo(
            name=parts[0],
            windows=win_count,
            attached=parts[2] == "1",
        ))
    return sessions


async def has_tmux() -> bool:
    """Check if tmux server is running."""
    try:
        await _run("tmux", "list-sessions", "-F", "#{session_name}")
        return True
    except (RuntimeError, FileNotFoundError, asyncio.TimeoutError):
        return False
