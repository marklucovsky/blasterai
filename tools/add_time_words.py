#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""One-shot: add the Time vocabulary, the Time page, and its home-page link.

    python3 tools/add_time_words.py

Idempotent — safe to re-run; it adds nothing that is already present.

WHY THIS RUNS BEFORE THE ART EXISTS
-----------------------------------
Every one of these words will render as the missing-art placeholder
(`TileImageView.missingTilePlaceholder` — the word-class colour, the first
letter, and a dot) until art is generated. That is deliberate. The page shape,
the word choice and the home-page cell budget are worth reviewing on a device
now, and none of them depend on the pictures.

WHY `time_when` AND NOT `time`
------------------------------
The page key and the link tile key are different namespaces, but a person
reading the JSON cannot tell that at a glance, and the bug that broke bootstrap
came from exactly that confusion. `time` is the *word* on the home page; the
page it opens is `time_when`. Naming them differently makes the two roles
visible in the file.

WORD CLASS vs PART OF SPEECH
----------------------------
Both are set for every word, because they do different jobs and the fallback is
wrong for this vocabulary. `wordClass` decides which page a word can be pulled
onto by a `class` selector. `partOfSpeech` decides colour. Left to the class
default, `before` would inherit `core` and draw as a function word (correct by
luck) while `now` would inherit `describe` and draw as an adjective (correct),
but `morning` filed under `describe` would draw blue rather than orange. So
each is stated rather than derived.

There is no `adverb` case in `PartOfSpeech`. The codebase files adverbs under
`describe` -> adjective, which is why `now`, `later` and `today` are adjectives
here. Adding a real `adverb` case is a separate, additive decision.
"""

import collections
import json
from pathlib import Path

# (key, wordClass, partOfSpeech)
NEW = [
    ("now", "describe", "adjective"), ("later", "describe", "adjective"),
    ("soon", "describe", "adjective"), ("today", "describe", "adjective"),
    ("tomorrow", "describe", "adjective"), ("yesterday", "describe", "adjective"),
    ("tonight", "describe", "adjective"), ("morning", "object", "noun"),
    ("afternoon", "object", "noun"), ("night", "object", "noun"),
    ("day", "object", "noun"), ("before", "core", "preposition"),
    ("after", "core", "preposition"), ("first", "describe", "adjective"),
    ("next", "describe", "adjective"), ("last", "describe", "adjective"),
    ("time", "object", "noun"), ("week", "object", "noun"),
    ("weekend", "object", "noun"), ("always", "describe", "adjective"),
    ("never", "describe", "adjective"), ("sometimes", "describe", "adjective"),
]

PAGE_KEY = "time_when"
# Clusters in reading order, mirroring the home page's discipline: contiguous
# groups a person can scan, rather than one undifferentiated block.
PAGE_CLUSTERS = [
    ["now", "later", "soon", "today", "tomorrow", "yesterday", "tonight"],
    ["morning", "afternoon", "night", "day"],
    ["before", "after", "first", "next", "last"],
    ["time", "week", "weekend"],
    ["always", "never", "sometimes"],
    ["wait", "again"],   # already in the vocabulary, placed here explicitly
]


def main():
    vocab_path = Path("claudeBlast/Resources/vocabulary.json")
    pos_path = Path("claudeBlast/Resources/parts_of_speech.json")
    scene_path = Path("claudeBlast/Resources/scenes/core_first.json")
    for p in (vocab_path, pos_path, scene_path):
        if not p.exists():
            raise SystemExit(f"run from the repo root — {p} not found")

    vocab = json.loads(vocab_path.read_text())
    present = {t["key"] for t in vocab}
    added = [{"key": k, "wordClass": c} for k, c, _ in NEW if k not in present]
    vocab = sorted(vocab + added, key=lambda t: t["key"])
    vocab_path.write_text(json.dumps(vocab, indent=2) + "\n")
    print(f"vocabulary.json      +{len(added):2d}  -> {len(vocab)} tiles")

    pos = json.loads(pos_path.read_text(), object_pairs_hook=collections.OrderedDict)
    n = sum(1 for k, _, p in NEW if k not in pos[p])
    for key, _, part in NEW:
        if key not in pos[part]:
            pos[part].append(key)
    for part in pos:
        pos[part] = sorted(set(pos[part]))
    pos_path.write_text(json.dumps(pos, indent=2) + "\n")
    print(f"parts_of_speech.json +{n:2d}")

    scene = json.loads(scene_path.read_text(), object_pairs_hook=collections.OrderedDict)
    if not any(p["key"] == PAGE_KEY for p in scene["pages"]):
        scene["pages"].append(collections.OrderedDict([
            ("key", PAGE_KEY),
            ("tiles", [collections.OrderedDict([("keys", c)]) for c in PAGE_CLUSTERS]),
        ]))
        print(f"{PAGE_KEY} page       +{sum(len(c) for c in PAGE_CLUSTERS):2d} words")

    for page in scene["pages"]:
        if page["key"] != scene["homePageKey"]:
            continue
        if any(t.get("to") == PAGE_KEY for t in page["tiles"]):
            continue
        # Keep the link run contiguous — insert after the last existing link.
        last_link = max(i for i, t in enumerate(page["tiles"]) if t.get("link"))
        page["tiles"].insert(last_link + 1, collections.OrderedDict(
            [("link", "time"), ("to", PAGE_KEY), ("audible", False)]))
        print('home                 +1  link tile "time" -> ' + PAGE_KEY)

    scene_path.write_text(json.dumps(scene, indent=2) + "\n")

    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])
    links = sum(1 for t in home["tiles"] if t.get("link"))
    words = sum(len(t.get("keys", [])) for t in home["tiles"])
    print(f"\nhome: {links} links + {words} words = {links + words} content cells "
          f"(+Home = {links + words + 1} of 60)")


if __name__ == "__main__":
    main()
