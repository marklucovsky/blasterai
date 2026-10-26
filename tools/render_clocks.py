#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Draw the clock tiles: o'clock and half past.

    python3 tools/render_clocks.py --sets classic

Drawn, not generated, for the reason the day strips are (render_strips.py): the
meaning is where the hands point, and that is arithmetic. A generated clock
puts the hands wherever the drawing looks nice, and "half past" with the minute
hand at 4 teaches the wrong thing.

Both tiles read the same clock at three: o'clock with the long hand straight up,
half past with it straight down and the hour hand halfway to four. Half past
also shades the half of the face the minute hand has swept, so "half" is visible
before a child can read hands. The long hand is red in every set: it is the
hand these two tiles are about.
"""

import argparse
import math
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("pip install pillow")

SIZE = 1024
RED = (214, 43, 40)
SWEPT = (186, 220, 250)        # the half hour gone, a light blue

STYLES = {
    "classic":          dict(bg=(255, 255, 255), face=(255, 255, 255), ink=(17, 17, 17)),
    "classic_chain_medium":      dict(bg=(255, 255, 255), face=(255, 255, 255), ink=(17, 17, 17)),
    "classic_chain_medium_dark": dict(bg=(255, 255, 255), face=(255, 255, 255), ink=(17, 17, 17)),
    "high_contrast_v2": dict(bg=(0, 0, 0), face=(0, 0, 0), ink=(255, 255, 255)),
    "playful_3d":       dict(bg=(255, 255, 255), face=(252, 246, 238), ink=(92, 64, 43)),
}

# key -> (hour, minute)
TIMES = {"oclock": (3, 0), "half_past": (3, 30)}


def point(cx, cy, r, turns):
    """A point `turns` of the way round from 12 o'clock, clockwise."""
    a = 2 * math.pi * turns - math.pi / 2
    return cx + r * math.cos(a), cy + r * math.sin(a)


def hand(draw, cx, cy, length, turns, colour, width):
    x, y = point(cx, cy, length, turns)
    draw.line([(cx, cy), (x, y)], fill=colour, width=width)
    draw.ellipse([x - width / 2, y - width / 2, x + width / 2, y + width / 2], fill=colour)


def render(key, style):
    s = STYLES[style]
    hour, minute = TIMES[key]
    img = Image.new("RGB", (SIZE, SIZE), s["bg"])
    draw = ImageDraw.Draw(img)
    cx = cy = SIZE / 2
    r = SIZE * 0.42
    box = [cx - r, cy - r, cx + r, cy + r]
    draw.ellipse(box, fill=s["face"])
    if minute:
        # PIL angles start at 3 o'clock; -90 is 12.
        draw.pieslice(box, -90, -90 + 360 * minute / 60, fill=SWEPT)
    draw.ellipse(box, outline=s["ink"], width=int(SIZE * 0.035))
    for i in range(12):
        long_tick = i % 3 == 0
        outer = point(cx, cy, r * 0.88, i / 12)
        inner = point(cx, cy, r * (0.72 if long_tick else 0.79), i / 12)
        draw.line([inner, outer], fill=s["ink"], width=int(SIZE * (0.03 if long_tick else 0.016)))
    hand(draw, cx, cy, r * 0.5, (hour % 12 + minute / 60) / 12, s["ink"], int(SIZE * 0.05))
    hand(draw, cx, cy, r * 0.74, minute / 60, RED, int(SIZE * 0.035))
    d = SIZE * 0.035
    draw.ellipse([cx - d, cy - d, cx + d, cy + d], fill=s["ink"])
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sets", default=",".join(STYLES))
    ap.add_argument("--out-root", default="tools/tile_sets",
                    help="write <out-root>/<set>/<key>.png; a staging folder for review")
    args = ap.parse_args()
    for style in [x.strip() for x in args.sets.split(",") if x.strip()]:
        if style not in STYLES:
            sys.exit(f"unknown set {style!r}; known: {', '.join(STYLES)}")
        out = Path(args.out_root) / style
        out.mkdir(parents=True, exist_ok=True)
        for key in TIMES:
            render(key, style).save(out / f"{key}.png")
            print(f"✓ {style}/{key}.png  (drawn)")


if __name__ == "__main__":
    main()
