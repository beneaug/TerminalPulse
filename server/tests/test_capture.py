import asyncio
import os
from pathlib import Path
import sys
import unittest
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ["TP_TOKEN"] = "unit-test-token"
import main
from starlette.requests import Request
from starlette.responses import Response
from tmux_bridge import PaneInfo
from fastapi.security import HTTPAuthorizationCredentials
from fastapi import HTTPException


class CaptureTests(unittest.IsolatedAsyncioTestCase):
    async def test_non_ascii_invalid_token_is_rejected_not_a_server_error(self):
        with self.assertRaises(HTTPException) as error:
            main._verify(HTTPAuthorizationCredentials(scheme="Bearer", credentials="無効なトークン"))
        self.assertEqual(error.exception.status_code, 401)

    async def test_missing_tmux_is_a_gateway_error(self):
        with patch.object(main, "list_sessions", AsyncMock(side_effect=FileNotFoundError("tmux"))):
            with self.assertRaises(HTTPException) as error:
                await main.sessions("test")
        self.assertEqual(error.exception.status_code, 502)

    async def asyncSetUp(self):
        self.pane = PaneInfo("dev", 1, "build", "%1", "zsh")
        self.info = patch.object(main, "get_pane_info", AsyncMock(return_value=self.pane))
        self.raw = patch.object(main, "capture_pane", AsyncMock(return_value="\x1b[32mready\x1b[0m\n"))
        self.info.start()
        self.capture_mock = self.raw.start()
        self.addCleanup(self.info.stop)
        self.addCleanup(self.raw.stop)

    async def capture(self, etag=None, compact=False):
        headers = [] if etag is None else [(b"if-none-match", etag.encode())]
        request = Request({"type": "http", "headers": headers})
        response = Response()
        value = await main.capture(request, response, "test", 80, None, compact)
        return value, response

    async def test_unchanged_returns_no_body_without_parsing(self):
        value, response = await self.capture(compact=True)
        self.assertEqual(value["raw"], "")
        self.assertEqual(value["parsed_lines"][0][0]["t"], "ready")
        with patch.object(main, "parse_lines") as parser:
            second, _ = await self.capture(etag=response.headers["etag"], compact=True)
        self.assertEqual(second.status_code, 304)
        self.assertEqual(second.body, b"")
        parser.assert_not_called()

    async def test_metadata_change_invalidates_etag(self):
        _, response = await self.capture()
        self.pane.window_name = "renamed"
        value, second = await self.capture(etag=response.headers["etag"])
        self.assertIsInstance(value, dict)
        self.assertNotEqual(response.headers["etag"], second.headers["etag"])

    async def test_command_change_invalidates_etag(self):
        _, response = await self.capture()
        self.pane.pane_current_command = "python3"
        value, _ = await self.capture(etag=response.headers["etag"])
        self.assertEqual(value["pane"]["paneCurrentCommand"], "python3")

    async def test_legacy_raw_preserved_and_pane_target_resolved(self):
        value, _ = await self.capture()
        self.assertIn("\x1b[32m", value["raw"])
        self.capture_mock.assert_awaited_once_with(lines=80, target="%1")

    async def test_simultaneous_clients_share_capture(self):
        async def slow_capture(**kwargs):
            await asyncio.sleep(0.02)
            return "ready"
        self.capture_mock.side_effect = slow_capture
        await asyncio.gather(self.capture(), self.capture(), self.capture())
        self.capture_mock.assert_awaited_once()

    async def test_disconnect_does_not_cancel_other_client(self):
        async def slow_capture(**kwargs):
            await asyncio.sleep(0.02)
            return "ready"
        self.capture_mock.side_effect = slow_capture
        first = asyncio.create_task(self.capture())
        second = asyncio.create_task(self.capture())
        await asyncio.sleep(0.005)
        first.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await first
        value, _ = await second
        self.assertEqual(value["raw"], "ready")
        self.capture_mock.assert_awaited_once()
