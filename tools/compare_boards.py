#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Compare our home page against the two reference boards, word by word.

    python3 tools/compare_boards.py --obz /path/to/vocal-flair-40.obz

WHAT THIS ANSWERS
-----------------
Not "how many words do we have" — that question has never been the problem. The
question is **which words a child can reach without navigating**, because the
home page is the only surface available mid-sentence. A word one tap away on a
category page is not available to a child assembling an utterance; it is
available to a caregiver who already knows where it lives.

So everything here is measured on the home page, and every difference falls into
one of three kinds:

  MISSING     on a reference board, absent from our vocabulary entirely.
              Needs a word and art before it can be placed anywhere.

  BURIED      on a reference board, in our vocabulary, not on our home page.
              Costs nothing but a decision: it already exists and is already
              drawn. These are the cheapest wins and the easiest to overlook,
              because a vocabulary diff reports them as present.

  EXTRA       on our home page and on neither reference. Not automatically
              wrong — we are not copying either board — but every one of them
              is occupying a cell that something in MISSING or BURIED cannot
              have, so each should be a choice rather than an accident.

THE TWO REFERENCES ARE NOT EQUAL
--------------------------------
**WordPower Basic 48** is the vocabulary on the device of the child this project
is built for, from the vendor with the largest installed base in this space. Its
choices reflect a great deal of clinical experience and it is what her SLP is
fluent in. Where we differ from it, we should be able to say why.

**Vocal Flair 40** is a published CC BY example board from OpenAAC, and useful
as a second opinion — but it is an *adult* system: its wider vocabulary includes
Work, Jobs, News and Organs. Agreement between the two references is a much
stronger signal than either alone, so the report calls that out separately.
"""

import argparse
import json
import re
import sys
import zipfile
from pathlib import Path

VOCAB = Path("claudeBlast/Resources/vocabulary.json")
SCENE = Path("claudeBlast/Resources/scenes/core_first.json")
AUBREY = Path("tools/reference_boards/aubrey_home.txt")

# Utility cells, not vocabulary: a keyboard, a clear key, punctuation, a link
# to more words. Excluded so they are not reported as words we are missing.
NOT_VOCABULARY = {"clear", "period", "abc123", "extrawords"}


def our_home():
    scene = json.loads(SCENE.read_text())
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])
    words, links = [], []
    for tile in home["tiles"]:
        if tile.get("link"):
            links.append(tile["link"])
            # An audible link speaks as well as navigating — `eat` says "eat"
            # and opens the food page. Counting it only as a link reported two
            # words as missing that a child can already tap, which is exactly
            # the kind of false finding that wastes a review.
            if tile.get("audible"):
                words.append(tile["link"])
        words.extend(tile.get("keys", []))
    return set(words), set(links)


def aubrey_home():
    words, links = set(), set()
    for line in AUBREY.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        for cell in line.split("|"):
            cell = cell.strip()
            if not cell:
                continue
            (links if cell.isupper() else words).add(cell.lower())
    return words - NOT_VOCABULARY, links


def vocal_flair_home(obz_path):
    norm = lambda s: re.sub(r"[^a-z0-9]+", "_", (s or "").strip().lower()).strip("_")
    z = zipfile.ZipFile(obz_path)
    manifest = json.loads(z.read("manifest.json"))
    board = json.loads(z.read(manifest["root"]))
    words, links = set(), set()
    for btn in board.get("buttons", []):
        key = norm(btn.get("label"))
        if not key:
            continue
        (links if btn.get("load_board") else words).add(key)
    return words - NOT_VOCABULARY, links


def show(title, items, vocab, note=""):
    print(f"\n{title}  ({len(items)})")
    if note:
        print(f"  {note}")
    if not items:
        print("  —")
        return
    width = max(len(w) for w in items) + 2
    for w in sorted(items):
        mark = "" if w in vocab else "   ** not in our vocabulary at all"
        print(f"  {w:{width}}{mark}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--obz", type=Path, help="vocal-flair-40.obz, for the second reference")
    args = ap.parse_args()

    if not VOCAB.exists():
        sys.exit(f"run from the repo root — {VOCAB} not found")
    vocab = {t["key"] for t in json.loads(VOCAB.read_text())}

    ours, our_links = our_home()
    theirs, their_links = aubrey_home()
    vf, vf_links = (vocal_flair_home(args.obz) if args.obz else (set(), set()))

    print("=" * 68)
    print("HOME PAGE COMPARISON — what a child can reach without navigating")
    print("=" * 68)
    print(f"  ours (core_first)      {len(ours):3d} words + {len(our_links):2d} links")
    print(f"  WordPower Basic 48     {len(theirs):3d} words + {len(their_links):2d} links")
    if args.obz:
        print(f"  Vocal Flair 40         {len(vf):3d} words + {len(vf_links):2d} links")

    refs = theirs | vf
    both_refs = theirs & vf if args.obz else set()

    if both_refs:
        agreed = both_refs - ours
        show("ON BOTH REFERENCE BOARDS, NOT ON OURS", agreed, vocab,
             "The strongest signal in this report: two independently designed "
             "boards put these\n  on the home page and we did not.")

    show("ON WORDPOWER, NOT ON OURS", theirs - ours - both_refs, vocab)
    if args.obz:
        show("ON VOCAL FLAIR, NOT ON OURS", vf - ours - both_refs, vocab)

    buried = {w for w in (refs - ours) if w in vocab}
    show("BURIED — we have the word and the art, it is just not on home", buried, vocab,
         "Cheapest to fix: no new vocabulary, no new art, only a placement decision.")

    show("EXTRA — on our home page, on neither reference", ours - refs, vocab,
         "Not wrong by itself. Each one holds a cell that something above cannot.")

    print(f"\n{'=' * 68}")
    print(f"  agreement with WordPower: {len(ours & theirs)}/{len(theirs)} of its words")
    if args.obz:
        print(f"  agreement with Vocal Flair: {len(ours & vf)}/{len(vf)} of its words")
    # Cells, not words plus links: an audible link is ONE tile that does both,
    # so adding the two totals counts `eat` and `play` twice.
    print(f"  cells in use: {len(ours | our_links)} + Home")


if __name__ == "__main__":
    main()
