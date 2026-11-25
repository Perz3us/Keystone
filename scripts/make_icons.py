#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Draw the Keystone logo (an arch with its keystone) and write every app icon.

Run from the repo root: python scripts/make_icons.py  (needs Pillow)
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

BG = (11, 15, 23)  # #0B0F17, also @color/ic_launcher_background
STONE = (232, 236, 242)
KEY = (59, 130, 246)  # #3B82F6
LIGHT_BG = (246, 247, 249)
LIGHT_STONE = (30, 41, 59)

SS = 2048  # draw big, then downsample for clean edges


def glyph(size, stone, key, scale=1.0):
    """The arch on a transparent canvas; scale < 1 leaves padding."""
    im = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    s = SS * scale
    cx, cy = SS / 2, SS / 2 + 0.225 * s
    outer, inner, lift = 0.40 * s, 0.24 * s, 0.05 * s
    gap = 2.2  # degrees between stones
    spans = [(180, 216), (216, 252), (252, 288), (288, 324), (324, 360)]
    for i, (a0, a1) in enumerate(spans):
        a0 += gap / 2 if a0 != 180 else 0
        a1 -= gap / 2 if a1 != 360 else 0
        is_key = i == 2
        r_out = outer + (lift if is_key else 0)
        pts = []
        for a in (a0, a1):
            t = math.radians(a)
            pts.append((cx + r_out * math.cos(t), cy + r_out * math.sin(t)))
        if not is_key:
            # follow the outer curve so side stones stay round
            pts = [
                (cx + outer * math.cos(math.radians(a)), cy + outer * math.sin(math.radians(a)))
                for a in [a0 + (a1 - a0) * k / 24 for k in range(25)]
            ]
        inner_pts = [
            (cx + inner * math.cos(math.radians(a)), cy + inner * math.sin(math.radians(a)))
            for a in [a1 - (a1 - a0) * k / 24 for k in range(25)]
        ]
        d.polygon(pts + inner_pts, fill=key if is_key else stone)
    return im.resize((size, size), Image.LANCZOS)


def tile(size, bg, stone, key, radius=0.0, circle=False, scale=0.78):
    im = Image.new("RGBA", (SS, SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if circle:
        d.ellipse((0, 0, SS - 1, SS - 1), fill=bg)
    else:
        d.rounded_rectangle((0, 0, SS - 1, SS - 1), radius=int(SS * radius), fill=bg)
    im.alpha_composite(glyph(SS, stone, key, scale))
    return im.resize((size, size), Image.LANCZOS)


def save(im, path, rgb=False):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    (im.convert("RGB") if rgb else im).save(path)


def main():
    res = Path("android/app/src/main/res")
    # Adaptive icons: art must sit in the middle 66 of 108 dp.
    for folder, legacy, adaptive in [
        ("mdpi", 48, 108),
        ("hdpi", 72, 162),
        ("xhdpi", 96, 216),
        ("xxhdpi", 144, 324),
        ("xxxhdpi", 192, 432),
    ]:
        m = res / f"mipmap-{folder}"
        save(tile(legacy, BG, STONE, KEY, radius=0.22), m / "ic_launcher.png")
        save(tile(legacy, BG, STONE, KEY, circle=True, scale=0.7), m / "ic_launcher_round.png")
        save(Image.new("RGBA", (adaptive, adaptive), BG + (255,)), m / "ic_launcher_background.png")
        save(glyph(adaptive, STONE, KEY, 0.5), m / "ic_launcher_foreground.png")
        save(glyph(adaptive, (255, 255, 255), (255, 255, 255), 0.5), m / "ic_launcher_monochrome.png")
    save(glyph(512, STONE, KEY, 0.5), res / "drawable-v24/ic_launcher_foreground.png")
    save(glyph(432, (255, 255, 255), (255, 255, 255), 0.5), res / "drawable-v24/ic_launcher_monochrome.png")

    # iOS wants square, opaque icons; it rounds the corners itself.
    ios = Path("ios/Runner/Assets.xcassets/AppIcon.appiconset")
    for f in ios.glob("*.png"):
        n = Image.open(f).size[0]
        save(tile(n, BG, STONE, KEY), f, rgb=True)

    full = tile(512, BG, STONE, KEY, radius=0.22)
    for p in ["assets/icons/app_icon.png", "assets/icons/ic_launcher.png",
              "assets/icons/app-icon-dark.png", "assets/images/app_logo.png",
              "assets/images/play_store_listing_icon.png"]:
        save(full, p)
    save(tile(512, LIGHT_BG, LIGHT_STONE, KEY, radius=0.22), "assets/icons/app-icon-light.png")
    # In-app logo is tinted by ThemeRouterLogo, so only its shape matters.
    mask = glyph(512, (255, 255, 255), (255, 255, 255), 0.92)
    save(mask, "assets/images/app_logo_transparent.png")
    save(mask, "assets/images/app_logo_router_clean.png")


if __name__ == "__main__":
    main()
