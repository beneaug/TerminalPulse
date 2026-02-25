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
    cmd = ["tmux", "display-message", "-p"]
    if target:
        cmd.extend(["-t", target])
    cmd.append(fmt)
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


@dataclass
class WindowInfo:
    session_name: str
    window_index: int
    window_name: str
    active: bool


async def list_windows(session: str | None = None) -> list[WindowInfo]:
    """List tmux windows, optionally scoped to one session."""
    _validate_target(session)
    fmt = "#{session_name}|#{window_index}|#{window_name}|#{window_active}"
    cmd = ["tmux", "list-windows", "-F", fmt]
    if session:
        cmd.extend(["-t", session])
    out = await _run(*cmd)
    windows: list[WindowInfo] = []
    for line in out.strip().split("\n"):
        if not line:
            continue
        parts = line.split("|", 3)
        if len(parts) < 4:
            continue
        try:
            window_index = int(parts[1])
        except ValueError:
            continue
        windows.append(
            WindowInfo(
                session_name=parts[0],
                window_index=window_index,
                window_name=parts[2],
                active=parts[3] == "1",
            )
        )
    return windows


async def switch_window(direction: int, target: str | None = None) -> PaneInfo:
    """Switch to next/previous window in a tmux session and return active pane info."""
    _validate_target(target)
    if direction == 0:
        raise ValueError("direction must be non-zero")

    # Resolve the session from the provided target (pane/window/session) or current context.
    current = await get_pane_info(target=target)
    session_name = current.session_name

    windows = await list_windows(session=session_name)
    if len(windows) <= 1:
        raise ValueError("No additional tmux windows")

    ordered = sorted(windows, key=lambda w: w.window_index)
    ordered_indexes = [w.window_index for w in ordered]
    try:
        current_pos = ordered_indexes.index(current.window_index)
    except ValueError:
        current_pos = 0

    step = 1 if direction > 0 else -1
    next_pos = (current_pos + step + len(ordered_indexes)) % len(ordered_indexes)
    next_index = ordered_indexes[next_pos]
    await _run("tmux", "select-window", "-t", f"{session_name}:{next_index}")
    return await get_pane_info(target=session_name)


_ALLOWED_SPECIAL_KEYS: frozenset[str] = frozenset({
    "Enter", "Escape", "Tab", "BSpace",
    "Up", "Down", "Left", "Right",
    "C-c", "C-d", "C-z", "C-l", "C-a", "C-e", "C-r", "C-u", "C-k", "C-w",
    "Space", "Home", "End", "PageUp", "PageDown",
})

_MAX_TEXT_LENGTH = 512


async def send_keys(
    text: str | None = None,
    special: str | None = None,
    target: str | None = None,
) -> None:
    """Send keystrokes to a tmux pane.

    Exactly one of *text* or *special* must be provided.
    - text: sent literally via ``tmux send-keys -l`` (no key interpretation).
    - special: must be in ``_ALLOWED_SPECIAL_KEYS``; sent as a tmux key name.
    """
    _validate_target(target)

    if text is not None and special is not None:
        raise ValueError("Provide exactly one of text or special, not both")
    if text is None and special is None:
        raise ValueError("Provide exactly one of text or special")

    if text is not None:
        if len(text) > _MAX_TEXT_LENGTH:
            raise ValueError(f"Text exceeds {_MAX_TEXT_LENGTH} characters")
        cmd = ["tmux", "send-keys", "-l"]
        if target:
            cmd.extend(["-t", target])
        cmd.append(text)
    else:
        assert special is not None
        if special not in _ALLOWED_SPECIAL_KEYS:
            raise ValueError(f"Special key {special!r} not allowed")
        cmd = ["tmux", "send-keys"]
        if target:
            cmd.extend(["-t", target])
        cmd.append(special)

    await _run(*cmd)


async def has_tmux() -> bool:
    """Check if tmux server is running."""
    try:
        await _run("tmux", "list-sessions", "-F", "#{session_name}")
        return True
    except (RuntimeError, FileNotFoundError, asyncio.TimeoutError):
        return False
