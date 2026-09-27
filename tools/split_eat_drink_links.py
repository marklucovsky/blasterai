#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Give `eat` and `drink` separate links on the home page. Idempotent.

    python3 tools/split_eat_drink_links.py

THE FAULT
---------
Home had one combined entry: `eat` spoke "eat" and opened `food_drinks`, a page
holding food *and* drink. So the tile said one thing and did another, and the
only way to stop it saying the wrong thing was to silence it — which is what
happened, leaving a board where `eat` navigates without speaking while `play`
beside it still speaks. Two adjacent link tiles behaving differently is worse
than either rule applied consistently.

Both references separate them. WordPower Basic 48 has distinct `eat` and `drink`
cells; Vocal Flair has `eat` on its home page as a word. And our own `actions`
page has had the right shape all along:

    {"link": "drink", "to": "drinks", "audible": true}
    {"link": "eat",   "to": "food",   "audible": true}

So this makes home match the page that already got it right: `eat` speaks and
opens food, `drink` speaks and opens drinks. Both audible, because on both
reference boards these are words a child taps to ask for something — the folder
is the secondary function.

WHY `food_drinks` GOES
----------------------
Nothing else linked to it, so splitting the link would leave it unreachable —
present in the file, reachable by nobody, which reads as missing vocabulary
rather than missing navigation. It is also redundant: `food` and `drinks` are
built from `{"class": "food"}` and `{"class": "drinks"}` and between them hold
everything `food_drinks` listed by hand, plus every food word added since.
"""

import collections
import json
from pathlib import Path

SCENE = Path("claudeBlast/Resources/scenes/core_first.json")


def main():
    if not SCENE.exists():
        raise SystemExit(f"run from the repo root — {SCENE} not found")
    scene = json.loads(SCENE.read_text(), object_pairs_hook=collections.OrderedDict)
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])

    changed = False
    for tile in home["tiles"]:
        if tile.get("link") == "eat":
            if tile.get("to") != "food" or not tile.get("audible"):
                tile["to"] = "food"
                tile["audible"] = True
                changed = True
                print('home: eat -> food, audible')

    if not any(t.get("link") == "drink" for t in home["tiles"]):
        idx = max(i for i, t in enumerate(home["tiles"]) if t.get("link") == "eat")
        home["tiles"].insert(idx + 1, collections.OrderedDict(
            [("link", "drink"), ("to", "drinks"), ("audible", True)]))
        changed = True
        print('home: + drink -> drinks, audible')

    before = len(scene["pages"])
    scene["pages"] = [p for p in scene["pages"] if p["key"] != "food_drinks"]
    if len(scene["pages"]) != before:
        changed = True
        print("removed page 'food_drinks' (unreferenced; food + drinks cover it)")

    if changed:
        SCENE.write_text(json.dumps(scene, indent=2) + "\n")

    links = sum(1 for t in home["tiles"] if t.get("link"))
    words = sum(len(t.get("keys", [])) for t in home["tiles"])
    total = links + words + 1
    print(f"\nhome: {links} links + {words} words + Home = {total} of 60")
    if total > 60:
        print(f"  ** {total - 60} over — the last {total - 60} cell(s) spill to page 2")


if __name__ == "__main__":
    main()
