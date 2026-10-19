#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Compare BlasterAI 60's levels with a CoughDrop board set's, word by word.

    python3 tools/compare_levels.py --obz /path/to/vocal-flair-60.obz
    python3 tools/compare_levels.py --obz ... --offline     # cache only

WHERE THE LEVELS ARE
--------------------
Not in the .obz. OBF has no notion of levels, and CoughDrop's export drops
them: every button in `vocal-flair-60.obz` (OpenAAC, checked 2026-10-18)
carries part of speech and vocalization extensions, and nothing about level.

They live on CoughDrop's server, per button, as `level_modifications`:

    {"pre": {"hidden": true}, "5": {"hidden": false}}

"hidden before any level is applied; shown from level 5". The board set is
public, so the public board API returns them — one request per board. The .obz
supplies the list of boards and each board's `data_url`; this fetches each once
into `build/coughdrop_cache/` (gitignored) and reads the cache after that.

WHAT "LEVEL" MEANS HERE
-----------------------
A word's level is the lowest level at which a child can *reach* it: the button
is shown, and so is every folder on the way from the home board. A word shown
from level 2 on a page behind a level-5 folder is a level-5 word. Where a word
has several places, the most reachable one counts.

Ours come from `core_first.json`'s home page, where the level map lives: the
`level` blocks name words for levels 1-3 and `rest` puts everything else at 4.
Words off our home page are reported as "elsewhere" rather than given a level:
they sit behind folders, and BlasterAI 60's demo map does not level those pages.

LICENCE
-------
Vocal Flair is CC BY 4.0 (OpenAAC / CoughDrop). Reading its structure to learn
from is fine. If BlasterAI 60's level map ends up following theirs, credit it in
NOTICE and in the scene's description. This tool never reads the .obz images,
for the reason `tools/obz_mine.py` gives.
"""

import argparse
import json
import re
import sys
import time
import subprocess
import zipfile
from collections import defaultdict, deque
from pathlib import Path

VOCAB = Path("claudeBlast/Resources/vocabulary.json")
SCENE = Path("claudeBlast/Resources/scenes/core_first.json")
CACHE = Path("build/coughdrop_cache")
OUR_TOP = 4

# Utility cells, not vocabulary — see compare_boards.py.
NOT_VOCABULARY = {"clear", "period", "abc123", "extrawords"}

# Their label → our key, where the two name one word differently.
ALIASES = {"done": "all_done", "questions": "question"}


def norm(s):
    key = re.sub(r"[^a-z0-9']+", "_", (s or "").strip().lower()).strip("_")
    return ALIASES.get(key, key)


# MARK: - Theirs

def boards_in(obz_path):
    """(root id, {board id: data_url}) from the .obz, without its images."""
    z = zipfile.ZipFile(obz_path)
    manifest = json.loads(z.read("manifest.json"))
    boards, root = {}, None
    for name in z.namelist():
        if not name.endswith(".obf"):
            continue
        board = json.loads(z.read(name))
        boards[board["id"]] = board["data_url"]
        if name == manifest["root"]:
            root = board["id"]
    return root, boards


def fetch(board_id, url, offline, delay):
    """The board's API JSON, from the cache or, once, from CoughDrop."""
    path = CACHE / f"{board_id}.json"
    if path.exists():
        return json.loads(path.read_text())
    if offline:
        sys.exit(f"not cached and --offline: {board_id}")
    # curl rather than urllib: the python.org build ships without CA
    # certificates until "Install Certificates" is run, and curl uses the
    # system's.
    out = subprocess.run(["curl", "-sSfL", "-m", "30",
                          "-A", "BlasterAI level comparison (one-off, cached)", url],
                         capture_output=True, check=True)
    data = json.loads(out.stdout)
    CACHE.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data))
    time.sleep(delay)
    return data


def shown_from(button):
    """The level a button appears at: 1 when never hidden, None when always."""
    mods = button.get("level_modifications") or {}
    hidden = bool(button.get("hidden"))
    if (mods.get("pre") or {}).get("hidden") is not None:
        hidden = mods["pre"]["hidden"]
    if not hidden:
        return 1
    shown = [int(k) for k, v in mods.items() if k.isdigit() and v.get("hidden") is False]
    return min(shown) if shown else None


def their_levels(root, api):
    """word → (level, on the home board at that level?), and the level each
    board becomes reachable at."""
    board_level = {root: 1}
    queue = deque([root])
    while queue:
        bid = queue.popleft()
        for b in api[bid]["board"]["buttons"]:
            target = (b.get("load_board") or {}).get("id")
            lvl = shown_from(b)
            if not target or target not in api or lvl is None:
                continue
            reach = max(board_level[bid], lvl)
            if reach < board_level.get(target, 99):
                board_level[target] = reach
                queue.append(target)

    words = {}
    for bid, level in board_level.items():
        for b in api[bid]["board"]["buttons"]:
            lvl = shown_from(b)
            key = norm(b.get("label"))
            if lvl is None or not key or key in NOT_VOCABULARY or b.get("load_board"):
                continue
            reach = max(level, lvl)
            on_home = bid == root
            best = words.get(key)
            if best is None or (reach, not on_home) < (best[0], not best[1]):
                words[key] = (reach, on_home)
    return words, board_level


