from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import notify_event as notify


class NotifyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        directory = Path(self.temp.name)
        self.original_delivery_directory = notify.delivery_directory
        scope = patch.object(notify, "delivery_directory", return_value=directory)
        scope.start()
        self.addCleanup(scope.stop)
        for name, value in {"CONFIG_DIR": directory, "STATE_FILE": directory / "state.json",
                            "QUEUE_FILE": directory / "queue.jsonl"}.items():
            patcher = patch.object(notify, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def test_empty_queue_does_not_write_on_every_shell_prompt(self):
        notify.write_queue([])
        self.assertFalse(notify.QUEUE_FILE.exists())

    def test_failed_event_is_only_queued_once(self):
        args = dict(event_id="build-1", title="Build", message="Done", attempts=1, now=0)
        queue = notify.enqueue([], **args)
        queue = notify.enqueue(queue, **args)
        self.assertEqual(len(queue), 1)

    def test_retry_backlog_is_bounded_and_records_dedupe(self):
        queue = [dict(event_id=str(i), title="Build", message="Done", next_attempt_at=0) for i in range(20)]
        with patch.object(notify, "webhook_post", return_value=(True, 200)) as post:
            kept = notify.flush_queue("https://example.test", "test", queue, 100)
        self.assertEqual(post.call_count, 2)
        self.assertEqual(len(kept), 18)
        self.assertEqual(notify.read_state()["events"], {"0": 100, "1": 100})

    def test_retry_preserves_original_creation_time(self):
        queue = [dict(event_id="1", title="Build", message="Done", created_at=1, attempts=1)]
        with patch.object(notify, "webhook_post", return_value=(False, 500)):
            kept = notify.flush_queue("https://example.test", "test", queue, 100)
        self.assertEqual(kept[0]["created_at"], 1)
        self.assertEqual(kept[0]["attempts"], 2)

    def test_atomic_queue_roundtrip(self):
        queue = [dict(event_id="1", title="Build", message="Done")]
        notify.write_queue(queue)
        self.assertEqual(notify.load_queue(), queue)
        self.assertEqual(notify.QUEUE_FILE.stat().st_mode & 0o777, 0o600)

    def test_malformed_state_is_normalized(self):
        notify._atomic_write(notify.STATE_FILE, '{"events": null, "last_sent_at": "bad"}')
        self.assertEqual(notify.read_state(), {"events": {}, "last_sent_at": 0})

    def args(self, **overrides):
        import argparse
        values = dict(token="unit-test-token", webhook_url="https://relay.example.test/events",
                      event_id="event-1", title="tmuxonwatch", message="Turn finished.",
                      duration=0, min_seconds=-1, debounce_seconds=-1, dedupe_seconds=-1,
                      flush_only=False, force=True, check=False)
        values.update(overrides)
        return argparse.Namespace(**values)

    def test_zero_delivery_receipt_does_not_discard_retry(self):
        import json
        for receipt in ({"ok": True, "delivered": 0, "failed": 1},
                        {"ok": True, "delivered": 0, "failed": 0}):
            self.assertFalse(notify.relay_accepted(202, json.dumps(receipt).encode()))
        with patch.object(notify, "configuration", return_value=("test", "https://example.test")), \
             patch.object(notify, "webhook_post", return_value=(False, 202)):
            self.assertEqual(notify._main(self.args()), 0)
        self.assertEqual(notify.load_queue()[0]["event_id"], "event-1")
        self.assertNotIn("event-1", notify.read_state()["events"])

    def test_partial_acceptance_is_not_replayed_to_successful_devices(self):
        self.assertTrue(notify.relay_accepted(200, b'{"ok":true,"delivered":1,"failed":1}'))

    def test_legacy_acknowledgement_is_supported_without_claiming_delivery(self):
        self.assertTrue(notify.relay_accepted(204, b""))
        self.assertTrue(notify.relay_accepted(200, b'{"ok":true}'))
        self.assertTrue(notify.relay_accepted(200, b'ok'))
        self.assertTrue(notify.relay_accepted(200, b'[]'))
        self.assertTrue(notify.relay_accepted(200, b'x' * (notify.MAX_RELAY_RESPONSE_BYTES + 1)))

    def test_invalid_relay_receipts_are_not_success(self):
        for body in (b'{"ok":false}', b'{"delivered":true,"failed":0}',
                     b'{"delivered":-1,"failed":0}', b'{"delivered":1}'):
            self.assertFalse(notify.relay_accepted(200, body), body[:80])
        self.assertFalse(notify.relay_accepted(503, b'{"ok":true}'))

    def test_webhook_reads_bounded_receipt_not_status_only(self):
        from unittest.mock import MagicMock
        response = MagicMock()
        response.__enter__.return_value = response
        response.status = 202
        response.read.return_value = b'{"ok":true,"delivered":0,"failed":1}'
        with patch.object(notify.request, "urlopen", return_value=response):
            self.assertEqual(notify.webhook_post("https://example.test", "test", "Title", "Message"), (False, 202))
        response.read.assert_called_once_with(notify.MAX_RELAY_RESPONSE_BYTES + 1)

    def test_force_never_bypasses_event_dedupe(self):
        notify.write_state({"last_sent_at": 100, "events": {"event-1": 100}})
        with patch.object(notify, "configuration", return_value=("test", "https://example.test")), \
             patch.object(notify.time, "time", return_value=101), \
             patch.object(notify, "webhook_post") as post:
            self.assertEqual(notify._main(self.args()), 0)
        post.assert_not_called()

    def test_force_does_bypass_unrelated_event_debounce(self):
        notify.write_state({"last_sent_at": 100, "events": {"other-event": 100}})
        with patch.object(notify, "configuration", return_value=("test", "https://example.test")), \
             patch.object(notify.time, "time", return_value=101), \
             patch.object(notify, "webhook_post", return_value=(True, 200)) as post:
            self.assertEqual(notify._main(self.args()), 0)
        self.assertEqual(post.call_count, 1)
        self.assertIn("event-1", notify.read_state()["events"])

    def test_queued_event_is_not_retried_before_due_time(self):
        notify.write_queue([dict(event_id="event-1", title="Title", message="Message", next_attempt_at=200)])
        with patch.object(notify, "configuration", return_value=("test", "https://example.test")), \
             patch.object(notify.time, "time", return_value=101), \
             patch.object(notify, "webhook_post") as post:
            self.assertEqual(notify._main(self.args()), 0)
        post.assert_not_called()
        self.assertEqual(len(notify.load_queue()), 1)

    def test_invalid_custom_url_never_falls_back_to_default_recipient(self):
        for url in ("http://custom.example/", "https:///events", "https://u:secret@example.test/",
                    "https://example.test/?token=secret", "https://example.test/#secret", "https://example.test:bad/"):
            with self.assertRaises(ValueError):
                notify.canonical_webhook_url(url)
        self.assertEqual(notify.canonical_webhook_url("https://custom.example/events"), "https://custom.example/events")
        self.assertEqual(notify.canonical_webhook_url("https://tmuxonwatch.com/api/webhook"), notify.DEFAULT_WEBHOOK_URL)

    def test_environment_config_supports_scripts_without_copying_credentials(self):
        with patch.object(notify, "load_export_env", return_value={"TP_NOTIFY_TOKEN": "file-token"}), \
             patch.dict(notify.os.environ, {"TP_NOTIFY_TOKEN": "environment-token", "TP_NOTIFY_WEBHOOK_URL": "https://private.example/hook"}, clear=True):
            self.assertEqual(notify.configuration(self.args(token="", webhook_url="")),
                             ("environment-token", "https://private.example/hook"))

    def test_configuration_check_does_not_send_or_create_files(self):
        import contextlib
        import io
        import json
        output = io.StringIO()
        with patch.object(notify, "parse_args", return_value=self.args(check=True)), \
             patch.object(notify, "configuration", return_value=("do-not-print", "https://private.example/hook")), \
             patch.object(notify, "webhook_post") as post, contextlib.redirect_stdout(output):
            self.assertEqual(notify.main(), 0)
        self.assertNotIn("do-not-print", output.getvalue())
        self.assertEqual(json.loads(output.getvalue())["delivery"], "not_tested")
        self.assertEqual(list(notify.CONFIG_DIR.iterdir()), [])
        post.assert_not_called()

    def test_pending_event_survives_interruption_before_response(self):
        with patch.object(notify, "configuration", return_value=("test", "https://example.test")), \
             patch.object(notify, "webhook_post", side_effect=KeyboardInterrupt):
            with self.assertRaises(KeyboardInterrupt):
                notify._main(self.args())
        self.assertEqual(notify.load_queue()[0]["event_id"], "event-1")
        self.assertEqual(notify.load_queue()[0]["attempts"], 0)

    def test_recorded_acceptance_prevents_replay_after_queue_write_interruption(self):
        notify.write_state({"last_sent_at": 101, "events": {"event-1": 101}})
        pending = [dict(event_id="event-1", title="Title", message="Message", created_at=100)]
        with patch.object(notify, "webhook_post") as post:
            self.assertEqual(notify.flush_queue("https://example.test", "test", pending, 102), [])
        post.assert_not_called()

    def test_queue_and_dedupe_never_cross_recipient_configuration(self):
        with patch.object(notify, "delivery_directory", side_effect=self.original_delivery_directory):
            for token, endpoint in (("account-a", "https://old.example/hook"), ("account-b", "https://new.example/hook")):
                with patch.object(notify, "configuration", return_value=(token, endpoint)), \
                     patch.object(notify, "webhook_post", return_value=(False, 503)) as post:
                    notify._main(self.args())
                self.assertEqual(post.call_count, 1)
                self.assertEqual(post.call_args.args[:2], (endpoint, token))
            paths = [self.original_delivery_directory("https://old.example/hook", "account-a"),
                     self.original_delivery_directory("https://new.example/hook", "account-b")]
            self.assertNotEqual(paths[0], paths[1])
            for path in paths:
                self.assertTrue((path / "queue.jsonl").exists())
                self.assertNotIn("account-", str(path))
            with patch.object(notify, "configuration", return_value=("account-c", "https://third.example/hook")), \
                 patch.object(notify, "webhook_post") as post:
                notify._main(self.args(flush_only=True))
            post.assert_not_called()

    def test_unscoped_legacy_queue_is_not_forwarded_to_new_account(self):
        notify._atomic_write(notify.CONFIG_DIR / "notify-queue.jsonl", '{"event_id":"old","title":"Private","message":"Old account"}\n')
        with patch.object(notify, "delivery_directory", side_effect=self.original_delivery_directory), \
             patch.object(notify, "configuration", return_value=("new-account", "https://new.example/hook")), \
             patch.object(notify, "webhook_post") as post:
            notify._main(self.args(flush_only=True))
        post.assert_not_called()
        self.assertTrue((notify.CONFIG_DIR / "notify-queue.jsonl").exists())

    def test_capacity_keeps_recent_pending_events_despite_priority_order(self):
        queue = [dict(event_id="recent", created_at=900)] + [dict(event_id=str(i), created_at=i) for i in range(1, 200)]
        queue = notify.enqueue(queue, event_id="new", title="Title", message="Message", attempts=0, now=1000)
        self.assertEqual(len(queue), 200)
        ids = [item["event_id"] for item in queue]
        self.assertIn("recent", ids)
        self.assertIn("new", ids)
        self.assertNotIn("1", ids)
        notify.write_queue(list(reversed(queue)))
        stored = notify.load_queue()
        self.assertEqual([row["created_at"] for row in stored], sorted(row["created_at"] for row in stored))
