#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Optimize tile images for app bundle inclusion.

Resizes full-resolution DALL-E masters (1024×1024) to app-ready size (512×512)
with PNG optimization. Output goes to tools/tile_sets/optimized/{set_name}/.

Usage:
    python3 tools/optimize_tiles.py --set playful_3d
    python3 tools/optimize_tiles.py --set high_contrast
    python3 tools/optimize_tiles.py --set both
    python3 tools/optimize_tiles.py --set both --size 256  # smaller for testing
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("pip install Pillow")

INPUT_BASE = Path("tools/tile_sets")
OUTPUT_BASE = Path("tools/tile_sets/optimized")
DEFAULT_SIZE = 512


def optimize_set(set_name: str, target_size: int) -> None:
    src_dir = INPUT_BASE / set_name
    dst_dir = OUTPUT_BASE / set_name
    dst_dir.mkdir(parents=True, exist_ok=True)

    if not src_dir.exists():
        print(f"  Source not found: {src_dir}")
        return

    tiles = sorted(src_dir.glob("*.png"))
    if not tiles:
        print(f"  No PNGs in {src_dir}")
        return

    optimized = 0
    skipped = 0
    total_src = 0
    total_dst = 0

    for src in tiles:
        dst = dst_dir / src.name

        # Skip if optimized version is newer than source
        if dst.exists() and dst.stat().st_mtime >= src.stat().st_mtime:
            skipped += 1
            continue

        try:
            img = Image.open(src)
            img = img.convert("RGB")
            img = img.resize((target_size, target_size), Image.LANCZOS)
            img.save(dst, "PNG", optimize=True)

            src_kb = src.stat().st_size // 1024
            dst_kb = dst.stat().st_size // 1024
            total_src += src.stat().st_size
            total_dst += dst.stat().st_size
            optimized += 1

        except Exception as e:
            print(f"  ERROR {src.name}: {e}")

    print(f"  {set_name}: {optimized} optimized, {skipped} skipped (up to date)")
    if optimized > 0:
        ratio = (1 - total_dst / total_src) * 100 if total_src > 0 else 0
        print(f"  Size: {total_src // 1024 // 1024}MB → {total_dst // 1024 // 1024}MB ({ratio:.0f}% reduction)")


def main():
    parser = argparse.ArgumentParser(description="Optimize tiles for app bundle")
    parser.add_argument("--set", required=True,
                        choices=["playful_3d", "high_contrast", "high_contrast_v2", "classic", "both"])
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE, help=f"Target size in px (default {DEFAULT_SIZE})")
    args = parser.parse_args()

    sets = ["playful_3d", "high_contrast"] if args.set == "both" else [args.set]

    print(f"Optimizing to {args.size}×{args.size}...")
    for s in sets:
        optimize_set(s, args.size)

    print(f"\nOutput: {OUTPUT_BASE}/")
    print("These optimized tiles are committed to git and used by the app.")


if __name__ == "__main__":
    main()
