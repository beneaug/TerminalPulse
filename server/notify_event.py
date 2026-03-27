#!/usr/bin/env python3
"""Send reliable tmuxonwatch webhook notifications with local retry/dedupe."""

from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path
from typing import Any
from urllib import error, parse, request

CONFIG_DIR = Path.home() / ".config" / "tmuxonwatch"
ENV_FILE = CONFIG_DIR / "env"
STATE_FILE = CONFIG_DIR / "notify-state.json"
QUEUE_FILE = CONFIG_DIR / "notify-queue.jsonl"

DEFAULT_WEBHOOK_URL = "https://www.tmuxonwatch.com/api/webhook"
DEFAULT_MIN_SECONDS = 2.0
DEFAULT_DEBOUNCE_SECONDS = 12.0
DEFAULT_DEDUPE_SECONDS = 120.0
MAX_QUEUE_ITEMS = 200
MAX_TITLE_LEN = 120
MAX_MESSAGE_LEN = 240


def load_export_env(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.exists():
        return values

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :]
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'").strip('"')
        if key:
            values[key] = value
    return values


def canonical_webhook_url(raw: str) -> str:
    raw = raw.strip()
    if not raw:
        return DEFAULT_WEBHOOK_URL

    parsed = parse.urlparse(raw)
    if parsed.scheme != "https":
        return DEFAULT_WEBHOOK_URL

    host = (parsed.hostname or "").lower()
    if host == "tmuxonwatch.com":
        parsed = parsed._replace(netloc="www.tmuxonwatch.com")
        return parse.urlunparse(parsed)
    return raw


def read_state() -> dict[str, Any]:
    if not STATE_FILE.exists():
        return {"last_sent_at": 0.0, "events": {}}
    try:
        value = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        if isinstance(value, dict):
            value.setdefault("last_sent_at", 0.0)
            value.setdefault("events", {})
            return value
    except Exception:
        pass
    return {"last_sent_at": 0.0, "events": {}}


def write_state(state: dict[str, Any]) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state, separators=(",", ":")), encoding="utf-8")


def sanitize(text: str, limit: int) -> str:
    value = " ".join(text.split())
    return value[:limit]


