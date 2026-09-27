#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Read structure and words out of an .obz. Never its art.

    Usage:
        python3 tools/obz_mine.py <file.obz> --tree
        python3 tools/obz_mine.py <file.obz> --board "Small Words"
        python3 tools/obz_mine.py <file.obz> --diff
        python3 tools/obz_mine.py <file.obz> --licenses
        python3 tools/obz_mine.py <file.obz> --scene out.json --boards root,Actions

THIS IS NOT AN IMPORTER
-----------------------
There is no OBF/OBZ import in the app and this tool does not move us toward one.
It is a reading tool: point it at a published board set, see how somebody else
organised a vocabulary, and diff their words against ours. What comes out is a
report for a human and, optionally, a scene *skeleton* that a human then edits.
Nothing it emits is meant to ship unreviewed.

The distinction matters because the two jobs have opposite standards. An importer
has to survive whatever a user feeds it. This has to be honest about one file at
a time, and is allowed to print "17 buttons had no grid position" instead of
guessing where they went.

WHY THE ART IS NOT TOUCHED
--------------------------
Not a simplification — a licensing requirement, and the reason is invisible from
the outside of the file.

An .obz carries a licence per *board* and a separate licence per *image*, and
they routinely disagree. Measured on `vocal-flair-40.obz` (OpenAAC, 2026-09-24):
all 96 boards are CC BY 4.0, which is why mining their structure is fine. But of
the images, **1,672 are CC BY-NC-SA by Sergio Palao** — ARASAAC, the art removed
from this project in July 2026 — and the rest span 300+ authors across CC BY-SA,
CC BY-NC, CC BY-ND and public domain.

NonCommercial and ShareAlike are both incompatible with shipping inside an
Apache-2.0 app. So a tool that reads `images/` would be a tool whose output can
never be distributed, and the board-level licence would tell you nothing about
it. `--licenses` prints both tables precisely so this is checked rather than
assumed on the next file.

THREE THINGS THE FORMAT DOES NOT PROMISE
----------------------------------------
Learned the hard way from a real file, and recorded here because every one of
them is a silent wrong answer rather than a crash:

1. **Boards are not under `boards/`.** Our own exporter writes them there, and
   it is tempting to read them back the same way. `vocal-flair-40.obz` puts every
   `.obf` at the zip root. `manifest.paths.boards` is the only reliable index —
   the directory layout is a convention, not a rule.

2. **A button is not a cell.** That file has 2,870 buttons and 2,414 grid
   positions. Buttons missing from `grid.order` are real, carry words, and are
   simply not placed. We report them; we never quietly append them, because
   where they were meant to go is unknowable and a guess corrupts the layout
   the tool exists to study.

3. **`background_color` encodes part of speech**, which is free classification
   data — but the palettes differ between systems. Vocal Flair uses yellow for
   people and orange for places; we use purple and blue. So colour is reported
   as a *hint to map*, never a value to copy.

