#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Exchange two words' positions on the home page. Idempotent per pair.

    python3 tools/swap_home_words.py with not like open

Takes pairs. Each pair swaps the two words wherever they sit, leaving every
other cell exactly where it is — which is the whole point, because on this
board a cell's position *is* its meaning. Anything that reflows the page moves
words a child has already learned.

THE TWO SWAPS THIS WAS WRITTEN FOR
----------------------------------
The home page resolves into three vertical bands — pronouns in columns 0-2,
a 4x4 block of verbs in columns 3-6, function words in 7-10 — and 32 of its 36
vertical neighbours share a colour. Two cells spoiled it:

`with` <-> `not`
    `not` is a negation, drawn red, sitting at the foot of column 7 with three
    greys above it. Moving `with` there makes that column `to / for / here /
    with`: four prepositions, one colour, top to bottom. `not` takes `with`'s
    place in column 11, which is already mixed, so nothing new is spoiled.

`like` <-> `open`
    Puts `want` directly above `like` in column 4 — the pair a child reaches for
    together — and leaves `help` above `open` in column 3, which is a sensible
    pair in its own right. Both cells stay inside the verb block, so the 4x4 is
    untouched.

Deliberately NOT done: gathering `yes`/`no`/`stop` out of the bottom-left
corner. Every arrangement that collects them either breaks the verb block or
evicts a pronoun from columns 0-2, and the bottom-left is where a child's hand
rests anyway — a good home for the three highest-frequency answers whatever
colour they draw in.
"""

import collections
import json
import sys
from pathlib import Path

SCENE = Path("claudeBlast/Resources/scenes/core_first.json")


def locate(home, word):
    for tile in home["tiles"]:
        keys = tile.get("keys")
        if keys and word in keys:
            return tile, keys.index(word)
    return None, None


def main():
    args = sys.argv[1:]
    if not args or len(args) % 2:
        sys.exit(__doc__)
    if not SCENE.exists():
        sys.exit(f"run from the repo root — {SCENE} not found")

    scene = json.loads(SCENE.read_text(), object_pairs_hook=collections.OrderedDict)
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])

    for a, b in zip(args[::2], args[1::2]):
        tile_a, i = locate(home, a)
        tile_b, j = locate(home, b)
        if tile_a is None or tile_b is None:
            missing = a if tile_a is None else b
            sys.exit(f"{missing!r} is not on the home page")
        tile_a["keys"][i], tile_b["keys"][j] = b, a
        print(f"swapped {a} <-> {b}")

    SCENE.write_text(json.dumps(scene, indent=2) + "\n")


if __name__ == "__main__":
    main()
