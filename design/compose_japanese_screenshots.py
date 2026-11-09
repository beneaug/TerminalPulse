#!/usr/bin/env python3
"""
Minimal App Store screenshot compositor for tmuxonwatch.

Exports matching English and Japanese screenshot sets using the dark,
terminal-forward direction from tmuxonwatch.com.

Output:
  ./design/assets/screenshots-minimal-redesign/{en,ja}/
"""

from __future__ import annotations

import subprocess
from collections import deque
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path("./design/assets")
ASSETS = ROOT / "figma-assets"
OUTPUT = ROOT / "screenshots-minimal-redesign"

IPHONE_BEZEL = ASSETS / "iphone-bezel.png"
WATCH_BEZEL = ASSETS / "watch-bezel.png"
LOGO_SVG = Path("./design/assets/logo.svg")
IPHONE_SCREENSHOT = Path(
    "./design/assets/iphone-screenshot.png"
)
RAW_WATCH_SCREENSHOT = Path(
    "./design/assets/watch-screenshot.png"
)
WATCH_SCREENSHOTS_DIR = ROOT / "screenshots-watch"

JP_FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"
LATIN_FONT = "/System/Library/Fonts/HelveticaNeue.ttc"
MONO_FONT = "/System/Library/Fonts/Menlo.ttc"

IPHONE_SCREEN_BBOX = (90, 90, 1268, 2645)
WATCH_SCREEN_BBOX = (95, 219, 504, 720)

CANVASES = {
    "69-1260": (1260, 2736),
    "69-1290": (1290, 2796),
    "69-1320": (1320, 2868),
    "65-1284": (1284, 2778),
    "65-1242": (1242, 2688),
}

INK = (245, 247, 245)
MUTED = (154, 162, 156)
DIM = (92, 100, 95)
PANEL = (10, 11, 10)
PANEL_2 = (15, 17, 16)
STROKE = (42, 48, 44)
GREEN = (104, 255, 119)
GREEN_DIM = (41, 190, 78)
BLUE = (92, 178, 255)
YELLOW = (220, 204, 98)
RED = (255, 104, 104)


def font(size: int, weight: str = "regular", mono: bool = False, latin: bool = False) -> ImageFont.FreeTypeFont:
    if mono:
        return ImageFont.truetype(MONO_FONT, size, index=0)
    if latin:
        return ImageFont.truetype(LATIN_FONT, size, index=1 if weight == "bold" else 0)
    return ImageFont.truetype(JP_FONT, size, index=1 if weight == "bold" else 0)


