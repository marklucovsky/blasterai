#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Put Questions on the home page and move the category folders behind Groups.

    python3 tools/add_questions_groups.py

Idempotent.

WHY QUESTIONS GOES TOP-LEVEL
----------------------------
Both reference boards put it there — WordPower Basic 48 has a **QUESTIONS**
folder in its top row, Vocal Flair has **questions** as its first folder — and
ours had `what`/`where`/`who`/`why`/`when`/`how` two taps deep behind a folder
labelled *social*, which is not where an SLP or a child looks for them. It is
the first thing a reviewer familiar with either board will ask about.

WHY GROUPS PAYS FOR IT
----------------------
The home page is full at 60 cells, so Questions has to be bought. Both
references also show where the money is: each carries a single folder of
categories — **GROUPS** in WordPower, **categories** in Vocal Flair — where we
had hoisted four category folders onto the home page instead.

So `body_health`, `weather`, `colors_shapes` and the new `feelings` page move
behind one `groups` folder. Two home cells are freed and two are spent, leaving
the count unchanged at 60.

WHAT SPLITS OUT OF SOCIAL
-------------------------
`social` was `{"class": ["social", "feeling", "question"]}` — three categories
behind one door. It becomes `{"class": "social"}`, with `question` and `feeling`
each getting their own page. That is the change that makes Questions reachable
in one tap and Feelings findable at all.

LINK TILES
----------
`question` already exists as a vocabulary word with art in every set, so the
Questions folder costs no new artwork. `groups` and `feelings` do not exist and
are added here; their art is generated like any other object tile.

NOT DONE, AND WHY
-----------------
**Letters and numbers** are pack-only: `GlyphTile` renders them from keys like
`letter_a`, and none of the 37 are in `vocabulary.json`. Putting them behind
Groups would mean adding all 37 as vocabulary, and the `keyboard` placeholder
already covers that territory — it should be decided with the keyboard feature
rather than ahead of it.

**Small words** would be a page of function words, and ours are already on the
home page. The overflow that would justify a page — `because`, `but`, `if`,
`of` — is mostly vocabulary we do not have yet.
"""

import collections
import json
from pathlib import Path

VOCAB = Path("claudeBlast/Resources/vocabulary.json")
POS = Path("claudeBlast/Resources/parts_of_speech.json")
SCENE = Path("claudeBlast/Resources/scenes/core_first.json")
PROMPTS = Path("tools/prompts.json")

NEW_WORDS = [("groups", "object", "noun"), ("feelings", "object", "noun")]

PROMPT_TEXT = {
    # A folder of categories reads as an assortment of unlike things. Both
    # vendors draw it that way — WordPower a tree and a car, Vocal Flair hands
    # holding differently coloured balls — and not as a crowd of people, which
    # is what "groups" suggests in isolation and would collide with `people`.
    "groups": (
        "AAC pictogram: An assortment of four different everyday objects arranged "
        "together in a loose square group — a red apple, a yellow toy car, a green "
        "tree and a blue ball — all about the same size and clearly separate from "
        "each other, showing a collection of different kinds of things. Flat "
        "illustration, white background, single clear subject centered, bold "
        "saturated colors, no text, square."
    ),
    # Three faces differing only in the mouth, so the tile reads as "feelings"
    # rather than as any one feeling.
    "feelings": (
        "AAC pictogram: Three simple round cartoon faces side by side showing "
        "different feelings — the left one smiling happily, the middle one with a "
        "straight mouth looking neutral, the right one frowning sadly. All three "
        "faces are the same size and shape and differ only in the mouth and "
        "eyebrows. Flat illustration, white background, single clear subject "
        "centered, bold saturated colors, no text, square."
    ),
}

# Pages that move off home and behind Groups, with the tile key that opens each.
IN_GROUPS = [
    ("body_health", "body_health"),
    ("weather", "weather"),
    ("colors", "colors_shapes"),
    ("feelings", "feelings"),
]


def main():
    for p in (VOCAB, POS, SCENE, PROMPTS):
        if not p.exists():
            raise SystemExit(f"run from the repo root — {p} not found")

    vocab = json.loads(VOCAB.read_text())
    have = {t["key"] for t in vocab}
    add = [{"key": k, "wordClass": c} for k, c, _ in NEW_WORDS if k not in have]
    if add:
        vocab = sorted(vocab + add, key=lambda t: t["key"])
        VOCAB.write_text(json.dumps(vocab, indent=2) + "\n")
        print(f"vocabulary.json       +{len(add)}  -> {len(vocab)} tiles")

    pos = json.loads(POS.read_text(), object_pairs_hook=collections.OrderedDict)
    for key, _, part in NEW_WORDS:
        if key not in pos[part]:
            pos[part] = sorted(set(pos[part] + [key]))
    POS.write_text(json.dumps(pos, indent=2) + "\n")

    prompts = json.loads(PROMPTS.read_text())
    for key, text in PROMPT_TEXT.items():
        prompts.setdefault(key, text)
    PROMPTS.write_text(json.dumps(dict(sorted(prompts.items())), indent=2,
                                  ensure_ascii=False) + "\n")

    scene = json.loads(SCENE.read_text(), object_pairs_hook=collections.OrderedDict)
    pages = {p["key"]: p for p in scene["pages"]}

    # Social sheds the two categories that were hiding inside it.
    for tile in pages["social"]["tiles"]:
        if isinstance(tile.get("class"), list):
            tile["class"] = "social"

    def page(key, tiles):
        if key not in pages:
            scene["pages"].append(collections.OrderedDict([("key", key), ("tiles", tiles)]))
            print(f"+ page {key}")

    page("questions", [collections.OrderedDict([("class", "question")])])
    page("feelings", [collections.OrderedDict([("class", "feeling")])])
    page("groups", [collections.OrderedDict(
        [("link", tile), ("to", target), ("audible", False)])
        for tile, target in IN_GROUPS])

    # Weather was parented under `describe` when it came off the home page; its
    # home is Groups now, and two parents is one more than a page needs.
    describe = pages["describe"]
    describe["tiles"] = [t for t in describe["tiles"] if t.get("to") != "weather"]

    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])
    swap = {"body_health": ("question", "questions"), "colors": ("groups", "groups")}
    for tile in home["tiles"]:
        if tile.get("link") in swap:
            was = tile["link"]
            tile["link"], tile["to"] = swap[was]
            print(f"home: {was} -> {tile['link']} (opens {tile['to']})")

    SCENE.write_text(json.dumps(scene, indent=2) + "\n")

    links = sum(1 for t in home["tiles"] if t.get("link"))
    words = sum(len(t.get("keys", [])) for t in home["tiles"])
    print(f"\nhome: {links} links + {words} words + Home = {links + words + 1} of 60")


if __name__ == "__main__":
    main()
