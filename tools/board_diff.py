#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Diff a reference home board against our vocabulary and our own home page.

    Usage:
        python3 tools/board_diff.py tools/reference_boards/aubrey_home.txt
        python3 tools/board_diff.py <board.txt> --against core_first

WHY A SEPARATE TOOL FROM obz_mine.py
------------------------------------
`obz_mine.py` reads a file format. This reads a transcription — a board somebody
photographed or typed out, in a plain pipe-delimited grid, because the boards
worth comparing against are not all published as `.obz`. The most important one
is not published at all: it is the board on the child's device.

The question this answers is narrow and it is the one that actually blocks a
starter-board decision: **for every cell on a reference board, do we have that
word, and is it on our home page?** Three outcomes, and the third is the
interesting one:

  - we have it and it is on our home page      -> agreement, nothing to do
  - we do not have the word at all             -> a vocabulary gap
  - we have it but it is not on our home page  -> a placement gap

Placement gaps are invisible in a vocabulary diff, and they are most of what
separates a board that feels complete from one that does not. A word that exists
three taps away is not available to a child mid-sentence.

FORMAT
------
Pipe-delimited rows, one line per grid row. `#` comments and blank lines are
skipped. ALLCAPS cells are treated as navigation links and excluded from the
word counts; lowercase cells are speaking tiles. `.` is an empty cell.
"""

import argparse
import collections
import json
import sys
from pathlib import Path

VOCAB = Path("claudeBlast/Resources/vocabulary.json")
SCENES = Path("claudeBlast/Resources/scenes")


def read_board(path):
    rows = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        rows.append([c.strip() for c in line.split("|")])
    return rows


def split_cells(rows):
    """(speaking words, link labels), preserving reading order."""
    words, links = [], []
    for row in rows:
        for cell in row:
            if not cell or cell == ".":
                continue
            (links if cell.isupper() else words).append(cell)
    return words, links


def home_page_keys(scene_key):
    """Every tile key on the named scene's home page."""
    path = SCENES / f"{scene_key}.json"
    if not path.exists():
        sys.exit(f"no scene at {path}")
    scene = json.loads(path.read_text())
    home = scene.get("homePageKey")
    for page in scene.get("pages", []):
        if page.get("key") != home:
            continue
        keys = []
        for tile in page.get("tiles", []):
            keys.extend(tile.get("keys", []))
        return set(keys), home
    sys.exit(f"{scene_key}: no page matching homePageKey {home!r}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("board")
    ap.add_argument("--against", default="core_first", help="scene key to compare (default: core_first)")
    args = ap.parse_args()

    if not VOCAB.exists():
        sys.exit(f"run from the repo root — {VOCAB} not found")
    ours = {t["key"]: t["wordClass"] for t in json.loads(VOCAB.read_text())}
    home, home_key = home_page_keys(args.against)

    rows = read_board(args.board)
    words, links = split_cells(rows)
    cells = sum(len(r) for r in rows)

    print(f"reference: {args.board}")
    print(f"  {len(rows)}x{max(len(r) for r in rows)} = {cells} cells | "
          f"{len(words)} speaking, {len(links)} links")
    print(f"ours: {args.against} home page '{home_key}' — {len(home)} tiles\n")

    absent = [w for w in words if w not in ours]
    misplaced = [w for w in words if w in ours and w not in home]
    agreed = [w for w in words if w in home]

    print(f"AGREEMENT           {len(agreed):3d}  on their board and ours")
    print(f"PLACEMENT GAP       {len(misplaced):3d}  we have the word, it is not on our home page")
    print(f"VOCABULARY GAP      {len(absent):3d}  we do not have the word at all\n")

    if absent:
        print("VOCABULARY GAP — needs a word and art before it can be placed:")
        print(f"  {', '.join(absent)}\n")

    if misplaced:
        print("PLACEMENT GAP — exists in our vocabulary, filed under:")
        by_class = collections.defaultdict(list)
        for w in misplaced:
            by_class[ours[w]].append(w)
        for cls in sorted(by_class):
            print(f"  {cls:10s} {', '.join(sorted(by_class[cls]))}")
        print()

    extra = sorted(home - set(words))
    if extra:
        print(f"ON OUR HOME PAGE, NOT ON THEIRS ({len(extra)}) — the displacement budget:")
        print(f"  {', '.join(extra)}")


if __name__ == "__main__":
    main()
