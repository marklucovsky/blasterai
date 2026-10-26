#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Draw the month tiles: a calendar page with the month's name and its picture.

    python3 tools/render_months.py --sets classic [--out-root DIR]

Avaz's approach (Mark, 2026-10-25, over plain text tiles): every month is the
same calendar page, so the twelve read as one set, and each carries one picture
a child connects with that month (a party hat, a heart, a pumpkin, a tree) and
its name in the page's header.

The page is drawn here; only the picture is generated, once per month and
style, into `tools/tile_sets/month_icons/<style>/` (generate_by_reference.py
with the subjects in `tools/board_spec/month_icons.json`). The skin-tone sets
use Classic's: a month has no skin. The name is data, like the function-word
glyphs, so a translated board changes a string and re-runs this script.
"""
import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageChops, ImageDraw, ImageFont
except ImportError:
    sys.exit("pip install pillow")

SIZE = 1024
ICONS = Path("tools/tile_sets/month_icons")
RED = (214, 43, 40)

MONTHS = {
    "january": "January", "february": "February", "march_": "March", "april": "April",
    "may_": "May", "june": "June", "july": "July", "august": "August",
    "september": "September", "october": "October", "november": "November",
    "december": "December",
}

STYLES = {
    "classic": dict(bg=(255, 255, 255), page=(255, 255, 255), ink=(17, 17, 17), band=RED, band_ink=(255, 255, 255)),
    "classic_chain_medium": dict(bg=(255, 255, 255), page=(255, 255, 255), ink=(17, 17, 17), band=RED, band_ink=(255, 255, 255)),
    "classic_chain_medium_dark": dict(bg=(255, 255, 255), page=(255, 255, 255), ink=(17, 17, 17), band=RED, band_ink=(255, 255, 255)),
    "high_contrast_v2": dict(bg=(0, 0, 0), page=(0, 0, 0), ink=(255, 255, 255), band=(255, 255, 255), band_ink=(0, 0, 0)),
    "playful_3d": dict(bg=(255, 255, 255), page=(252, 246, 238), ink=(92, 64, 43), band=RED, band_ink=(255, 255, 255)),
}

# Which style's pictures a set uses.
ICON_STYLE = {"classic_chain_medium": "classic", "classic_chain_medium_dark": "classic"}

FONT = "/System/Library/Fonts/Supplemental/Arial Bold.ttf"


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def render(key, style, icon_dir):
    s = STYLES[style]
    img = Image.new("RGB", (SIZE, SIZE), s["bg"])
    d = ImageDraw.Draw(img)
    ink, sw = s["ink"], 14

    # The page: the lower two thirds, a header band with the name, a 7 × 5 grid.
    left, right, top, bottom = 150, SIZE - 150, 430, SIZE - 40
    d.rounded_rectangle([left, top, right, bottom], radius=26, fill=s["page"], outline=ink, width=sw)
    band_bottom = top + 130
    d.rounded_rectangle([left, top, right, band_bottom], radius=26, fill=s["band"], outline=ink, width=sw)
    d.rectangle([left + sw, band_bottom - 30, right - sw, band_bottom - sw // 2], fill=s["band"])
    d.line([left, band_bottom, right, band_bottom], fill=ink, width=sw)
    name = MONTHS[key]
    rings = (left + 62, right - 62)
    pt = 92
    # The name fits between the rings, so September and May share a page.
    while pt > 40 and d.textlength(name, font=font(pt)) > (rings[1] - rings[0]) - 80:
        pt -= 4
    f = font(pt)
    box = d.textbbox((0, 0), name, font=f)
    d.text(((left + right) / 2 - (box[0] + box[2]) / 2, (top + band_bottom) / 2 - (box[1] + box[3]) / 2),
           name, font=f, fill=s["band_ink"])
    cols, rows = 7, 5
    gx0, gx1, gy0, gy1 = left + 40, right - 40, band_bottom + 36, bottom - 36
    cw, ch = (gx1 - gx0) / cols, (gy1 - gy0) / rows
    for r in range(rows):
        for c in range(cols):
            x, y = gx0 + c * cw, gy0 + r * ch
            d.rounded_rectangle([x + 6, y + 6, x + cw - 6, y + ch - 6], radius=6, outline=ink, width=5)
    # Two binder rings over the band.
    for x in rings:
        d.rounded_rectangle([x - 18, top - 40, x + 18, top + 40], radius=18, fill=s["bg"], outline=ink, width=10)

    # The month's picture, above the page.
    icon_path = icon_dir / ICON_STYLE.get(style, style) / f"{key}.png"
    if icon_path.exists():
        icon = Image.open(icon_path).convert("RGB")
        icon = icon.resize((430, 430), Image.LANCZOS)
        spot = img.crop(((SIZE - 430) // 2, 0, (SIZE + 430) // 2, 430))
        # Drop the art's own background and keep its ink: multiply drops white,
        # screen drops black (High Contrast draws on black).
        # Snap the near-background first: Playful 3D draws on an off-white that
        # would otherwise leave a faint square on the page.
        if sum(s["bg"]) < 384:
            icon = icon.point(lambda v: 0 if v < 16 else v)
            blended = ImageChops.screen(spot, icon)
        else:
            icon = icon.point(lambda v: 255 if v > 236 else v)
            blended = ImageChops.multiply(spot, icon)
        img.paste(blended, ((SIZE - 430) // 2, 0))
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sets", default="classic")
    ap.add_argument("--out-root", default="tools/tile_sets")
    ap.add_argument("--icons", type=Path, default=ICONS)
    args = ap.parse_args()
    for style in [x.strip() for x in args.sets.split(",") if x.strip()]:
        if style not in STYLES:
            sys.exit(f"unknown set {style!r}")
        out = Path(args.out_root) / style
        out.mkdir(parents=True, exist_ok=True)
        for key in MONTHS:
            render(key, style, args.icons).save(out / f"{key}.png")
            print(f"✓ {style}/{key}.png")


if __name__ == "__main__":
    main()