LABEL NORMALISATION IS LOSSY ON PURPOSE
---------------------------------------
Their labels are display strings ("let's", "-er", "no- ?"); our keys are
lowercase identifiers. `normalize_key` collapses the former toward the latter so
a diff is possible at all, which means morphemes and punctuation-bearing entries
come out mangled (`-est` -> `est`). That is fine for "do we have this word", and
useless as a key to create. Anything the diff proposes gets read by a person
before it becomes vocabulary.
"""

import argparse
import collections
import json
import re
import sys
import zipfile
from pathlib import Path

VOCAB = Path("claudeBlast/Resources/vocabulary.json")


def normalize_key(label):
    """An OBF display label, collapsed toward our key convention. Lossy: see above."""
    return re.sub(r"[^a-z0-9]+", "_", (label or "").strip().lower()).strip("_")


class Obz:
    """One .obz, read as structure. `images/` is never opened."""

    def __init__(self, path):
        self.zip = zipfile.ZipFile(path)
        self.manifest = json.loads(self.zip.read("manifest.json"))
        # paths.boards, not a directory scan — see note 1 in the module docstring.
        self.board_paths = self.manifest.get("paths", {}).get("boards", {})
        self.root_path = self.manifest.get("root")
        self._cache = {}

    def board(self, path):
        if path not in self._cache:
            self._cache[path] = json.loads(self.zip.read(path))
        return self._cache[path]

    def boards(self):
        """(path, board) for every board the manifest indexes, root first."""
        seen = []
        if self.root_path:
            seen.append(self.root_path)
        for p in self.board_paths.values():
            if p not in seen:
                seen.append(p)
        return [(p, self.board(p)) for p in seen]

    def id_to_path(self):
        return {bid: p for bid, p in self.board_paths.items()}


def placed_cells(board):
    """Grid positions in reading order: (row, col, button_id or None)."""
    grid = board.get("grid", {})
    for r, row in enumerate(grid.get("order", [])):
        for c, bid in enumerate(row):
            yield r, c, bid


def buttons_by_id(board):
    return {b["id"]: b for b in board.get("buttons", [])}


def speaking(button):
    """A button that says something, as opposed to navigating."""
    return not button.get("load_board")


# --------------------------------------------------------------------------
# reports
# --------------------------------------------------------------------------

def cmd_tree(obz, args):
    by_id = obz.id_to_path()
    edges = collections.defaultdict(list)
    for path, board in obz.boards():
        for btn in board.get("buttons", []):
            target = btn.get("load_board") or {}
            tid = target.get("id")
            if tid and tid in by_id:
                edges[path].append((btn.get("label", "?"), by_id[tid]))

    printed = set()

    def walk(path, depth):
        board = obz.board(path)
        grid = board.get("grid", {})
        n_words = sum(1 for b in board.get("buttons", []) if speaking(b))
        mark = "" if path not in printed else "  (seen)"
        print(f"{'  ' * depth}{board.get('name', path)}"
              f"  [{grid.get('rows')}x{grid.get('columns')}, {n_words} words]{mark}")
        if path in printed:
            return
        printed.add(path)
        for label, target in edges.get(path, []):
            walk(target, depth + 1)

    if obz.root_path:
        walk(obz.root_path, 0)
    orphans = [p for p, _ in obz.boards() if p not in printed]
    if orphans:
        print(f"\n{len(orphans)} board(s) not reachable from root:")
        for p in orphans:
            print(f"  {obz.board(p).get('name', p)}")


def cmd_board(obz, args):
    needle = args.board.lower()
    hits = [(p, b) for p, b in obz.boards() if needle in (b.get("name") or "").lower()]
    if not hits:
        sys.exit(f"no board matching {args.board!r}")
    for path, board in hits:
        by_id = buttons_by_id(board)
        grid = board.get("grid", {})
        print(f"\n{board.get('name')}  ({grid.get('rows')}x{grid.get('columns')})\n")
        width = 13
        for row in grid.get("order", []):
            cells = []
            for bid in row:
                btn = by_id.get(bid)
                if not btn:
                    cells.append("·".center(width))
                    continue
                label = (btn.get("label") or "?")[: width - 2]
                cells.append((("→" + label) if not speaking(btn) else label).center(width))
            print("|".join(cells))

        laid = {bid for _, _, bid in placed_cells(board) if bid}
        stray = [b for b in board.get("buttons", []) if b["id"] not in laid]
        if stray:
            # Note 2: reported, never appended.
            print(f"\n  {len(stray)} button(s) with no grid position: "
                  + ", ".join((b.get("label") or "?") for b in stray))


def cmd_diff(obz, args):
    if not VOCAB.exists():
        sys.exit(f"run from the repo root — {VOCAB} not found")
    ours = {t["key"] for t in json.loads(VOCAB.read_text())}

    per_board = []
    everything = collections.Counter()
    for path, board in obz.boards():
        words = {normalize_key(b.get("label")) for b in board.get("buttons", []) if speaking(b)}
        words.discard("")
        everything.update(words)
        missing = sorted(words - ours)
        per_board.append((board.get("name", path), len(words), missing))

    theirs = set(everything)
    print(f"their unique words: {len(theirs)}")
    print(f"  we already have:  {len(theirs & ours)}")
    print(f"  we are missing:   {len(theirs - ours)}")
    print(f"  ours they lack:   {len(ours - theirs)}\n")

    if args.by_board:
        for name, total, missing in per_board:
            if missing:
                print(f"{name}  ({len(missing)}/{total} missing)")
                print(f"    {', '.join(missing)}")
    else:
        print("missing, most-used first (a word on many boards is load-bearing):")
        for word, n in everything.most_common():
            if word not in ours:
                print(f"  {n:3d}  {word}")


def cmd_licenses(obz, args):
    boards = collections.Counter()
    images = collections.Counter()
    for _, board in obz.boards():
        lic = board.get("license") or {}
        boards[(lic.get("type"), lic.get("author_name"))] += 1
        for img in board.get("images", []):
            ilic = img.get("license") or {}
            images[(ilic.get("type"), ilic.get("author_name"))] += 1

    print("BOARD licences (this is what governs structure + words):")
    for (kind, who), n in boards.most_common():
        print(f"  {n:5d}  {kind}  —  {who}")

    print("\nIMAGE licences (this is why we do not read images/):")
    for (kind, who), n in images.most_common(15):
        print(f"  {n:5d}  {kind}  —  {who}")
    if len(images) > 15:
        print(f"  ... and {len(images) - 15} more distinct image licence/author pairs")

    restrictive = sum(n for (kind, _), n in images.items()
                      if kind and re.search(r"NC|SA|ND", kind, re.I))
    total = sum(images.values())
    if total:
        print(f"\n  {restrictive} of {total} images carry NC, SA or ND terms "
              f"({100 * restrictive // total}%) — incompatible with shipping in an "
              "Apache-2.0 app.")


def cmd_scene(obz, args):
    """Emit a scene skeleton. A starting point for a human, not a finished scene."""
    ours = {t["key"] for t in json.loads(VOCAB.read_text())} if VOCAB.exists() else set()
    wanted = [s.strip().lower() for s in (args.boards or "").split(",") if s.strip()]

    chosen = []
    for path, board in obz.boards():
        name = (board.get("name") or "").lower()
        if not wanted or any(w in name or (w == "root" and path == obz.root_path) for w in wanted):
            chosen.append((path, board))
    if not chosen:
        sys.exit("no boards matched --boards")

    path_to_key = {p: normalize_key(b.get("name")) or f"page{i}"
                   for i, (p, b) in enumerate(chosen)}
    by_id = obz.id_to_path()

    pages, unknown = [], collections.Counter()
    for path, board in chosen:
        btns = buttons_by_id(board)
        tiles = []
        for _, _, bid in placed_cells(board):
            btn = btns.get(bid)
            if not btn:
                continue
            if not speaking(btn):
                target = by_id.get((btn.get("load_board") or {}).get("id"))
                if target in path_to_key:
                    tiles.append({"link": path_to_key[target], "to": path_to_key[target],
                                  "audible": False})
                continue
            key = normalize_key(btn.get("label"))
            if not key:
                continue
            if key not in ours:
                unknown[key] += 1
            tiles.append({"keys": [key], "audible": True,
                          "_colorHint": btn.get("background_color")})
        pages.append({"key": path_to_key[path], "tiles": tiles})

    scene = {
        "key": normalize_key(obz.board(obz.root_path).get("name")) if obz.root_path else "imported",
        "name": f"{obz.board(obz.root_path).get('name')} (structure only)" if obz.root_path else "Imported",
        "description": "Skeleton mined from an .obz. Review before use.",
        "homePageKey": path_to_key.get(obz.root_path, pages[0]["key"]),
        "isDefault": False,
        "_provenance": _provenance(obz),
        "pages": pages,
    }
    Path(args.scene).write_text(json.dumps(scene, indent=2) + "\n")
    print(f"wrote {args.scene}: {len(pages)} pages, "
          f"{sum(len(p['tiles']) for p in pages)} tiles")
    if unknown:
        print(f"\n{len(unknown)} word(s) not in our vocabulary — these need a decision "
              "(add, rename, or drop) before this scene means anything:")
        for key, n in unknown.most_common():
            print(f"  {n:3d}  {key}")
    print("\n_colorHint is their palette, not ours. Map it to wordClass; do not copy it.")


def _provenance(obz):
    """Attribution travels with anything mined. CC BY makes this a condition, not a courtesy."""
    root = obz.board(obz.root_path) if obz.root_path else {}
    lic = root.get("license") or {}
    return {
        "source": root.get("name"),
        "license": lic.get("type"),
        "author": lic.get("author_name"),
        "authorUrl": lic.get("author_url"),
        "note": "Structure and words only. No art was taken from this source.",
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("obz")
    ap.add_argument("--tree", action="store_true", help="board hierarchy from the root")
    ap.add_argument("--board", help="dump one board's grid, matched by name substring")
    ap.add_argument("--diff", action="store_true", help="their vocabulary against ours")
    ap.add_argument("--by-board", action="store_true", help="with --diff, group by board")
    ap.add_argument("--licenses", action="store_true", help="board and image licence tables")
    ap.add_argument("--scene", metavar="OUT.json", help="emit a scene skeleton")
    ap.add_argument("--boards", help="with --scene, comma-separated name substrings ('root' for the root board)")
    args = ap.parse_args()

    obz = Obz(args.obz)
    did = False
    for flag, fn in (("tree", cmd_tree), ("board", cmd_board), ("diff", cmd_diff),
                     ("licenses", cmd_licenses), ("scene", cmd_scene)):
        if getattr(args, flag):
            fn(obz, args)
            did = True
    if not did:
        ap.error("pick at least one of --tree / --board / --diff / --licenses / --scene")


if __name__ == "__main__":
    main()
