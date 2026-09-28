#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Print any page of a scene as the grid it will actually render.

    python3 tools/show_page_grid.py                      # the home page
    python3 tools/show_page_grid.py --page actions       # a leaf page
    python3 tools/show_page_grid.py --list               # what pages exist
    python3 tools/show_page_grid.py --page food --pos    # with parts of speech

Was `show_home_grid.py`, which only ever knew about the home page.

FOR LAYOUT WORK, WHICH THE JSON IS BAD AT
-----------------------------------------
A page is stored as a flat list of build commands, so the file says nothing
about where a row ends. Reordering words in it is done blind: you can move a
word three places and not discover until the app launches that it crossed a row
boundary and now sits under a different column.

WHY LEAF PAGES NEEDED THIS TOO
------------------------------
Brandi, reviewing the board: *"we want to think about the order of words in each
part of speech: touch chat orders them by alpha order. Do we want them organized
in a certain way?"*

Ours are not even alphabetical — a `class` selector emits vocabulary-file order,
which is alphabetical only because `vocabulary.json` happens to be sorted. Either
way it is an accident rather than a decision, and on a 108-word page like
`actions` the difference between an accident and a decision is most of the value
of the page. This makes the accident visible so it can be argued with.

**A hand-placed prefix works**, which is what makes iterating cheap:

    {"keys": ["go", "come", "want", "help"]},
    {"class": "actions"}

Both commands skip a key that is already on the page (`SceneMaterializer`
dedupes on every command), so the named words take the first cells in the order
given and the class fills in behind them. No exclude list to maintain, and a
word promoted to the front does not have to be removed from anywhere.

PAGING
------
Home occupies cell 0 of **every** chunk — it is an invariant position, which is
motor planning — so a page holds `cols * rows - 1` words per chunk and the app
pages through the rest. That is why a long page is shown here in chunks rather
than as one tall grid: the chunk boundary is where a column relationship breaks.

WHY 12 COLUMNS
--------------
An 11" iPad Pro at the default density gives **12 x 5 = 60** cells, and since the
large-iPad tier was added (`GridLayoutCalculator.iPadLargeBaseSize`) a 13" gives
the same 12 columns rather than 14. iPad mini and iPhone reflow to their own
column counts and are deliberately not what this optimises for — tile position is
motor planning, and it can only be held stable across the sizes the board is
actually used on.
"""

import argparse
import json
from pathlib import Path

SCENES = Path("claudeBlast/Resources/scenes")
VOCAB = Path("claudeBlast/Resources/vocabulary.json")
POS = Path("claudeBlast/Resources/parts_of_speech.json")


def expand(page, vocab_by_class, vocab_order):
    """The ordered cells a page produces.

    A trimmed-down `SceneMaterializer` — enough to lay a page out, deliberately
    not enough to build one. The dedupe on every command is the part that
    matters here, because it is what makes a hand-placed prefix work.
    """
    cells = []
    seen = set()

    def add(key, label):
        if key in seen:
            return
        seen.add(key)
        cells.append(label)

    for cmd in page["tiles"]:
        if "class" in cmd:
            classes = cmd["class"]
            if isinstance(classes, str):
                classes = [classes]
            exclude = set(cmd.get("exclude", []))
            matched = [k for k in vocab_order
                       if vocab_by_class.get(k) in classes and k not in exclude]
            if cmd.get("orderBy") == "name":
                matched.sort()
            if cmd.get("limit"):
                matched = matched[:cmd["limit"]]
            for key in matched:
                add(key, key)
        elif "keys" in cmd:
            for key in cmd["keys"]:
                add(key, key)
        elif "link" in cmd:
            add(cmd["link"], f"→{cmd['link']}")
        elif "remove" in cmd:
            key = cmd["remove"]
            if key in seen:
                seen.discard(key)
                for label in (key, f"→{key}"):
                    if label in cells:
                        cells.remove(label)
        elif "space" in cmd:
            count = cmd["space"]
            cells.extend(["·"] * (int(count) if isinstance(count, int) else 1))
    return cells


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--scene", default="core_first")
    ap.add_argument("--page", default=None,
                    help="page key; defaults to the scene's home page")
    ap.add_argument("--list", action="store_true", help="list the scene's pages")
    ap.add_argument("--pos", action="store_true",
                    help="annotate each word with its part of speech")
    ap.add_argument("--cols", type=int, default=12)
    ap.add_argument("--rows", type=int, default=5)
    args = ap.parse_args()

    path = SCENES / f"{args.scene}.json"
    if not path.exists():
        raise SystemExit(f"no scene at {path}")
    scene = json.loads(path.read_text())
    vocab = json.loads(VOCAB.read_text())
    vocab_by_class = {t["key"]: t["wordClass"] for t in vocab}
    vocab_order = [t["key"] for t in vocab]

    if args.list:
        print(f"{scene['name']}")
        for page in scene["pages"]:
            cells = expand(page, vocab_by_class, vocab_order)
            home = "  (home)" if page["key"] == scene["homePageKey"] else ""
            print(f"  {page['key']:18} {len(cells):4} cells{home}")
        return

    key = args.page or scene["homePageKey"]
    page = next((p for p in scene["pages"] if p["key"] == key), None)
    if page is None:
        names = ", ".join(p["key"] for p in scene["pages"])
        raise SystemExit(f"no page '{key}' in {args.scene}. Pages: {names}")

    cells = expand(page, vocab_by_class, vocab_order)
    if args.pos:
        parts = {w: p for p, ws in json.loads(POS.read_text()).items() for w in ws}
        cells = [c if c.startswith(("→", "·"))
                 else f"{c}:{parts.get(c, '?')[:4]}" for c in cells]

    # Home takes cell 0 of every chunk, so each chunk carries one fewer word.
    per_chunk = args.cols * args.rows - 1
    chunks = [cells[i:i + per_chunk] for i in range(0, len(cells), per_chunk)] or [[]]

    print(f"{scene['name']} — page '{key}'")
    print(f"{args.cols} columns x {args.rows} rows, Home in cell 0 of every page")
    print(f"{len(cells)} tiles over {len(chunks)} page(s), {per_chunk} per page\n")

    width = max((len(c) for c in cells), default=6) + 1
    width = max(width, 8)
    for number, chunk in enumerate(chunks, 1):
        if len(chunks) > 1:
            print(f"  page {number} of {len(chunks)}")
        laid = ["⌂ HOME"] + chunk
        for r in range(args.rows):
            row = laid[r * args.cols:(r + 1) * args.cols]
            if not row:
                break
            print(f"  {r * args.cols:3d} │ " + "".join(c.ljust(width) for c in row))
        spare = args.cols * args.rows - len(laid)
        if spare:
            print(f"      {spare} spare cell(s) on this page")
        print()


if __name__ == "__main__":
    main()
