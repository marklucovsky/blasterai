#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Prototype layouts: lay a topic page's ranked words into the iPad 12 × 5 grid.

The model returns words; code places them (docs/eval/scenes.md). Two templates:

- **home** — a scene's home page. Row 1 is Home plus links to the scene's leaf
  pages. BlasterAI 60's level-1 words keep the cells they hold on the default
  board (I, you, want, more, go, stop, help, yes, all done, no), so a child who
  knows where "want" is finds it in the same place on every scene. The topic
  words fill the 38 cells left.
- **leaf** — no frame: Home in the first cell, the topic words after it.

Words are grouped Fitzgerald-style into vertical bands, left to right: pronouns,
people, actions, describing words, social words, then things and places. Within
a band they keep the model's rank. Columns fill top to bottom, skipping frame
cells.

    python3 tools/eval/build_layouts.py            # tools/eval/layouts.json
    open docs/eval/runs/<stamp>-layouts/layouts.html

Pages come from saved runs (sample 0) or are generated now with the plan-of-
record model (gpt-6.1-sol, low) and cached next to the page. A NEW word gets
drawn art in the app; one that names a character or a real person is marked
for a caregiver's photo (the image model refuses or draws it wrong —
`probe_art_refusals.py`).
"""
import argparse
import base64
import html
import json
import subprocess
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

import client
import models
import prompts as P
import scorers as S

SPEC = Path(__file__).parent / "layouts.json"
RUNS = P.ROOT / "docs/eval/runs"
ART = P.ROOT / "claudeBlast/TileImageSets"
THUMBS = P.ROOT / "tools/tile_sets/layout_thumbs_gi2"   # gitignored
MODEL, EFFORT = "gpt-6.1-sol", "low"
ROWS, COLS = 5, 12

# BlasterAI 60 home cells (row, col), 0-based, for the level-1 words.
FRAME = {(1, 0): "i", (1, 4): "go", (1, 9): "more", (2, 4): "want", (2, 11): "stop",
         (3, 0): "you", (3, 3): "help", (4, 0): "yes", (4, 1): "all_done", (4, 2): "no"}

# VocabularyClasses.fitzgerald, plus wayfinding and chrome.
COLOR = {"pronoun": "#facc33", "verb": "#4db859", "adjective": "#5cb3f5", "noun": "#f59929",
         "question": "#9e66d1", "negation": "#e64a45", "social": "#f28cb8", "interjection": "#f28cb8",
         "function": "#9ea3ab", "link": "#2942ad", "home": "#6b7280"}
BANDS = ["pronoun", "people", "verb", "adjective", "social", "noun"]

NAMED_SYSTEM = """For every input word, say whether a picture of it can be drawn: "named" if the word is a specific fictional character, mascot or puppet from a show, film, book, game or toy line (Bluey, Elsa, Elmo, Pikachu), or a real person by name (a celebrity, a presenter, a historical figure). Everything else is "drawable": ordinary words, kinds of thing ("princess", "superhero", "robot"), brands, products, restaurants and places ("McDonald's", "Lego", "Eiffel Tower"), the titles of shows and games, and figures from religion, folklore and holidays ("Jesus", "Santa", "Tooth Fairy").
Return ONLY JSON: {"art": {"<word>": "named" | "drawable", ...}} with an entry for every input word, keyed exactly as given."""


def vocab_labels() -> dict[str, str]:
    out = {}
    for t in json.loads((P.RESOURCES / "vocabulary.json").read_text()):
        out.setdefault(t["key"], t.get("label") or t["key"].rstrip("_").replace("_", " "))
    return out


def chat(body: dict) -> str:
    sent, _ = models.adapt(body, MODEL, EFFORT)
    r = client.call(sent)
    if r.get("error"):
        raise RuntimeError(r["error"])
    return r["text"]


# MARK: - Pages


def load_page(ref: dict, spec: dict, cache: dict, template: str) -> dict:
    """{"summary", "description"} for one page, re-scored with today's matcher."""
    if "describe" in ref:
        text = cache.get(ref["describe"])
        if text is None:
            text = cache[ref["describe"]] = chat(P.topic_words_body(ref["describe"], template))
        description = ref["describe"]
    else:
        run = RUNS / spec["runs"][ref["run"]]
        rec = next(json.loads(l) for l in (run / "results.jsonl").read_text().splitlines()
                   if json.loads(l)["case"] == ref["case"] and json.loads(l)["sample"] == 0)
        text, description = rec["output"], rec["input"]["description"]
    summary, _ = S.score_topic_words(text, template, {})
    return {"summary": summary, "description": description}


