#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Build BlasterAI 60's pages from its hierarchy spec, so cells are computed, not counted.

    python3 tools/build_core_board.py                 # report what would change
    python3 tools/build_core_board.py --write         # write core_first.json (+ vocab, parts of speech)
    python3 tools/build_core_board.py --check         # fail if the committed board != the spec
    python3 tools/build_core_board.py --html out.html # every page as a board, with art

Then `python3 tools/resolve_link_colors.py --write`: this tool writes "auto" on the
links it adds and leaves colour to the tool that owns it, and `--check` here ignores
`linkColor` for the same reason.

WHAT BRANDI ASKED FOR, AND WHAT THIS ENFORCES
---------------------------------------------
Brandi (2026-10-23): the board is too small, and growing it needs a hierarchy a
child can see and enter from any word. The spec, `tools/board_spec/blasterai60.json`,
says where every word lives. This tool turns it into pages with four rules that
are tedious and error-prone by hand:

1. **The system row.** Row 1 of every page is Home (drawn by the grid in cell 0)
   and the spec's `systemRow`, keyboard last, in r1c12. Avaz's bottom bar, on top.
   Pages in `systemRowExempt` don't get it yet: they would overflow one screen,
   and each leaves the list when it is split into folders.

2. **Doorways.** A word in `doorways` speaks AND opens a page, on every page it is
   on: *go* opens Places from Home, Actions, Moving and the I page alike. It is a
   property of the word, written onto every placement, and never on the page it
   opens (no *feel* → Feelings on Feelings).

3. **Folders in columns 11–12.** A page's folders take r2c12 down, then r2c11
   down, the leaf template's link slots (`page_templates.json`). The column
   belongs to the page that owns the folders, and only that page: it extends the
   path one level down, it is not a topic toolbar. A folder page does not repeat
   its siblings (Mark 2026-10-25: Describe › How much showing Size, Where… made
   deep, confusing chains). What a folder page keeps is **its own tile, in the
   cell its parent shows it in**: the app draws it as "you are here" (a striped
   ring and a red dot) and it does nothing when pressed, so a child who cannot
   read sees the tile they just pressed, where they pressed it. The rest of the
   column is empty unless the page has folders of its own, declared as
   `folders` inside the folder.

4. **Same word, same cell** (Avaz, Mark 2026-10-25: *teacher* sits in one cell on
   People and on School people). A word on a page and on one of its ancestors
   takes the ancestor's cell, nearest ancestor first. Only words in columns 1–10
   pin: a cell in the folder column is a folder on the page below. Up-front words
   on Actions take their Home cells, and Moving's take Actions'.

Everything else fills columns 1–10 row by row, in spec order.

PAGES THE SPEC DOES NOT OWN
---------------------------
Get the system row and one gap prepended, which moves the page down exactly one
row so every column it was laid out in survives, and their doorways made links.
Otherwise they are left as authored, class selectors and all. Re-running strips
what a previous run added before adding it again, so the tool is idempotent.

