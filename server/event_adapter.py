#!/usr/bin/env python3
"""Normalize explicit task outcomes without inspecting an agent's private state."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import unicodedata
import uuid
from typing import Any

MAX_INPUT_BYTES = 65536
MAX_FIELD_LENGTH = 256
DELIVERY_TIMEOUT_SECONDS = 30
OUTCOMES = {
    "completed": ("Task complete", "A task has completed. Check your terminal."),
    "failed": ("Task failed", "A task has failed. Check your terminal."),
    "attention-needed": ("Attention needed", "A task needs your attention. Check your terminal."),
}


class InvalidEvent(ValueError):
    """Invalid or unsupported input; messages deliberately omit input contents."""


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise InvalidEvent("Duplicate JSON fields are not supported.")
        result[key] = value
    return result


def decode_event(raw: bytes) -> dict[str, Any]:
    if len(raw) > MAX_INPUT_BYTES:
        raise InvalidEvent("Event exceeds the 64 KiB input limit.")
    try:
        value = json.loads(raw.decode("utf-8"), object_pairs_hook=_unique_object,
                           parse_constant=lambda _: (_ for _ in ()).throw(InvalidEvent("Invalid JSON number.")))
    except (UnicodeError, ValueError, RecursionError) as exc:
        raise InvalidEvent("Expected one valid UTF-8 JSON object.") from exc
    if not isinstance(value, dict):
        raise InvalidEvent("Expected one JSON object.")
    return value


def _field(data: dict[str, Any], key: str, *, required: bool = False) -> str:
    value = data.get(key, "")
    if not isinstance(value, str) or len(value) > MAX_FIELD_LENGTH:
        raise InvalidEvent("Event fields must be strings of at most 256 characters.")
    if any(unicodedata.category(char).startswith("C") for char in value):
        raise InvalidEvent("Event fields must not contain control characters.")
    if value != value.strip() or (required and not value):
        raise InvalidEvent("Required event fields must be nonempty and fields must have no surrounding whitespace.")
    return value


def normalize_event(data: dict[str, Any]) -> dict[str, Any]:
    """Whitelist metadata and emit generic text. Never copy prompts or output."""
    if not isinstance(data, dict):
        raise InvalidEvent("Expected one JSON object.")
    if type(data.get("version", 1)) is not int or data.get("version", 1) != 1:
        raise InvalidEvent("Unsupported event schema version.")
    outcome = _field(data, "outcome", required=True)
    if outcome not in OUTCOMES:
        raise InvalidEvent("Unsupported event outcome.")
    occurrence_id = _field(data, "event_id", required=True)
    metadata = {key: _field(data, key) for key in ("source", "session_id", "target")}
    # Only explicit identity fields participate; prompt/output changes cannot leak
    # through either the visible text or the hash. Version the identity format.
    identity = {"version": 1, "event_id": occurrence_id, "outcome": outcome, **metadata}
    digest = hashlib.sha256(json.dumps(identity, ensure_ascii=False, sort_keys=True,
                                       separators=(",", ":")).encode("utf-8")).hexdigest()
    title, message = OUTCOMES[outcome]
    return {"version": 1, "event_id": "adapter-v1-" + digest, "outcome": outcome,
            **{key: value for key, value in metadata.items() if value},
            "title": title, "message": message}


INTEGRATIONS = ("codex-hook", "codex-notify", "claude-hook")


def normalize_integration(data: dict[str, Any], source: str,
                          occurrence_id: str | None = None,
                          target: str | None = None) -> dict[str, Any] | None:
    """Translate only documented lifecycle signals; never infer from text."""
    if source == "codex-notify":
        if data.get("type") != "agent-turn-complete":
            return None
        outcome, session_key, turn_key = "completed", "thread-id", "turn-id"
    else:
        name = data.get("hook_event_name")
        supported = {"Stop": "completed", "PermissionRequest": "attention-needed"}
        if source == "claude-hook":
            supported["StopFailure"] = "failed"
        if not isinstance(name, str) or name not in supported:
            return None
        if name == "Stop":
            active = data.get("stop_hook_active", False)
            if not isinstance(active, bool):
                raise InvalidEvent("Invalid stop recursion guard.")
            if active:
                return None
        outcome, session_key, turn_key = supported[name], "session_id", "turn_id"
    session = _field(data, session_key, required=True)
    # Use stable documented completion IDs when present. Otherwise generate once
    # per invocation; the sender retains this identity for its queue retries.
    # Duplicate producer invocations can duplicate without an explicit override.
    if occurrence_id is None:
        stable_turn = (_field(data, turn_key) if source != "claude-hook"
                       and outcome == "completed" else "")
        occurrence_id = stable_turn or str(uuid.uuid4())
    event = normalize_event({"event_id": occurrence_id, "outcome": outcome,
                             "source": source, "session_id": session,
                             "target": target or ""})
    provider = "Claude Code" if source == "claude-hook" else "Codex"
    event["title"] = provider + {
        "completed": " turn finished", "failed": " turn failed",
        "attention-needed": " needs attention",
    }[outcome]
    event["message"] = {
        "completed": "An agent turn has finished. Check your terminal.",
        "failed": "An agent turn has failed. Check your terminal.",
        "attention-needed": "An agent needs your attention. Check your terminal.",
    }[outcome]
    return event


def deliver(event: dict[str, Any]) -> int:
    # A fixed sibling sender is the only executable target. No supplied command,
    # path, URL, session, or target is ever executed or interpolated into a shell.
    sender = Path(__file__).resolve().with_name("notify_event.py")
    try:
        result = subprocess.run([
            sys.executable, str(sender), "--event-id", event["event_id"],
            "--title", event["title"], "--message", event["message"], "--force",
        ], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
           timeout=DELIVERY_TIMEOUT_SECONDS)
    except subprocess.TimeoutExpired:
        print("Notification sender timed out; delivery status is unknown.", file=sys.stderr)
        return 1
    except OSError:
        print("Could not start notification sender.", file=sys.stderr)
        return 1
    return result.returncode if result.returncode >= 0 else 1


class QuietArgumentParser(argparse.ArgumentParser):
    def error(self, message: str) -> None:
        raise InvalidEvent("Invalid adapter arguments; see --help.")


def _main(argv: list[str] | None = None) -> int:
    parser = QuietArgumentParser(description=__doc__)
    parser.add_argument("payload", nargs="?", help="Codex notify JSON argument only")
    parser.add_argument("--dry-run", action="store_true", help="Print normalized JSON; no sender, network, or config access")
    parser.add_argument("--outcome", choices=tuple(OUTCOMES), help="Use CLI fields instead of JSON stdin")
    parser.add_argument("--event-id", help="Stable caller-issued ID for one occurrence; reuse on retries")
    for key in ("source", "session-id", "target"):
        parser.add_argument("--" + key)
    args = parser.parse_args(argv)
    integration = args.source in INTEGRATIONS
    # Codex command hooks require neutral JSON stdout on success. Even a local
    # delivery/parse error must not accidentally become a blocking hook decision.
    passive = args.source in ("codex-hook", "claude-hook") and not args.dry_run
    neutral_json = args.source == "codex-hook"
    try:
        fields = {key: getattr(args, key) for key in ("outcome", "event_id", "source", "session_id", "target")}
        if integration:
            if args.outcome is not None or args.session_id is not None:
                raise InvalidEvent("Integration mode cannot override outcome or session.")
            if args.payload is not None:
                if args.source != "codex-notify":
                    raise InvalidEvent("Only codex-notify accepts a JSON argument.")
                raw = args.payload.encode("utf-8")
            else:
                raw = sys.stdin.buffer.read(MAX_INPUT_BYTES + 1)
            event = normalize_integration(decode_event(raw), args.source, args.event_id, args.target)
        elif args.payload is not None:
            raise InvalidEvent("JSON argument requires codex-notify mode.")
        elif any(value is not None for value in fields.values()):
            data = {key: value for key, value in fields.items() if value is not None}
        else:
            data = decode_event(sys.stdin.buffer.read(MAX_INPUT_BYTES + 1))
        if not integration:
            event = normalize_event(data)
    except (InvalidEvent, UnicodeError) as exc:
        print(str(exc) if isinstance(exc, InvalidEvent) else "Invalid UTF-8 input.", file=sys.stderr)
        if passive:
            if neutral_json:
                print("{}")
            return 0
        return 2
    if event is None:
        if (passive and neutral_json) or args.dry_run:
            print("{}")
        return 0
    if args.dry_run:
        print(json.dumps(event, ensure_ascii=False, sort_keys=True))
        return 0
    result = deliver(event)
    if passive:
        if neutral_json:
            print("{}")
        return 0
    return result


def main(argv: list[str] | None = None) -> int:
    arguments = list(sys.argv[1:] if argv is None else argv)
    try:
        return _main(arguments)
    except InvalidEvent as exc:
        # Argument errors are passive too; never echo caller-supplied values.
        source = None
        for index, argument in enumerate(arguments):
            if argument == "--source" and index + 1 < len(arguments):
                source = arguments[index + 1]
            elif argument.startswith("--source="):
                source = argument.split("=", 1)[1]
        print(str(exc), file=sys.stderr)
        if "--dry-run" not in arguments and source in ("codex-hook", "claude-hook"):
            if source == "codex-hook":
                print("{}")
            return 0
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
