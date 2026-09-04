#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Diff shipped tile art against the words that can reference it.

Two failure modes, both silent:

  * **art with no word** — a `.heic` no vocabulary key, pack word, or scene can
    ever name. It ships, adds bytes, and nothing renders it. `p3d_bassketball`
    (a corrected vocabulary typo whose art was never removed) is why this exists.
  * **words with no art** — a word that renders as a placeholder in at least one
    shipped set. Worse than the first case, because it is visible to a child.

Run from the repository root:

    python3 tools/audit_art_coverage.py

Exits non-zero if either list is non-empty, so it can gate a build if we ever
want it to.
"""

import json
import os
import sys

RESOURCES = "claudeBlast/Resources"
ART = "claudeBlast/TileImageSets"


def known_words() -> set[str]:
    """Every art name a board can reference.

    Resolved through `bundleImage`, never the word's own key — the same rule
    `BoardPDFRenderer` and `TileImageView` follow. A pronoun's picture is the
    same picture: `him` renders `he`, `us` renders `we`. Comparing on `key`
    reports those as missing art when the art is there under another name.
    """
    with open(f"{RESOURCES}/vocabulary.json") as f:
        keys = {tile.get("bundleImage") or tile["key"] for tile in json.load(f)}
    for name in os.listdir(RESOURCES):
        if name.startswith("pack_") and name.endswith(".json"):
            with open(f"{RESOURCES}/{name}") as f:
                keys |= {
                    word.get("bundleImage") or word["key"]
                    for word in json.load(f)["words"]
                }
    return keys


def art_keys() -> set[str]:
    """Word keys with art, from `<set>_<key>.heic`. Pack covers are not words."""
    keys = set()
    for name in os.listdir(ART):
        if not name.endswith(".heic"):
            continue
        key = name[: -len(".heic")].partition("_")[2]
        if not key.startswith("packcover_"):
            keys.add(key)
    return keys


def main() -> int:
    words, art = known_words(), art_keys()
    orphaned, missing = sorted(art - words), sorted(words - art)

    print(f"words: {len(words)}   art keys: {len(art)}")
    print(f"art with no word ({len(orphaned)}): {orphaned or 'none'}")
    print(f"words with no art ({len(missing)}): {missing or 'none'}")
    return 1 if orphaned or missing else 0


if __name__ == "__main__":
    sys.exit(main())
