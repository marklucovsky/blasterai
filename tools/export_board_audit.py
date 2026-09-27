#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Export the board comparison as CSV, for reading in a spreadsheet.

    python3 tools/export_board_audit.py --obz /path/to/vocal-flair-40.obz

Writes into build/:

  audit_home_pages.csv    one row per word on any of the three HOME pages
  audit_core_gaps.csv     core words the references carry that we do not have
  audit_summary.csv       the counts, for the top of a sheet

WHY TWO DIFFERENT QUESTIONS
---------------------------
**The home page** is the only surface available mid-sentence, so which words sit
on it is a different question from which words exist. A word on a category page
is reachable by a caregiver who knows where it lives and effectively absent to a
child assembling an utterance. `audit_home_pages.csv` is that comparison, and
every row carries a `group` column — common / ours_only / theirs_only — so a
spreadsheet can pivot on it without anyone re-deriving the sets.

**The core gap** is the other question: words the reference systems treat as
core vocabulary that our 535-word list does not contain at all. Those need a
word, a part of speech and art before any placement decision can even be made,
so they are a different kind of work and get their own file.

WHAT COUNTS AS "CORE" HERE
--------------------------
Stated because it is a judgement and someone will want to argue with it: the
core set is the two reference HOME pages plus Vocal Flair's **Small Words**
page. Home pages are core by construction — that is what a home page is for —
and Small Words is that system's own name for its function-word page, which is
precisely the category we were found thin in.

Deliberately excluded: the rest of Vocal Flair's 96 boards. That system is built
for adults and its wider vocabulary runs to Work, Jobs, News and Organs. Mining
it for "missing" words would produce a long list that is mostly irrelevant to a
child and would bury the handful that matter.
"""

import argparse
import csv
import json
import re
import sys
import zipfile
from pathlib import Path

VOCAB = Path("claudeBlast/Resources/vocabulary.json")
SCENE = Path("claudeBlast/Resources/scenes/core_first.json")
AUBREY = Path("tools/reference_boards/aubrey_home.txt")
OUT = Path("build")

# Utility cells, not vocabulary: a keyboard, a clear key, punctuation, a link
# to more words. Excluded so they are never reported as words we lack.
NOT_VOCABULARY = {"clear", "period", "abc123", "extrawords", "extra_words"}

norm = lambda s: re.sub(r"[^a-z0-9]+", "_", (s or "").strip().lower()).strip("_")


def our_home():
    scene = json.loads(SCENE.read_text())
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])
    words = set()
    for tile in home["tiles"]:
        # An audible link speaks as well as navigating, so it is a word too.
        if tile.get("link") and tile.get("audible"):
            words.add(tile["link"])
        words.update(tile.get("keys", []))
    return words


def aubrey_home():
    words = set()
    for line in AUBREY.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        for cell in line.split("|"):
            cell = cell.strip()
            if cell and not cell.isupper():
                words.add(norm(cell))
    return words - NOT_VOCABULARY


def vocal_flair(obz_path):
    """(home page words, small-words page words)."""
    z = zipfile.ZipFile(obz_path)
    manifest = json.loads(z.read("manifest.json"))
    root = json.loads(z.read(manifest["root"]))
    home = {norm(b.get("label")) for b in root.get("buttons", [])
            if b.get("label") and not b.get("load_board")}

    small = set()
    for path in manifest["paths"]["boards"].values():
        board = json.loads(z.read(path))
        if "small words" in (board.get("name") or "").lower():
            small = {norm(b.get("label")) for b in board.get("buttons", [])
                     if b.get("label") and not b.get("load_board")}
            break
    return home - NOT_VOCABULARY, small - NOT_VOCABULARY


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--obz", type=Path, required=True)
    args = ap.parse_args()

    if not VOCAB.exists():
        sys.exit(f"run from the repo root — {VOCAB} not found")
    vocab = {t["key"]: t["wordClass"] for t in json.loads(VOCAB.read_text())}

    ours = our_home()
    wp = aubrey_home()
    vf_home, vf_small = vocal_flair(args.obz)
    OUT.mkdir(parents=True, exist_ok=True)

    # ---- home page comparison, ONE COLUMN PER LIST -----------------------
    #
    # Column-per-category, not row-per-word. A row-per-word sheet is the
    # natural shape for a program and the wrong shape for a reader: answering
    # "what is only on ours?" means filtering, and comparing two of those
    # answers means filtering twice and remembering the first. Side-by-side
    # columns put every list in view at once, which is the actual question.
    columns = {
        "common_all_three": sorted(ours & wp & vf_home),
        "ours_only": sorted(ours - wp - vf_home),
        "both_refs_not_ours": sorted((wp & vf_home) - ours),
        "wordpower_only": sorted(wp - ours - vf_home),
        "vocal_flair_only": sorted(vf_home - ours - wp),
    }

    p = OUT / "audit_home_pages.csv"
    with p.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(list(columns))
        # Second row is the count, so the header block reads as a summary
        # before the lists begin.
        writer.writerow([len(v) for v in columns.values()])
        writer.writerow([])
        for i in range(max(len(v) for v in columns.values())):
            writer.writerow([v[i] if i < len(v) else "" for v in columns.values()])
    print(f"wrote {p}")
    for name, words in columns.items():
        print(f"  {len(words):3d}  {name}")

    # ---- core gaps -------------------------------------------------------
    core = (wp | vf_home | vf_small) - NOT_VOCABULARY
    gaps = sorted(w for w in core if w not in vocab)

    # Also columns, and split by where the word came from — because the source
    # is what decides whether it is worth adding. A word both references carry
    # is a different proposition from one that appears only on an adult
    # system's function-word page.
    gap_columns = {
        "on_two_or_more_sources": sorted(
            w for w in gaps if sum([w in wp, w in vf_home, w in vf_small]) >= 2),
        "wordpower_home_only": sorted(
            w for w in gaps if w in wp and w not in vf_home and w not in vf_small),
        "vocal_flair_home_only": sorted(
            w for w in gaps if w in vf_home and w not in wp and w not in vf_small),
        "vocal_flair_small_words_only": sorted(
            w for w in gaps if w in vf_small and w not in wp and w not in vf_home),
    }

    p = OUT / "audit_core_gaps.csv"
    with p.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(list(gap_columns))
        writer.writerow([len(v) for v in gap_columns.values()])
        writer.writerow([])
        for i in range(max(len(v) for v in gap_columns.values())):
            writer.writerow([v[i] if i < len(v) else "" for v in gap_columns.values()])
    print(f"wrote {p}  ({len(gaps)} words missing from our vocabulary)")
    for name, words in gap_columns.items():
        print(f"  {len(words):3d}  {name}")

    # ---- summary ---------------------------------------------------------
    counts = {
        "our home page words": len(ours),
        "WordPower Basic 48 home words": len(wp),
        "Vocal Flair 40 home words": len(vf_home),
        "common to all three": len(ours & wp & vf_home),
        "unique to ours": len(ours - wp - vf_home),
        "on both references, not ours": len((wp & vf_home) - ours),
        "on exactly one reference, not ours": len((wp ^ vf_home) - ours),
        "reference core words missing from our vocabulary": len(gaps),
    }
    p = OUT / "audit_summary.csv"
    with p.open("w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["measure", "count"])
        for k, v in counts.items():
            writer.writerow([k, v])
    print(f"wrote {p}\n")
    for k, v in counts.items():
        print(f"  {v:4d}  {k}")


if __name__ == "__main__":
    main()
