#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Derive one tile from another by mirroring it.

Some tiles are supposed to be exact opposites — next/previous, left/right,
up/down. Generating each one independently gives you two arrows that point
opposite ways but differ in weight, length, corner radius and position, which
reads as sloppy on a board where they sit side by side.

Flipping the accepted one is the only way to guarantee a true mirror, and it
costs nothing.

Usage:
    python3 tools/mirror_tile.py --set high_contrast_v2 --from next_page --to previous_page
    python3 tools/mirror_tile.py --set high_contrast_v2 --from up --to down --axis vertical
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("pip install Pillow")

OUTPUT_BASE = Path("tools/tile_sets")


def main() -> None:
    ap = argparse.ArgumentParser(description="Mirror one tile to create its opposite")
    ap.add_argument("--set", required=True, help="Set folder under tools/tile_sets")
    ap.add_argument("--from", dest="source", required=True, help="Key to mirror from")
    ap.add_argument("--to", dest="dest", required=True, help="Key to write")
    ap.add_argument("--axis", choices=["horizontal", "vertical"], default="horizontal",
                    help="horizontal flips left/right (default), vertical flips up/down")
    args = ap.parse_args()

    set_dir = OUTPUT_BASE / args.set
    src = set_dir / f"{args.source}.png"
    dst = set_dir / f"{args.dest}.png"

    if not src.exists():
        sys.exit(f"No such tile: {src}")

    method = (Image.FLIP_LEFT_RIGHT if args.axis == "horizontal"
              else Image.FLIP_TOP_BOTTOM)
    with Image.open(src) as img:
        img.convert("RGB").transpose(method).save(dst, "PNG")

    print(f"✓ {args.dest}.png  ←  {args.source}.png ({args.axis} mirror, "
          f"{dst.stat().st_size // 1024} KB)")
    print("  Re-run build_review_page.py to review it — its fingerprint changed.")


if __name__ == "__main__":
    main()
