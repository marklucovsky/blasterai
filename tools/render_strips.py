#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Draw the day-strip tiles: today, tomorrow, yesterday, week, weekend.

    python3 tools/render_strips.py --sets classic,playful_3d,high_contrast

WHY THESE ARE DRAWN AND NOT GENERATED
-------------------------------------
A day strip has to have seven cells. Not about seven — seven, because the
picture is a week and a child is being taught to read it. The model cannot do
this. Across three styles and many passes it produced six cells, eight, ten,
thirteen, two stacked rows of four, and a month grid, from prompts that said
"exactly seven" in several different ways. Counting is not what it does.

Everything else about these tiles is equally exact: which cell is red, that the
green one touches it on the right, that the weekend is the last two. All of it
is arithmetic, and none of it is illustration.

So they are rendered. This is the same argument `GlyphTile` already makes for
letters and numbers — a glyph from a font is exact, free, instant and identical
across every set, where generation is none of those — and the same standing
preference that sends colours and shapes to `render_shapes.py` rather than to
the model. A strip of squares belongs in that group, and putting it there ends
a whole class of review finding permanently.

PER-STYLE PALETTES
------------------
Each set keeps its own materials, so the tiles still belong to their set:
Classic is black on white, High Contrast inverts to white on black, and Playful
3D uses its warm ground with rounded cells and a soft drop shadow. The accent
colours — red for today, green for tomorrow, blue for yesterday, orange for the
weekend — are shared, because they are the part carrying the meaning and must
mean the same thing in every style.
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except ImportError:
    sys.exit("pip install pillow")

SIZE = 1024
CELLS = 7                      # the whole point
RED = (214, 43, 40)            # today
GREEN = (44, 160, 62)          # tomorrow
BLUE = (22, 104, 209)          # yesterday
ORANGE = (240, 138, 22)        # the weekend pair

STYLES = {
    # bg, cell fill, stroke, stroke width, corner radius, shadow
    "classic":       dict(bg=(255, 255, 255), cell=(255, 255, 255),
                          stroke=(17, 17, 17), sw=9, radius=10, shadow=False),
    "high_contrast": dict(bg=(0, 0, 0), cell=(0, 0, 0),
                          stroke=(255, 255, 255), sw=11, radius=10, shadow=False),
    # `high_contrast_v2` is the set that actually SHIPS as `hc` — see
    # SET_PREFIX in sync_to_app.py. The unversioned folder is the earlier
    # generation and reaches no device.
    "high_contrast_v2": dict(bg=(0, 0, 0), cell=(0, 0, 0),
                             stroke=(255, 255, 255), sw=11, radius=10, shadow=False),
    "playful_3d":    dict(bg=(246, 214, 181), cell=(252, 246, 238),
                          stroke=(120, 88, 62), sw=7, radius=26, shadow=True),
}


def strip_geometry(has_arrow):
    """Seven equal cells across the canvas.

    Sized to carry at tile scale. A seven-cell strip is inherently wide and
    short, and drawn to a polite margin it became a thin ribbon adrift in a
    square — legible at 1024px and a smudge at the ~92pt a board actually
    renders. So the margin is small and the cells are tall, which is as much
    presence as seven-across allows.

    Tiles with an arrow sit slightly lower to leave it room, rather than
    shrinking the strip to make space: the strip is the subject.
    """
    margin = int(SIZE * 0.035)
    cell_w = (SIZE - 2 * margin) // CELLS
    width = cell_w * CELLS                      # exact, no rounding drift
    left = (SIZE - width) // 2
    cell_h = int(cell_w * 1.9)
    top = (SIZE - cell_h) // 2 + (int(SIZE * 0.06) if has_arrow else 0)
    return [(left + i * cell_w, top, left + (i + 1) * cell_w, top + cell_h)
            for i in range(CELLS)]


def arrow(draw, x0, x1, y, colour, pointing_right, thickness):
    """A plain block arrow above the strip."""
    head = thickness * 2
    if pointing_right:
        draw.line([(x0, y), (x1 - head, y)], fill=colour, width=thickness)
        draw.polygon([(x1, y), (x1 - head, y - head), (x1 - head, y + head)], fill=colour)
    else:
        draw.line([(x0 + head, y), (x1, y)], fill=colour, width=thickness)
        draw.polygon([(x0, y), (x0 + head, y - head), (x0 + head, y + head)], fill=colour)


def render(key, style):
    s = STYLES[style]
    img = Image.new("RGB", (SIZE, SIZE), s["bg"])
    cells = strip_geometry(has_arrow=key in ("tomorrow", "yesterday"))

    if s["shadow"]:
        shadow = Image.new("RGB", (SIZE, SIZE), s["bg"])
        sd = ImageDraw.Draw(shadow)
        off = 14
        for (a, b, c, d) in cells:
            sd.rounded_rectangle([a + off, b + off, c + off, d + off],
                                 radius=s["radius"], fill=(214, 178, 140))
        img = Image.blend(img, shadow.filter(ImageFilter.GaussianBlur(12)), 0.55)

    draw = ImageDraw.Draw(img)

    # Which cells are filled, and with what. `today` is always the middle cell.
    fills = {}
    mid = CELLS // 2
    if key == "today":
        fills = {mid: RED}
    elif key == "tomorrow":
        fills = {mid: RED, mid + 1: GREEN}
    elif key == "yesterday":
        fills = {mid: RED, mid - 1: BLUE}
    elif key == "weekend":
        fills = {CELLS - 2: ORANGE, CELLS - 1: ORANGE}
    elif key == "week":
        fills = {}
    else:
        raise ValueError(key)

    for i, (a, b, c, d) in enumerate(cells):
        draw.rounded_rectangle([a, b, c, d], radius=s["radius"],
                               fill=fills.get(i, s["cell"]),
                               outline=s["stroke"], width=s["sw"])

    if key == "week":
        # One ring around the whole row: the week as a single unit.
        pad = int(SIZE * 0.035)
        draw.rounded_rectangle([cells[0][0] - pad, cells[0][1] - pad,
                                cells[-1][2] + pad, cells[0][3] + pad],
                               radius=s["radius"] + pad, outline=BLUE,
                               width=int(s["sw"] * 2.2))

    if key in ("tomorrow", "yesterday"):
        right = key == "tomorrow"
        colour = GREEN if right else BLUE
        y = cells[0][1] - int(SIZE * 0.075)
        if right:
            x0, x1 = cells[mid][0], cells[mid + 1][2]
        else:
            x0, x1 = cells[mid - 1][0], cells[mid][2]
        arrow(draw, x0, x1, y, colour, right, thickness=int(SIZE * 0.022))

    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sets", default=",".join(STYLES))
    args = ap.parse_args()

    for style in [s.strip() for s in args.sets.split(",") if s.strip()]:
        if style not in STYLES:
            sys.exit(f"unknown set {style!r}; known: {', '.join(STYLES)}")
        out = Path("tools/tile_sets") / style
        out.mkdir(parents=True, exist_ok=True)
        for key in ("today", "tomorrow", "yesterday", "week", "weekend"):
            render(key, style).save(out / f"{key}.png")
            print(f"✓ {style}/{key}.png  (7 cells, drawn)")


if __name__ == "__main__":
    main()
