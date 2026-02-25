from pathlib import Path
import sys
import unittest
from unittest.mock import AsyncMock, patch

SERVER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_DIR))

import tmux_bridge


class ValidateTargetTests(unittest.TestCase):
    def test_accepts_none(self):
        self.assertIsNone(tmux_bridge._validate_target(None))

    def test_accepts_valid_target(self):
        self.assertEqual(tmux_bridge._validate_target("work:2.1"), "work:2.1")

    def test_rejects_invalid_target(self):
        with self.assertRaises(ValueError):
            tmux_bridge._validate_target("work:2; rm -rf /")


class SendKeysValidationTests(unittest.IsolatedAsyncioTestCase):
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
            "echo hi",
        )

    async def test_sends_special_key(self):
        with patch.object(tmux_bridge, "_run", AsyncMock(return_value="")) as run_mock:
            await tmux_bridge.send_keys(special="Enter")
        run_mock.assert_awaited_once_with("tmux", "send-keys", "Enter")


if __name__ == "__main__":
    unittest.main()
