#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Validate a bundled scene JSON before it reaches a device.

    Usage:
        python3 tools/check_scene.py claudeBlast/Resources/scenes/core_first.json
        python3 tools/check_scene.py --all

Exits non-zero on any error, so it can gate a commit.

WHY THIS EXISTS
---------------
Written immediately after shipping a `core_first.json` that broke bootstrap
entirely — a fresh install came up with **no scenes at all**, which is the worst
failure this file has, because there is nothing left on screen to diagnose it
from.

The cause was a misreading of the scene DSL that looks completely reasonable in
a diff:

    {"link": "play_activities", "to": "play_activities", "audible": false}

`to` is a **page key**. `link` is a **tile key** — a word from `vocabulary.json`
that must already exist and have art, because the link is rendered as a tile
like any other. The two are equal for `people` and `places` only because those
happen to be both a page name and a real word. They are *not* equal in the
general case, and the original file said so plainly:

    {"link": "eat",  "to": "food_drinks",     "audible": true}
    {"link": "play", "to": "play_activities", "audible": true}

There, a real word does double duty: `eat` speaks *and* opens the food page.
Inventing `food_drinks` as a tile key produces a placement pointing at a
TileModel that was never created.

The check that would have caught it is one line, and none of the validation
written that day performed it: every `link` value must be a key in
`vocabulary.json`. Checking `to` against page names — which was done — passes
happily while the board is broken.

WHAT ELSE IS CHECKED
--------------------
Each is a real failure mode of this format rather than a hypothetical:

- **link tile exists in vocabulary** — the bug above.
- **`to` names a real page** — a link into nowhere.
- **explicit `keys` exist in vocabulary** — renders an empty cell, silently.
- **no duplicate tile on a page** — a `keys` list repeating a word already
  placed by a `link` command yields two tiles for one word, and the DSL's
  update-in-place rule makes which one wins depend on command order.
- **homePageKey names a real page** — the scene opens on nothing.
- **every page is reachable** from the home page, transitively. An unreachable
  page is not an error the app reports; the words on it simply cannot be found
  by anyone, which looks like missing vocabulary rather than missing navigation.
"""

import argparse
import json
import sys
from pathlib import Path

VOCAB = Path("claudeBlast/Resources/vocabulary.json")
SCENES = Path("claudeBlast/Resources/scenes")


def check(path, vocab):
    errors, warnings = [], []
    scene = json.loads(Path(path).read_text())
    pages = {p["key"] for p in scene["pages"]}

    if scene.get("homePageKey") not in pages:
        errors.append(f"homePageKey {scene.get('homePageKey')!r} is not a page")

    edges = {p["key"]: set() for p in scene["pages"]}
    for page in scene["pages"]:
        key, placed = page["key"], []
        for tile in page["tiles"]:
            if "link" in tile:
                if tile["link"] not in vocab:
                    errors.append(f"{key}: link tile {tile['link']!r} is not in vocabulary.json "
                                  "— `link` is a TILE key, `to` is the page key")
                if tile["to"] not in pages:
                    errors.append(f"{key}: link to {tile['to']!r}, which is not a page")
                edges[key].add(tile["to"])
                placed.append(tile["link"])
            if "space" in tile:
                # A gap holds a cell and names no word, so there is nothing to
                # look up. Counted in the cell total, skipped by every check
                # that asks "is this a real word".
                count = tile["space"]
                placed.extend([None] * (int(count) if isinstance(count, int) else 1))
                continue
            for word in tile.get("keys", []):
                if word not in vocab:
                    errors.append(f"{key}: key {word!r} is not in vocabulary.json "
                                  "— this renders an empty cell")
                placed.append(word)
        placed = [w for w in placed if w is not None]
        dupes = sorted({w for w in placed if placed.count(w) > 1})
        if dupes:
            errors.append(f"{key}: duplicate tiles {dupes}")

    # Reachability from home.
    home = scene.get("homePageKey")
    if home in pages:
        seen, stack = {home}, [home]
        while stack:
            for nxt in edges.get(stack.pop(), ()):
                if nxt not in seen:
                    seen.add(nxt)
                    stack.append(nxt)
        for orphan in sorted(pages - seen):
            warnings.append(f"page {orphan!r} is not reachable from {home!r}")

    return errors, warnings


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("scene", nargs="?")
    ap.add_argument("--all", action="store_true", help="every scene in Resources/scenes")
    args = ap.parse_args()

    if not VOCAB.exists():
        sys.exit(f"run from the repo root — {VOCAB} not found")
    vocab = {t["key"] for t in json.loads(VOCAB.read_text())}

    targets = sorted(SCENES.glob("*.json")) if args.all else [Path(args.scene)]
    if not args.all and not args.scene:
        ap.error("pass a scene path or --all")

    failed = False
    for target in targets:
        errors, warnings = check(target, vocab)
        status = "FAIL" if errors else ("warn" if warnings else "ok")
        print(f"[{status}] {target}")
        for e in errors:
            print(f"   ERROR   {e}")
        for w in warnings:
            print(f"   warning {w}")
        failed |= bool(errors)

    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
