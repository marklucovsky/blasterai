#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Render the shape tiles for a dark-background set, deterministically.

Same reasoning as tools/render_hc_colors.py. A shape tile's entire content is
its geometry, so generating it adds variance and subtracts nothing: the model
returned mid-tone fills that measured 4.8-7.5 contrast against a set whose
whole premise is high contrast, put one on the wrong background, and drew the
triangle pointing sideways.

Drawn instead: solid white on #000000, so every shape sits at ~21 contrast, and
sized so a child comparing two tiles is comparing *form*, not scale. Squares
and rectangles, circles and ovals, only differ by proportion, so their relative
sizes have to be deliberate rather than whatever came back.

Usage:
    python3 tools/render_hc_shapes.py --set high_contrast_v2
    python3 tools/render_hc_shapes.py --set high_contrast_v2 --key triangle
"""

import argparse
import math
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("pip install Pillow")

OUTPUT_BASE = Path("tools/tile_sets")
SIZE = 1024
SS = 4                      # supersample factor
BG = (0, 0, 0)
INK = (255, 255, 255)
R = 0.36                    # nominal half-extent, as a fraction of the canvas


def _poly(n: int, rot: float, r: float, cx: float, cy: float) -> list[tuple[float, float]]:
    """Regular n-gon, `rot` radians from pointing straight up."""
    return [
        (cx + r * math.sin(rot + 2 * math.pi * i / n),
         cy - r * math.cos(rot + 2 * math.pi * i / n))
        for i in range(n)
    ]


def _star(points: int, r_out: float, r_in: float, cx: float, cy: float) -> list[tuple[float, float]]:
    pts = []
    for i in range(points * 2):
        r = r_out if i % 2 == 0 else r_in
        a = math.pi * i / points
        pts.append((cx + r * math.sin(a), cy - r * math.cos(a)))
    return pts


def render(key: str) -> Image.Image:
    s = SIZE * SS
    img = Image.new("RGB", (s, s), BG)
    d = ImageDraw.Draw(img)
    cx = cy = s / 2
    r = s * R

    if key == "circle":
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=INK)
    elif key == "oval":
        # Visibly wider than tall, or it is just a circle.
        d.ellipse([cx - r * 1.28, cy - r * 0.78, cx + r * 1.28, cy + r * 0.78], fill=INK)
    elif key == "square":
        d.rectangle([cx - r * 0.92, cy - r * 0.92, cx + r * 0.92, cy + r * 0.92], fill=INK)
    elif key == "rectangle":
        d.rectangle([cx - r * 1.30, cy - r * 0.72, cx + r * 1.30, cy + r * 0.72], fill=INK)
    elif key == "triangle":
        # Points up. Drawn larger than the others because a triangle inscribed
        # in the same circle covers far less area, and on a shapes page they
        # should look like siblings. Nudged down so its visual centre of mass,
        # which sits low, ends up centred.
        d.polygon(_poly(3, 0.0, r * 1.34, cx, cy + r * 0.16), fill=INK)
    elif key == "diamond":
        d.polygon(_poly(4, 0.0, r * 1.10, cx, cy), fill=INK)
    elif key == "octagon":
        d.polygon(_poly(8, math.pi / 8, r * 1.04, cx, cy), fill=INK)
    elif key == "star":
        d.polygon(_star(5, r * 1.10, r * 0.44, cx, cy + r * 0.04), fill=INK)
    elif key == "heart":
        # Two lobes plus a triangular point — simple, symmetrical, and reads at
        # tile size, which a bezier heart often does not.
        lobe = r * 0.52
        top = cy - r * 0.26
        d.ellipse([cx - lobe * 1.92, top - lobe, cx - lobe * 0.08, top + lobe], fill=INK)
        d.ellipse([cx + lobe * 0.08, top - lobe, cx + lobe * 1.92, top + lobe], fill=INK)
        d.polygon([(cx - lobe * 1.90, top + lobe * 0.16),
                   (cx + lobe * 1.90, top + lobe * 0.16),
                   (cx, cy + r * 1.02)], fill=INK)
    else:
        raise KeyError(key)

    return img.resize((SIZE, SIZE), Image.LANCZOS)


SHAPES = ["circle", "oval", "square", "rectangle", "triangle",
          "diamond", "octagon", "star", "heart"]


def main() -> None:
    ap = argparse.ArgumentParser(description="Render shape tiles for a dark set")
    ap.add_argument("--set", required=True, help="Set folder under tools/tile_sets")
    ap.add_argument("--key", action="append", default=None,
                    help="Only this shape (repeatable). Default: all.")
    args = ap.parse_args()

    out_dir = OUTPUT_BASE / args.set
    out_dir.mkdir(parents=True, exist_ok=True)

    keys = args.key or SHAPES
    unknown = [k for k in keys if k not in SHAPES]
    if unknown:
        sys.exit(f"Not shape keys: {unknown}. Known: {', '.join(SHAPES)}")

    for key in keys:
        render(key).save(out_dir / f"{key}.png", "PNG")
        print(f"  ✓ {key}")

    print(f"\n{len(keys)} shape tile(s) → {out_dir}/")
    print("Drawn, not generated — regenerating the set will not overwrite them")
    print("unless you delete them first.")


if __name__ == "__main__":
    main()
