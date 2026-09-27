#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Show a home page's structure: parts of speech, bands, and vertical pairs.

    python3 tools/analyze_home_layout.py [--scene core_first] [--cols 12]

WHY BOTH AXES
-------------
`show_home_grid.py` prints what is where. This asks whether the arrangement
*means* anything, which is a different question and needs both directions.

The board is 12 wide, so cell n and cell n+12 are vertically adjacent — and a
child scanning for a word uses that adjacency exactly as much as the horizontal
one. Laying the page out as a reading-order run and then judging it as a run
misses half the structure: `in`/`out`, `on`/`off` and `up`/`down` sit one above
the other here, which is invisible in a flat list and obvious on the grid.

So this prints three things:

  - the part of speech in every cell, which makes colour bands visible
  - whether each column is single-purpose, which is what a band actually is
  - the vertical pairs, where antonyms and related verbs can be stacked

Colour is the child-facing signal — a tile is drawn by its part of speech — so a
column that holds one part of speech reads as one block of colour, and a column
that mixes reads as noise regardless of how sensible the words are.
"""

import argparse
import json
from pathlib import Path

SCENES = Path("claudeBlast/Resources/scenes")
POS = Path("claudeBlast/Resources/parts_of_speech.json")

# Short codes, upper-case for the parts of speech that carry their own colour
# and lower-case for the ones that share the function-word grey.
CODE = {
    "pronoun": "PRO", "verb": "VRB", "negation": "NEG", "question": "QST",
    "social": "soc", "interjection": "soc", "adjective": "adj", "noun": "nou",
    "preposition": "fn", "determiner": "fn", "conjunction": "fn",
}
COLOUR = {
    "pronoun": "yellow", "verb": "green", "negation": "red", "question": "purple",
    "social": "pink", "interjection": "pink", "adjective": "blue", "noun": "orange",
    "preposition": "grey", "determiner": "grey", "conjunction": "grey",
}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--scene", default="core_first")
    ap.add_argument("--cols", type=int, default=12)
    args = ap.parse_args()

    scene = json.loads((SCENES / f"{args.scene}.json").read_text())
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])
    table = json.loads(POS.read_text())
    w2p = {w: p for p, ws in table.items() for w in ws}

    cells = [("HOME", "·", "chrome")]
    for tile in home["tiles"]:
        if tile.get("link"):
            cells.append((f"→{tile['link']}", "LNK", "link"))
        if "space" in tile:
            n = tile["space"]
            cells.extend([("·", "", "gap")] * (int(n) if isinstance(n, int) else 1))
        for k in tile.get("keys", []):
            part = w2p.get(k)
            cells.append((k, CODE.get(part, "???"), COLOUR.get(part, "unknown")))

    cols = args.cols
    rows = (len(cells) + cols - 1) // cols

    print("WORDS\n")
    for r in range(rows):
        print("  " + " ".join(f"{c[0][:8]:>8}" for c in cells[r * cols:(r + 1) * cols]))
    print("\nPART OF SPEECH\n")
    for r in range(rows):
        print("  " + " ".join(f"{c[1]:>8}" for c in cells[r * cols:(r + 1) * cols]))

    print("\nCOLUMNS — a single-colour column reads as one block\n")
    for c in range(cols):
        col = [cells[r * cols + c] for r in range(rows) if r * cols + c < len(cells)]
        words = [x for x in col if x[2] not in ("chrome", "link", "gap")]
        kinds = {x[2] for x in words}
        if not words:
            continue
        flag = "" if len(kinds) == 1 else f"   MIXED: {', '.join(sorted(kinds))}"
        print(f"  col {c:2d}  {'/'.join(sorted(kinds)):28s}{flag}")

    print("\nVERTICAL PAIRS (n, n+12) — both cells a word\n")
    for a in range(len(cells) - cols):
        top, bottom = cells[a], cells[a + cols]
        if top[2] in ("chrome", "link", "gap") or bottom[2] in ("chrome", "link", "gap"):
            continue
        same = "same colour" if top[2] == bottom[2] else f"{top[2]} / {bottom[2]}"
        print(f"  col {a % cols:2d}  {top[0]:10s} over {bottom[0]:10s}  ({same})")


if __name__ == "__main__":
    main()
