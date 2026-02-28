"""TerminalPulse FastAPI server — tmux capture bridge."""

from __future__ import annotations

import hashlib
import os
import socket
import time
from datetime import datetime, timezone
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, model_validator

from ansi_parser import parse_lines
from tmux_bridge import (
    capture_pane,
    get_pane_info,
    has_tmux,
    list_sessions,
    list_windows,
    send_keys,
    switch_window,
)

app = FastAPI(title="TerminalPulse", version="1.0.0")
_security = HTTPBearer()

TOKEN = os.environ.get("TP_TOKEN", "changeme")
NOTIFY_TOKEN = os.environ.get("TP_NOTIFY_TOKEN", "").strip()
NOTIFY_WEBHOOK_URL = os.environ.get("TP_NOTIFY_WEBHOOK_URL", "https://www.tmuxonwatch.com/api/webhook")
NOTIFY_REGISTER_URL = os.environ.get("TP_NOTIFY_REGISTER_URL", "https://www.tmuxonwatch.com/api/push/register")
NOTIFY_UNREGISTER_URL = os.environ.get("TP_NOTIFY_UNREGISTER_URL", "https://www.tmuxonwatch.com/api/push/unregister")

if TOKEN == "changeme":
    import sys

    print(
        "\n\033[1;31mFATAL: TP_TOKEN is set to 'changeme'.\033[0m\n"
        "Generate a secure token:  python3 -c \"import secrets; print(secrets.token_urlsafe(32))\"\n"
        "Then set it:  export TP_TOKEN=<your-token>\n",
        file=sys.stderr,
    )
    sys.exit(1)


def _verify(creds: HTTPAuthorizationCredentials = Depends(_security)) -> str:
    if creds.credentials != TOKEN:
        raise HTTPException(status_code=401, detail="Invalid token")
    return creds.credentials


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "hostname": socket.gethostname(),
        "tmux": await has_tmux(),
    }


@app.get("/notify-config")
async def notify_config(_: str = Depends(_verify)):
    return {
        "notify_token": NOTIFY_TOKEN or None,
        "notify_webhook_url": NOTIFY_WEBHOOK_URL,
        "notify_register_url": NOTIFY_REGISTER_URL,
        "notify_unregister_url": NOTIFY_UNREGISTER_URL,
    }


@app.get("/capture")
async def capture(
    _: str = Depends(_verify),
    lines: int = Query(default=80, ge=1, le=500),
    target: str | None = Query(default=None),
):
    try:
        raw = await capture_pane(lines=lines, target=target)
    except (RuntimeError, ValueError) as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    try:
        pane = await get_pane_info(target=target)
    except (RuntimeError, ValueError):
        pane = None

    content_hash = hashlib.sha256(raw.encode()).hexdigest()[:16]
    parsed = parse_lines(raw)

    # Strip trailing empty lines to avoid dead space on watch
    while parsed and all(run.get("t", "").strip() == "" for run in parsed[-1]):
        parsed.pop()

    pane_current_command = None
    if pane is not None:
        pane_current_command = getattr(pane, "pane_current_command", None)
        if pane_current_command is None:
            pane_current_command = getattr(pane, "current_command", None)

    return {
        "raw": raw,
        "hash": content_hash,
        "pane": {
            "session": pane.session_name,
            "winIndex": pane.window_index,
            "winName": pane.window_name,
            "paneId": pane.pane_id,
            "paneCurrentCommand": pane_current_command,
        } if pane else None,
        "parsed_lines": parsed,
        "ts": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/sessions")
async def sessions(_: str = Depends(_verify)):
    try:
        sess_list = await list_sessions()
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    return {
        "sessions": [
            {"name": s.name, "windows": s.windows, "attached": s.attached}
            for s in sess_list
        ]
    }


@app.get("/windows")
async def windows(
    _: str = Depends(_verify),
    session: str | None = Query(default=None),
):
    try:
        windows_list = await list_windows(session=session)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    return {
        "windows": [
            {
                "session": w.session_name,
                "index": w.window_index,
                "name": w.window_name,
                "active": w.active,
            }
            for w in windows_list
        ]
    }


class SendKeysRequest(BaseModel):
    text: Optional[str] = None
    special: Optional[str] = None
    target: Optional[str] = None

    @model_validator(mode="after")
    def exactly_one(self):
        if (self.text is None) == (self.special is None):
            raise ValueError("Provide exactly one of text or special")
        return self


class SwitchWindowRequest(BaseModel):
    direction: int = 1
    target: Optional[str] = None

    @model_validator(mode="after")
    def validate_direction(self):
        if self.direction == 0:
            raise ValueError("direction must be non-zero")
        return self


class _RateLimiter:
    """Simple in-memory sliding-window rate limiter."""

    def __init__(self, max_per_sec: int = 20):
        self._max = max_per_sec
        self._timestamps: list[float] = []

    def check(self) -> None:
        now = time.monotonic()
        self._timestamps = [t for t in self._timestamps if now - t < 1.0]
        if len(self._timestamps) >= self._max:
            raise HTTPException(status_code=429, detail="Rate limit exceeded")
        self._timestamps.append(now)


_send_keys_limiter = _RateLimiter(max_per_sec=20)


@app.post("/send-keys")
async def post_send_keys(
    body: SendKeysRequest,
    _: str = Depends(_verify),
):
    _send_keys_limiter.check()
    try:
        await send_keys(text=body.text, special=body.special, target=body.target)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc))
    return {"ok": True}


@app.post("/switch-window")
async def post_switch_window(
    body: SwitchWindowRequest,
    _: str = Depends(_verify),
):
    try:
        pane = await switch_window(direction=body.direction, target=body.target)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc))

    return {
        "ok": True,
        "pane": {
            "session": pane.session_name,
            "winIndex": pane.window_index,
            "winName": pane.window_name,
            "paneId": pane.pane_id,
        },
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8787)