def pos_of(key: str, summary: dict) -> str:
    """The word's part of speech. A new word the model filed under "social" that
    is a name (Christmas, Hanukkah) is a noun: social is for greetings and
    manners, and those are already in the vocabulary."""
    info = summary["words"][key]
    if info["new"] and info["pos"] == "social":
        return "noun"
    return info["pos"]


def band(key: str, summary: dict, classes: dict) -> str:
    pos = pos_of(key, summary)
    if pos == "noun":
        wc = (summary["new_words"].get(key) or {}).get("wordClass") or classes.get(key)
        return "people" if wc == "people" else "noun"
    if pos in ("interjection", "question", "negation"):
        return "social"
    if pos in ("preposition", "determiner", "conjunction"):
        return "adjective"
    return pos if pos in BANDS else "noun"


def place(summary: dict, template: str, links: list[dict], classes: dict) -> dict:
    """(row, col) → cell. A cell is {"kind": "home" | "link" | "frame" | "word", ...}."""
    grid = {(0, 0): {"kind": "home"}}
    if template == "home":
        for (r, c), k in FRAME.items():
            grid[(r, c)] = {"kind": "frame", "key": k}
        for n, link in enumerate(links[:COLS - 1], 1):
            grid[(0, n)] = {"kind": "link", **link}
        rows = range(1, ROWS)
    else:
        rows = range(ROWS)
    words = sorted(summary["page"], key=lambda k: BANDS.index(band(k, summary, classes)))  # stable: rank kept
    if template == "leaf":
        return spread(grid, words, summary, classes)
    free = [(r, c) for c in range(COLS) for r in rows if (r, c) not in grid]
    for cell, k in zip(free, words):
        grid[cell] = {"kind": "word", "key": k}
    return grid


def spread(grid: dict, words: list[str], summary: dict, classes: dict) -> dict:
    """A leaf page has no frame, so its bands can breathe: each band starts a
    new column, with an empty column between bands when the grid has room."""
    groups = [[k for k in words if band(k, summary, classes) == b] for b in BANDS]
    groups = [g for g in groups if g]
    for gap in (1, 0):
        cells, col, row, fits = {}, 0, 0, True
        for n, g in enumerate(groups):
            for k in g:
                while (row, col) in grid:
                    row += 1
                if row == ROWS:
                    row, col = 0, col + 1
                    while (row, col) in grid:
                        row += 1
                if col >= COLS:
                    fits = False
                    break
                cells[(row, col)] = {"kind": "word", "key": k}
                row += 1
            if not fits:
                break
            if n < len(groups) - 1:
                row, col = 0, col + 1 + gap
        if fits:
            return {**grid, **cells}
    raise ValueError("page does not fit the grid")


# MARK: - Art


def thumb(key: str) -> str | None:
    src = ART / f"cls_{key}.heic"
    if not src.exists():
        return None
    out = THUMBS / f"{key}.jpg"
    if not out.exists():
        subprocess.run(["sips", "-s", "format", "jpeg", "-s", "formatOptions", "70", "-Z", "160",
                        str(src), "--out", str(out)], check=True, capture_output=True)
    return "data:image/jpeg;base64," + base64.b64encode(out.read_bytes()).decode()


def named_words(words: list[str], cache: dict) -> set[str]:
    todo = [w for w in words if w not in cache]
    for i in range(0, len(todo), 60):
        chunk = todo[i:i + 60]
        t = chat({"model": "gpt-4o-mini", "messages": [{"role": "system", "content": NAMED_SYSTEM},
                                                       {"role": "user", "content": ", ".join(chunk)}]})
        art = json.loads(t[t.index("{"):t.rindex("}") + 1]).get("art", {})
        cache.update({w: art.get(w) == "named" for w in chunk})
    return {w for w in words if cache.get(w)}


# MARK: - HTML


