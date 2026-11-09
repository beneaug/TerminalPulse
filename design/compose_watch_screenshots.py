#!/usr/bin/env python3
"""JA Apple Watch App Store screenshots — black bg, screen-forward hero shots."""
from collections import deque
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ASSETS = Path("./design/assets/figma-assets")
WATCH_BEZEL = ASSETS / "watch-bezel.png"
RAW_WATCH = Path("./design/assets/watch-screenshot.png")
LOGO_PNG = Path("/tmp/tmuxonwatch-logo-rendered.png")
OUT_DIR = Path("./design/assets/screenshots-minimal-redesign/ja")
OUT_DIR.mkdir(parents=True, exist_ok=True)

JP_FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
EN_FONT = "/System/Library/Fonts/HelveticaNeue.ttc"

LOCALES = {
    "ja": {"font": JP_FONT, "out_dir": Path("./design/assets/screenshots-minimal-redesign/ja"),
           "title_size": 48, "title_lead": 1.04, "body_size": 19, "body_lead": 26,
           "body_y": 158, "watch_top": 222},
    "en": {"font": EN_FONT, "out_dir": Path("./design/assets/screenshots-minimal-redesign/en"),
           "title_size": 54, "title_lead": 1.10, "body_size": 19, "body_lead": 26,
           "body_y": 196, "watch_top": 252},
}
CURRENT_LOCALE = "ja"  # set in main() before each render

CANVAS_W, CANVAS_H = 410, 502
GREEN_GLOW = (56, 255, 96)
INK = (255, 255, 255, 255)
BODY = (235, 235, 235, 175)
SAFE = 26

# Bezel image is 600×940; screen area inside bezel:
BEZEL_W, BEZEL_H = 600, 940
SCREEN_TOP_FRAC = 219 / BEZEL_H   # 0.233
SCREEN_BOT_FRAC = 720 / BEZEL_H   # 0.766
SCREEN_CTR_FRAC = (SCREEN_TOP_FRAC + SCREEN_BOT_FRAC) / 2  # 0.50


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    fp = LOCALES[CURRENT_LOCALE]["font"]
    return ImageFont.truetype(fp, size, index=(1 if bold else 0))


def screen_mask(bezel_path: Path) -> Image.Image:
    bezel = Image.open(bezel_path).convert("RGBA")
    alpha = bezel.split()[3]
    w, h = bezel.size
    visited = {(w // 2, h // 2)}
    pixels = set()
    q = deque([(w // 2, h // 2)])
    while q:
        x, y = q.popleft()
        if alpha.getpixel((x, y)) > 30:
            continue
        pixels.add((x, y))
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited:
                visited.add((nx, ny))
                q.append((nx, ny))
    mask = Image.new("L", bezel.size, 0)
    md = ImageDraw.Draw(mask)
    for (x, y) in pixels:
        md.point((x, y), fill=255)
    return mask


_MASK = None
def get_mask() -> Image.Image:
    global _MASK
    if _MASK is None:
        _MASK = screen_mask(WATCH_BEZEL)
    return _MASK


def watch_mockup(target_w: int, rotate_deg: float = 0.0,
                 crop_top: float = 0.05, crop_bottom: float = 0.0) -> Image.Image:
    """Return composed watch (RGBA) at target_w. crop_top/crop_bottom: fraction
    of original bezel height to trim from each end (keep the natural top strap wrap)."""
    bezel = Image.open(WATCH_BEZEL).convert("RGBA")
    mask = get_mask()
    bbox = mask.getbbox()
    sx0, sy0, sx1, sy1 = bbox
    sw, sh = sx1 - sx0, sy1 - sy0
    raw = Image.open(RAW_WATCH).convert("RGBA")
    rw, rh = raw.size
    if rw / rh > sw / sh:
        nh = sh
        nw = int(rw * (nh / rh))
    else:
        nw = sw
        nh = int(rh * (nw / rw))
    raw = raw.resize((nw, nh), Image.LANCZOS)
    cx, cy = (nw - sw) // 2, (nh - sh) // 2
    raw = raw.crop((cx, cy, cx + sw, cy + sh))
    base = Image.new("RGBA", bezel.size, (0, 0, 0, 0))
    base.paste(raw, (sx0, sy0), mask.crop(bbox))
    base.alpha_composite(bezel)
    bw, bh = base.size
    top_px = int(bh * crop_top)
    bot_px = int(bh * crop_bottom)
    base = base.crop((0, top_px, bw, bh - bot_px))
    ratio = target_w / base.width
    base = base.resize((target_w, int(base.height * ratio)), Image.LANCZOS)
    if rotate_deg != 0:
        base = base.rotate(rotate_deg, expand=True, resample=Image.BICUBIC)
    return base


def background() -> Image.Image:
    img = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 255))
    d = ImageDraw.Draw(img, "RGBA")
    for y in range(CANVAS_H):
        t = y / CANVAS_H
        v = int(2 + 8 * t)
        d.line((0, y, CANVAS_W, y), fill=(v, v + 1, v, 255))
    glow = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow, "RGBA")
    gd.ellipse((int(CANVAS_W * 0.65), int(-CANVAS_H * 0.18),
                int(CANVAS_W * 1.20), int(CANVAS_H * 0.12)),
               fill=(*GREEN_GLOW, 22))
    gd.ellipse((int(-CANVAS_W * 0.20), int(CANVAS_H * 0.85),
                int(CANVAS_W * 0.20), int(CANVAS_H * 1.10)),
               fill=(*GREEN_GLOW, 14))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(80)))
    return img


