#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Find tone variants where the model painted the BACKGROUND instead of skin.

`mouth` in Classic is lips on white with no face at all. Asked to recolour "the
skin", the model filled the entire canvas with skin colour — the tile went from
a mouth to a mouth on a brown field. That is a different failure from a wrong
tone, and a reviewer scanning 255 rows can easily read it as "darker" rather
than "the background is gone".

The test is cheap and exact: Classic tiles sit on a white ground, so if a tile's
corners were white and no longer are, the background was repainted. That catches
the whole class in one pass instead of relying on the eye to spot it 255 times.

Any tile flagged here should be **excluded from toning entirely** rather than
regenerated — a tile with no skin has no tone, and the base art is already
correct for every set.

Usage:
    python3 tools/check_background_fill.py
"""

import json
from pathlib import Path

from PIL import Image

BASE = Path("tools/tile_sets")
SOURCE = BASE / "classic"
TONES = ["classic_chain_medium", "classic_chain_medium_dark"]
INSET = 6          # sample just inside the edge, avoiding any border artefact


def corners(img: Image.Image):
    w, h = img.size
    px = img.load()
    return [px[INSET, INSET], px[w - 1 - INSET, INSET],
            px[INSET, h - 1 - INSET], px[w - 1 - INSET, h - 1 - INSET]]


def is_white(c) -> bool:
    return min(c) > 233


def main():
    keys = sorted(p.stem for p in SOURCE.glob("*.png"))
    flagged = {}

    for key in keys:
        base = Image.open(SOURCE / f"{key}.png").convert("RGB")
        bc = corners(base)
        if not all(is_white(c) for c in bc):
            continue          # base was never white-ground; nothing to compare
        for tone in TONES:
            p = BASE / tone / f"{key}.png"
            if not p.exists():
                continue
            vc = corners(Image.open(p).convert("RGB"))
            painted = sum(1 for c in vc if not is_white(c))
            if painted >= 3:   # 3+ corners lost = the ground itself was filled
                flagged.setdefault(key, []).append(tone.replace("classic_chain_", ""))

    print(f"checked {len(keys)} tiles × {len(TONES)} tones")
    if not flagged:
        print("no background fills found")
        return
    print(f"\n{len(flagged)} tiles had their background painted:\n")
    for k, tones in sorted(flagged.items()):
        print(f"  {k:22} {', '.join(tones)}")
    print("\nThese have no skin to tone — exclude them rather than regenerate.")
    out = BASE / "tone_background_fills.json"
    out.write_text(json.dumps(sorted(flagged), indent=2) + "\n")
    print(f"→ {out}")


if __name__ == "__main__":
    main()