def tile_html(cell: dict | None, summary: dict, labels: dict, named: set) -> str:
    if cell is None:
        return '<div class="cell empty"></div>'
    kind = cell["kind"]
    if kind == "home":
        img, label, color, cls = thumb("home_") or thumb("home"), "Home", COLOR["home"], "nav"
    elif kind == "link":
        img, label, color, cls = cell.get("img"), cell["name"], COLOR["link"], "nav"
    else:
        k = cell["key"]
        info = (summary["words"].get(k) if kind == "word" else None) or {}
        pos = (pos_of(k, summary) if info else None) or S.part_of_speech().get(k, "noun")
        if pos in ("preposition", "determiner", "conjunction"):
            pos = "function"
        new = info.get("new", False)
        label = ((summary["new_words"].get(k) or {}).get("displayName") if new else None) \
            or labels.get(k) or k.replace("_", " ")
        img, color, cls = (None if new else thumb(k)), COLOR.get(pos, COLOR["noun"]), kind
        if new:
            cls += " named" if label in named else " new"
    pic = (f'<img src="{img}" alt="">' if img else
           '<span class="ph">photo</span>' if "named" in cls else '<span class="ph">new art</span>')
    return (f'<div class="cell {cls}" style="--c:{color}"><div class="pic">{pic}</div>'
            f'<div class="lbl">{html.escape(label)}</div></div>')


def grid_html(title: str, sub: str, grid: dict, summary: dict, labels: dict, named: set) -> str:
    cells = "".join(tile_html(grid.get((r, c)), summary, labels, named) for r in range(ROWS) for c in range(COLS))
    words = [c["key"] for c in grid.values() if c["kind"] == "word"]
    new = [k for k in words if summary["words"][k]["new"]]
    photo = [summary["new_words"][k]["displayName"] for k in new if summary["new_words"][k]["displayName"] in named]
    over = ", ".join(html.escape(labels.get(k) or (summary["new_words"].get(k) or {}).get("displayName") or k)
                     for k in summary["overflow"])
    stats = (f"{len(words)} topic words · {len(new) - len(photo)} new art · {len(photo)} need a photo"
             + (f" · <b>Suggestions (overflow):</b> {over}" if over else ""))
    return (f'<section class="page"><h3>{html.escape(title)}</h3><p class="desc">{html.escape(sub)}</p>'
            f'<div class="grid">{cells}</div><p class="stats">{stats}</p></section>')


