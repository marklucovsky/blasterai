#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Repair the two faults a hand-added `keyboard` page introduced. Idempotent.

    python3 tools/fix_keyboard_page.py

1. `{"link": "keyboard", "to": "keyboard"}` named a tile key that is not in
   `vocabulary.json`. `link` is a TILE key and `to` is a PAGE key; they coincide
   for `people` and `places` only because those happen to be both. So `keyboard`
   is added as a real word — `object` / noun — and needs art like any other.

   This is the same fault that once broke bootstrap outright, which is why
   `check_scene.py` exists and why it catches it in a second now.

2. `when` appeared twice on the Time page: once at the front, added by hand, and
   once at the end, appended by tools/add_function_words.py. Two tiles for one
   word, and which wins depends on command order. The first occurrence is kept —
   a question word reads better leading the page than trailing it.
"""

import collections
import json
from pathlib import Path


def main():
    vp = Path("claudeBlast/Resources/vocabulary.json")
    pp = Path("claudeBlast/Resources/parts_of_speech.json")
    sp = Path("claudeBlast/Resources/scenes/core_first.json")
    for p in (vp, pp, sp):
        if not p.exists():
            raise SystemExit(f"run from the repo root — {p} not found")

    vocab = json.loads(vp.read_text())
    if not any(t["key"] == "keyboard" for t in vocab):
        vocab = sorted(vocab + [{"key": "keyboard", "wordClass": "object"}],
                       key=lambda t: t["key"])
        vp.write_text(json.dumps(vocab, indent=2) + "\n")
        print(f"vocabulary.json       + keyboard  -> {len(vocab)} tiles")

    pos = json.loads(pp.read_text(), object_pairs_hook=collections.OrderedDict)
    if "keyboard" not in pos["noun"]:
        pos["noun"] = sorted(set(pos["noun"] + ["keyboard"]))
        pp.write_text(json.dumps(pos, indent=2) + "\n")
        print("parts_of_speech.json  + keyboard  -> noun")

    scene = json.loads(sp.read_text(), object_pairs_hook=collections.OrderedDict)
    removed = 0
    for page in scene["pages"]:
        seen = set()
        for tile in page["tiles"]:
            if tile.get("link"):
                seen.add(tile["link"])
            keys = tile.get("keys")
            if not keys:
                continue
            kept = []
            for k in keys:
                if k in seen:
                    removed += 1
                else:
                    seen.add(k)
                    kept.append(k)
            tile["keys"] = kept
    if removed:
        sp.write_text(json.dumps(scene, indent=2) + "\n")
        print(f"core_first.json       - {removed} duplicate tile(s)")


if __name__ == "__main__":
    main()
