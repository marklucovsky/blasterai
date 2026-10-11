#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Measure what a contact sheet hides, before a candidate set goes to review.

    python3 tools/check_candidate_set.py tools/tile_sets/classic_gi2 --bg white

Faults like a grey canvas, a frame or a subject cropped at the edge are invisible
at thumbnail size and obvious on a board, so they are measured rather than
eyeballed. Flags, per tile:

  - canvas      corners are not the set's background (white 255 / black 0)
  - edge        the outer border band is not mostly background — a frame, panel
                or subject bleeding off the tile
  - small       the subject's bounding box covers too little of the tile
  - size        not 1024x1024
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("pip install Pillow")

BG = {"white": 255, "black": 0}


def check(path: Path, bg: int, tol: int) -> list[str]:
    im = Image.open(path).convert("L")
    w, h = im.size
    flags = [] if (w, h) == (1024, 1024) else [f"size {w}x{h}"]
    px = im.load()
    corners = [px[4, 4], px[w - 5, 4], px[4, h - 5], px[w - 5, h - 5]]
    if any(abs(c - bg) > tol for c in corners):
        flags.append(f"canvas corners={corners}")
    band = max(4, w // 64)
    border = [px[x, y] for y in range(0, h, 4) for x in range(0, w, 4)
              if x < band or y < band or x >= w - band or y >= h - band]
    off = sum(abs(v - bg) > tol for v in border) / len(border)
    if off > 0.05:
        flags.append(f"edge {off:.0%} of border is not background")
    mask = im.point(lambda v: 255 if abs(v - bg) > tol else 0)
    box = mask.getbbox()
    if box:
        cover = (box[2] - box[0]) * (box[3] - box[1]) / (w * h)
        if cover < 0.30:
            flags.append(f"small subject box {cover:.0%} of tile")
    return flags


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", type=Path)
    ap.add_argument("--bg", choices=BG, default="white")
    ap.add_argument("--tol", type=int, default=12)
    args = ap.parse_args()
    paths = sorted(args.folder.glob("*.png"))
    if not paths:
        sys.exit(f"no PNGs in {args.folder}")  # could-not-look, not "all clear"
    bad = {p.stem: f for p in paths if (f := check(p, BG[args.bg], args.tol))}
    for key, flags in bad.items():
        print(f"{key:28s} {'; '.join(flags)}")
    print(f"\n{len(paths)} checked, {len(bad)} flagged")


if __name__ == "__main__":
    main()
