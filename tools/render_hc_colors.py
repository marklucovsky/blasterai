#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Render the colour tiles for a dark-background set, deterministically.

Colour words are the one place where the tile IS the colour, and that makes
them the worst possible candidate for image generation. Asked for "black" on a
black canvas, gpt-image-1 produced a billiards 8-ball — white-dominant, and a
homonym of the wrong sense. Asked for fifteen colours it produced fifteen
different circles at fifteen different sizes.

Drawing them is better on every axis: the geometry is identical across the set,
the hex values match the Classic set exactly (sampled from it — see COLORS),
it costs nothing, and it takes a second.

**The white ring is the load-bearing part.** On #000000, a dark swatch has
almost no edge — black is invisible, and brown, grey and purple are close to
it. A bold white ring gives every swatch a guaranteed high-contrast boundary
regardless of its fill, so the shape reads first and the colour reads second.
It is applied to every colour rather than only the dark ones: a child scanning
a grid should meet one visual grammar, not two.

The alternative considered and rejected was reusing the Classic tiles here.
They are correct in isolation, but a white-background tile dropped into a
dark-background set is a bright rectangle in a dark grid — a glare source, and
it breaks the scanning pattern the set exists to provide.

Usage:
    python3 tools/render_hc_colors.py --set high_contrast_v2
    python3 tools/render_hc_colors.py --set high_contrast_v2 --key red --key black
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("pip install Pillow")

OUTPUT_BASE = Path("tools/tile_sets")
SIZE = 1024
BG = (0, 0, 0)
RING = (255, 255, 255)

# Sampled from tools/tile_sets/classic/<key>.png so the two sets name the same
# colour with the same pixels. If Classic is ever regenerated, re-sample.
COLORS: dict[str, tuple[int, int, int]] = {
    "red":     (227, 31, 12),
    "orange_": (254, 128, 9),
    "yellow":  (255, 212, 0),
    "green":   (5, 167, 60),
    "blue":    (0, 148, 249),
    "purple":  (127, 60, 179),
    "pink":    (235, 50, 139),
    "black":   (7, 7, 7),
    "brown":   (162, 84, 21),
    "white":   (255, 255, 255),
    "grey":    (130, 132, 135),
    "gold":    (249, 185, 14),
    "silver":  (173, 179, 182),
    "tan":     (229, 176, 94),
}

# Proportions of the canvas.
FILL_R = 0.34      # swatch radius
RING_W = 0.035     # ring thickness
GAP = 0.018        # dark gap between swatch and ring, so white on white reads


def render(color: tuple[int, int, int]) -> Image.Image:
    """One swatch: a filled circle, ringed in white unless it is already white.

    The ring's job is to supply an edge the fill doesn't have. A near-white
    swatch already has maximum edge against black, and ringing it produces a
    donut — two concentric white bands with a dark line between them, which
    reads as a target rather than a colour. Those are drawn as a plain disc at
    the same outer diameter, so every colour tile keeps an identical footprint
    in the grid.

    Supersampled 4x and downscaled, because a hand-drawn circle at 1024 has
    visibly stepped edges and these tiles sit next to AI art that does not.
    """
    s = SIZE * 4
    img = Image.new("RGB", (s, s), BG)
    d = ImageDraw.Draw(img)
    cx = cy = s / 2
    outer = s * (FILL_R + GAP + RING_W)

    if min(color) > 200:
        d.ellipse([cx - outer, cy - outer, cx + outer, cy + outer], fill=color)
    else:
        inner = s * (FILL_R + GAP)
        fill_r = s * FILL_R
        d.ellipse([cx - outer, cy - outer, cx + outer, cy + outer], fill=RING)
        d.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=BG)
        d.ellipse([cx - fill_r, cy - fill_r, cx + fill_r, cy + fill_r], fill=color)

    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> None:
    ap = argparse.ArgumentParser(description="Render colour tiles for a dark set")
    ap.add_argument("--set", required=True, help="Set folder under tools/tile_sets")
    ap.add_argument("--key", action="append", default=None,
                    help="Only this colour (repeatable). Default: all.")
    args = ap.parse_args()

    out_dir = OUTPUT_BASE / args.set
    out_dir.mkdir(parents=True, exist_ok=True)

    keys = args.key or list(COLORS)
    unknown = [k for k in keys if k not in COLORS]
    if unknown:
        sys.exit(f"Not colour keys: {unknown}. Known: {', '.join(COLORS)}")

    for key in keys:
        color = COLORS[key]
        render(color).save(out_dir / f"{key}.png", "PNG")
        print(f"  ✓ {key:9s} #{color[0]:02X}{color[1]:02X}{color[2]:02X}"
              f"{'  (no ring — already max contrast)' if min(color) > 200 else ''}")

    print(f"\n{len(keys)} colour tile(s) → {out_dir}/")
    print("These are drawn, not generated — regenerating the set will not overwrite")
    print("them unless you delete them first.")


if __name__ == "__main__":
    main()