def their_home(root, api):
    """level → (words, folders) on the home board: where a level map is
    actually authored. Everything else follows from which folders show."""
    by_level = defaultdict(lambda: ([], []))
    for b in api[root]["board"]["buttons"]:
        lvl, key = shown_from(b), norm(b.get("label"))
        if lvl is None or not key or key in NOT_VOCABULARY:
            continue
        by_level[lvl][1 if b.get("load_board") else 0].append(key)
    return by_level


# MARK: - Ours

def our_home_levels():
    """word → level on our home page; levels 1-3 named, the rest at 4."""
    scene = json.loads(SCENE.read_text())
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])
    on_home, named = set(), {}
    for tile in home["tiles"]:
        if tile.get("link"):
            on_home.add(tile["link"])
        on_home.update(tile.get("keys", []))
        if "level" in tile and "words" in tile:
            for w in tile["words"]:
                named[w] = tile["level"]
    return {norm(w): named.get(w, OUR_TOP) for w in on_home}


# MARK: - Report

def ours_label(word, ours, vocab):
    if word in ours:
        return f"L{ours[word]}"
    return "elsewhere" if word in vocab else "MISSING"


def columns(words, render, width=4):
    items = [render(w) for w in sorted(words)]
    if not items:
        print("    —")
        return
    cell = max(len(i) for i in items) + 2
    for i in range(0, len(items), width):
        print("    " + "".join(f"{x:{cell}}" for x in items[i:i + width]))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--obz", type=Path, required=True)
    ap.add_argument("--offline", action="store_true", help="read the cache only")
    ap.add_argument("--delay", type=float, default=0.5, help="seconds between requests")
    ap.add_argument("--through", type=int, default=5, help="list their words through this level")
    args = ap.parse_args()
    if not SCENE.exists():
        sys.exit(f"run from the repo root — {SCENE} not found")

    root, urls = boards_in(args.obz)
    api = {bid: fetch(bid, url, args.offline, args.delay) for bid, url in sorted(urls.items())}
    theirs, board_level = their_levels(root, api)
    ours = our_home_levels()
    vocab = {norm(t["key"]) for t in json.loads(VOCAB.read_text())}
    name = api[root]["board"]["name"]

    print("=" * 72)
    print(f"LEVELS — BlasterAI 60 (home, {OUR_TOP} levels) vs {name} ({len(api)} boards)")
    print("=" * 72)

    top = max(l for l, _ in theirs.values())
    print(f"\n{name}: words a child can reach, by level")
    print("    level   new   total   on home")
    total = 0
    for lvl in range(1, top + 1):
        new = [w for w, (l, _) in theirs.items() if l == lvl]
        total += len(new)
        home = sum(1 for w in new if theirs[w][1])
        print(f"    {lvl:5d} {len(new):5d} {total:7d} {home:9d}")
    unreached = len(api) - len(board_level)
    if unreached:
        print(f"    ({unreached} boards are reached by no visible folder at any level)")

    print(f"\n{name}: the home board, level by level  (word = ours)")
    for lvl, (words, folders) in sorted(their_home(root, api).items()):
        print(f"  L{lvl}:  {len(words)} words, {len(folders)} folders")
        if words:
            columns(words, lambda w: f"{w}={ours_label(w, ours, vocab)}")
        if folders:
            print("    folders: " + ", ".join(sorted(folders)))

    # Our folders are leveled too; compare them with their home folders.
    folders = {f: lvl for lvl, (_, fs) in their_home(root, api).items() for f in fs}
    def their_level(w):
        if w in theirs:
            return theirs[w][0]
        return f"{folders[w]}f" if w in folders else "—"

    print("\nOUR LEVELS, AND WHERE THEY SIT IN THEIRS")
    for lvl in range(1, OUR_TOP):
        words = [w for w, l in ours.items() if l == lvl]
        print(f"\n  our L{lvl} ({len(words)}):  word = their level "
              f"('f' = their home folder, '—' = not on their board)")
        columns(words, lambda w: f"{w}={their_level(w)}")

    for lvl in range(1, args.through + 1):
        words = [w for w, (l, _) in theirs.items() if l == lvl]
        print(f"\nTHEIR L{lvl} ({len(words)}):  word = ours (L1-L4 on our home, "
              f"'elsewhere' behind a folder, MISSING from our vocabulary)")
        columns(words, lambda w: f"{w}={ours_label(w, ours, vocab)}", width=3)

    # Agreement: of their first N levels, how many we also put early.
    print("\nAGREEMENT")
    for lvl in range(1, OUR_TOP):
        mine = {w for w, l in ours.items() if l <= lvl}
        early = {w for w in mine if w in theirs and theirs[w][0] <= lvl}
        print(f"  our L1-L{lvl}: {len(mine):3d} words, {len(early):3d} also by their L{lvl}, "
              f"{sum(1 for w in mine if w not in theirs):3d} not on their board")


if __name__ == "__main__":
    main()
