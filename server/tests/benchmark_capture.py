"""Synthetic capture microbenchmark; no real tmux, credentials, radio or disk I/O.

Compares this handler's legacy full-response path against its conditional path.
This is not a device battery benchmark or an old-versus-new server measurement.
"""
import asyncio
import json
import os
from pathlib import Path
import statistics
import sys
import time
from unittest.mock import AsyncMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
os.environ["TP_TOKEN"] = "synthetic-benchmark-token"
import main
from starlette.requests import Request
from starlette.responses import Response
from tmux_bridge import PaneInfo


async def benchmark():
    raw = "\n".join(f"\x1b[32m{i:03d}\x1b[0m Compiling 模組 {i}: " + "x" * 60 for i in range(80))
    pane = PaneInfo("demo", 0, "build", "%1", "swift")
    async def capture(compact=False, etag=None):
        headers = [(b"if-none-match", etag.encode())] if etag else []
        response = Response()
        value = await main.capture(Request({"type": "http", "headers": headers}), response,
                                   "synthetic", 80, None, compact)
        size = len(value.body) if isinstance(value, Response) else len(json.dumps(value, ensure_ascii=False, separators=(",", ":")).encode())
        return value, response, size

    with patch.object(main, "get_pane_info", AsyncMock(return_value=pane)), \
         patch.object(main, "capture_pane", AsyncMock(return_value=raw)):
        _, _, full_size = await capture()
        _, response, compact_size = await capture(compact=True)
        etag = response.headers["etag"]
        timings = {}
        for label, conditional in [("legacy_full", False), ("conditional_unchanged", True)]:
            samples = []
            with patch.object(main, "parse_lines", wraps=main.parse_lines) as parser:
                for _ in range(200):
                    start = time.perf_counter()
                    value, _, size = await capture(compact=conditional, etag=etag if conditional else None)
                    samples.append((time.perf_counter() - start) * 1000)
                    if conditional:
                        assert value.status_code == 304 and size == 0
                timings[label] = {"median_ms": round(statistics.median(samples), 3), "parse_calls": parser.call_count}
        print(json.dumps({"fixture_lines": 80, "samples_per_path": 200,
                          "full_body_bytes": full_size, "compact_body_bytes": compact_size,
                          "unchanged_body_bytes": 0, "timings": timings}, indent=2))


if __name__ == "__main__":
    asyncio.run(benchmark())
