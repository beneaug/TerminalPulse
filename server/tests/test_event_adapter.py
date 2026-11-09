"""Offline stdlib checks: python3 -m unittest discover -s server/tests -p test_event_adapter.py -v."""
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("event_adapter", Path(__file__).resolve().parents[1] / "event_adapter.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class AdapterTests(unittest.TestCase):
    def event(self, **extra):
        return {"outcome": "completed", "event_id": "turn-42", **extra}

    def test_outcomes(self):
        for outcome in module.OUTCOMES:
            result = module.normalize_event(self.event(outcome=outcome))
            self.assertEqual(result["outcome"], outcome)
            self.assertTrue(result["event_id"].startswith("adapter-v1-"))

    def test_private_content_never_forwarded(self):
        base = module.normalize_event(self.event())
        private = module.normalize_event(self.event(prompt="secret", message="secret", title="secret", output="secret", command="secret", transcript_path="secret"))
        self.assertEqual(base, private)
        self.assertNotIn("secret", json.dumps(private))

    def test_identity_stable_and_scoped(self):
        data = self.event(source="codex", session_id="s", target="main:1")
        self.assertEqual(module.normalize_event(data), module.normalize_event(dict(reversed(list(data.items())))))
        for key in ("event_id", "source", "session_id", "target"):
            self.assertNotEqual(module.normalize_event(data)["event_id"], module.normalize_event({**data, key: "different"})["event_id"])

    def test_unicode(self):
        result = module.normalize_event(self.event(event_id="回合-🦊", source="助手"))
        self.assertEqual(result["source"], "助手")
        self.assertEqual(module.normalize_event(module.decode_event(json.dumps(self.event(event_id="回合-🦊", source="助手")).encode())), result)

    def test_bad_json(self):
        for raw in (b"{", b"[]", b"null", b"{} {}", b"\xff", b'{"a":1,"a":2}', b'{"a":NaN}', b"[" * 2000):
            with self.subTest(raw=raw[:30]), self.assertRaises(module.InvalidEvent):
                module.decode_event(raw)

    def test_size_bound(self):
        with self.assertRaises(module.InvalidEvent):
            module.decode_event(b" " * (module.MAX_INPUT_BYTES + 1))
        for value in ("x" * 257, 1, None, "line\nbreak", " x", "\ud800"):
            with self.subTest(value=repr(value)), self.assertRaises(module.InvalidEvent):
                module.normalize_event(self.event(source=value))

    def test_invalid_event(self):
        for data in ({}, self.event(event_id=""), self.event(outcome="running"), self.event(version=2), self.event(version=True), self.event(version=1.0)):
            with self.assertRaises(module.InvalidEvent):
                module.normalize_event(data)

    def test_dry_run_does_not_deliver(self):
        with patch.object(module, "deliver") as send, patch("sys.stdout", new_callable=io.StringIO) as output:
            self.assertEqual(module.main(["--dry-run", "--outcome", "completed", "--event-id", "one"]), 0)
        send.assert_not_called()
        self.assertEqual(json.loads(output.getvalue())["outcome"], "completed")

    def test_invalid_stdin_does_not_deliver(self):
        for raw in (b"{", b'{"outcome":"running","event_id":"one"}', b" " * (module.MAX_INPUT_BYTES + 1)):
            with patch("sys.stdin", io.TextIOWrapper(io.BytesIO(raw))), patch("sys.stderr", new_callable=io.StringIO), patch.object(module, "deliver") as send:
                self.assertEqual(module.main([]), 2)
                send.assert_not_called()

    def test_sender_uses_fixed_argv_and_generic_text(self):
        event = module.normalize_event(self.event(target="$(touch /tmp/not-executed)"))
        with patch.object(module.subprocess, "run") as run:
            run.return_value.returncode = 0
            self.assertEqual(module.deliver(event), 0)
        argv = run.call_args.args[0]
        self.assertEqual(Path(argv[1]).name, "notify_event.py")
        self.assertNotIn(event["target"], argv)
        self.assertNotIn("shell", run.call_args.kwargs)
        self.assertIn(event["event_id"], argv)

    def test_codex_modes(self):
        hook = {"hook_event_name": "Stop", "session_id": "s", "turn_id": "t", "last_assistant_message": "secret"}
        event = module.normalize_integration(hook, "codex-hook")
        self.assertEqual(event["title"], "Codex turn finished")
        self.assertNotIn("secret", json.dumps(event))
        self.assertEqual(event, module.normalize_integration(hook, "codex-hook"))
        self.assertIsNone(module.normalize_integration({**hook, "stop_hook_active": True}, "codex-hook"))
        self.assertIsNone(module.normalize_integration({**hook, "hook_event_name": "PostModelRequest"}, "codex-hook"))
        notify = {"type": "agent-turn-complete", "thread-id": "s", "turn-id": "t", "input-messages": ["secret"]}
        with patch("sys.stdout", new_callable=io.StringIO) as output, patch.object(module, "deliver") as send:
            self.assertEqual(module.main(["--source", "codex-notify", "--dry-run", json.dumps(notify)]), 0)
        send.assert_not_called()
        self.assertEqual(json.loads(output.getvalue())["title"], "Codex turn finished")

    def test_claude_and_permission_generate_occurrence_id(self):
        for source, name in (("claude-hook", "Stop"), ("claude-hook", "StopFailure"), ("codex-hook", "PermissionRequest")):
            data = {"hook_event_name": name, "session_id": "s", "turn_id": "t", "tool_input": "secret"}
            generated = module.normalize_integration(data, source)
            generated_again = module.normalize_integration(data, source)
            self.assertNotEqual(generated["event_id"], generated_again["event_id"])
            first = module.normalize_integration(data, source, "occurrence-1")
            self.assertEqual(first, module.normalize_integration(data, source, "occurrence-1"))
            second = module.normalize_integration(data, source, "occurrence-2")
            self.assertNotEqual(first["event_id"], second["event_id"])
            self.assertNotIn("secret", json.dumps(first))
        self.assertEqual(first["outcome"], "attention-needed")
        self.assertIsNone(module.normalize_integration({"hook_event_name": "Notification"}, "claude-hook"))
        self.assertIsNone(module.normalize_integration({"hook_event_name": []}, "codex-hook"))

    def test_codex_hook_neutral_response_on_errors_and_skip(self):
        inputs = [b"{", b'{"hook_event_name":"Unknown"}', b'{"hook_event_name":"Stop","session_id":"s","turn_id":"t"}']
        for raw in inputs:
            with patch("sys.stdin", io.TextIOWrapper(io.BytesIO(raw))), patch("sys.stdout", new_callable=io.StringIO) as output, patch("sys.stderr", new_callable=io.StringIO), patch.object(module, "deliver", return_value=1):
                self.assertEqual(module.main(["--source", "codex-hook"]), 0)
                self.assertEqual(output.getvalue(), "{}\n")

    def test_claude_hook_passive_on_errors(self):
        for raw in (b"{", b'{"hook_event_name":"Stop","session_id":"s"}'):
            with patch("sys.stdin", io.TextIOWrapper(io.BytesIO(raw))), patch("sys.stdout", new_callable=io.StringIO) as output, patch("sys.stderr", new_callable=io.StringIO), patch.object(module, "deliver", return_value=1):
                self.assertEqual(module.main(["--source", "claude-hook"]), 0)
                self.assertEqual(output.getvalue(), "")
        for source in ("claude-hook", "codex-hook"):
            with patch("sys.stdout", new_callable=io.StringIO), patch("sys.stderr", new_callable=io.StringIO):
                self.assertEqual(module.main(["--source", source, "--unknown"]), 0)

    def test_delivery_timeout_is_bounded(self):
        event = module.normalize_event(self.event())
        with patch.object(module.subprocess, "run", side_effect=module.subprocess.TimeoutExpired("sender", 30)) as run, patch("sys.stderr", new_callable=io.StringIO):
            self.assertEqual(module.deliver(event), 1)
            self.assertEqual(run.call_args.kwargs["timeout"], 30)

    def test_missing_codex_turn_generates_id(self):
        data = {"hook_event_name": "Stop", "session_id": "s"}
        self.assertNotEqual(module.normalize_integration(data, "codex-hook")["event_id"], module.normalize_integration(data, "codex-hook")["event_id"])


if __name__ == "__main__":
    unittest.main()