def add_logo(img: Image.Image, x: int = 22, y: int = 18) -> None:
    if not LOGO_PNG.exists():
        return
    logo = Image.open(LOGO_PNG).convert("RGBA")
    target_h = 28
    ratio = target_h / logo.height
    logo = logo.resize((int(logo.width * ratio), target_h), Image.LANCZOS)
    # Tint to white via alpha mask
    alpha = logo.split()[3]
    white = Image.new("RGBA", logo.size, (255, 255, 255, 255))
    white.putalpha(alpha)
    img.alpha_composite(white, (x, y))


def text_lines(d: ImageDraw.ImageDraw, lines: list[str], xy: tuple[int, int],
               size: int, align: str = "left", fill=INK, leading: float = 1.04) -> int:
    f = font(size, bold=True)
    x, y = xy
    cy = y
    for line in lines:
        bb = d.textbbox((0, 0), line, font=f)
        tw = bb[2] - bb[0]
        if align == "left":
            tx = x
        elif align == "right":
            tx = CANVAS_W - SAFE - tw
        elif align == "center":
            tx = (CANVAS_W - tw) // 2
        d.text((tx, cy), line, font=f, fill=fill)
        cy += int(size * leading)
    return cy


def body_lines(d: ImageDraw.ImageDraw, lines: list[str], xy: tuple[int, int],
               align: str = "left") -> None:
    f = font(LOCALES[CURRENT_LOCALE]["body_size"], bold=False)
    x, y = xy
    for line in lines:
        bb = d.textbbox((0, 0), line, font=f)
        tw = bb[2] - bb[0]
        if align == "left":
            tx = x
        elif align == "right":
            tx = CANVAS_W - SAFE - tw
        elif align == "center":
            tx = (CANVAS_W - tw) // 2
        d.text((tx, y), line, font=f, fill=BODY)
        y += LOCALES[CURRENT_LOCALE]["body_lead"]


def add_watch_shadow(base: Image.Image, watch: Image.Image, xy: tuple[int, int]) -> None:
    x, y = xy
    alpha = watch.split()[3]
    shadow = Image.new("RGBA", watch.size, (0, 0, 0, 170))
    shadow.putalpha(alpha.filter(ImageFilter.GaussianBlur(36)))
    base.alpha_composite(shadow, (x + 4, y + 22))
    base.alpha_composite(watch, (x, y))