def webhook_post(url: str, token: str, title: str, message: str) -> tuple[bool, int]:
    payload = json.dumps({"title": title, "message": message}).encode("utf-8")
    req = request.Request(
        url=url,
        data=payload,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with request.urlopen(req, timeout=8) as resp:
            return 200 <= resp.status < 300, resp.status
    except error.HTTPError as exc:
        return False, int(exc.code)
    except Exception:
        return False, 0


def next_backoff_seconds(attempts: int) -> float:
    return float(min(300, 2 ** max(1, attempts)))


def load_queue() -> list[dict[str, Any]]:
    if not QUEUE_FILE.exists():
        return []
    rows: list[dict[str, Any]] = []
    for line in QUEUE_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            value = json.loads(line)
            if isinstance(value, dict):
                rows.append(value)
        except Exception:
            continue
    return rows


def write_queue(rows: list[dict[str, Any]]) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not rows:
        QUEUE_FILE.write_text("", encoding="utf-8")
        return
    trimmed = rows[-MAX_QUEUE_ITEMS:]
    text = "\n".join(json.dumps(row, separators=(",", ":")) for row in trimmed) + "\n"
    QUEUE_FILE.write_text(text, encoding="utf-8")


def enqueue(
    queue: list[dict[str, Any]],
    *,
    event_id: str,
    title: str,
    message: str,
    attempts: int,
    now: float,
) -> list[dict[str, Any]]:
    queue.append(
        {
            "event_id": event_id,
            "title": title,
            "message": message,
            "attempts": attempts,
            "next_attempt_at": now + next_backoff_seconds(attempts),
            "created_at": now,
        }
    )
    return queue[-MAX_QUEUE_ITEMS:]


def flush_queue(url: str, token: str, queue: list[dict[str, Any]], now: float) -> list[dict[str, Any]]:
    if not queue:
        return []
    kept: list[dict[str, Any]] = []
    for item in queue:
        when = float(item.get("next_attempt_at", 0.0) or 0.0)
        if when > now:
            kept.append(item)
            continue

        title = sanitize(str(item.get("title", "")), MAX_TITLE_LEN)
        message = sanitize(str(item.get("message", "")), MAX_MESSAGE_LEN)
        if not title or not message:
            continue

        ok, status = webhook_post(url, token, title, message)
        if ok:
            continue

        # Don't retain permanently invalid authorization entries.
        if status in (400, 401, 403):
            continue

        attempts = int(item.get("attempts", 0) or 0) + 1
        if attempts > 20:
            continue
        kept = enqueue(
            kept,
            event_id=str(item.get("event_id", "queued")),
            title=title,
            message=message,
            attempts=attempts,
            now=now,
        )
    return kept


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Send tmuxonwatch notification event")
    parser.add_argument("--event-id", default="", help="Stable dedupe key for this event")
    parser.add_argument("--title", default="", help="Notification title")
    parser.add_argument("--message", default="", help="Notification message")
    parser.add_argument("--duration", type=float, default=0.0, help="Command duration in seconds")
    parser.add_argument("--token", default="", help="Override TP_NOTIFY_TOKEN")
    parser.add_argument("--webhook-url", default="", help="Override webhook URL")
    parser.add_argument("--min-seconds", type=float, default=-1.0)
    parser.add_argument("--debounce-seconds", type=float, default=-1.0)
    parser.add_argument("--dedupe-seconds", type=float, default=-1.0)
    parser.add_argument("--flush-only", action="store_true", help="Only retry pending queue")
    parser.add_argument("--force", action="store_true", help="Bypass threshold/debounce checks")
    return parser.parse_args()


def env_float(name: str, fallback: float) -> float:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return fallback
    try:
        return float(raw)
    except ValueError:
        return fallback


def main() -> int:
    args = parse_args()
    file_env = load_export_env(ENV_FILE)

    token = (args.token or file_env.get("TP_NOTIFY_TOKEN", "")).strip()
    if not token:
        return 0

    url = canonical_webhook_url(args.webhook_url or file_env.get("TP_NOTIFY_WEBHOOK_URL", DEFAULT_WEBHOOK_URL))
    now = time.time()

    queue = load_queue()
    queue = flush_queue(url, token, queue, now)

    if args.flush_only:
        write_queue(queue)
        return 0

    title = sanitize(args.title, MAX_TITLE_LEN)
    message = sanitize(args.message, MAX_MESSAGE_LEN)
    if not title or not message:
        write_queue(queue)
        return 0

    min_seconds = args.min_seconds if args.min_seconds >= 0 else env_float("TP_NOTIFY_MIN_SECONDS", DEFAULT_MIN_SECONDS)
    debounce_seconds = (
        args.debounce_seconds if args.debounce_seconds >= 0 else env_float("TP_NOTIFY_DEBOUNCE_SECONDS", DEFAULT_DEBOUNCE_SECONDS)
    )
    dedupe_seconds = args.dedupe_seconds if args.dedupe_seconds >= 0 else env_float("TP_NOTIFY_DEDUPE_SECONDS", DEFAULT_DEDUPE_SECONDS)

    event_id = args.event_id.strip() or f"manual-{int(now)}"
    state = read_state()
    events = state.get("events", {})
    if not isinstance(events, dict):
        events = {}

    if not args.force:
        if args.duration < min_seconds:
            write_queue(queue)
            return 0

        last_sent_at = float(state.get("last_sent_at", 0.0) or 0.0)
        if now - last_sent_at < debounce_seconds:
            write_queue(queue)
            return 0

        last_event = float(events.get(event_id, 0.0) or 0.0)
        if now - last_event < dedupe_seconds:
            write_queue(queue)
            return 0

    ok, status = webhook_post(url, token, title, message)
    if ok:
        state["last_sent_at"] = now
        events[event_id] = now
        cutoff = now - max(dedupe_seconds * 3.0, 600.0)
        state["events"] = {
            key: ts
            for key, ts in events.items()
            if isinstance(ts, (int, float)) and float(ts) >= cutoff
        }
        write_state(state)
        write_queue(queue)
        return 0

    if status not in (400, 401, 403):
        queue = enqueue(queue, event_id=event_id, title=title, message=message, attempts=1, now=now)
    write_queue(queue)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