LAYING OUT A PAGE
-----------------
An entry in a page's `words` is a word or a **run**, a list kept side by side in
one row (`["fast", "slow"]`). A run that holds an inherited word grows out from
that word's cell. `at` places a run by hand (`{"r5c1": ["right", "okay_",
"wrong"]}`). Everything else takes the first free cells, row by row.

THE CHECKS
----------
`--check` fails on: a board that differs from the spec (colours aside), a page
over one screen, a doorway on its own target, an unknown key, a word that was on
the board and is now on no page, or a pinned word that could not take its cell.
"""
import argparse
import base64
import copy
import html
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = ROOT / "tools/board_spec/blasterai60.json"
SCENE = ROOT / "claudeBlast/Resources/scenes/core_first.json"
VOCAB = ROOT / "claudeBlast/Resources/vocabulary.json"
POS = ROOT / "claudeBlast/Resources/parts_of_speech.json"
ART = ROOT / "claudeBlast/TileImageSets"
THUMBS = ROOT / "tools/tile_sets/layout_thumbs_gi2"   # gitignored; shared with tools/eval/build_layouts.py

sys.path.insert(0, str(ROOT / "tools"))
from show_page_grid import expand  # noqa: E402

COLS, ROWS = 12, 5
CELLS = COLS * ROWS                      # cell 0 is Home, so a page holds CELLS - 1 tiles
WORD_COLS = range(0, 10)                 # columns 1–10
FOLDER_SLOTS = [r * COLS + 11 for r in range(1, ROWS)] + [r * COLS + 10 for r in range(1, ROWS)]
KEYBOARD_CELL = 11                       # r1c12
NEW_TILE_CLASS = "navigation"            # chrome: hidden from AI prompts, no part of speech (TileModel.isStructuralChrome)


def cell(row: int, col: int) -> int:
    return row * COLS + col


def word_cells():
    """Columns 1–10 of rows 2–5, row by row."""
    return [cell(r, c) for r in range(1, ROWS) for c in WORD_COLS]


class Board:
    def __init__(self, spec, scene, vocab):
        self.spec, self.scene, self.vocab = spec, scene, vocab
        self.keys = {t["key"] for t in vocab} | {t["key"] for t in spec.get("newTiles", [])}
        self.doorways = spec["doorways"]
        self.row_keys = {e["key"] for e in spec["systemRow"]}
        self.errors, self.notes = [], []
        self.layouts = {}                    # page key -> {cell: entry}
        self.folders_of = {}                 # page -> its folder column {cell: entry}
        old = {p["key"]: p for p in scene["pages"]}
        self.old_colors = {(p["key"], c.get("link")): c.get("linkColor")
                           for p in scene["pages"] for c in p["tiles"] if "link" in c}
        self.home_colors = {c["link"]: c.get("linkColor") for c in old["home"]["tiles"] if "link" in c}
        self._index_pages()

    # MARK: - Spec

    def _index_pages(self):
        """Folder pages are declared inside their category; give each its own entry."""
        self.pages = {}

        def add_folders(parent, page):
            for f in page.get("folders", []):
                if "words" in f:
                    self.pages[f["page"]] = {"parent": parent, "words": f["words"], "label": f["key"],
                                             "folders": f.get("folders", [])}
                    add_folders(f["page"], f)

        for key, page in self.spec["pages"].items():
            self.pages[key] = page
            add_folders(key, page)

    def ancestors(self, key):
        chain, page = [], self.pages.get(key)
        while page and page.get("parent"):
            chain.append(page["parent"])
            page = self.pages.get(page["parent"])
        return chain

    def check_key(self, key, where):
        if key not in self.keys:
            self.errors.append(f"{where}: unknown key {key!r}")

    # MARK: - Entries

    def word(self, key, page):
        self.check_key(key, page)
        target = self.doorways.get(key)
        if target and target != page:
            return {"key": key, "to": target, "audible": True}
        return {"key": key}

    def system_row(self):
        row = {}
        entries = self.spec["systemRow"]
        for i, e in enumerate(entries):
            self.check_key(e["key"], "systemRow")
            c = KEYBOARD_CELL if e["key"] == "keyboard" else i + 1
            row[c] = {"key": e["key"], "to": e["to"], "audible": False}
        return row

    def folder_column(self, key):
        if key in self.folders_of:
            return self.folders_of[key]
        col = {}
        # "You are here": a folder page keeps its own tile where its parent shows it.
        parent = self.pages[key].get("parent")
        if parent in self.pages:
            col.update({c: e for c, e in self.folder_column(parent).items() if e["to"] == key})
        folders = self.pages[key].get("folders", [])
        slots = [c for c in FOLDER_SLOTS if c not in col]
        if len(folders) > len(slots):
            self.errors.append(f"{key}: {len(folders)} folders, room for {len(slots)}")
        for slot, f in zip(slots, folders):
            self.check_key(f["key"], key)
            col[slot] = {"key": f["key"], "to": f["page"], "audible": False}
        self.folders_of[key] = col
        return col

    # MARK: - Layout

    def layout(self, key):
        if key in self.layouts:
            return self.layouts[key]
        page = self.pages[key]
        grid = self.system_row()
        if key == "home":
            for r, row in enumerate(page["rows"], start=1):
                if len(row) != COLS:
                    self.errors.append(f"home row {r + 1} has {len(row)} cells, needs {COLS}")
                for c, w in enumerate(row):
                    if w:
                        grid[cell(r, c)] = self.word(w, key)
            self.layouts[key] = grid
            return grid

        grid.update(self.folder_column(key))
        taken = {e["key"] for e in grid.values()}
        # An item is a word, or a run: a list that stays side by side in one row
        # (opposites, `come go`, `talk say ask answer speak`).
        items = [i if isinstance(i, list) else [i] for i in page["words"]]
        items = [[w for w in run if w not in taken] for run in items]
        items = [run for run in items if run]
        flat = [w for run in items for w in run]
        dupes = sorted({w for w in flat if flat.count(w) > 1})
        if dupes:
            self.errors.append(f"{key}: listed twice: {dupes}")

        # Same word, same cell: nearest ancestor first. Only pages the spec lays
        # out have cells to inherit; `things` sits under the Things hub, a page
        # of folders the spec does not own.
        lineage = [self.layout(a) for a in self.ancestors(key) if a in self.pages]
        inherited = {}
        for w in flat:
            for anc in lineage:
                c = next((c for c, e in anc.items() if e["key"] == w), None)
                if c is not None:
                    if c >= COLS and c % COLS in WORD_COLS:
                        inherited[w] = c
                    break

        def free(c):
            return c >= COLS and c % COLS in WORD_COLS and c not in grid

        def put(w, c):
            grid[c] = self.word(w, key)

        # `at` places a run by hand: Describe's right · okay · wrong under Home's
        # yes · all done · no.
        for name, run in page.get("at", {}).items():
            r, c = int(name[1:].split("c")[0]) - 1, int(name.split("c")[1]) - 1
            for j, w in enumerate(run):
                if not free(cell(r, c + j)):
                    self.errors.append(f"{key}: {name} cannot hold {run}")
                    break
                put(w, cell(r, c + j))
        placed = {e["key"] for e in grid.values()}

        # Inherited cells first, so nothing else can take them.
        for w, c in inherited.items():
            if w not in placed and free(c):
                put(w, c)
                placed.add(w)
            elif w not in placed:
                self.errors.append(f"{key}: {w} cannot take its cell {c} (taken)")

        def span(start, n):
            cells = [start + j for j in range(n)]
            return cells if all(free(x) and x // COLS == start // COLS for x in cells) else None

        for run in items:
            rest = [w for w in run if w not in placed]
            if not rest:
                continue
            anchor = next(((j, inherited[w]) for j, w in enumerate(run) if w in placed and w in inherited), None)
            spot = None
            if anchor:
                # Grow the run out from the word that already has its cell.
                j, c = anchor
                cells = [c - j + i for i in range(len(run))]
                ok = all(x // COLS == c // COLS and (free(x) or grid.get(x, {}).get("key") == run[i])
                         for i, x in enumerate(cells))
                if ok:
                    for i, x in enumerate(cells):
                        if run[i] not in placed:
                            put(run[i], x)
                            placed.add(run[i])
                    continue
                self.errors.append(f"{key}: run {run} cannot form around {run[j]}")
            for start in word_cells():
                spot = span(start, len(rest))
                if spot:
                    break
            if not spot:
                self.errors.append(f"{key}: no room for {rest}")
                continue
            for w, x in zip(rest, spot):
                put(w, x)
                placed.add(w)
        self.layouts[key] = grid
        return grid

    # MARK: - Commands

    def commands(self, key, grid):
        cmds, run, gap = [], [], 0
        last = max(grid) if grid else 0

        def flush():
            nonlocal run, gap
            if run:
                cmds.append({"keys": run})
                run = []
            if gap:
                cmds.append({"space": gap})
                gap = 0

        for c in range(1, last + 1):
            e = grid.get(c)
            if e is None:
                if run:
                    flush()
                gap += 1
                continue
            if gap:
                flush()
            if "to" in e:
                flush()
                color = self.old_colors.get((key, e["key"])) or self.home_colors.get(e["key"]) or "auto"
                cmds.append({"link": e["key"], "to": e["to"], "audible": e["audible"], "linkColor": color})
            else:
                run.append(e["key"])
        flush()
        if key == "home":
            cmds += self.pages["home"].get("levels", [])
        return cmds

    def row_commands(self, page_key):
        """The system row as commands: eleven links, so the keyboard lands in r1c12."""
        return [{"link": e["key"], "to": e["to"], "audible": False,
                 "linkColor": self.old_colors.get((page_key, e["key"])) or self.home_colors.get(e["key"]) or "auto"}
                for e in self.spec["systemRow"]]

    def door(self, page_key, w):
        return {"link": w, "to": self.doorways[w], "audible": True,
                "linkColor": self.old_colors.get((page_key, w)) or "auto"}

    def passthrough(self, page, vocab_by_class, vocab_order):
        """An unowned page: strip what an earlier run added, then add it again.

        A doorway word in an explicit `keys` list is split out of it in place, so
        it keeps its cell; `check_scene.py` rejects a `link` laid over a word a
        `keys` list already placed. One a class selector placed gets a `link`
        after it, which the materializer applies in place.

        A row-1 folder the page also lists later (Time's own `time`, Social's
        `social`, the hub's `feelings`) is taken out there, since the row holds
        it, **without moving anything after it**: a gap takes its cell in a
        `keys` list or in place of a link, and a class selector excludes it.
        Under a `limit` the selector simply pulls one more of its own words, so
        the count is unchanged; without one, a gap follows the selector.
        Each fix is written into the page, so a second run finds nothing to do.
        """
        key = page["key"]
        exempt = key in self.spec.get("systemRowExempt", [])
        tiles = list(page["tiles"])
        while tiles and "link" in tiles[0] and tiles[0]["link"] in self.row_keys and not tiles[0]["audible"]:
            tiles.pop(0)
        if not exempt and tiles and tiles[0] == {"space": 1}:
            tiles.pop(0)
        while tiles and "link" in tiles[-1] and tiles[-1]["audible"] \
                and self.doorways.get(tiles[-1]["link"]) == tiles[-1]["to"]:
            tiles.pop()
        row_keys = set() if exempt else self.row_keys
        is_door = lambda w: w in self.doorways and self.doorways[w] != key
        body = []
        for cmd in tiles:
            if "keys" in cmd:
                run = []
                for w in cmd["keys"]:
                    if w in row_keys:
                        if run:
                            body.append({"keys": run})
                            run = []
                        body.append({"space": 1})
                        continue
                    if is_door(w):
                        if run:
                            body.append({"keys": run})
                            run = []
                        body.append(self.door(key, w))
                    else:
                        run.append(w)
                if run:
                    body.append({"keys": run})
            elif "link" in cmd and cmd["link"] in row_keys:
                body.append({"space": 1})
            elif "class" in cmd:
                classes = cmd["class"] if isinstance(cmd["class"], list) else [cmd["class"]]
                hits = [w for w in vocab_order if vocab_by_class.get(w) in classes
                        and w in row_keys and w not in cmd.get("exclude", [])]
                if hits:
                    cmd = dict(cmd, exclude=cmd.get("exclude", []) + hits)
                    body.append(cmd)
                    if not cmd.get("limit"):
                        body.append({"space": len(hits)})
                else:
                    body.append(cmd)
            else:
                body.append(cmd)
        placed = expand({"key": key, "tiles": body}, vocab_by_class, vocab_order)
        words = [c for c in placed if c != "·" and not c.startswith("→")]
        doors = [self.door(key, w) for w in words if is_door(w)]
        # One gap after the row moves the page down exactly one row, so every
        # column it was laid out in survives: Social's yes / I don't know / no
        # stay level with Drinks' yummy / all done / yucky.
        row = [] if exempt else self.row_commands(key) + [{"space": 1}]
        return row + body + doors

    # MARK: - Build

    def build(self):
        vocab_by_class = {t["key"]: t["wordClass"] for t in self.vocab}
        vocab_order = [t["key"] for t in self.vocab]
        out = copy.deepcopy(self.scene)
        # A page a split replaced (Body & health → Body, Health) leaves the scene.
        retired = set(self.spec.get("retiredPages", []))
        out["pages"] = [p for p in out["pages"] if p["key"] not in retired]
        existing = [p["key"] for p in out["pages"]]
        new_pages = []
        for p in out["pages"]:
            if p["key"] in self.pages:
                p["tiles"] = self.commands(p["key"], self.layout(p["key"]))
            else:
                p["tiles"] = self.passthrough(p, vocab_by_class, vocab_order)
        for key in self.pages:
            if key not in existing:
                new_pages.append({"key": key, "tiles": self.commands(key, self.layout(key))})
        out["pages"] += new_pages
        names = self.page_names()
        out["pages"] = [{"key": p["key"], **({"name": names[p["key"]]} if p["key"] in names else {}),
                         "tiles": p["tiles"]} for p in out["pages"]]
        self.validate(out, vocab_by_class, vocab_order)
        return out

    def page_names(self):
        """`pageNames` from the spec, and each folder page named after its folder
        tile: `actions_moving` is "Moving", so Find Word reads Actions › Moving."""
        labels = {t["key"]: t["label"] for t in self.spec.get("newTiles", [])}
        names = dict(self.spec.get("pageNames", {}))
        for page in self.spec["pages"].values():
            for f in page.get("folders", []):
                if "words" in f and f["key"] in labels:
                    names.setdefault(f["page"], labels[f["key"]])
        return names

    def validate(self, out, vocab_by_class, vocab_order):
        page_keys = {p["key"] for p in out["pages"]}
        before, after = set(), set()
        vocab_order = vocab_order + [t["key"] for t in self.spec.get("newTiles", []) if t["key"] not in vocab_by_class]
        for p in self.scene["pages"]:
            before |= {c for c in expand(p, vocab_by_class, vocab_order) if c != "·"}
        for p in out["pages"]:
            cells = expand(p, vocab_by_class, vocab_order)
            after |= {c for c in cells if c != "·"}
            if len(cells) > CELLS - 1:
                self.errors.append(f"{p['key']}: {len(cells)} tiles, one screen holds {CELLS - 1}")
            for c in p["tiles"]:
                if "link" in c:
                    if c["to"] not in page_keys:
                        self.errors.append(f"{p['key']}: {c['link']} opens missing page {c['to']}")
                    if c["audible"] and c["to"] == p["key"]:
                        self.errors.append(f"{p['key']}: doorway {c['link']} opens its own page")
        strip = lambda s: s.lstrip("→")
        # A retired page's own folder tile goes with it.
        lost = ({strip(w) for w in before} - {strip(w) for w in after}
                - set(self.spec.get("retiredPages", [])))
        if lost:
            self.errors.append(f"words no longer on any page: {sorted(lost)}")


# MARK: - Vocabulary


def updated_vocab(spec, vocab):
    vocab = copy.deepcopy(vocab)
    have = {t["key"] for t in vocab}
    for t in spec.get("newTiles", []):
        if t["key"] not in have:
            vocab.append({"key": t["key"], "wordClass": NEW_TILE_CLASS, "label": t["label"]})
    for t in vocab:
        if t["key"] in spec.get("relabel", {}):
            t["label"] = spec["relabel"][t["key"]]
    return vocab


def updated_pos(spec, pos):
    """Folder tiles are navigation, not words, so they carry no part of speech
    (`PartOfSpeechTests.chromeIsExcluded`). Kept as a hook for spec words that
    will need one."""
    return copy.deepcopy(pos)


# MARK: - HTML

COLOR = {"pronoun": "#facc33", "verb": "#4db859", "adjective": "#5cb3f5", "noun": "#f59929",
         "question": "#9e66d1", "negation": "#e64a45", "social": "#f28cb8", "interjection": "#f28cb8",
         "preposition": "#9ea3ab", "determiner": "#9ea3ab", "conjunction": "#9ea3ab",
         "link": "#2942ad", "home": "#6b7280"}


def thumb(key):
    src = ART / f"cls_{key}.heic"
    if not src.exists():
        return None
    THUMBS.mkdir(parents=True, exist_ok=True)
    out = THUMBS / f"{key}.jpg"
    if not out.exists():
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "70", "-Z", "160",
                        str(src), "--out", str(out)], check=True, capture_output=True)
    return "data:image/jpeg;base64," + base64.b64encode(out.read_bytes()).decode()


def render_html(board, vocab, pos, path):
    label = {t["key"]: t.get("label") or t["key"].rstrip("_").replace("_", " ") for t in vocab}
    part = {k: p for p, ks in pos.items() for k in ks}
    titles = {"home": "Home"}
    for f in [f for p in board.spec["pages"].values() for f in p.get("folders", [])]:
        titles[f["page"]] = label.get(f["key"], f["key"])

    def tile(c, e, pins, key, path):
        if c == 0:
            img, name, color, cls = thumb("home_") or thumb("home"), "Home", COLOR["home"], "nav"
        elif e is None:
            return '<div class="cell empty"></div>'
        else:
            k = e["key"]
            name = label.get(k, k)
            img = thumb(k)
            silent = "to" in e and not e["audible"]
            color = COLOR["link"] if silent else COLOR.get(part.get(k, "noun"), COLOR["noun"])
            cls = "nav" if silent else "door" if "to" in e else "word"
            if c in pins:
                cls += " pin"
            if e.get("to") == key:
                cls += " here"
            elif e.get("to") in path:
                cls += " path"
        pic = f'<img src="{img}" alt="">' if img else '<span class="ph">new art</span>'
        pic = f'<div class="pic">{pic}</div>'
        if "here" in cls or "path" in cls:
            pic = f'<div class="frame">{pic}</div>'
        badge = ('<span class="dot"></span>' if "here" in cls
                 else '<span class="arrow">↗</span>' if "door" in cls else "")
        return (f'<div class="cell {cls}" style="--c:{color}">{badge}{pic}'
                f'<div class="lbl">{html.escape(name)}</div></div>')

    def section(key):
        grid = board.layouts[key]
        anc = board.ancestors(key)
        parent = board.layouts.get(anc[0]) if anc else None
        pins = {c for c, e in grid.items() if parent and parent.get(c, {}).get("key") == e["key"]
                and c >= COLS and c % COLS in WORD_COLS} if key != "home" else set()
        cells = "".join(tile(c, grid.get(c), pins, key, set(anc)) for c in range(CELLS))
        words = sum(1 for c, e in grid.items() if c >= COLS and not ("to" in e and not e["audible"]))
        sub = (f"{words} words · {len(pins)} in the same cell as on {titles.get(anc[0], anc[0])}"
               if anc else f"{words} words")
        title = titles.get(key) or key.replace("_", " ").title()
        parent = board.pages.get(key, {}).get("parent")
        if parent and key not in board.spec["pages"]:
            title = f"{titles.get(parent, parent.title())} › {title}"
        return (f'<section class="page" id="{key}"><h3>{html.escape(title)}</h3><p class="desc">{sub}</p>'
                f'<div class="grid">{cells}</div></section>')

    order = ["home"]

    def folders(page):
        for f in page.get("folders", []):
            if "words" in f:
                yield f["page"]
                yield from folders(f)   # Things › House things › Kitchen

    for key, page in board.spec["pages"].items():
        if key == "home":
            continue
        order.append(key)
        order += list(folders(page))
    body = "".join(section(k) for k in order)
    css = """
:root { --bg:#f4f4f2; --fg:#1d1d1f; --muted:#666; --card:#fff; --line:#d9d9d6; }
@media (prefers-color-scheme: dark) { :root { --bg:#161617; --fg:#ececec; --muted:#9a9a9a; --card:#222; --line:#3a3a3a; } }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
main { max-width:1280px; margin:0 auto; padding:24px 16px 64px; }
h1 { font-size:26px; margin:0 0 6px; } h3 { font-size:17px; margin:34px 0 2px; }
.desc, .lede { color:var(--muted); margin:2px 0 8px; }
.grid { display:grid; grid-template-columns:repeat(12, 1fr); gap:5px; background:var(--card); padding:8px; border-radius:12px; border:1px solid var(--line); }
.cell { position:relative; aspect-ratio:1/1.12; border-radius:8px; background:var(--c); display:flex; flex-direction:column; overflow:hidden; min-width:0; }
.cell.empty { background:transparent; border:1.5px dashed var(--line); }
.cell.pin { box-shadow:0 0 0 3px var(--fg); }
.frame { flex:1; display:flex; margin:1px 1px 0; padding:3px; border-radius:7px; min-height:0;
  background:repeating-linear-gradient(45deg, #111 0 6px, #ffd600 6px 12px); }
.here .frame .pic { opacity:.55; }
.frame .pic { margin:0; }
.dot { position:absolute; top:1px; left:1px; width:12px; height:12px; border-radius:50%; background:#e5262b; box-shadow:0 0 0 2px #fff; z-index:2; }
.arrow { position:absolute; top:2px; right:4px; font-size:13px; font-weight:800; color:#111; z-index:1; }
.pic { flex:1; margin:4px 4px 0; background:#fff; border-radius:6px; display:flex; align-items:center; justify-content:center; overflow:hidden; min-height:0; }
.pic img { width:100%; height:100%; object-fit:contain; }
.lbl { font-size:clamp(8px, 1.05vw, 13px); font-weight:600; text-align:center; padding:2px 3px 4px; color:#111; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.nav .lbl { color:#fff; }
.ph { font-size:10px; color:#888; text-transform:uppercase; letter-spacing:.04em; }
.legend { display:flex; flex-wrap:wrap; gap:6px 18px; color:var(--muted); font-size:13px; }
"""
    doc = f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>BlasterAI 60 Pages</title><style>{css}</style></head>
<body><main><h1>BlasterAI 60, page by page</h1>
<p class="lede">Built from <code>tools/board_spec/blasterai60.json</code> by <code>tools/build_core_board.py</code>.
Row 1 is the system row on every page. Blue tiles are folders; a ↗ marks a doorway, a word that speaks and opens a page.
A ringed cell holds the same word in the same cell as on the page above it.
A blue-and-green striped tile is on the way to this page; with a red dot, it is this page (pressing it does nothing).</p>{body}</main></body></html>"""
    Path(path).write_text(doc)


# MARK: - Main


def dump(obj):
    return json.dumps(obj, indent=2, ensure_ascii=False) + "\n"


def without_colors(scene):
    s = copy.deepcopy(scene)
    for p in s["pages"]:
        for c in p["tiles"]:
            c.pop("linkColor", None)
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    g = ap.add_mutually_exclusive_group()
    g.add_argument("--write", action="store_true")
    g.add_argument("--check", action="store_true")
    ap.add_argument("--html", type=Path)
    args = ap.parse_args()

    spec = json.loads(SPEC.read_text())
    scene = json.loads(SCENE.read_text())
    vocab0, pos0 = json.loads(VOCAB.read_text()), json.loads(POS.read_text())
    vocab, pos = updated_vocab(spec, vocab0), updated_pos(spec, pos0)

    if args.check:
        # Rebuild from the committed board: it already carries a previous run's
        # additions, which the build strips and re-adds.
        board = Board(spec, scene, vocab)
        out = board.build()
        if without_colors(out) != without_colors(scene):
            board.errors.append("core_first.json differs from the spec: run --write")
        if vocab != vocab0:
            board.errors.append("vocabulary.json is missing spec tiles or labels: run --write")
        if pos != pos0:
            board.errors.append("parts_of_speech.json is missing spec tiles: run --write")
    else:
        board = Board(spec, scene, vocab)
        out = board.build()

    for e in board.errors:
        print("ERROR:", e)
    if args.html:
        render_html(board, vocab, pos, args.html)
        print(f"wrote {args.html}")
    if board.errors:
        return 1
    if args.write:
        SCENE.write_text(dump(out))
        VOCAB.write_text(dump(vocab))
        POS.write_text(dump(pos))
        print("wrote core_first.json, vocabulary.json, parts_of_speech.json — now run resolve_link_colors.py --write")
    elif not args.check:
        changed = [p["key"] for p, q in zip(out["pages"], scene["pages"] + [None] * 99) if q is None or p != q]
        print(f"{len(changed)} page(s) would change: {', '.join(changed)}")
    else:
        print("board matches the spec")
    return 0


if __name__ == "__main__":
    sys.exit(main())
