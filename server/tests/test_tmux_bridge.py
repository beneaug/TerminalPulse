from pathlib import Path
import asyncio
import sys
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

SERVER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_DIR))

import tmux_bridge


class ValidateTargetTests(unittest.TestCase):
    def test_rejects_trailing_newline(self):
        with self.assertRaises(ValueError):
            tmux_bridge._validate_target("work\n")
    def test_accepts_none(self):
        self.assertIsNone(tmux_bridge._validate_target(None))

    def test_accepts_valid_target(self):
        self.assertEqual(tmux_bridge._validate_target("work:2.1"), "work:2.1")

    def test_rejects_invalid_target(self):
        with self.assertRaises(ValueError):
            tmux_bridge._validate_target("work:2; rm -rf /")


class SendKeysValidationTests(unittest.IsolatedAsyncioTestCase):
    async def test_timed_out_child_is_killed_and_reaped(self):
        proc = MagicMock(returncode=None)
        proc.communicate = AsyncMock(side_effect=[asyncio.TimeoutError(), (b"", b"")])
        with patch.object(asyncio, "create_subprocess_exec", AsyncMock(return_value=proc)):
            with self.assertRaises(RuntimeError):
                await tmux_bridge._run("tmux", "display-message")
        proc.kill.assert_called_once()
        self.assertEqual(proc.communicate.await_count, 2)

    async def test_cancelled_child_is_killed_and_reaped(self):
        proc = MagicMock(returncode=None)
        proc.communicate = AsyncMock(side_effect=[asyncio.CancelledError(), (b"", b"")])
        with patch.object(asyncio, "create_subprocess_exec", AsyncMock(return_value=proc)):
            with self.assertRaises(asyncio.CancelledError):
                await tmux_bridge._run("tmux", "display-message")
        proc.kill.assert_called_once()
        self.assertEqual(proc.communicate.await_count, 2)

    async def test_rejects_both_text_and_special(self):
        with self.assertRaises(ValueError):
            await tmux_bridge.send_keys(text="ls", special="Enter")

    async def test_rejects_when_missing_text_and_special(self):
        with self.assertRaises(ValueError):
            await tmux_bridge.send_keys()

    async def test_rejects_disallowed_special_key(self):
        with self.assertRaises(ValueError):
            await tmux_bridge.send_keys(special="F1")

    async def test_rejects_oversized_text(self):
        with self.assertRaises(ValueError):
            await tmux_bridge.send_keys(text="x" * 513)

    async def test_sends_literal_text_with_target(self):
        with patch.object(tmux_bridge, "_run", AsyncMock(return_value="")) as run_mock:
            await tmux_bridge.send_keys(text="echo hi", target="dev:1")
        run_mock.assert_awaited_once_with(
            "tmux",
            "send-keys",
            "-l",
            "-t",
            "dev:1",
            "--",
            "echo hi",
        )

    async def test_sends_special_key(self):
        with patch.object(tmux_bridge, "_run", AsyncMock(return_value="")) as run_mock:
            await tmux_bridge.send_keys(special="Enter")
        run_mock.assert_awaited_once_with("tmux", "send-keys", "Enter")

    async def test_dash_prefixed_text_cannot_become_an_option(self):
        with patch.object(tmux_bridge, "_run", AsyncMock(return_value="")) as run:
            await tmux_bridge.send_keys(text="-R")
        run.assert_awaited_once_with("tmux", "send-keys", "-l", "--", "-R")

    async def test_session_with_multiple_attached_clients(self):
        with patch.object(tmux_bridge, "_run", AsyncMock(return_value="dev\x1f2\x1f3\n")):
            sessions = await tmux_bridge.list_sessions()
        self.assertTrue(sessions[0].attached)

    async def test_window_name_can_contain_separator_character(self):
        with patch.object(tmux_bridge, "_run", AsyncMock(return_value="dev\x1f2\x1fa|b\x1f1\n")):
            windows = await tmux_bridge.list_windows()
        self.assertEqual(windows[0].window_name, "a|b")


if __name__ == "__main__":
    unittest.main()