def place_watch_at_top(target_w: int, top_canvas_y: int,
                        crop_top: float = 0.05, crop_bottom: float = 0.0,
                        rotate_deg: float = 0.0, x_offset: int = 0
                        ) -> tuple[Image.Image, tuple[int, int]]:
    """Build watch (optionally rotated/cropped); horizontally center then offset by x_offset."""
    watch = watch_mockup(target_w, rotate_deg=rotate_deg,
                         crop_top=crop_top, crop_bottom=crop_bottom)
    x = (CANVAS_W - watch.width) // 2 + x_offset
    return watch, (x, top_canvas_y)


# ─────────────────────────────────────────────────────────────────────────────
# Slides — black bg, screen-forward, varied composition
# ─────────────────────────────────────────────────────────────────────────────

WATCH_W = 300       # watch hero width — with crop_top=0.05 → h ≈ 446, bleeds bottom
WATCH_TOP = 222     # canvas y for top of watch (just below body text)
TITLE_Y = 50
BODY_Y = 158


def title_size() -> int:
    return LOCALES[CURRENT_LOCALE]["title_size"]


def _hero(title_lines: list[str], body_lines_l: list[str], align: str,
          rotate_deg: float = 0.0, x_offset: int = 0,
          title_lead_override=None) -> Image.Image:
    cfg = LOCALES[CURRENT_LOCALE]
    img = background()
    d = ImageDraw.Draw(img, "RGBA")
    text_x = (SAFE if align == "left" else 0, TITLE_Y)
    body_xy = (SAFE if align == "left" else 0, cfg["body_y"])
    lead = title_lead_override if title_lead_override is not None else cfg["title_lead"]
    text_lines(d, title_lines, text_x, size=title_size(), align=align,
               leading=lead)
    body_lines(d, body_lines_l, body_xy, align=align)
    watch, pos = place_watch_at_top(target_w=WATCH_W, top_canvas_y=cfg["watch_top"],
                                     rotate_deg=rotate_deg, x_offset=x_offset)
    add_watch_shadow(img, watch, pos)
    return img


# (title_lines, body_lines, align, rotate_deg, x_offset)
SLIDES = {
    "ja": [
        (["手首に", "tmux。"],     ["Macのtmux出力を", "Apple Watchへ。"], "left",   -5,  18),
        (["完了を", "逃さない。"],  ["長い処理の終わりを", "手元に通知。"], "right",   6, -22),
        (["ウォッチで", "入力。"],  ["音声、Scribble、キー。"],            "center",  0,   0),
        (["iPhoneで", "つなぐ。"],  ["QRひとつで", "セットアップ完了。"],   "right",  -7, -18),
        (["進捗を", "ひと目で。"],  ["席に戻らず", "最新出力を確認。"],     "left",    4,  12),
    ],
    "en": [
        (["tmux", "on wrist."],     ["Mac tmux output, live", "on Apple Watch."],  "left",   -5,  18, 0.95),
        (["Never miss", "the moment."],["Get pinged when long", "jobs end."],       "right",   6, -22, None),
        (["Type from", "your wrist."],["Voice, Scribble, keys."],                   "center",  0,   0, None),
        (["Connect", "via iPhone."],  ["One QR scan to set up."],                   "right",  -7, -18, None),
        (["Progress at", "a glance."],["See latest output", "without leaving."],    "left",    4,  12, None),
    ],
}


def render_slide(idx: int, spec: tuple) -> Image.Image:
    if len(spec) == 6:
        title, body, align, rot, xoff, lead = spec
    else:
        title, body, align, rot, xoff = spec
        lead = None
    return _hero(title, body, align=align, rotate_deg=rot, x_offset=xoff,
                 title_lead_override=lead)


def main() -> None:
    global CURRENT_LOCALE
    for loc in ("ja", "en"):
        CURRENT_LOCALE = loc
        out_dir = LOCALES[loc]["out_dir"]
        out_dir.mkdir(parents=True, exist_ok=True)
        prefix = loc
        for i, spec in enumerate(SLIDES[loc], 1):
            img = render_slide(i, spec).convert("RGB")
            out = out_dir / f"{prefix}-watch-{i:02d}-49-410x502.png"
            img.save(out, "PNG", optimize=True)
            print(f"wrote {out}")


if __name__ == "__main__":
    main()
