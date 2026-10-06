#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Lay tiles out side by side for review: one row per word, one column per source.

    # A new candidate against what ships today:
    python3 tools/compare_tiles.py --keys my your his our their \\
        --col "shipped=claudeBlast/TileImageSets/cls_{key}.heic" \\
        --col "candidate=/tmp/candidates/classic/{key}.png" \\
        --out /tmp/possessives.png

    # A word as a unit across the sets it is generated in:
    python3 tools/compare_tiles.py --keys-file keys.txt \\
        --col "classic=tools/tile_sets/classic/{key}.png" \\
        --col "playful 3d=tools/tile_sets/playful_3d/{key}.png" \\
        --col "high contrast=tools/tile_sets/high_contrast_v2/{key}.png" \\
        --out /tmp/unit.png

Each `--col` is `label=path-template`, with `{key}` substituted. A missing file
draws as an empty cell marked "none", so "there is no current tile" reads as such
rather than as an error. HEIC (the shipped format) is converted with `sips`.

Review is easier by eye than by filename, and the question a review answers is
almost always comparative — is the new one better than what we have, does this
word look like itself in every set — which a folder of images does not show.
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError:
    sys.exit("pip install pillow")

CELL = 220
LABEL = 120
HEADER = 26


def load(path: Path, tmp: Path) -> Image.Image | None:
    if not path.exists():
        return None
    if path.suffix.lower() == ".heic":
        png = tmp / (path.stem + ".png")
        subprocess.run(["sips", "-s", "format", "png", str(path), "--out", str(png)],
                       capture_output=True, check=True)
        path = png
    im = Image.open(path).convert("RGBA")
    flat = Image.new("RGBA", im.size, "white")
    flat.alpha_composite(im)
    return flat.convert("RGB")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--keys", nargs="*", default=[])
    ap.add_argument("--keys-file", type=Path)
    ap.add_argument("--col", action="append", required=True,
                    help="label=path-template with {key}")
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    keys = list(args.keys)
    if args.keys_file:
        keys += [k.strip() for k in args.keys_file.read_text().splitlines() if k.strip()]
    cols = [c.split("=", 1) for c in args.col]

    sheet = Image.new("RGB", (LABEL + CELL * len(cols), HEADER + CELL * len(keys)), "white")
    draw = ImageDraw.Draw(sheet)
    for c, (label, _) in enumerate(cols):
        draw.text((LABEL + c * CELL + 8, 6), label, fill="black")
    with tempfile.TemporaryDirectory() as t:
        for r, key in enumerate(keys):
            y = HEADER + r * CELL
            draw.text((8, y + CELL // 2), key, fill="black")
            for c, (_, template) in enumerate(cols):
                x = LABEL + c * CELL
                im = load(Path(template.format(key=key)), Path(t))
                if im is None:
                    draw.rectangle([x + 6, y + 6, x + CELL - 6, y + CELL - 6], outline="#ccc")
                    draw.text((x + CELL // 2 - 14, y + CELL // 2), "none", fill="#999")
                else:
                    sheet.paste(im.resize((CELL - 12, CELL - 12)), (x + 6, y + 6))
    sheet.save(args.out)
    print(f"{len(keys)} rows × {len(cols)} columns → {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
