#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Add the five function words to the vocabulary and the home page. Idempotent.

    python3 tools/add_function_words.py

a / the / and / is / at were the words the board diff found missing against both
reference boards, and they are the ones that turn a row of tiles into a
sentence. Their art is drawn by tools/render_word_glyphs.py, not generated.

Also places `when` on the Time page. `when` is a question word and already
reachable through the Social page, but a child answering "when?" looks where the
time words are — and the commercial boards agree: WordPower Basic 48 puts TIME
in its top row of folders, and Vocal Flair has a Time page. The link tile on our
home page is `time`, matching the vendor convention, while `when` stays content.
"""

import collections
import json
from pathlib import Path

# (key, wordClass, partOfSpeech)
NEW = [
    ("a", "core", "determiner"),
    ("the", "core", "determiner"),
    ("and", "core", "conjunction"),
    ("is", "core", "verb"),
    ("at", "core", "preposition"),
]

HOME_ADDITIONS = {
    # cluster head -> words appended to it, so each stays one colour
    "grey": ["at", "a", "the", "and"],   # prepositions, determiners, conjunction
    "green": ["is"],                      # copula, with the verbs
}


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
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])

    # The grey cluster is the one holding `to`; the green one holds `want`.
    for tile in home["tiles"]:
        keys = tile.get("keys")
        if not keys:
            continue
        if "to" in keys:
            for w in HOME_ADDITIONS["grey"]:
                if w not in keys:
                    keys.append(w)
        elif "want" in keys:
            for w in HOME_ADDITIONS["green"]:
                if w not in keys:
                    keys.append(w)

    # `when` belongs on the Time page as content.
    for page in scene["pages"]:
        if page["key"] != "time_when":
            continue
        last = page["tiles"][-1]
        if "when" not in last.get("keys", []):
            last.setdefault("keys", []).append("when")

    scene_path.write_text(json.dumps(scene, indent=2) + "\n")

    links = sum(1 for t in home["tiles"] if t.get("link"))
    words = sum(len(t.get("keys", [])) for t in home["tiles"])
    print(f"\nhome: {links} links + {words} words = {links + words} content cells "
          f"(+Home = {links + words + 1} of 60)")


if __name__ == "__main__":
    main()
