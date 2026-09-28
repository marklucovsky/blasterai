#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Put the green folders directly above the green words.

    python3 tools/align_link_row.py [--write]

Idempotent. Reorders the link row on `home` and changes nothing else — no
words move, no colors change, no cell is added or removed.

WHY
---
Once `eat`, `drink` and `play` took their own verb color (they speak as well as
navigate), the home page had four green folders — those three plus `actions` —
and a 4x4 block of green verbs sitting three columns to their left. Mark:
*"we have an opportunity to re-structure the top row and put our 4 green links
directly over the strong verb column in the middle of the board."*

Color on an AAC board is a column you scan, not a label you read one tile at a
time. A folder of doing words standing at the head of the doing words is the
board explaining its own layout; the same folder three columns over is just a
green tile. This is the payoff of destination coloring, and it costs a reorder.

WHAT LINES UP AFTERWARDS
------------------------
    col  0   Home
    col  1   people    yellow   over the pronoun columns
    col  2   question  purple
    col  3   eat       green  |
    col  4   drink     green  |  over the 4x4 verb block
    col  5   play      green  |
    col  6   actions   green  |
    col  7   places    orange |
    col  8   social    pink   |  over the 4x4 function-word block
    col  9   time      blue   |
    col 10   describe  blue   |
    col 11   groups    navy     over don't / all_done / not / keyboard

Columns 7-10 are the function-word block, which is grey, and no folder is grey
because no page is mostly function words — every one of ours is already on the
home page. Those four are the honest leftovers rather than a second alignment.
"""

import argparse
import collections
import json
from pathlib import Path

SCENE = Path("claudeBlast/Resources/scenes/core_first.json")

# The order the row should read in. Only links listed here are placed; anything
# else keeps its relative position after them, so adding a folder without
# touching this list degrades to "appended" rather than "dropped".
ORDER = ["people", "question", "eat", "drink", "play", "actions",
         "places", "social", "time", "describe", "groups"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    if not SCENE.exists():
        raise SystemExit(f"run from the repo root — {SCENE} not found")

    scene = json.loads(SCENE.read_text(), object_pairs_hook=collections.OrderedDict)
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])

    # Permute IN PLACE, across the cells the named links already occupy.
    #
    # The first version of this pulled every link to the front and pushed the
    # words after them, which looked right until `keyboard` moved: it is a link,
    # but it deliberately sits in the very last cell rather than in the folder
    # row, and hoisting it shunted `don't`/`all_done`/`not` into column 0 and
    # wrecked the whole layout. Only the links named in ORDER move, and they only
    # ever trade places with each other.
    rank = {key: i for i, key in enumerate(ORDER)}
    slots = [i for i, t in enumerate(home["tiles"])
             if t.get("link") in rank]
    links = [home["tiles"][i] for i in slots]
    ordered = sorted(links, key=lambda t: rank[t["link"]])

    before = [t["link"] for t in links]
    after = [t["link"] for t in ordered]

    print(f"{'cell':6} {'was':12} {'now':12}")
    for slot, b, a in zip(slots, before, after):
        mark = "" if b == a else "  <--"
        print(f"  {slot:4}  {b:12} {a:12}{mark}")

    if before == after:
        print("\nalready aligned")
        return

    if not args.write:
        print("\n(dry run — pass --write to apply)")
        return

    for slot, tile in zip(slots, ordered):
        home["tiles"][slot] = tile
    SCENE.write_text(json.dumps(scene, indent=2) + "\n")
    print(f"\nwritten — {sum(1 for b, a in zip(before, after) if b != a)} moved")


if __name__ == "__main__":
    main()
