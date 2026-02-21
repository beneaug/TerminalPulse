"""TerminalPulse FastAPI server — tmux capture bridge."""

from __future__ import annotations

import hashlib
import os
import socket
from datetime import datetime, timezone

from fastapi import Depends, FastAPI, HTTPException, Query
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from ansi_parser import parse_lines
from tmux_bridge import capture_pane, get_pane_info, has_tmux, list_sessions

app = FastAPI(title="TerminalPulse", version="1.0.0")
_security = HTTPBearer()

TOKEN = os.environ.get("TP_TOKEN", "changeme")

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

    return {
        "raw": raw,
        "hash": content_hash,
        "pane": {
            "session": pane.session_name,
            "winIndex": pane.window_index,
            "winName": pane.window_name,
            "paneId": pane.pane_id,
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


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8787)