def fit_cover(img: Image.Image, size: tuple[int, int]) -> Image.Image:
    img = img.convert("RGBA")
    w, h = size
    iw, ih = img.size
    scale = max(w / iw, h / ih)
    nw, nh = int(iw * scale), int(ih * scale)
    resized = img.resize((nw, nh), Image.LANCZOS)
    return resized.crop(((nw - w) // 2, (nh - h) // 2, (nw + w) // 2, (nh + h) // 2))


def screen_mask(bezel_path: Path) -> Image.Image:
    bezel = Image.open(bezel_path).convert("RGBA")
    alpha = bezel.split()[3]
    w, h = bezel.size
    q: deque[tuple[int, int]] = deque([(w // 2, h // 2)])
    visited = {(w // 2, h // 2)}
    pixels: list[tuple[int, int]] = []

    while q:
        x, y = q.popleft()
        if alpha.getpixel((x, y)) > 30:
            continue
        pixels.append((x, y))
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited:
                visited.add((nx, ny))
                q.append((nx, ny))

    mask = Image.new("L", (w, h), 0)
    for px, py in pixels:
        mask.putpixel((px, py), 255)
    return mask


IPHONE_MASK = screen_mask(IPHONE_BEZEL)
WATCH_MASK = screen_mask(WATCH_BEZEL)


def device_mockup(
    bezel_path: Path,
    screenshot: Path | Image.Image,
    bbox: tuple[int, int, int, int],
    mask: Image.Image,
    target_w: int,
) -> Image.Image:
    bezel = Image.open(bezel_path).convert("RGBA")
    shot = screenshot.convert("RGBA") if isinstance(screenshot, Image.Image) else Image.open(screenshot).convert("RGBA")
    bw, bh = bezel.size
    scale = target_w / bw
    target_h = int(bh * scale)
    bezel_s = bezel.resize((target_w, target_h), Image.LANCZOS)
    sl, st, sr, sb = [int(v * scale) for v in bbox]
    sw, sh = sr - sl, sb - st
    shot_crop = fit_cover(shot, (sw, sh))

    out = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 0))
    mask_s = mask.resize((target_w, target_h), Image.LANCZOS)
    fill_mask = mask_s
    for _ in range(2):
        fill_mask = fill_mask.filter(ImageFilter.MaxFilter(21))
    dark = Image.new("RGBA", (target_w, target_h), (0, 0, 0, 255))
    out = Image.composite(dark, out, fill_mask)
    out.paste(shot_crop, (sl, st), shot_crop)
    return Image.alpha_composite(out, bezel_s)


def watch_screen_from_asset(index: int) -> Image.Image:
    return Image.open(RAW_WATCH_SCREENSHOT).convert("RGBA")


def add_shadow(base: Image.Image, obj: Image.Image, xy: tuple[int, int], radius: int = 44, opacity: int = 120) -> None:
    x, y = xy
    alpha = obj.split()[3]
    shadow = Image.new("RGBA", obj.size, (0, 0, 0, opacity))
    shadow.putalpha(alpha.filter(ImageFilter.GaussianBlur(radius)))
    base.alpha_composite(shadow, (x, y + radius // 2))
    base.alpha_composite(obj, xy)


def background(size: tuple[int, int]) -> Image.Image:
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 255))
    d = ImageDraw.Draw(img, "RGBA")
    for y in range(h):
        t = y / h
        v = int(2 + 9 * t)
        d.line((0, y, w, y), fill=(v, v + 1, v, 255))
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow, "RGBA")
    gd.ellipse((int(w * 0.70), int(-h * 0.18), int(w * 1.10), int(h * 0.10)), fill=(56, 255, 96, 18))
    gd.ellipse((int(-w * 0.14), int(h * 0.84), int(w * 0.16), int(h * 1.04)), fill=(56, 255, 96, 12))
    img = Image.alpha_composite(img, glow.filter(ImageFilter.GaussianBlur(110)))
    d = ImageDraw.Draw(img, "RGBA")
    d.line((int(w * 0.074), int(h * 0.312), int(w * 0.926), int(h * 0.312)), fill=(255, 255, 255, 20), width=1)
    return img


def wrap(draw: ImageDraw.ImageDraw, text: str, fnt: ImageFont.FreeTypeFont, max_w: int) -> list[str]:
    lines: list[str] = []
    for raw in text.split("\n"):
        current = ""
        for chunk in raw.split(" ") if " " in raw else list(raw):
            candidate = (current + " " + chunk).strip() if " " in raw else current + chunk
            if current and draw.textlength(candidate, font=fnt) > max_w:
                lines.append(current)
                current = chunk
            else:
                current = candidate
        if current:
            lines.append(current)
    return lines


def text_block(
    draw: ImageDraw.ImageDraw,
    xy: tuple[int, int],
    title: str,
    body: str,
    width: int,
    locale: str,
) -> None:
    x, y = xy
    title_size = 108 if locale == "en" else 92
    title_font = font(title_size, "bold", latin=(locale == "en"))
    body_font = font(56 if locale == "en" else 50, latin=(locale == "en"))
    for line in wrap(draw, title, title_font, width):
        draw.text((x, y), line, font=title_font, fill=INK)
        y += int(title_size * 1.03)
    y += 28
    for line in wrap(draw, body, body_font, width):
        draw.text((x, y), line, font=body_font, fill=MUTED)
        y += int(body_font.size * 1.22)


_WHITE_LOGO: Image.Image | None = None


def white_logo() -> Image.Image:
    global _WHITE_LOGO
    if _WHITE_LOGO is not None:
        return _WHITE_LOGO

    tmp = Path("/tmp/tmuxonwatch-logo-rendered.png")
    subprocess.run(
        ["sips", "-s", "format", "png", str(LOGO_SVG), "--out", str(tmp)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    rendered = Image.open(tmp).convert("RGBA")
    alpha = rendered.split()[3]
    bbox = alpha.getbbox()
    if bbox:
        alpha = alpha.crop(bbox)
    logo_img = Image.new("RGBA", alpha.size, (255, 255, 255, 0))
    logo_img.putalpha(alpha)
    _WHITE_LOGO = logo_img
    return logo_img


def logo(img: Image.Image) -> None:
    mark = white_logo()
    target_w = int(img.width * 0.17)
    target_h = int(mark.height * target_w / mark.width)
    mark = mark.resize((target_w, target_h), Image.LANCZOS)
    img.alpha_composite(mark, (76, 72))


def terminal(size: tuple[int, int], title: str, lines: list[tuple[str, tuple[int, int, int]]]) -> Image.Image:
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle((0, 0, w, h), radius=26, fill=PANEL + (246,), outline=STROKE + (180,), width=1)
    d.ellipse((24, 24, 44, 44), fill=RED + (220,))
    d.ellipse((56, 24, 76, 44), fill=YELLOW + (220,))
    d.ellipse((88, 24, 108, 44), fill=GREEN_DIM + (220,))
    d.text((132, 18), title, font=font(24, latin=True), fill=DIM)
    mono = font(36, mono=True)
    y = 86
    for text, color in lines:
        for line in wrap(d, text, mono, w - 70):
            d.text((34, y), line, font=mono, fill=color)
            y += 52
            if y > h - 44:
                return img
    return img


def panel(size: tuple[int, int], heading: str, rows: list[tuple[str, str, tuple[int, int, int]]], locale: str) -> Image.Image:
    w, h = size
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    d.rounded_rectangle((0, 0, w, h), radius=24, fill=PANEL_2 + (238,), outline=STROKE + (180,), width=1)
    d.text((30, 28), heading, font=font(32, "bold", latin=(locale == "en")), fill=INK)
    y = 94
    for label, value, color in rows:
        d.text((30, y), label, font=font(25, latin=True), fill=DIM)
        vf = font(27, "bold", latin=True)
        vw = d.textlength(value, font=vf)
        d.text((w - 30 - vw, y - 1), value, font=vf, fill=color)
        y += 54
    return img


def watch_asset(index: int) -> Path:
    return WATCH_SCREENSHOTS_DIR / f"watch-{index:02d}.png"


@dataclass(frozen=True)
class Slide:
    title: str
    body: str
    kind: str


SLIDES = {
    "en": [
        Slide("Your terminal.\nOn your wrist.", "Live tmux output on Apple Watch.", "hero"),
        Slide("Know when it finishes.", "Get notified when long jobs complete.", "terminal"),
        Slide("Connect from iPhone.", "Scan the QR and choose what to watch.", "iphone"),
        Slide("Check progress\nat a glance.", "See the latest output without going back.", "watch"),
        Slide("Pin what matters.", "Follow focus or lock onto one session.", "target"),
        Slide("Runs on your Mac.", "A lightweight local server.", "local"),
    ],
    "ja": [
        Slide("tmuxを手首に", "Macのtmux出力をApple Watchへ。", "hero"),
        Slide("完了の瞬間を逃さない", "長い処理の完了を手元に通知。", "terminal"),
        Slide("iPhoneで接続", "QRを読み取り、監視先を選ぶ。", "iphone"),
        Slide("進捗を\nひと目で確認", "席に戻らず最新出力を確認。", "watch"),
        Slide("見たい先を固定", "フォーカス追従も固定監視も。", "target"),
        Slide("自分のMacで動く", "軽量なローカルサーバー方式。", "local"),
    ],
}


def render(slide: Slide, size: tuple[int, int], locale: str) -> Image.Image:
    w, h = size
    img = background(size)
    d = ImageDraw.Draw(img, "RGBA")
    logo(img)
    margin = int(w * 0.074)
    text_block(d, (margin, int(h * 0.118)), slide.title, slide.body, int(w * 0.78), locale)

    if slide.kind == "hero":
        phone = device_mockup(IPHONE_BEZEL, IPHONE_SCREENSHOT, IPHONE_SCREEN_BBOX, IPHONE_MASK, int(w * 0.60))
        watch = device_mockup(WATCH_BEZEL, watch_screen_from_asset(0), WATCH_SCREEN_BBOX, WATCH_MASK, int(w * 0.39))
        term = terminal((int(w * 0.65), int(h * 0.16)), "tmux", [
            ("$ tokenmax --watch", GREEN),
            ("training/eval 98% eta 00:12", INK),
        ])
        add_shadow(img, phone, (int(w * 0.46), int(h * 0.38)), 52, 130)
        add_shadow(img, watch, (int(w * 0.075), int(h * 0.53)), 42, 120)
        img.alpha_composite(term, (margin, int(h * 0.72)))

    elif slide.kind == "terminal":
        term = terminal((w - 2 * margin, int(h * 0.32)), "tmux pane 0:build", [
            ("$ pnpm build && pnpm test", GREEN),
            ("✓ compiled in 18.4s", GREEN),
            ("✓ 246 tests passed", GREEN),
            ("watch alert: finished", BLUE),
        ])
        img.alpha_composite(term, (margin, int(h * 0.41)))
        watch = device_mockup(WATCH_BEZEL, watch_screen_from_asset(0), WATCH_SCREEN_BBOX, WATCH_MASK, int(w * 0.48))
        add_shadow(img, watch, (int(w * 0.48), int(h * 0.55)), 42, 118)

    elif slide.kind == "iphone":
        phone = device_mockup(IPHONE_BEZEL, IPHONE_SCREENSHOT, IPHONE_SCREEN_BBOX, IPHONE_MASK, int(w * 0.66))
        add_shadow(img, phone, (int(w * 0.40), int(h * 0.36)), 52, 125)
        heading = "Connection" if locale == "en" else "接続状態"
        p = panel((int(w * 0.48), 268), heading, [
            ("Server", "Online", GREEN),
            ("Watch", "Reachable", GREEN),
            ("Target", "0:server", BLUE),
        ], locale)
        img.alpha_composite(p, (margin, int(h * 0.58)))

    elif slide.kind == "watch":
        watch = device_mockup(WATCH_BEZEL, watch_screen_from_asset(0), WATCH_SCREEN_BBOX, WATCH_MASK, int(w * 0.61))
        add_shadow(img, watch, (int(w * 0.18), int(h * 0.37)), 54, 135)

    elif slide.kind == "target":
        heading = "Target" if locale == "en" else "監視ターゲット"
        target_panel = panel((int(w * 0.50), 360), heading, [
            ("Mode", "Focus", GREEN),
            ("Session", "work", INK),
            ("Window", "api", BLUE),
            ("Pane", "active", YELLOW),
        ], locale)
        phone = device_mockup(IPHONE_BEZEL, IPHONE_SCREENSHOT, IPHONE_SCREEN_BBOX, IPHONE_MASK, int(w * 0.56))
        add_shadow(img, phone, (int(w * 0.38), int(h * 0.40)), 50, 125)
        img.alpha_composite(target_panel, (margin, int(h * 0.56)))

    elif slide.kind == "local":
        term = terminal((w - 2 * margin, int(h * 0.37)), "tmuxonwatch server", [
            ("$ brew install beneaug/tmuxonwatch/tmuxonwatch", GREEN),
            ("$ tmuxonwatch-install", GREEN),
            ("✓ server api check passed", GREEN),
            ("✓ QR pairing ready", BLUE),
            ("localhost + trusted network", MUTED),
        ])
        img.alpha_composite(term, (margin, int(h * 0.42)))

    return img


def contact_sheet(images: list[tuple[str, Image.Image]]) -> Image.Image:
    thumb_w = 322
    thumb_h = 699
    gutter = 28
    cols = 3
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * thumb_w + (cols + 1) * gutter, rows * (thumb_h + 54) + gutter), (5, 5, 5))
    d = ImageDraw.Draw(sheet)
    for idx, (name, im) in enumerate(images):
        row, col = divmod(idx, cols)
        x = gutter + col * (thumb_w + gutter)
        y = gutter + row * (thumb_h + 54)
        sheet.paste(im.convert("RGB").resize((thumb_w, thumb_h), Image.LANCZOS), (x, y))
        d.text((x, y + thumb_h + 14), name, font=ImageFont.truetype(LATIN_FONT, 18, index=0), fill=(170, 176, 170))
    return sheet


def main() -> None:
    for locale, slides in SLIDES.items():
        out = OUTPUT / locale
        out.mkdir(parents=True, exist_ok=True)
        for old in out.glob("*.png"):
            old.unlink()

        sheet_images: list[tuple[str, Image.Image]] = []
        for suffix, size in CANVASES.items():
            for index, slide in enumerate(slides, start=1):
                im = render(slide, size, locale)
                name = f"{locale}-minimal-{index:02d}-{suffix}.png"
                im.convert("RGB").save(out / name, quality=95)
                if suffix == "69-1290":
                    sheet_images.append((name, im))
        contact_sheet(sheet_images).save(out / "contact-sheet.png", quality=95)
        print(f"Wrote {len(slides) * len(CANVASES)} {locale} screenshots plus contact sheet to {out}")


if __name__ == "__main__":
    missing = [str(p) for p in [IPHONE_BEZEL, WATCH_BEZEL, LOGO_SVG, IPHONE_SCREENSHOT, RAW_WATCH_SCREENSHOT, watch_asset(1), watch_asset(2), watch_asset(4)] if not p.exists()]
    if missing:
        raise SystemExit("Missing assets:\n" + "\n".join(missing))
    main()