CSS = """
:root { --bg:#f4f4f2; --fg:#1d1d1f; --muted:#666; --card:#fff; --line:#d9d9d6; }
@media (prefers-color-scheme: dark) { :root { --bg:#161617; --fg:#ececec; --muted:#9a9a9a; --card:#222; --line:#3a3a3a; } }
* { box-sizing:border-box; }
body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
main { max-width:1280px; margin:0 auto; padding:24px 16px 64px; }
h1 { font-size:26px; margin:0 0 6px; } h2 { font-size:21px; margin:44px 0 4px; border-top:1px solid var(--line); padding-top:24px; }
h3 { font-size:16px; margin:18px 0 2px; } .desc, .lede, .stats { color:var(--muted); margin:2px 0 8px; } .stats { font-size:13px; }
.legend { display:flex; flex-wrap:wrap; gap:6px 14px; font-size:13px; color:var(--muted); margin:10px 0; }
.legend span::before { content:""; display:inline-block; width:12px; height:12px; border-radius:3px; background:var(--c); margin-right:5px; vertical-align:-1px; }
.grid { display:grid; grid-template-columns:repeat(12, 1fr); gap:5px; background:var(--card); padding:8px; border-radius:12px; border:1px solid var(--line); }
.cell { aspect-ratio:1/1.12; border-radius:8px; background:var(--c); display:flex; flex-direction:column; overflow:hidden; min-width:0; }
.cell.empty { background:transparent; border:1.5px dashed var(--line); }
.pic { flex:1; margin:4px 4px 0; background:#fff; border-radius:6px; display:flex; align-items:center; justify-content:center; overflow:hidden; min-height:0; }
.pic img { width:100%; height:100%; object-fit:contain; }
.lbl { font-size:clamp(8px, 1.05vw, 13px); font-weight:600; text-align:center; padding:2px 3px 4px; color:#111; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
.nav .lbl { color:#fff; }
.frame { box-shadow:inset 0 0 0 3px rgba(0,0,0,.28); }
.ph { font-size:11px; color:#888; text-transform:uppercase; letter-spacing:.04em; }
.new .pic { background:repeating-linear-gradient(45deg,#fff,#fff 6px,#f2f2f2 6px,#f2f2f2 12px); }
.named .pic { background:#fff3cd; } .named .ph { color:#9a6b00; }
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--spec", default=str(SPEC))
    ap.add_argument("--out", help="output folder (reuses its generated pages)")
    args = ap.parse_args()
    spec = json.loads(Path(args.spec).read_text())
    out = Path(args.out).resolve() if args.out else RUNS / f"{datetime.now():%Y-%m-%d-%H%M}-layouts"
    out.mkdir(parents=True, exist_ok=True)
    THUMBS.mkdir(parents=True, exist_ok=True)
    cache_file, named_file = out / "generated.json", out / "named.json"
    cache = json.loads(cache_file.read_text()) if cache_file.exists() else {}
    named_cache = json.loads(named_file.read_text()) if named_file.exists() else {}
    labels, classes = vocab_labels(), P.word_classes()

    # Generate any missing leaf pages in parallel, then everything else is local.
    todo = [l["describe"] for s in spec["scenes"] for l in s.get("leaves", []) if "describe" in l and l["describe"] not in cache]
    with ThreadPoolExecutor(6) as ex:
        for d, t in zip(todo, ex.map(lambda d: chat(P.topic_words_body(d, "leaf")), todo)):
            cache[d] = t
    cache_file.write_text(json.dumps(cache, indent=1, ensure_ascii=False) + "\n")

    scenes = []
    for s in spec["scenes"]:
        home_t = "leaf" if s.get("leaf_only") else "home"
        home = load_page(s["home"], spec, cache, home_t)
        leaves = [(l["name"], load_page(l, spec, cache, "leaf")) for l in s.get("leaves", [])]
        scenes.append((s, home_t, home, leaves))
    new_labels = sorted({w["displayName"] for _, _, h, ls in scenes for pg in [h] + [p for _, p in ls]
                         for w in pg["summary"]["new_words"].values()})
    named = named_words(new_labels, named_cache)
    named_file.write_text(json.dumps(named_cache, indent=1, ensure_ascii=False) + "\n")

    body = []
    for s, home_t, home, leaves in scenes:
        links = []
        for name, pg in leaves:
            first = next((k for k in pg["summary"]["page"] if not pg["summary"]["words"][k]["new"] and thumb(k)), None)
            links.append({"name": name, "img": thumb(first) if first else None})
        body.append(f'<h2>{html.escape(s["name"])}</h2>')
        kind = "Leaf page — no frame" if home_t == "leaf" else (
            f"Scene home page + {len(leaves)} linked pages" if leaves else "Single-page scene (home template)")
        body.append(grid_html(kind, home["description"], place(home["summary"], home_t, links, classes),
                              home["summary"], labels, named))
        for name, pg in leaves:
            body.append(grid_html(f"{name} — leaf page", pg["description"],
                                  place(pg["summary"], "leaf", [], classes), pg["summary"], labels, named))

    legend = "".join(f'<span style="--c:{COLOR[k]}">{t}</span>' for k, t in [
        ("pronoun", "pronouns"), ("verb", "actions"), ("adjective", "describing"), ("noun", "people, things, places"),
        ("social", "social"), ("question", "questions"), ("link", "page links"), ("home", "Home")])
    page = f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1"><title>Scene Layouts</title><style>{CSS}</style></head>
<body><main><h1>Scene layouts — prototype</h1>
<p class="lede">iPad 12 × 5. Words: gpt-6.1-sol (prompt t8). Placement: code. On a scene's home page the
outlined tiles are BlasterAI 60's level-1 words in the same cells they hold on the default board; row 1 is Home
and the links to the scene's pages. Topic words fill the rest in colour bands, left to right: pronouns, people,
actions, describing, social, things and places. Striped = new word, art drawn by the app.
Yellow = a named character or person: the caregiver adds a photo.</p>
<div class="legend">{legend}</div>{''.join(body)}</main></body></html>"""
    (out / "layouts.html").write_text(page)
    print(out.relative_to(P.ROOT) / "layouts.html")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
