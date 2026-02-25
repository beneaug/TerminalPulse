from pathlib import Path
import sys
import unittest

SERVER_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SERVER_DIR))

from ansi_parser import parse_lines


class AnsiParserTests(unittest.TestCase):
    def test_basic_color_then_reset(self):
        parsed = parse_lines("\x1b[31mred\x1b[0m plain")
        self.assertEqual(parsed[0][0]["t"], "red")
        self.assertEqual(parsed[0][0]["fg"], "red")
        self.assertEqual(parsed[0][1]["t"], " plain")
        self.assertNotIn("fg", parsed[0][1])

    def test_reverse_defaults(self):
        parsed = parse_lines("\x1b[7mrev\x1b[0m")
        run = parsed[0][0]
        self.assertEqual(run["fg"], "_defBg")
        self.assertEqual(run["bg"], "_defFg")

    def test_strips_non_sgr_escapes(self):
        parsed = parse_lines("hello\x1b]0;title\x07 world")
        self.assertEqual(parsed[0][0]["t"], "hello world")


if __name__ == "__main__":
    unittest.main()
