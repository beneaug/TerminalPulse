#!/usr/bin/env python3
"""Send reliable tmuxonwatch webhook notifications with local retry/dedupe."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import hashlib
import fcntl
import json
import math
import os
import sys
import time
import tempfile
import uuid
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
MAX_RELAY_RESPONSE_BYTES = 8192


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
    # Never silently send a custom relay's token to the default destination.
    # Invalid configuration must fail closed instead of changing recipients.
    if (parsed.scheme != "https" or not parsed.hostname or parsed.username
            or parsed.password or parsed.query or parsed.fragment):
        raise ValueError("Notify webhook must be an HTTPS URL without credentials, query, or fragment")
    port = parsed.port  # Also validates malformed/out-of-range ports.
    host = parsed.hostname.lower()
    if host == "tmuxonwatch.com" and port in (None, 443):
        parsed = parsed._replace(netloc="www.tmuxonwatch.com")
        return parse.urlunparse(parsed)
    return raw


def read_state() -> dict[str, Any]:
    if not STATE_FILE.exists():
        return {"last_sent_at": 0.0, "events": {}}
    try:
        value = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        if isinstance(value, dict):
            if not isinstance(value.get("last_sent_at"), (int, float)):
                value["last_sent_at"] = 0.0
            events = value.get("events")
            value["events"] = {key: ts for key, ts in events.items() if isinstance(ts, (int, float))} if isinstance(events, dict) else {}
            return value
    except Exception:
        pass
    return {"last_sent_at": 0.0, "events": {}}


def write_state(state: dict[str, Any]) -> None:
    _atomic_write(STATE_FILE, json.dumps(state, separators=(",", ":")))


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as output:
            output.write(text)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def sanitize(text: str, limit: int) -> str:
    value = " ".join(text.split())
    return value[:limit]


def relay_accepted(status: int, body: bytes) -> bool:
    """Whether the relay accepted an alert, not proof of device delivery.

    Legacy/custom relays may return no receipt. For the documented count-based
    response, zero accepted devices is never a success, even with HTTP 202.
    Partial acceptance is not replayed wholesale (that would duplicate alerts
    on successful devices). Per-device retries require relay-side idempotency.
    """
    if not 200 <= status < 300:
        return False
    if len(body) > MAX_RELAY_RESPONSE_BYTES:
        return True  # Unknown legacy receipt; never replay a successful POST blindly.
    if not body.strip():
        return True  # Legacy HTTP-only acknowledgement.
    try:
        receipt = json.loads(body)
    except (ValueError, UnicodeDecodeError):
        return True  # Preserve HTTP-only custom relays, including a plaintext "ok".
    if not isinstance(receipt, dict):
        return True
    if receipt.get("ok") is False:
        return False
    if "delivered" not in receipt and "failed" not in receipt:
        return True  # Legacy JSON acknowledgement; no delivery claim.
    delivered, failed = receipt.get("delivered"), receipt.get("failed")
    if type(delivered) is not int or type(failed) is not int or min(delivered, failed) < 0:
        return False
    return delivered > 0


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
            body = resp.read(MAX_RELAY_RESPONSE_BYTES + 1)
            return relay_accepted(resp.status, body), resp.status
    except error.HTTPError as exc:
        return False, int(exc.code)
    except Exception:
        return False, 0


def next_backoff_seconds(attempts: int) -> float:
    return float(min(300, 2 ** max(1, min(attempts, 9))))


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


def creation_time(item: dict[str, Any]) -> float:
    value = item.get("created_at", 0)
    return float(value) if type(value) in (int, float) and math.isfinite(value) else 0.0


def write_queue(rows: list[dict[str, Any]]) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    if not rows:
        if QUEUE_FILE.exists() and QUEUE_FILE.stat().st_size:
            _atomic_write(QUEUE_FILE, "")
        return
    # Storage/retention is chronological even when delivery prioritizes a new
    # event ahead of old backlog. At capacity, discard the oldest, not newest.
    trimmed = sorted(rows, key=creation_time)[-MAX_QUEUE_ITEMS:]
    text = "\n".join(json.dumps(row, separators=(",", ":")) for row in trimmed) + "\n"
    _atomic_write(QUEUE_FILE, text)


def enqueue(
    queue: list[dict[str, Any]],
    *,
    event_id: str,
    title: str,
    message: str,
    attempts: int,
    now: float,
) -> list[dict[str, Any]]:
    if any(item.get("event_id") == event_id for item in queue):
        return queue
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
    return sorted(queue, key=creation_time)[-MAX_QUEUE_ITEMS:]


def flush_queue(url: str, token: str, queue: list[dict[str, Any]], now: float) -> list[dict[str, Any]]:
    if not queue:
        return []
    kept: list[dict[str, Any]] = []
    state = read_state()
    deadline = time.monotonic() + 8
    sent = 0
    for item in queue:
        event_id = str(item.get("event_id", "queued"))
        accepted_at = state.get("events", {}).get(event_id)
        if accepted_at is not None and accepted_at >= creation_time(item):
            # A process may stop after recording acceptance but before removing
            # the queued item. Do not replay that already acknowledged event.
            continue
        # A long offline backlog must not create hundreds of network attempts
        # or delay a new notification by minutes on the next shell prompt.
        if sent >= 2 or time.monotonic() >= deadline:
            kept.append(item)
            continue
        when = float(item.get("next_attempt_at", 0.0) or 0.0)
        if when > now:
            kept.append(item)
            continue

        title = sanitize(str(item.get("title", "")), MAX_TITLE_LEN)
        message = sanitize(str(item.get("message", "")), MAX_MESSAGE_LEN)
        if not title or not message:
            continue

        sent += 1
        ok, status = webhook_post(url, token, title, message)
        if ok:
            state = read_state()
            state.setdefault("events", {})[str(item.get("event_id", "queued"))] = now
            state["events"] = {key: ts for key, ts in state["events"].items() if ts >= now - 3600}
            state["last_sent_at"] = now
            write_state(state)
            continue

        # Don't retain permanently invalid authorization entries.
        if status in (400, 401, 403):
            continue

        attempts = int(item.get("attempts", 0) or 0) + 1
        if attempts > 20:
            continue
        kept.append({**item, "attempts": attempts, "next_attempt_at": now + next_backoff_seconds(attempts)})
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
    parser.add_argument("--check", action="store_true", help="Check local configuration without sending or writing anything")
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


def configuration(args: argparse.Namespace) -> tuple[str, str]:
    file_env = load_export_env(ENV_FILE)
    token = (args.token or os.environ.get("TP_NOTIFY_TOKEN") or file_env.get("TP_NOTIFY_TOKEN", "")).strip()
    url = canonical_webhook_url(args.webhook_url or os.environ.get("TP_NOTIFY_WEBHOOK_URL")
                                or file_env.get("TP_NOTIFY_WEBHOOK_URL", DEFAULT_WEBHOOK_URL))
    return token, url


def delivery_directory(url: str, token: str) -> Path:
    # Account identity is an opaque digest, never a raw token/path component.
    key = hashlib.sha256(json.dumps([url, token], separators=(",", ":")).encode()).hexdigest()
    return CONFIG_DIR / "delivery" / key


@contextmanager
def delivery_scope(url: str, token: str):
    global STATE_FILE, QUEUE_FILE
    previous = STATE_FILE, QUEUE_FILE
    directory = delivery_directory(url, token)
    STATE_FILE, QUEUE_FILE = directory / "state.json", directory / "queue.jsonl"
    try:
        yield directory
    finally:
        STATE_FILE, QUEUE_FILE = previous


def main() -> int:
    return _main()


def _main(args: argparse.Namespace | None = None) -> int:
    args = args or parse_args()
    try:
        token, url = configuration(args)
    except (OSError, ValueError):
        # Do not echo a malformed URL: it may contain credentials.
        print("Invalid notification configuration. Use a readable config and HTTPS without URL credentials, query, or fragment.", file=sys.stderr)
        return 2
    with delivery_scope(url, token) as directory:
        if args.check:
            print(json.dumps({"configured": bool(token), "relay_host": parse.urlparse(url).hostname,
                              "queued_events": len(load_queue()), "delivery": "not_tested",
                              "legacy_queue_present": (CONFIG_DIR / "notify-queue.jsonl").exists()}))
            return 0 if token else 2
        if not token:
            return 0
        # Serialize only this relay/account. Queued content must never migrate
        # to another token or endpoint selected by an environment/CLI override.
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        with (directory / "notify.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            return send_or_queue(args, url, token)


def send_or_queue(args: argparse.Namespace, url: str, token: str) -> int:
    now = time.time()
    queue = load_queue()
    if args.flush_only:
        write_queue(flush_queue(url, token, queue, now))
        return 0

    title = sanitize(args.title, MAX_TITLE_LEN)
    message = sanitize(args.message, MAX_MESSAGE_LEN)
    if not title or not message:
        return 0

    min_seconds = args.min_seconds if args.min_seconds >= 0 else env_float("TP_NOTIFY_MIN_SECONDS", DEFAULT_MIN_SECONDS)
    debounce_seconds = args.debounce_seconds if args.debounce_seconds >= 0 else env_float("TP_NOTIFY_DEBOUNCE_SECONDS", DEFAULT_DEBOUNCE_SECONDS)
    dedupe_seconds = args.dedupe_seconds if args.dedupe_seconds >= 0 else env_float("TP_NOTIFY_DEDUPE_SECONDS", DEFAULT_DEDUPE_SECONDS)

    event_id = args.event_id.strip() or f"manual-{uuid.uuid4()}"
    state = read_state()
    events = state.get("events", {})
    last_event = events.get(event_id)
    if last_event is not None and now - float(last_event) < dedupe_seconds:
        return 0
    if any(item.get("event_id") == event_id for item in queue):
        # An identical producer retry never bypasses the pending event's backoff.
        write_queue(flush_queue(url, token, queue, now))
        return 0
    if not args.force:
        if args.duration < min_seconds:
            return 0
        if now - float(state.get("last_sent_at", 0) or 0) < debounce_seconds:
            return 0

    # Persist BEFORE any network or backlog work, so a killed async hook leaves
    # a recoverable pending event rather than silently losing the new alert.
    queue = enqueue(queue, event_id=event_id, title=title, message=message, attempts=0, now=now)
    newest = next(item for item in queue if item.get("event_id") == event_id)
    newest["next_attempt_at"] = now
    queue = [newest] + [item for item in queue if item is not newest]
    write_queue(queue)
    write_queue(flush_queue(url, token, queue, now))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
