"""ANSI SGR escape sequence parser.

Converts raw terminal text (with escape codes) into structured runs:
  [{"t": "hello", "fg": "green", "b": true}, ...]
"""

from __future__ import annotations

import re
from typing import Any

# Match SGR sequences (ending in 'm') for splitting, plus strip all other
# ANSI escape sequences (CSI, OSC, title sets, etc.) that we don't render.
_ESC_RE = re.compile(r"(\x1b\[[0-9;]*m)")
_STRIP_RE = re.compile(r"\x1b(?:\][^\x07\x1b]*(?:\x07|\x1b\\)|\[[0-9;]*[A-HJKSTfhln]|\([AB012])")

_BASIC_FG = {
    30: "black", 31: "red", 32: "green", 33: "yellow",
    34: "blue", 35: "magenta", 36: "cyan", 37: "white",
    90: "brBlack", 91: "brRed", 92: "brGreen", 93: "brYellow",
    94: "brBlue", 95: "brMagenta", 96: "brCyan", 97: "brWhite",
}

_BASIC_BG = {
    40: "black", 41: "red", 42: "green", 43: "yellow",
    44: "blue", 45: "magenta", 46: "cyan", 47: "white",
    100: "brBlack", 101: "brRed", 102: "brGreen", 103: "brYellow",
    104: "brBlue", 105: "brMagenta", 106: "brCyan", 107: "brWhite",
}

# 256-color palette: indices 0-15 map to named colors
_COLOR_256_NAMES = [
    "black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
    "brBlack", "brRed", "brGreen", "brYellow", "brBlue", "brMagenta", "brCyan", "brWhite",
]


def _color_256(n: int) -> str:
    """Convert a 256-color index to a named color or #rrggbb hex string."""
    if 0 <= n <= 15:
        return _COLOR_256_NAMES[n]
    if 16 <= n <= 231:
        n -= 16
        r = (n // 36) * 51
        g = ((n % 36) // 6) * 51
        b = (n % 6) * 51
        return f"#{r:02x}{g:02x}{b:02x}"
    if 232 <= n <= 255:
        v = 8 + (n - 232) * 10
        return f"#{v:02x}{v:02x}{v:02x}"
    return "white"


class _State:
    __slots__ = ("fg", "bg", "bold", "dim", "italic", "underline", "reverse")

    def __init__(self) -> None:
        self.fg: str | None = None
        self.bg: str | None = None
        self.bold: bool = False
        self.dim: bool = False
        self.italic: bool = False
        self.underline: bool = False
        self.reverse: bool = False

    def reset(self) -> None:
        self.fg = None
        self.bg = None
        self.bold = False
        self.dim = False
        self.italic = False
        self.underline = False
        self.reverse = False

    def to_run(self, text: str) -> dict[str, Any]:
        """Build a compact run dict, omitting falsy fields."""
        run: dict[str, Any] = {"t": text}
        fg, bg = self.fg, self.bg
        # SGR 7 (reverse video): swap fg and bg for rendering
        if self.reverse:
            fg, bg = bg, fg
            # When reversed, missing fg becomes "default_bg" and missing bg becomes "default_fg"
            if fg is None:
                fg = "_defBg"
            if bg is None:
                bg = "_defFg"
        if fg:
            run["fg"] = fg
        if bg:
            run["bg"] = bg
        if self.bold:
            run["b"] = True
        if self.dim:
            run["d"] = True
        if self.italic:
            run["i"] = True
        if self.underline:
            run["u"] = True
        return run


def _apply_sgr(state: _State, params: list[int]) -> None:
    """Apply SGR parameter codes to the current state."""
    i = 0
    while i < len(params):
        p = params[i]
        if p == 0:
            state.reset()
        elif p == 1:
            state.bold = True
        elif p == 2:
            state.dim = True
        elif p == 3:
            state.italic = True
        elif p == 4:
            state.underline = True
        elif p == 22:
            state.bold = False
            state.dim = False
        elif p == 23:
            state.italic = False
        elif p == 7:
            state.reverse = True
        elif p == 24:
            state.underline = False
        elif p == 27:
            state.reverse = False
        elif p == 39:
            state.fg = None
        elif p == 49:
            state.bg = None
        elif p in _BASIC_FG:
            state.fg = _BASIC_FG[p]
        elif p in _BASIC_BG:
            state.bg = _BASIC_BG[p]
        elif p == 38:  # extended fg
            if i + 1 < len(params) and params[i + 1] == 5 and i + 2 < len(params):
                state.fg = _color_256(params[i + 2])
                i += 2
            elif i + 1 < len(params) and params[i + 1] == 2 and i + 4 < len(params):
                r, g, b = params[i + 2], params[i + 3], params[i + 4]
                state.fg = f"#{r:02x}{g:02x}{b:02x}"
                i += 4
        elif p == 48:  # extended bg
            if i + 1 < len(params) and params[i + 1] == 5 and i + 2 < len(params):
                state.bg = _color_256(params[i + 2])
                i += 2
            elif i + 1 < len(params) and params[i + 1] == 2 and i + 4 < len(params):
                r, g, b = params[i + 2], params[i + 3], params[i + 4]
                state.bg = f"#{r:02x}{g:02x}{b:02x}"
                i += 4
        i += 1


def parse_line(line: str, state: _State) -> list[dict[str, Any]]:
    """Parse a single line with ANSI escapes into a list of runs.

    The state is mutated in-place so it carries across lines.
    """
    # Strip non-SGR ANSI escapes (OSC, cursor movement, title sets) first
    line = _STRIP_RE.sub("", line)
    tokens = _ESC_RE.split(line)
    runs: list[dict[str, Any]] = []
    for token in tokens:
        if not token:
            continue
        if token.startswith("\x1b["):
            param_str = token[2:-1]  # strip ESC[ and m
            params = []
            for s in param_str.split(";"):
                try:
                    params.append(int(s))
                except ValueError:
                    params.append(0)
            _apply_sgr(state, params)
        else:
            runs.append(state.to_run(token))
    return runs


def parse_lines(raw: str) -> list[list[dict[str, Any]]]:
    """Parse multi-line raw terminal output into structured runs.

    Returns a list of lines, each line a list of run dicts.
    """
    state = _State()
    result: list[list[dict[str, Any]]] = []
    for line in raw.split("\n"):
        result.append(parse_line(line, state))
    return result
