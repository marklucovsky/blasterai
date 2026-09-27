#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Validate a proposed board's words against the shipping vocabulary.

    Usage:
        python3 tools/check_board_words.py <proposal.json>

A board proposal is a design document before it is a scene: a list of clusters,
each an ordered list of words someone believes belongs on the home page. This
checks every one of them exists, reports the part of speech each will be drawn
in, and lists what would have to be created first.

WHY THIS IS NOT DONE BY HAND
----------------------------
A key that is not in `vocabulary.json` does not fail loudly. `BootstrapLoader`
resolves placements against tiles it has, and a placement naming a word that was
never created simply renders nothing — an empty cell in the middle of a board,
with no error anywhere. A proposal that invents `a`, `the` or `and` because they
are obviously words looks completely fine in a diff and ships a board with holes
in it.

So the rule is: a proposal names words, this says whether they exist, and
nothing becomes a scene until the missing ones have been created with art.
"""

import json
import sys
from pathlib import Path

VOCAB = Path("claudeBlast/Resources/vocabulary.json")
POS_TABLE = Path("claudeBlast/Resources/parts_of_speech.json")

# The colour a part of speech is drawn in — VocabularyClasses.fitzgerald().
# Several parts of speech share the function-word grey, which is why a cluster
# can mix them and still read as one block.
COLOUR = {
    "pronoun": "yellow", "verb": "green", "adjective": "light blue",
    "noun": "orange", "question": "purple", "negation": "red",
    "social": "pink", "interjection": "pink",
    "preposition": "grey", "determiner": "grey", "conjunction": "grey",
}


def part_of_speech_table():
    """word -> part of speech, from the bundled exact table.

    The class default in VocabularyClasses is a *fallback* for words the table
    does not know, and it is wrong for exactly the words a sentence-building
    home page is made of: prepositions filed under `describe`, pronouns filed
    under `people`. Reading the class would therefore report the wrong colour
    for every function word here, which is the one thing this check exists to
    get right.
    """
    table = json.loads(POS_TABLE.read_text())
    return {word: pos for pos, words in table.items() for word in words}


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    if not VOCAB.exists():
        sys.exit(f"run from the repo root — {VOCAB} not found")

    vocab = {t["key"]: t["wordClass"] for t in json.loads(VOCAB.read_text())}
    w2p = part_of_speech_table()
    proposal = json.loads(Path(sys.argv[1]).read_text())

    total, missing_all = 0, []
    for cluster in proposal["clusters"]:
        name, words = cluster["name"], cluster["words"]
        have = [w for w in words if w in vocab]
        missing = [w for w in words if w not in vocab]
        missing_all += missing
        total += len(words)

        print(f"\n{name}  ({len(have)}/{len(words)} exist)")
        parts = sorted({w2p.get(w, "?") for w in have})
        colours = sorted({COLOUR.get(w2p.get(w), "?") for w in have})
        print(f"  part of speech: {', '.join(parts) or '-'}")
        print(f"  colour:         {', '.join(colours) or '-'}")
        if len(colours) > 1:
            off = [f"{w}={COLOUR.get(w2p.get(w), '?')}" for w in have
                   if COLOUR.get(w2p.get(w)) != colours[0]]
            print(f"  ** MIXED COLOURS — will not read as one block: {', '.join(off)}")
        unknown = [w for w in have if w not in w2p]
        if unknown:
            print(f"  ** NO PART OF SPEECH: {', '.join(unknown)} — falls back to its "
                  "word class, which is wrong for function words")
        if missing:
            print(f"  MISSING:   {', '.join(missing)}")

    links = proposal.get("links", [])
    print(f"\n{'=' * 58}")
    print(f"{total} words + {len(links)} links = {total + len(links)} cells")
    if missing_all:
        print(f"\n{len(missing_all)} word(s) must be created before this ships:")
        print(f"  {', '.join(sorted(set(missing_all)))}")
        print("\nEach needs a vocabulary.json entry with a wordClass, and art in "
              "every shipped image set. Until then those cells render empty.")
    else:
        print("\nevery word exists — this proposal can become a scene as-is")


if __name__ == "__main__":
    main()
