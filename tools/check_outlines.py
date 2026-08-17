#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Check that skin-tone correction left the black outlines alone.

Mark caught the correction washing out the black linework next to skin — jaw,
neckline, mouth, nose. The cause was antialiased outline pixels passing the skin
gamut test and being shifted like skin. This measures whether a fix actually held,
rather than trusting it by eye on one tile.

Method: take the pixels that are DARK in the Classic original (the linework), and
report how much lighter they became in the variant. A correct variant leaves them
essentially untouched — the model recolours skin, not lines.

Usage:
    python3 tools/check_outlines.py --tiles mom
    python3 tools/check_outlines.py               # every tile in every tone set
"""

import argparse
from pathlib import Path

from PIL import Image

BASE = Path("tools/tile_sets")
SOURCE = BASE / "classic"
TONES = ["light", "medium_light", "medium", "medium_dark", "dark"]
DARK_LUMA = 70.0          # the taper's cut-off — below this is linework


def luma(c) -> float:
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def outline_drift(orig_path: Path, var_path: Path, step: int = 2):
    o = Image.open(orig_path).convert("RGB")
    v = Image.open(var_path).convert("RGB")
    if o.size != v.size:
        v = v.resize(o.size, Image.LANCZOS)
    op, vp = o.load(), v.load()
    w, h = o.size
    deltas = []
    for y in range(0, h, step):
        for x in range(0, w, step):
            lo = luma(op[x, y])
            if lo > DARK_LUMA:
                continue
            deltas.append(luma(vp[x, y]) - lo)
    if not deltas:
        return None
    deltas.sort()
    n = len(deltas)
    return {
        "n": n,
        "median": deltas[n // 2],
        "p90": deltas[9 * n // 10],
        "washed": sum(1 for d in deltas if d > 40) / n * 100,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiles", default="")
    args = ap.parse_args()

    for tone in TONES:
        d = BASE / f"classic_{tone}"
        if not d.exists():
            continue
        keys = ([k.strip() for k in args.tiles.split(",") if k.strip()]
                or sorted(p.stem for p in d.glob("*.png")))
        print(f"--- classic_{tone}")
        for k in keys:
            v, o = d / f"{k}.png", SOURCE / f"{k}.png"
            if not (v.exists() and o.exists()):
                continue
            r = outline_drift(o, v)
            if not r:
                continue
            verdict = ("OUTLINES WASHED" if r["washed"] > 8 or r["median"] > 25
                       else "ok")
            print(f"    {k:8} dark px {r['n']:6d}  median +{r['median']:5.1f}  "
                  f"p90 +{r['p90']:5.1f}  washed {r['washed']:4.1f}%   {verdict}")

            # Same measure on the raw model output, so the correction is judged
            # against what the model produced rather than in isolation.
            raw = BASE / f"classic_{tone}_ai" / f"{k}.png"
            if raw.exists():
                rr = outline_drift(o, raw)
                if rr:
                    print(f"    {'':8} (raw model:  median +{rr['median']:5.1f}  "
                          f"washed {rr['washed']:4.1f}%)")


if __name__ == "__main__":
    main()
