#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Swap `all_done` and `stop` so the negations make one red column.

    python3 tools/cluster_negations.py [--write]

Idempotent. Two cells on the home page trade places; nothing else moves, no
link changes page, so no folder colour re-resolves.

WHY
---
    col 11 was      col 11 now
    don't   red     don't   red
    all_done pink   stop    red
    not     red     not     red
    >keyboard       >keyboard

`don't`, `stop` and `not` are all `negation`, and `all_done` is `interjection`
— so the one pink tile was sitting in the middle of what would otherwise be a
solid red column. Colour on a board is a column a child scans, not a label read
one tile at a time; the same argument put the four green folders over the verb
block in `align_link_row.py`.

`stop` also belongs there semantically. It is a negation-command like `don't`
and `not`, and `all_done` at the right-hand edge reads as *end of the row, end
of the turn*.

WHAT IT COSTS
-------------
Row 4 becomes `yes | all_done | no`, and `all_done` is pink like `yes` — so the
buffer Brandi asked for between `yes` and `no` is now positional only, where
`stop` gave both position and colour:

    "We often see yes and no spaced away from each other so a miss hit isn't
     accidental."

Her concern is a mis-hit, which is positional, and the cost of landing on
`all_done` instead of `yes` is nothing beside landing on `no`. The board is
60/60, so there is no spare non-pink tile that could buffer `yes`/`no` while
`stop` joins the red column — it is a genuine either/or, taken deliberately.
"""

import argparse
import collections
import json
from pathlib import Path

SCENE = Path("claudeBlast/Resources/scenes/core_first.json")
PAIR = ("all_done", "stop")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    if not SCENE.exists():
        raise SystemExit(f"run from the repo root — {SCENE} not found")

    scene = json.loads(SCENE.read_text(), object_pairs_hook=collections.OrderedDict)
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])
    rows = [t for t in home["tiles"] if "keys" in t]

    # Which row holds each word, and where in it.
    where = {}
    for index, row in enumerate(rows):
        for word in PAIR:
            if word in row["keys"]:
                where[word] = (index, row["keys"].index(word))

    missing = [w for w in PAIR if w not in where]
    if missing:
        raise SystemExit(f"not on the home page: {', '.join(missing)}")

    a, b = PAIR
    (row_a, col_a), (row_b, col_b) = where[a], where[b]

    # Already done: `stop` sits at the right-hand edge, `all_done` does not.
    if col_a < col_b:
        print("already clustered")
        return

    rows[row_a]["keys"][col_a] = b
    rows[row_b]["keys"][col_b] = a
    print(f"  {a:9} cell {row_a * 12 + col_a + 12:3}  ->  {b}")
    print(f"  {b:9} cell {row_b * 12 + col_b + 12:3}  ->  {a}")

    if not args.write:
        print("\n(dry run — pass --write to apply)")
        return

    SCENE.write_text(json.dumps(scene, indent=2) + "\n")
    print("\nwritten")


if __name__ == "__main__":
    main()
