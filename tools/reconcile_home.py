#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Reconcile the home page against WordPower Basic 48. Idempotent.

    python3 tools/reconcile_home.py

The audit put our home page beside the board the child actually uses, and this
acts on it. Every change is a swap, because the page is full: 60 cells on an
11" iPad at the default density, one of which is Home.

ADDED
-----
he, she      Pronouns, and the gap that mattered most. WordPower carries both
             and makes the case for them directly; a board with `i` and `you`
             and no third person can talk about the people in the room but not
             about anyone who is not.
can          On BOTH reference boards and not on ours — the single strongest
             signal the audit produced. Already drawn, already in the
             vocabulary; it was only ever a placement.
finish       Kept alongside `all_done` rather than instead of it. They are not
             synonyms on a child's board: `all_done` ends a activity the child
             is in, `finish` asks for one to be completed.
listen, work  From WordPower's home page, in place of two of ours.

REMOVED
-------
read  -> listen   Both ours-only. `listen` is the more useful of the pair for a
                  child directing an adult's attention.
turn  -> work     Same trade. `turn` is ambiguous without context (take a turn,
                  turn around, turn it on); `work` is not.
take, at          Cut to pay for `he`/`she`. Both were on neither reference
                  home page. Neither leaves the vocabulary — they remain
                  available to any scene built from it.

`can` also gains a part-of-speech entry. It had none, so it fell back to its
word class (`core`) and drew as a function word. It is a modal verb and belongs
in the green cluster with the other verbs.
"""

import collections
import json
from pathlib import Path

ADD_PRONOUNS = ["he", "she"]
ADD_VERBS = ["can", "finish", "listen", "work"]
REMOVE = ["read", "turn", "take", "at"]


def main():
    vocab_path = Path("claudeBlast/Resources/vocabulary.json")
    pos_path = Path("claudeBlast/Resources/parts_of_speech.json")
    scene_path = Path("claudeBlast/Resources/scenes/core_first.json")
    for p in (vocab_path, pos_path, scene_path):
        if not p.exists():
            raise SystemExit(f"run from the repo root — {p} not found")

    vocab = {t["key"] for t in json.loads(vocab_path.read_text())}
    for w in ADD_PRONOUNS + ADD_VERBS:
        if w not in vocab:
            raise SystemExit(f"{w!r} is not in vocabulary.json — nothing to place")

    # `can` is a modal verb; without an entry it inherits its word class.
    pos = json.loads(pos_path.read_text(), object_pairs_hook=collections.OrderedDict)
    if "can" not in pos["verb"]:
        pos["verb"] = sorted(set(pos["verb"] + ["can"]))
        pos_path.write_text(json.dumps(pos, indent=2) + "\n")
        print("parts_of_speech.json  + can -> verb")

    scene = json.loads(scene_path.read_text(), object_pairs_hook=collections.OrderedDict)
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])

    for tile in home["tiles"]:
        keys = tile.get("keys")
        if not keys:
            continue
        for w in REMOVE:
            if w in keys:
                keys.remove(w)
        # Clusters are identified by a word that never moves out of them.
        if "you" in keys:
            for w in ADD_PRONOUNS:
                if w not in keys:
                    keys.append(w)
        elif "want" in keys:
            for w in ADD_VERBS:
                if w not in keys:
                    keys.append(w)

    scene_path.write_text(json.dumps(scene, indent=2) + "\n")

    links = sum(1 for t in home["tiles"] if t.get("link"))
    words = sum(len(t.get("keys", [])) for t in home["tiles"])
    print(f"\nhome: {links} links + {words} words = {links + words} content cells "
          f"(+Home = {links + words + 1} of 60)")
    for tile in home["tiles"]:
        if tile.get("keys"):
            print(f"  {' '.join(tile['keys'])}")


if __name__ == "__main__":
    main()
