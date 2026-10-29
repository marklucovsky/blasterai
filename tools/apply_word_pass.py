#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Apply a word pass (tools/board_spec/word_pass_*.json) to BlasterAI 60.

Each entry names a page and the words it gains. For every word this adds:

- a `vocabulary.json` tile, if the key is new. Its wordClass is the most common
  class among the page's existing words, so a new animal is classed like the
  animals already there; an entry's `wordClass`, or `classOf` for one word,
  overrides it. Its label is written only when the key alone would not
  spell it (`cant` → "can't", `monday` → "Monday"). `imageOf` maps a key to an
  existing tile whose picture it borrows (`bundleImage`), the way an SLP reuses
  *new* for "This is new"; a folder's `image` does the same for its tile.
- a part of speech in `parts_of_speech.json`: the entry's `pos`, or `posOf` for
  that word. A key that already has one keeps it.
- a place in `tools/board_spec/blasterai60.json`: appended to the page's
  `words`. An entry with `folder` makes that page a new folder of `parent`.

It never removes or reorders anything. Then run build_core_board.py --write,
which lays the words out and reports any page that no longer fits.

    python3 tools/apply_word_pass.py tools/board_spec/word_pass_1.json
"""
import json
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "tools/board_spec/blasterai60.json"
VOCAB = ROOT / "claudeBlast/Resources/vocabulary.json"
POS = ROOT / "claudeBlast/Resources/parts_of_speech.json"
SCENE = ROOT / "claudeBlast/Resources/scenes/core_first.json"

# A page with no words of its own yet takes its class from its part of speech.
CLASS_FOR_POS = {"noun": "object", "verb": "actions", "adjective": "describe", "social": "social",
                 "interjection": "social", "question": "question", "determiner": "core",
                 "preposition": "core", "conjunction": "core", "negation": "core", "pronoun": "people"}


def flat(words):
    for w in words:
        if isinstance(w, list):
            yield from flat(w)
        else:
            yield w


def split(word):
    key, _, label = word.partition("|")
    return key, label


def strip_labels(words):
    return [strip_labels(w) if isinstance(w, list) else split(w)[0] for w in words]


def page_index(spec):
    """Every page the spec lays out, top-level and folder, by key."""
    found = {}

    def walk(parent_key, page):
        for f in page.get("folders", []):
            if "words" in f:
                found[f["page"]] = f
                walk(f["page"], f)

    for key, page in spec["pages"].items():
        found[key] = page
        walk(key, page)
    return found


def main():
    word_pass = json.loads(Path(sys.argv[1]).read_text())
    spec = json.loads(SPEC.read_text())
    vocab = json.loads(VOCAB.read_text())
    pos = json.loads(POS.read_text())
    scene = json.loads(SCENE.read_text())

    classes = {t["key"]: t["wordClass"] for t in vocab}
    has_pos = {k for ks in pos.values() if isinstance(ks, list) for k in ks}
    pages = page_index(spec)
    added_tiles, added_pos, placed = [], 0, 0

    for entry in word_pass["pages"]:
        key = entry["page"]
        if "folder" in entry:
            f = entry["folder"]
            parent = pages[f["parent"]]
            if key not in pages:
                folder = {"key": f["key"], "page": key, "words": []}
                parent.setdefault("folders", []).append(folder)
                pages[key] = folder
                tile = {"key": f["key"], "label": f["label"]}
                if "image" in f:
                    tile["bundleImage"] = f["image"]
                spec.setdefault("newTiles", []).append(tile)
        if key not in pages:
            sys.exit(f"{key}: not a page the spec lays out; adopt it into blasterai60.json first")
        page = pages[key]

        existing = [classes[w] for w in flat(page["words"]) if w in classes]
        page_class = entry.get("wordClass") or (Counter(existing).most_common(1)[0][0] if existing
                                                else CLASS_FOR_POS.get(entry["pos"], "object"))

        have = set(flat(page["words"]))
        for item in strip_labels(entry["words"]):
            new = [w for w in (item if isinstance(item, list) else [item]) if w not in have]
            if new:
                page["words"].append(new if isinstance(item, list) else new[0])
                have.update(new)
                placed += len(new)

        for word in flat(entry["words"]):
            k, label = split(word)
            if k not in classes:
                tile = {"key": k, "wordClass": entry.get("classOf", {}).get(k, page_class)}
                if label and label != k.rstrip("_").replace("_", " "):
                    tile["label"] = label
                if k in entry.get("imageOf", {}):
                    tile["bundleImage"] = entry["imageOf"][k]
                vocab.append(tile)
                classes[k] = tile["wordClass"]
                added_tiles.append(k)
            if k not in has_pos:
                p = entry.get("posOf", {}).get(k, entry["pos"])
                pos.setdefault(p, []).append(k)
                pos[p].sort()  # the index is kept alphabetical
                has_pos.add(k)
                added_pos += 1

    SPEC.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n")
    VOCAB.write_text(json.dumps(vocab, indent=2, ensure_ascii=False) + "\n")
    POS.write_text(json.dumps(pos, indent=2, ensure_ascii=False) + "\n")
    print(f"{len(added_tiles)} new tiles, {added_pos} parts of speech, {placed} placements")


if __name__ == "__main__":
    main()
