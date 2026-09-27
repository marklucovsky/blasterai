#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Print a scene's home page as the grid it will actually render.

    python3 tools/show_home_grid.py [--scene core_first] [--cols 12]

FOR LAYOUT WORK, WHICH THE JSON IS BAD AT
-----------------------------------------
`core_first.json` stores the home page as a flat list of build commands, so the
file says nothing about where a row ends. Reordering words in it is done blind:
you can move a word three places and not discover until the app launches that it
crossed a row boundary and now sits under a different column.

This lays the same list out at the width the board uses, with Home in cell 0
where the grid injects it, so a change can be judged before it is built.

WHY 12 COLUMNS
--------------
An 11" iPad Pro at the default density gives **12 x 5 = 60** cells, and since
the large-iPad tier was added (`GridLayoutCalculator.iPadLargeBaseSize`) a 13"
gives the same 12 columns rather than 14. Home occupies cell 0 of every page, so
**59 cells are available** and the two sizes agree on where every one of them
falls.

iPad mini and iPhone reflow to their own column counts and are deliberately not
what this optimises for — tile position is motor planning, and it can only be
held stable across the sizes the board is actually used on.
"""

import argparse
import json
from pathlib import Path

SCENES = Path("claudeBlast/Resources/scenes")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--scene", default="core_first")
    ap.add_argument("--cols", type=int, default=12)
    ap.add_argument("--rows", type=int, default=5)
    args = ap.parse_args()

    path = SCENES / f"{args.scene}.json"
    if not path.exists():
        raise SystemExit(f"no scene at {path}")
    scene = json.loads(path.read_text())
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])

    cells = ["⌂ HOME"]
    for tile in home["tiles"]:
        if tile.get("link"):
            cells.append(f"→{tile['link']}")
        if "space" in tile:
            count = tile["space"]
            cells.extend(["·"] * (int(count) if isinstance(count, int) else 1))
        cells.extend(tile.get("keys", []))

    capacity = args.cols * args.rows
    print(f"{scene['name']} — page '{home['key']}'")
    print(f"{args.cols} columns x {args.rows} rows = {capacity} cells, "
          f"{capacity - 1} available after Home\n")

    width = max(len(c) for c in cells) + 1
    for r in range(args.rows):
        row = cells[r * args.cols:(r + 1) * args.cols]
        if not row:
            break
        print(f"  {r * args.cols:3d} │ " + "".join(c.ljust(width) for c in row))

    print()
    if len(cells) > capacity:
        over = len(cells) - capacity
        print(f"  ** {len(cells)} cells — {over} OVER capacity; the last {over} "
              f"spill onto a second page")
    elif len(cells) == capacity:
        print(f"  {len(cells)} cells — exactly full, no spare")
    else:
        print(f"  {len(cells)} cells — {capacity - len(cells)} spare")


if __name__ == "__main__":
    main()
