"""TerminalPulse FastAPI server — tmux capture bridge."""

from __future__ import annotations

import asyncio
import hashlib
import json
import os
import secrets
import socket
import time
from datetime import datetime, timezone
from typing import Optional

from fastapi import Depends, FastAPI, HTTPException, Query, Request, Response
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

TOKEN = os.environ.get("TP_TOKEN", "changeme").strip()
NOTIFY_TOKEN = os.environ.get("TP_NOTIFY_TOKEN", "").strip()
NOTIFY_WEBHOOK_URL = os.environ.get("TP_NOTIFY_WEBHOOK_URL", "https://www.tmuxonwatch.com/api/webhook")
NOTIFY_REGISTER_URL = os.environ.get("TP_NOTIFY_REGISTER_URL", "https://www.tmuxonwatch.com/api/push/register")
NOTIFY_UNREGISTER_URL = os.environ.get("TP_NOTIFY_UNREGISTER_URL", "https://www.tmuxonwatch.com/api/push/unregister")

if not TOKEN.strip() or TOKEN == "changeme":
    import sys

    print(
        "\n\033[1;31mFATAL: TP_TOKEN is set to 'changeme'.\033[0m\n"
        "Generate a secure token:  python3 -c \"import secrets; print(secrets.token_urlsafe(32))\"\n"
        "Then set it:  export TP_TOKEN=<your-token>\n",
        file=sys.stderr,
    )
    sys.exit(1)


def _verify(creds: HTTPAuthorizationCredentials = Depends(_security)) -> str:
    if not secrets.compare_digest(creds.credentials.encode("utf-8"), TOKEN.encode("utf-8")):
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


async def _capture_snapshot(lines: int, target: str | None) -> tuple[str, dict | None, str]:
    try:
        # Resolve once so an external focus change cannot label one pane's text
        # with another pane's metadata.
        pane = await get_pane_info(target=target)
        raw = await capture_pane(lines=lines, target=pane.pane_id)
    except (RuntimeError, ValueError, FileNotFoundError) as exc:
        raise HTTPException(status_code=502, detail=str(exc))
    metadata = {
        "session": pane.session_name,
        "winIndex": pane.window_index,
        "winName": pane.window_name,
        "paneId": pane.pane_id,
        "paneCurrentCommand": getattr(pane, "pane_current_command", getattr(pane, "current_command", None)),
    }
    # Metadata changes matter even when two panes contain identical text.
    identity = json.dumps([raw, metadata], ensure_ascii=False, separators=(",", ":"))
    return raw, metadata, hashlib.sha256(identity.encode()).hexdigest()


_captures_in_flight: dict[tuple[int, str | None], asyncio.Task] = {}


async def _shared_capture(lines: int, target: str | None):
    key = (lines, target)
    task = _captures_in_flight.get(key)
    if task is None or task.done():
        task = asyncio.create_task(_capture_snapshot(lines, target))
        _captures_in_flight[key] = task
        def completed(done):
            if _captures_in_flight.get(key) is done:
                _captures_in_flight.pop(key, None)
            if not done.cancelled():
                done.exception()  # Retrieve exceptions even if every client disconnected.
        task.add_done_callback(completed)
    return await asyncio.shield(task)


@app.get("/capture")
async def capture(
    request: Request,
    response: Response,
    _: str = Depends(_verify),
    lines: int = Query(default=80, ge=1, le=500),
    target: str | None = Query(default=None),
    compact: bool = Query(default=False),
):
    raw, metadata, content_hash = await _shared_capture(lines, target)
    etag = f'"{content_hash}-{"compact" if compact else "full"}"'
    headers = {"ETag": etag, "Cache-Control": "private, no-cache"}
    validators = [v.strip().removeprefix("W/") for v in request.headers.get("if-none-match", "").split(",")]
    if etag in validators or "*" in validators:
        return Response(status_code=304, headers=headers)
    response.headers.update(headers)
    parsed = parse_lines(raw)

    # Strip trailing empty lines to avoid dead space on watch
    while parsed and all(run.get("t", "").strip() == "" for run in parsed[-1]):
        parsed.pop()

    return {
        # Retain the field for existing decoders; old clients still get raw text.
        "raw": "" if compact else raw,
        "hash": content_hash,
        "pane": metadata,
        "parsed_lines": parsed,
        "ts": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/sessions")
async def sessions(_: str = Depends(_verify)):
    try:
        sess_list = await list_sessions()
    except (RuntimeError, FileNotFoundError) as exc:
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
    except (RuntimeError, FileNotFoundError) as exc:
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
    except (RuntimeError, FileNotFoundError) as exc:
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
    except (RuntimeError, FileNotFoundError) as exc:
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
