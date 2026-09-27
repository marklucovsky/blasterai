#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Swap `please` for `don't` on home, place `at`, and drop two stale duplicates.

    python3 tools/place_dont_and_at.py

Idempotent. Touches `scenes/core_first.json` only — no vocabulary, no art.

WHY `don't` REPLACES `please`
-----------------------------
`don_t` is on WordPower Basic 48's home page — row 1, column 3, between `me`
and `that` (`tools/reference_boards/aubrey_home.txt`). `please` is not on that
board anywhere. Mark, who has watched the word in daily use: *"all done is on
aubrey's board and I've seen heavy use of this. Please is not."*

The swap is free: `don't` is already in `vocabulary.json` (class `social`, POS
`negation`) with art in all five shipped sets. `please` keeps its place on the
`social` page, so it moves one tap away rather than disappearing.

WHY `at` GOES ON `describe`
---------------------------
`at` is the only word in the `core` class that exists, has art in all five sets,
and appears on **no page at all** — it was reachable from nowhere. `describe`
already carries the rest of the prepositions (`behind`, `between`, `over`,
`under`, `near`, `top`, `bottom` …), so it costs no home cell to fix.

THE TWO DUPLICATES
------------------
`describe` listed `don't` and `happy` explicitly. Both were hoisted there when
those words had nowhere better to be; both now do. `don't` is going on home (and
is on `social` by class anyway), and `happy` is class `feeling`, which is its own
page since Questions/Groups split it out of `social`. A word on three pages is a
word whose home is unclear.

THE `play` SELECTOR WAS NEVER WIRED UP
--------------------------------------
`play_activities` selects `art`/`toy`/`sports`/`games` but not `play`, so the
three words in class `play` reached it through no selector at all — `tricycle`
was on no page. Adding `play` to the class list fixes all three.

`slide` and `swing` stay hand-listed on `places` as well, so they are on two
pages **on purpose**. I first read that hand-listing as a workaround for the
missing selector and removed it; Mark: *"when my granddaughters talk about these
they treat them as places: I want to go to the slide, or to the swing, or to the
playground. They view them as destinations more so than the activity."* A word
that is genuinely two categories to the child belongs in both, which is what the
published boards do too. That is a different case from `don't` and `happy` above,
which were on `describe` only because they had nowhere else to be.

STILL UNPLACED, DELIBERATELY: `bus`
-----------------------------------
The only vehicle in the whole vocabulary — no car, train, bike or truck — so
there is no transport category for it to join and no obvious page that wants one
bus. Left for Mark rather than guessed at.
"""

import collections
import json
from pathlib import Path

SCENE = Path("claudeBlast/Resources/scenes/core_first.json")


def main():
    if not SCENE.exists():
        raise SystemExit(f"run from the repo root — {SCENE} not found")

    scene = json.loads(SCENE.read_text(), object_pairs_hook=collections.OrderedDict)
    pages = {p["key"]: p for p in scene["pages"]}
    home = pages[scene["homePageKey"]]

    # 1. please -> don't, in place, so the rest of Mark's ordering is untouched.
    for tile in home["tiles"]:
        keys = tile.get("keys")
        if keys and "please" in keys:
            keys[keys.index("please")] = "don't"
            print("home: please -> don't")

    # 2 & 3. describe sheds the two duplicates and gains the orphan.
    describe = pages["describe"]
    for tile in describe["tiles"]:
        keys = tile.get("keys")
        if not keys:
            continue
        for stale in ("don't", "happy"):
            if stale in keys:
                keys.remove(stale)
                print(f"describe: -{stale}")
        if "at" not in keys:
            keys.append("at")
            print("describe: +at  (was on no page at all)")
    describe["tiles"] = [t for t in describe["tiles"] if t.get("keys") != []]

    # 4. Wire up the `play` class and undo the workaround it forced.
    for tile in pages["play_activities"]["tiles"]:
        cl = tile.get("class")
        if isinstance(cl, list) and "play" not in cl:
            cl.append("play")
            print("play_activities: +class play  (slide/swing/tricycle)")
    for tile in pages["places"]["tiles"]:
        keys = tile.get("keys")
        if keys is None:
            continue
        for both in ("slide", "swing"):
            if both not in keys:
                keys.append(both)
                print(f"places: +{both}  (destination to a child; also on play_activities)")

    SCENE.write_text(json.dumps(scene, indent=2) + "\n")

    links = sum(1 for t in home["tiles"] if t.get("link"))
    words = sum(len(t.get("keys", [])) for t in home["tiles"])
    print(f"\nhome: {links} links + {words} words + Home = {links + words + 1} of 60")


if __name__ == "__main__":
    main()
