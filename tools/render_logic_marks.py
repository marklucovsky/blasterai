#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Draw `because` and `but` as a pair of symbols, in every set.

    python3 tools/render_logic_marks.py              # all sets
    python3 tools/render_logic_marks.py --preview out.png

WHY DRAWN, AND WHY A PAIR
-------------------------
Connecting words have no referent, so a picture of one is a convention. The
question is only whether the convention is learnable. Two answers were on the
table in session 8:

- **Text**, as `render_word_glyphs.py` does for a / the / and / is / at, following
  WordPower. Honest, but English-only, and it adds a 7-letter word to a family
  sized by its widest member.
- **A small symbol system**, as ARASAAC does: its `because` and `but` share one
  mark and differ only in the path that reaches it. Learn one and the other is
  half-learned. QuickCore and Vocal Flair give each word an unrelated picture,
  and read worse for it.

We drew our own pair on the same principle (ARASAAC's art is CC BY-NC-SA and is
not used): a dot is a thing that happens, an arrow is "and so".

- `because`: small dot → arrow → big dot. *This leads to that.*
- `but`: small dot → arrow that sets off right, then turns back. *Going one way,
  then the other.*

Rendered, not generated: exact, identical in every set, free, and an image model
would never keep the mark the same across two prompts.
"""

import argparse
import shutil
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("pip install pillow")

SIZE = 1024
ROOT = Path("tools/tile_sets")

# ink, paper, accent — the accent fills the dots.
STYLES = {
    "classic": dict(paper=(255, 255, 255), ink=(17, 17, 17), accent=(47, 111, 219)),
    "playful_3d": dict(paper=(246, 214, 181), ink=(92, 64, 43), accent=(224, 108, 74)),
    "high_contrast_v2": dict(paper=(0, 0, 0), ink=(255, 255, 255), accent=(255, 149, 0)),
}
# The skin-tone sets carry Classic's art byte-for-byte for anything without a
# person in it, and a symbol has no person.
CLASSIC_COPIES = ["classic_chain_medium", "classic_chain_medium_dark"]

W = 64            # stroke width
SMALL, BIG = 70, 120


def dot(d, center, r, s):
    x, y = center
    d.ellipse([x - r, y - r, x + r, y + r], fill=s["accent"], outline=s["ink"], width=W // 2)


def head(d, tip, direction, s, size=150):
    """Filled arrowhead with its point at `tip`, pointing left or right."""
    x, y = tip
    back = -size if direction == "right" else size
    d.polygon([(x, y), (x + back, y - size * 0.75), (x + back, y + size * 0.75)], fill=s["ink"])


def because(s):
    im = Image.new("RGB", (SIZE, SIZE), s["paper"])
    d = ImageDraw.Draw(im)
    y = SIZE // 2
    dot(d, (190, y), SMALL, s)
    d.line([(190 + SMALL, y), (700, y)], fill=s["ink"], width=W)
    head(d, (760, y), "right", s)
    dot(d, (880, y), BIG - 30, s)
    return im


def but(s):
    im = Image.new("RGB", (SIZE, SIZE), s["paper"])
    d = ImageDraw.Draw(im)
    top, bottom = 380, 680
    dot(d, (170, top), SMALL, s)
    d.line([(170 + SMALL, top), (700, top)], fill=s["ink"], width=W)
    # The turn: a half-ring on the right joining the two rows. PIL draws an
    # arc's width INSIDE its bounding box, so the box is the centre radius plus
    # half a stroke — otherwise the curve's centreline sits W/2 inside the
    # straight strokes' and the joins visibly step.
    r = (bottom - top) // 2
    cx, cy = 700, (top + bottom) // 2
    o = r + W // 2
    d.arc([cx - o, cy - o, cx + o, cy + o], start=-90, end=90, fill=s["ink"], width=W)
    d.line([(700, bottom), (330, bottom)], fill=s["ink"], width=W)
    head(d, (250, bottom), "left", s)
    return im


MARKS = {"because": because, "but": but}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--preview", type=Path, help="write a sheet of every mark in every style")
    args = ap.parse_args()

    if args.preview:
        cell = 300
        sheet = Image.new("RGB", (cell * len(STYLES), cell * len(MARKS)), "white")
        for c, s in enumerate(STYLES.values()):
            for r, draw in enumerate(MARKS.values()):
                sheet.paste(draw(s).resize((cell - 10, cell - 10)), (c * cell + 5, r * cell + 5))
        sheet.save(args.preview)
        print(f"preview → {args.preview}")
        return 0

    for set_name, style in STYLES.items():
        for key, draw in MARKS.items():
            out = ROOT / set_name / f"{key}.png"
            draw(style).save(out)
            if set_name == "classic":
                for copy in CLASSIC_COPIES:
                    shutil.copy(out, ROOT / copy / f"{key}.png")
    print(f"drew {len(MARKS)} marks in {len(STYLES)} sets (+{len(CLASSIC_COPIES)} classic copies)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
