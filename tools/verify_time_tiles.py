#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Check the Time tiles against the rules they are supposed to satisfy.

    python3 tools/verify_time_tiles.py --sets classic,playful_3d,high_contrast

Exits non-zero if anything fails, so it can gate a commit.

WHY THIS EXISTS
---------------
Every fault in this set so far was found by a person looking at a picture, and
most were found late: a queue facing the wrong way, a figure clipped at the
canvas edge, a strip with six segments instead of seven, uneven gaps. Each was
obvious once seen at full size and invisible in a contact sheet, which is where
they kept being reviewed.

They are also all *measurable*. A row of figures either has four separable
blobs or it does not. A strip either has seven segments or it does not. A tile
either leaves a margin at the canvas edge or it does not. None of that needs
an eye, and an eye is demonstrably bad at it after the twentieth tile.

So the rules are written down here and checked. The point is not that the
checks are clever — they are deliberately crude — it is that they run every
time and do not get bored.

WHAT IS CHECKED
---------------
Queue tiles (first/next/last):
  - exactly four figures
  - the coloured one is at the index the word means (0, 1, 3)
  - nothing touches the canvas edge
  - gaps between figures are within tolerance of each other

Strip tiles (today/tomorrow/yesterday/week/weekend):
  - exactly seven segments

