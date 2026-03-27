#!/usr/bin/env python3
"""
tmuxonwatch App Store Screenshot Compositor v4
10 slides — dynamic island safe, watch-edge-fixed, mobile-optimized.

Output: /Volumes/SSD/tmuxonwatch/screenshots-v2/
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
from collections import deque
import os

# ── Paths ──────────────────────────────────────────────────────────────────
BEZEL_DIR = "/Volumes/SSD/tmuxonwatch/figma-assets"
OUTPUT_DIR = "/Volumes/SSD/tmuxonwatch/screenshots-v2"
FONT_PATH = "/System/Library/Fonts/HelveticaNeue.ttc"

IPHONE_BEZEL = os.path.join(BEZEL_DIR, "iphone-bezel.png")
WATCH_BEZEL = os.path.join(BEZEL_DIR, "watch-bezel.png")
LOGO_BADGE = os.path.join(BEZEL_DIR, "logo-badge.png")

WATCH_SCREENSHOT = "/Users/augustbenedikt/Downloads/incoming-6574001D-E82E-449B-82BC-F556F8EDFAE7.PNG"
IPHONE_SCREENSHOT = "/Users/augustbenedikt/Documents/Simulator Screenshot - iPhone 14 Plus - 2026-02-25 at 20.10.47.png"

# ── Design Tokens ──────────────────────────────────────────────────────────
BG = (185, 226, 102)           # #B9E266
INK = (10, 10, 14)             # near-black for text
SCREEN_BG = (11, 14, 20)      # dark fill behind screenshots to kill edge bleed

CANVASES = {"65": (1284, 2778), "69": (1260, 2736)}

IPHONE_SCREEN_BBOX = (90, 90, 1268, 2645)
WATCH_SCREEN_BBOX  = (95, 219, 504, 720)

# Dynamic island safe top margin — 7.5% of canvas height (~210px on 6.7")
SAFE_TOP = 0.075

# Real-world width ratio: Apple Watch Ultra (44mm) / iPhone 14 Plus (78.1mm)
WATCH_IPHONE_RATIO = 44.0 / 78.1  # ≈ 0.5634


# ── Utilities ──────────────────────────────────────────────────────────────

def font(size, bold=True):
    return ImageFont.truetype(FONT_PATH, size, index=(1 if bold else 0))


def build_screen_mask(bezel_path):
    """Flood-fill from center to find transparent screen opening."""
    bezel = Image.open(bezel_path).convert("RGBA")
    alpha = bezel.split()[3]
    w, h = bezel.size
    visited = set()
    pixels = set()
    q = deque([(w // 2, h // 2)])
    visited.add((w // 2, h // 2))
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
    mask = Image.new("L", (w, h), 0)
    for px, py in pixels:
        mask.putpixel((px, py), 255)
    return mask


def build_device_silhouette(bezel_path):
    """Flood-fill from all 4 corners to find exterior, then invert.
    Result: a solid white mask covering the entire device (frame + screen),
    with no gaps at anti-aliased corners."""
    bezel = Image.open(bezel_path).convert("RGBA")
    alpha = bezel.split()[3]
    w, h = bezel.size
    # Flood-fill exterior: start from corners, stop at any non-transparent pixel
    exterior = set()
    visited = set()
    q = deque()
    for sx, sy in [(0, 0), (w-1, 0), (0, h-1), (w-1, h-1)]:
        if (sx, sy) not in visited:
            q.append((sx, sy))
            visited.add((sx, sy))
    while q:
        x, y = q.popleft()
        if alpha.getpixel((x, y)) > 0:
            continue
        exterior.add((x, y))
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in visited:
                visited.add((nx, ny))
                q.append((nx, ny))
    # Invert: everything NOT exterior is device
    sil = Image.new("L", (w, h), 255)
    for px, py in exterior:
        sil.putpixel((px, py), 0)
    return sil


def mockup(bezel_path, ss_path, bbox, mask, target_w, silhouette=None):
    """Composite screenshot into bezel.
    1) Dark fill ONLY in screen area + buffer (dilated mask) — not the whole device
    2) Screenshot pasted at screen position
    3) Bezel frame on top — outer edges keep original anti-aliasing
    """
    bezel = Image.open(bezel_path).convert("RGBA")
    ss = Image.open(ss_path).convert("RGBA")
    ow, oh = bezel.size
    scale = target_w / ow
    sh = int(oh * scale)
    bezel_s = bezel.resize((target_w, sh), Image.LANCZOS)
    sl, st, sr, sb = [int(v * scale) for v in bbox]
    sw, shh = sr - sl, sb - st

    # COVER: scale screenshot to fill screen area
    ssw, ssh = ss.size
    if (ssw / ssh) > (sw / shh):
        nw, nh = int(ssw * (shh / ssh)), shh
    else:
        nw, nh = sw, int(ssh * (sw / ssw))
    ss_scaled = ss.resize((nw, nh), Image.LANCZOS)
    cx, cy = (nw - sw) // 2, (nh - shh) // 2
    ss_crop = ss_scaled.crop((cx, cy, cx + sw, cy + shh))

    # Start transparent
    device = Image.new("RGBA", (target_w, sh), (0, 0, 0, 0))

    # 1) Dark fill only in screen area + ~30px buffer (covers inner edge gap
    #    at corners but doesn't reach the bezel's outer anti-aliased edge).
    #    Bezel frame is ~90px wide, so 30px dilation is safely inside it.
    mask_s = mask.resize((target_w, sh), Image.LANCZOS)
    fill_mask = mask_s
    for _ in range(3):
        fill_mask = fill_mask.filter(ImageFilter.MaxFilter(size=21))
    dark = Image.new("RGBA", (target_w, sh), SCREEN_BG + (255,))
    device = Image.composite(dark, device, fill_mask)

    # 2) Screenshot at screen position (opaque, overwrites dark fill center)
    device.paste(ss_crop, (sl, st))

    # 3) Bezel frame on top — outer edge pixels retain original alpha,
    #    anti-alias cleanly against green background with no dark fringe
    device = Image.alpha_composite(device, bezel_s)
    return device


def shadow(img, offset=(10, 14), blur=28, opacity=70):
    """No-op — returns the image as-is with zero padding offset."""
    return img, 0


def headline(draw, cw, y, text, size, align="left", xo=0):
    f = font(size, bold=True)
    cy = y
    for line in text.split("\n"):
        bb = draw.textbbox((0, 0), line, font=f)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        tx = {"center": (cw - tw) // 2, "right": cw - tw - xo}.get(align, xo)
        draw.text((tx, cy), line, fill=INK, font=f)
        cy += th + int(size * 0.06)
    return cy


def subtext(draw, cw, y, text, size, align="left", xo=0):
    f = font(size, bold=False)
    cy = y
    for line in text.split("\n"):
        bb = draw.textbbox((0, 0), line, font=f)
        tw, th = bb[2] - bb[0], bb[3] - bb[1]
        tx = {"center": (cw - tw) // 2, "right": cw - tw - xo}.get(align, xo)
        draw.text((tx, cy), line, fill=INK, font=f)
        cy += th + int(size * 0.2)
    return cy


def stamp_logo(img):
    """Stamp logo badge in top-left, vertically aligned with dynamic island,
    horizontally centered between left edge and the dynamic island."""
    cw, ch = img.size
    logo_src = Image.open(LOGO_BADGE).convert("RGBA")

    # Badge width: ~12% of canvas width (~155px on 1290)
    badge_w = int(cw * 0.12)
    badge_h = int(badge_w * logo_src.height / logo_src.width)
    badge = logo_src.resize((badge_w, badge_h), Image.LANCZOS)

    # Dynamic island center Y: ~38pt from top ≈ 114px at 3x on 6.7"
    # 114/2796 ≈ 4.1% of canvas height
    di_y = int(ch * 0.041)
    # Dynamic island left edge X: ~456px on 1290w = 35.3% of canvas width
    di_left_x = int(cw * 0.353)
    # Center badge between x=0 and dynamic island left edge
    badge_cx = di_left_x // 2
    badge_cy = di_y

    bx = badge_cx - badge_w // 2
    by = badge_cy - badge_h // 2

    img.paste(badge, (bx, by), badge)
    return img


def canvas(cw, ch):
    return Image.new("RGBA", (cw, ch), BG + (255,))


def top(ch):
    return int(ch * SAFE_TOP)


def pad(cw):
    return int(cw * 0.07)


def hl(cw, m=0.12):
    return int(cw * m)


def sub(cw, m=0.050):
    return int(cw * m)


# ═══════════════════════════════════════════════════════════════════════════
#  1 — LIVE TMUX. ON WRIST.  (Hero: both devices, balanced)
# ═══════════════════════════════════════════════════════════════════════════
def s01(cw, ch, im, wm):
    c = canvas(cw, ch)
    d = ImageDraw.Draw(c)
    p = pad(cw)

    # Text — left-aligned, safe top
    by = headline(d, cw, top(ch), "LIVE TMUX.\nON WRIST.", hl(cw, 0.12), xo=p)
    subtext(d, cw, by + int(ch * 0.015), "Track your active pane.\nSee output in seconds.", sub(cw, 0.050), xo=p)

    # iPhone — right side, large, bleeds bottom
    ip_w = int(cw * 0.72)
    ip = mockup(IPHONE_BEZEL, IPHONE_SCREENSHOT, IPHONE_SCREEN_BBOX, im,silhouette=IPHONE_SIL,target_w=ip_w)
    ips, sp = shadow(ip)
    ip_x = cw - ip.width + int(cw * 0.06)
    c.paste(ips, (ip_x - sp, int(ch * 0.30) - sp), ips)

    # Watch — tucked left of iPhone, vertically centered on iPhone's mid-body
    wp_w = int(ip_w * WATCH_IPHONE_RATIO)
    wp = mockup(WATCH_BEZEL, WATCH_SCREENSHOT, WATCH_SCREEN_BBOX, wm,silhouette=WATCH_SIL,target_w=wp_w)
    wps, wsp = shadow(wp)
    c.paste(wps, (ip_x - wp.width + int(cw * 0.02) - wsp, int(ch * 0.44) - wsp), wps)

    return c.convert("RGB")


# ═══════════════════════════════════════════════════════════════════════════
#  2 — GLANCE. DON'T REACH.  (Watch hero — fixed safe zone + edges)
# ═══════════════════════════════════════════════════════════════════════════
def s02(cw, ch, wm):
    c = canvas(cw, ch)
    d = ImageDraw.Draw(c)

    by = headline(d, cw, top(ch), "GLANCE.\nDON'T REACH.", hl(cw, 0.10), align="center")
    subtext(d, cw, by + int(ch * 0.015), "See what changed without\npulling out your laptop.", sub(cw), align="center")

    wp = mockup(WATCH_BEZEL, WATCH_SCREENSHOT, WATCH_SCREEN_BBOX, wm,silhouette=WATCH_SIL,target_w= int(cw * 0.80))
    wps, sp = shadow(wp, blur=30)
    c.paste(wps, ((cw - wps.width) // 2, int(ch * 0.34)), wps)

    return c.convert("RGB")


# ═══════════════════════════════════════════════════════════════════════════
#  3 — BUILDS RUNNING? JUST LOOK DOWN.  (Watch bleeds right, text left)
# ═══════════════════════════════════════════════════════════════════════════
def s03(cw, ch, wm):
    c = canvas(cw, ch)
    d = ImageDraw.Draw(c)
    p = pad(cw)

    by = headline(d, cw, top(ch), "BUILDS\nRUNNING?", hl(cw, 0.15), xo=p)
    headline(d, cw, by + int(ch * 0.005), "JUST LOOK\nDOWN.", hl(cw, 0.11), xo=p)

    wp = mockup(WATCH_BEZEL, WATCH_SCREENSHOT, WATCH_SCREEN_BBOX, wm,silhouette=WATCH_SIL,target_w= int(cw * 0.82))
    wps, sp = shadow(wp)
    c.paste(wps, (cw - wp.width + int(cw * 0.12) - sp, int(ch * 0.48) - sp), wps)

    return c.convert("RGB")


# ═══════════════════════════════════════════════════════════════════════════
#  4 — TMUX MEETS WATCHOS.  (Side-by-side — iPhone left, Watch right, both large)
# ═══════════════════════════════════════════════════════════════════════════
def s04(cw, ch, im, wm):
    c = canvas(cw, ch)
    d = ImageDraw.Draw(c)

    by = headline(d, cw, top(ch), "TMUX MEETS\nWATCHOS.", hl(cw, 0.12), align="center")
    subtext(d, cw, by + int(ch * 0.01), "One app. Two screens.\nZero friction.", sub(cw), align="center")

    # iPhone — left of center, bleeds bottom
    ip_w = int(cw * 0.62)
    ip = mockup(IPHONE_BEZEL, IPHONE_SCREENSHOT, IPHONE_SCREEN_BBOX, im,silhouette=IPHONE_SIL,target_w=ip_w)
    ips, sp = shadow(ip, blur=22)
    ip_x = int(cw * 0.04)
    c.paste(ips, (ip_x - sp, int(ch * 0.30) - sp), ips)

    # Watch — right of iPhone, vertically centered on iPhone body
    wp_w = int(ip_w * WATCH_IPHONE_RATIO)
    wp = mockup(WATCH_BEZEL, WATCH_SCREENSHOT, WATCH_SCREEN_BBOX, wm,silhouette=WATCH_SIL,target_w=wp_w)
    wps, wsp = shadow(wp, blur=20)
    c.paste(wps, (ip_x + ip_w - int(cw * 0.02) - wsp, int(ch * 0.42) - wsp), wps)

    return c.convert("RGB")


# ═══════════════════════════════════════════════════════════════════════════
#  5 — STEP AWAY. STAY INFORMED.  (Watch huge left, text right)
# ═══════════════════════════════════════════════════════════════════════════
def s05(cw, ch, wm):
    c = canvas(cw, ch)
    d = ImageDraw.Draw(c)
    p = pad(cw)

    # Watch bleeds off left
    wp = mockup(WATCH_BEZEL, WATCH_SCREENSHOT, WATCH_SCREEN_BBOX, wm,silhouette=WATCH_SIL,target_w= int(cw * 0.72))
    wps, sp = shadow(wp)
    c.paste(wps, (-int(cw * 0.15) - sp, int(ch * 0.32) - sp), wps)

    # Text right-aligned
    by = headline(d, cw, top(ch) + int(ch * 0.02), "STEP\nAWAY.\nSTAY\nINFORMED.", hl(cw, 0.11), align="right", xo=p)
    subtext(d, cw, by + int(ch * 0.015), "Your build keeps running.\nYour watch keeps you\nposted.", sub(cw), align="right", xo=p)

    return c.convert("RGB")


# ═══════════════════════════════════════════════════════════════════════════
#  6 — GO LIVE YOUR LIFE.  (Both devices balanced, watch left, iPhone right)
# ═══════════════════════════════════════════════════════════════════════════
def s06(cw, ch, im, wm):
    c = canvas(cw, ch)
    d = ImageDraw.Draw(c)
    p = pad(cw)

    by = headline(d, cw, top(ch), "GO LIVE\nYOUR LIFE.", hl(cw, 0.13), align="center")
    subtext(d, cw, by + int(ch * 0.012), "Long tasks keep running.\nWe'll keep you posted.", sub(cw), align="center")

    # iPhone — centered, bleeds bottom
    ip_w = int(cw * 0.70)
    ip = mockup(IPHONE_BEZEL, IPHONE_SCREENSHOT, IPHONE_SCREEN_BBOX, im,silhouette=IPHONE_SIL,target_w=ip_w)
    ips, sp = shadow(ip, blur=24)
    ip_x = (cw - ip.width) // 2
    ip_y = int(ch * 0.38)
    c.paste(ips, (ip_x - sp, ip_y - sp), ips)

    # Watch — to-scale, centered at bottom, in front of iPhone
    wp_w = int(ip_w * WATCH_IPHONE_RATIO)
    wp = mockup(WATCH_BEZEL, WATCH_SCREENSHOT, WATCH_SCREEN_BBOX, wm,silhouette=WATCH_SIL,target_w=wp_w)
    wps, wsp = shadow(wp, blur=22)
    wx = (cw - wp.width) // 2
    wy = ch - int(wp.height * 0.85)
    c.paste(wps, (wx - wsp, wy - wsp), wps)

    return c.convert("RGB")


# ═══════════════════════════════════════════════════════════════════════════
#  7 — COFFEE RUN? YOU'RE COVERED.  (Fun — centered watch, playful copy)
# ═══════════════════════════════════════════════════════════════════════════
def s07(cw, ch, wm):
    c = canvas(cw, ch)
    d = ImageDraw.Draw(c)

    by = headline(d, cw, top(ch), "COFFEE RUN?\nYOU'RE\nCOVERED.", hl(cw, 0.12), align="center")
    subtext(d, cw, by + int(ch * 0.015), "Grab a drink. Your watch\nhas eyes on the build.", sub(cw), align="center")

    wp = mockup(WATCH_BEZEL, WATCH_SCREENSHOT, WATCH_SCREEN_BBOX, wm,silhouette=WATCH_SIL,target_w= int(cw * 0.74))
    wps, sp = shadow(wp, blur=28)
    c.paste(wps, ((cw - wps.width) // 2, int(ch * 0.42)), wps)

    return c.convert("RGB")


# ═══════════════════════════════════════════════════════════════════════════
#  8 — BABYSIT BUILDS. FROM ANYWHERE.  (Both devices, diagonal)
# ═══════════════════════════════════════════════════════════════════════════
def s08(cw, ch, im, wm):
    c = canvas(cw, ch)
    d = ImageDraw.Draw(c)

    by = headline(d, cw, top(ch), "BABYSIT\nBUILDS.", hl(cw, 0.14), align="center")
    subtext(d, cw, by + int(ch * 0.012), "At a glance.", sub(cw, 0.055), align="center")

    # iPhone — large, center-right, bleeds bottom
    ip_w = int(cw * 0.68)
    ip = mockup(IPHONE_BEZEL, IPHONE_SCREENSHOT, IPHONE_SCREEN_BBOX, im,silhouette=IPHONE_SIL,target_w=ip_w)
    ips, sp = shadow(ip, blur=22)
    ip_x = int(cw * 0.18)
    ip_y = int(ch * 0.42)
    c.paste(ips, (ip_x - sp, ip_y - sp), ips)

    # Watch — to-scale, tucked above and right of iPhone top
    wp_w = int(ip_w * WATCH_IPHONE_RATIO)
    wp = mockup(WATCH_BEZEL, WATCH_SCREENSHOT, WATCH_SCREEN_BBOX, wm,silhouette=WATCH_SIL,target_w=wp_w)
    wps, wsp = shadow(wp, blur=20)
    c.paste(wps, (ip_x + ip_w - wp_w + int(cw * 0.02) - wsp, ip_y - int(ch * 0.10) - wsp), wps)

    return c.convert("RGB")


# ═══════════════════════════════════════════════════════════════════════════
#  9 — FOLLOW LONG RUNS. LIVE.  (iPhone + watch overlapping top of screen)
# ═══════════════════════════════════════════════════════════════════════════
def s09(cw, ch, im, wm):
    c = canvas(cw, ch)
    d = ImageDraw.Draw(c)

    by = headline(d, cw, top(ch), "FOLLOW\nLONG RUNS.\nLIVE.", hl(cw, 0.11), align="center")
    subtext(d, cw, by + int(ch * 0.012), "Watch builds, logs, and\nlong-running tasks in real time.", sub(cw), align="center")

    # iPhone — large, slightly right of center, bleeds bottom
    ip_w = int(cw * 0.78)
    ip = mockup(IPHONE_BEZEL, IPHONE_SCREENSHOT, IPHONE_SCREEN_BBOX, im,silhouette=IPHONE_SIL,target_w=ip_w)
    ips, sp = shadow(ip, blur=28)
    ip_x = (cw - ip.width) // 2 + int(cw * 0.06)
    ip_y = int(ch * 0.35)
    c.paste(ips, (ip_x - sp, ip_y - sp), ips)

    # Watch — to-scale, overlapping upper-left of iPhone, slightly outside the bezel
    wp_w = int(ip_w * WATCH_IPHONE_RATIO)
    wp = mockup(WATCH_BEZEL, WATCH_SCREENSHOT, WATCH_SCREEN_BBOX, wm,silhouette=WATCH_SIL,target_w=wp_w)
    wps, wsp = shadow(wp, blur=18)
    wx = ip_x - int(cw * 0.12)
    wy = ip_y - int(ch * 0.01)
    c.paste(wps, (wx - wsp, wy - wsp), wps)

    return c.convert("RGB")


# ═══════════════════════════════════════════════════════════════════════════
#  10 — TWO SCREENS. ONE SESSION.  (Both devices side-by-side, symmetrical)
# ═══════════════════════════════════════════════════════════════════════════
def s10(cw, ch, im, wm):
    c = canvas(cw, ch)
    d = ImageDraw.Draw(c)

    by = headline(d, cw, top(ch), "TWO SCREENS.\nONE SESSION.", hl(cw, 0.12), align="center")
    subtext(d, cw, by + int(ch * 0.012), "Full detail on iPhone.\nInstant status on Apple Watch.", sub(cw), align="center")

    # iPhone left, large, bleeds bottom
    ip_w = int(cw * 0.62)
    ip = mockup(IPHONE_BEZEL, IPHONE_SCREENSHOT, IPHONE_SCREEN_BBOX, im,silhouette=IPHONE_SIL,target_w=ip_w)
    ips, sp = shadow(ip, blur=22)
    ip_x = int(cw * 0.02)
    ip_y = int(ch * 0.32)
    c.paste(ips, (ip_x - sp, ip_y - sp), ips)

    # Watch right, to-scale, vertically centered on iPhone mid-body
    wp_w = int(ip_w * WATCH_IPHONE_RATIO)
    wp = mockup(WATCH_BEZEL, WATCH_SCREENSHOT, WATCH_SCREEN_BBOX, wm,silhouette=WATCH_SIL,target_w=wp_w)
    wps, wsp = shadow(wp, blur=20)
    # Center watch vertically on iPhone's visible portion
    ip_mid_y = ip_y + ip.height // 3
    wp_y = ip_mid_y - wp.height // 2
    c.paste(wps, (ip_x + ip_w - int(cw * 0.01) - wsp, wp_y - wsp), wps)

    return c.convert("RGB")


# ═══════════════════════════════════════════════════════════════════════════

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    global IPHONE_SIL, WATCH_SIL
    print("Building screen masks + silhouettes...")
    im = build_screen_mask(IPHONE_BEZEL)
    wm = build_screen_mask(WATCH_BEZEL)
    IPHONE_SIL = build_device_silhouette(IPHONE_BEZEL)
    WATCH_SIL = build_device_silhouette(WATCH_BEZEL)
    print("  Done.\n")

    slides = [
        ("slide-01", "Live tmux on wrist",     lambda cw, ch: s01(cw, ch, im, wm)),
        ("slide-02", "Glance don't reach",      lambda cw, ch: s02(cw, ch, wm)),
        ("slide-03", "Builds running",           lambda cw, ch: s03(cw, ch, wm)),
        ("slide-04", "tmux meets watchOS",       lambda cw, ch: s04(cw, ch, im, wm)),
        ("slide-05", "Step away stay informed",  lambda cw, ch: s05(cw, ch, wm)),
        ("slide-06", "Go live your life",        lambda cw, ch: s06(cw, ch, im, wm)),
        ("slide-07", "Coffee run",               lambda cw, ch: s07(cw, ch, wm)),
        ("slide-08", "Babysit builds",           lambda cw, ch: s08(cw, ch, im, wm)),
        ("slide-09", "Follow long runs",         lambda cw, ch: s09(cw, ch, im, wm)),
        ("slide-10", "Two screens one session",  lambda cw, ch: s10(cw, ch, im, wm)),
    ]

    for slug, label, fn in slides:
        for sk, (cw, ch) in CANVASES.items():
            print(f"  {label} @ {sk}in ...", end=" ", flush=True)
            img = fn(cw, ch)
            stamp_logo(img)
            out = os.path.join(OUTPUT_DIR, f"{slug}-{sk}.png")
            img.save(out, "PNG", optimize=True)
            print(f"ok")

    print(f"\n{len(slides) * len(CANVASES)} screenshots -> {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