Everything else is left alone: a clock with a red slash is not something this
can judge, and pretending otherwise would give false confidence.
"""

import argparse
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("pip install pillow numpy")

TILE_SETS = Path("tools/tile_sets")
BG_TOLERANCE = 28

QUEUE_INDEX = {"first": 0, "next": 1, "last": 3}
STRIP_KEYS = ["today", "tomorrow", "yesterday", "week", "weekend"]


def load(path):
    px = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    edges = np.concatenate([px[:, :6], px[:, -6:]], axis=1)
    ref = np.median(edges, axis=1)
    is_bg = np.abs(px - ref[:, None, :]).max(axis=2) <= BG_TOLERANCE
    return px, is_bg


def spans_of(mask_1d):
    spans, start = [], None
    for x, v in enumerate(mask_1d):
        if v and start is None:
            start = x
        elif not v and start is not None:
            spans.append((start, x - 1))
            start = None
    if start is not None:
        spans.append((start, len(mask_1d) - 1))
    return spans


def check_queue(path, key):
    """Four figures, the coloured one in the right slot, nothing clipped."""
    px, is_bg = load(path)
    h, w = is_bg.shape
    fails = []

    band = ~is_bg[int(h * 0.20):int(h * 0.60)].all(axis=0)
    spans = [list(s) for s in spans_of(band)]
    while len(spans) > 4:                      # reunite detached noses
        gaps = [spans[i + 1][0] - spans[i][1] for i in range(len(spans) - 1)]
        i = gaps.index(min(gaps))
        spans[i][1] = spans[i + 1][1]
        del spans[i + 1]

    if len(spans) != 4:
        return [f"{len(spans)} figures, expected 4"]

    # Nothing may touch the canvas edge. A clipped nose is the fault this
    # catches; it is invisible at thumbnail size and unmistakable at full size.
    if spans[0][0] <= 1:
        fails.append(f"leftmost figure touches the left edge (x={spans[0][0]})")
    if spans[-1][1] >= w - 2:
        fails.append(f"rightmost figure touches the right edge (x={spans[-1][1]})")

    # Which figure is the coloured one: saturation is the discriminator, since
    # the others are grey, white or black by construction.
    sat = px.max(axis=2) - px.min(axis=2)
    scores = []
    for a, b in spans:
        region = sat[:, a:b + 1]
        mask = ~is_bg[:, a:b + 1]
        scores.append(float(region[mask].mean()) if mask.any() else 0.0)
    marked = int(np.argmax(scores))
    if marked != QUEUE_INDEX[key]:
        fails.append(f"coloured figure at index {marked}, expected {QUEUE_INDEX[key]} "
                     f"(saturation per figure: {[round(s, 1) for s in scores]})")

    # Even spacing. Generous, because crops are tight to differing silhouettes.
    gaps = [spans[i + 1][0] - spans[i][1] for i in range(3)]
    if max(gaps) - min(gaps) > 0.5 * max(max(gaps), 1):
        fails.append(f"uneven gaps between figures: {gaps}")

    return fails


def count_cells(px, y, x0, x1):
    """Cells along row `y` between `x0` and `x1`.

    A cell is a WIDE run of near-constant colour; a divider is a NARROW one.
    Counting ink runs directly does not work, because a filled cell is ink too
    and merges with the outline beside it — a red square and its black border
    read as one run. Segmenting by colour change and then discarding the thin
    runs separates "a cell that happens to be filled" from "the line between
    two cells", which is the distinction that matters.
    """
    row = px[y, x0:x1 + 1].astype(np.int16)
    breaks = np.where(np.abs(np.diff(row, axis=0)).max(axis=1) > 40)[0] + 1
    bounds = [0, *breaks.tolist(), row.shape[0]]
    widths = [bounds[i + 1] - bounds[i] for i in range(len(bounds) - 1)]
    span = x1 - x0 + 1

    # Two filters, because one is not enough.
    #
    # Dividers are a few pixels wide and cells are a seventh of the strip, so a
    # flat 4% cut separates them — but `week` is drawn with an enclosing frame,
    # and the frame's two end pieces measured 37px against cells of 83. Wide
    # enough to pass the flat cut, and not cells.
    #
    # Cells within one strip are all the same width by construction, so the
    # second filter keeps only runs close to the modal wide run. The frame ends
    # fall away; the seven cells stay.
    wide = [wd for wd in widths if wd >= span * 0.04]
    if not wide:
        return 0
    typical = sorted(wide)[len(wide) // 2]
    return sum(1 for wd in wide if wd >= typical * 0.6)


def check_strip(path, key, expect=7):
    """Exactly seven segments, on one row."""
    px, is_bg = load(path)
    h, w = is_bg.shape
    ink_rows = np.where(~is_bg.all(axis=1))[0]
    if len(ink_rows) == 0:
        return ["tile is empty"]

    # Locate the STRIP, not the artwork.
    #
    # Several of these tiles carry an arrow above the strip, and the first
    # version measured from the top of the ink to the bottom — so its sample
    # rows landed on the arrow, reported one segment, and its two-band check
    # fired on the empty space between arrow and strip. The strip is simply the
    # widest thing in the picture, so the rows that span nearly the full ink
    # width are the strip and everything else is annotation.
    extents = np.zeros(is_bg.shape[0], dtype=int)
    for y in range(is_bg.shape[0]):
        runs = spans_of(~is_bg[y])
        if runs:
            extents[y] = runs[-1][1] - runs[0][0]
    widest = extents.max()
    band_rows = np.where(extents > 0.8 * widest)[0]
    if len(band_rows) == 0:
        return ["no strip found"]
    top, bottom = int(band_rows[0]), int(band_rows[-1])

    # Two rows of squares is a failure mode this set hit repeatedly, and within
    # the strip's own rows it shows as a band of pure background.
    row_has_ink = (~is_bg[top:bottom + 1]).any(axis=1)
    gaps = [g for g in spans_of(~row_has_ink) if g[1] - g[0] > 0.06 * (bottom - top)]
    if gaps:
        return [f"strip splits into {len(gaps) + 1} horizontal bands — "
                "it must be a single row"]

    # Sample several rows through the strip and take the majority, so one row
    # clipping a binder ring cannot decide it alone.
    counts = []
    for frac in (0.35, 0.50, 0.65):
        y = int(top + (bottom - top) * frac)
        runs = spans_of(~is_bg[y])
        if not runs:
            continue
        counts.append(count_cells(px, y, runs[0][0], runs[-1][1]))
    if not counts:
        return ["no strip found on any sampled row"]

    best = max(set(counts), key=counts.count)
    if best != expect:
        return [f"{best} segments, expected {expect} (rows sampled: {counts})"]
    return []


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sets", default="classic,playful_3d,high_contrast")
    args = ap.parse_args()

    failed = False
    for name in [s.strip() for s in args.sets.split(",") if s.strip()]:
        root = TILE_SETS / name
        if not root.is_dir():
            print(f"[skip] {name}: no such set")
            continue
        print(f"\n=== {name} ===")
        for key in QUEUE_INDEX:
            p = root / f"{key}.png"
            if not p.exists():
                print(f"  [MISS] {key}: not generated")
                failed = True
                continue
            fails = check_queue(p, key)
            if fails:
                failed = True
                print(f"  [FAIL] {key}")
                for f in fails:
                    print(f"         {f}")
            else:
                print(f"  [ok]   {key}")

        for key in STRIP_KEYS:
            p = root / f"{key}.png"
            if not p.exists():
                print(f"  [MISS] {key}: not generated")
                failed = True
                continue
            fails = check_strip(p, key)
            if fails:
                failed = True
                print(f"  [FAIL] {key}")
                for f in fails:
                    print(f"         {f}")
            else:
                print(f"  [ok]   {key}")

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
