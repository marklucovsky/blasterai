#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Where every word on the board lives, and where else it might.

    python3 tools/audit_page_placement.py              # the report, as markdown
    python3 tools/audit_page_placement.py --scene x    # another bundled scene

WHY
---
A leaf page is mostly a class selector, and a class can only put a word on one
page. So `sick` — typed `feeling` — is on Feelings and nowhere else, though the
place a child reaches for it is as often Body & Health. A word can sit on any
number of pages (the materializer dedupes per page, not per scene), but only if
someone names it there, and nobody had looked.

WHAT IT REPORTS
---------------
1. **No page** — vocabulary nothing places. Navigation keys are excluded.
2. **More than one page already** — the words that have a second home today.
3. **Proposed second homes** — the `PROPOSALS` list below, each checked against
   the board: already there, proposed, or the word does not exist.
4. **Same label twice on a page** — two keys that draw the same word, such as
   `cold` (an illness) and `cold__` (a temperature). Checked for every page as
   it stands *and* as it would stand with the proposals applied, because adding
   a word to a page is exactly how a collision arrives.

The proposals are a list, written by hand, on purpose. Which page a word
belongs on is a clinical and linguistic judgement; a heuristic would be noise
dressed as analysis. This tool's job is to make the list checkable — and to say
what the board actually does — not to have the opinions.

Nothing here edits the scene. Applying a proposal is adding the word to that
page's `keys` in the scene JSON, never retyping its `wordClass`: retyping moves
a word, and the point is to copy it.
"""

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from show_page_grid import expand  # noqa: E402  — the same reading of a page

SCENES = Path("claudeBlast/Resources/scenes")
VOCAB = Path("claudeBlast/Resources/vocabulary.json")

NAVIGATION = {"home", "next_page", "previous_page"}

# Words a child's board is expected to have: (word, class, page, priority, why).
#
# Priority A — needs, safety, and the words children reach for most; B — round
# out a category; C — grammar the sentence engine normally supplies, worth having
# for Stage IV+ text. Written by hand, like PROPOSALS: the judgement is the
# list's; the tool only checks it against the vocabulary. `page` may name a page
# that does not exist yet — a whole missing category is a finding too.
#
# Sources: the session-8 gap pass (Mark's review of every class list), and the
# PRC-Saltillo 100 for the function words (`tools/audit_core_sets.py`).
EXPECTED = [
    # A — needs and safety
    ("break", "social", "social", "A", "“I need a break” — the request that prevents a meltdown"),
    ("potty", "health", "body_health", "A", "toileting; `bathroom`/`toilet` are places, not the need"),
    ("pee", "health", "body_health", "A", "toileting, said plainly"),
    ("poop", "health", "body_health", "A", "toileting, said plainly"),
    ("medicine", "health", "body_health", "A", "asked for, refused, reported"),
    ("bandaid", "health", "body_health", "A", "the first fix for every small hurt"),
    ("home_", "places", "places", "A", "“go home” — `home` is taken by the Home button's key"),
    ("hug", "actions", "actions", "A", "a request and a comfort; more frequent than kiss"),
    ("bye", "social", "social", "A", "core (PRC-Saltillo); quicker than goodbye"),
    ("calm", "feeling", "feelings", "A", "the middle the feelings list jumps over"),
    ("worried", "feeling", "feelings", "A", "the middle the feelings list jumps over"),
    ("upset", "feeling", "feelings", "A", "the word children use for most bad feelings"),
    # A — body parts children report
    ("hand", "body", "body_health", "A", "the most-reported body part"),
    ("foot", "body", "body_health", "A", "reported for every fall and shoe"),
    ("finger", "body", "body_health", "A", "cuts, pinches, splinters"),
    ("tooth", "body", "body_health", "A", "toothache is there; the tooth is not"),
    ("tummy", "body", "body_health", "A", "the child's word; `stomach` is the adult one"),
    # A — whole categories with nothing in them
    ("dog", "animals", "animals", "A", "no animals exist; the most-named animal"),
    ("cat", "animals", "animals", "A", "no animals exist"),
    ("car", "vehicles", "places", "A", "only `bus` exists; `cars` is a toy"),
    ("book", "object", "play_activities", "A", "`read` exists with nothing to read"),
    ("bed", "object", "things", "A", "bedtime, naps, “I want bed”"),
    ("cup", "object", "drinks", "A", "asked for at every drink"),
    ("shoes", "clothes", "clothes", "A", "no clothes exist; shoes are the daily fight"),
    ("because", "core", "home", "A", "the first word of an explanation; Stage IV+"),
    # B — round out categories
    ("climb", "actions", "actions", "B", "missing beside jump and ride"),
    ("share", "actions", "actions", "B", "a classroom word, and a request"),
    ("build", "actions", "actions", "B", "blocks and playdoh exist with no verb"),
    ("hide", "actions", "actions", "B", "hide-and-seek, and “where is it hiding?”"),
    ("hit", "actions", "actions", "B", "reporting what happened — `kick` exists"),
    ("bite", "actions", "actions", "B", "reporting what happened"),
    ("cut", "actions", "actions", "B", "scissors exist with no verb"),
    ("pour", "actions", "actions", "B", "mealtime independence"),
    ("train", "vehicles", "places", "B", "vehicles"),
    ("bike", "vehicles", "places", "B", "vehicles; `tricycle` is a play item"),
    ("airplane", "vehicles", "places", "B", "`airport` exists"),
    ("boat", "vehicles", "places", "B", "vehicles"),
    ("bird", "animals", "animals", "B", "animals"),
    ("fish", "animals", "animals", "B", "animals"),
    ("horse", "animals", "animals", "B", "animals"),
    ("cow", "animals", "animals", "B", "animals; `farm` exists"),
    ("pig", "animals", "animals", "B", "animals; `farm` exists"),
    ("duck", "animals", "animals", "B", "animals"),
    ("socks", "clothes", "clothes", "B", "clothes"),
    ("shirt", "clothes", "clothes", "B", "clothes"),
    ("pants", "clothes", "clothes", "B", "clothes"),
    ("coat", "clothes", "clothes", "B", "clothes"),
    ("hat", "clothes", "clothes", "B", "clothes"),
    ("pajamas", "clothes", "clothes", "B", "bedtime"),
    ("blanket", "object", "things", "B", "comfort object"),
    ("phone", "object", "things", "B", "“call mom”"),
    ("tv", "object", "things", "B", "requested daily; `watch` exists"),
    ("music", "object", "play_activities", "B", "requested daily; `sing`/`dance` exist"),
    ("toothbrush", "object", "things", "B", "`brush_teeth` exists"),
    ("spoon", "object", "food", "B", "mealtime"),
    ("fork", "object", "food", "B", "mealtime"),
    ("plate", "object", "food", "B", "mealtime"),
    ("knee", "body", "body_health", "B", "falls"),
    ("hair", "body", "body_health", "B", "`wash_hair` exists"),
    ("face", "body", "body_health", "B", "body"),
    ("nurse", "people", "people", "B", "school nurse; `doctor` exists"),
    ("itchy", "health", "body_health", "B", "a symptom children have words for"),
    ("cough", "health", "body_health", "B", "a symptom"),
    ("closed", "describe", "describe", "B", "the state beside `open`"),
    ("sticky", "describe", "describe", "B", "sensory"),
    ("sharp", "describe", "describe", "B", "safety"),
    ("his", "people", "people", "B", "pronouns: her / him exist"),
    ("our", "people", "people", "B", "pronouns: we / us exist"),
    ("their", "people", "people", "B", "pronouns: they / them exist"),
    ("but", "core", "home", "B", "core (PRC-Saltillo)"),
    ("one", "core", "home", "B", "core (PRC-Saltillo); counting"),
    ("will", "core", "home", "B", "core (PRC-Saltillo); future"),
    ("lets", "core", "home", "B", "core (PRC-Saltillo); “let's go”"),
    # C — grammar the sentence engine supplies
    ("am", "core", "home", "C", "core (PRC-Saltillo); the AI conjugates for sentence mode"),
    ("are", "core", "home", "C", "core (PRC-Saltillo)"),
    ("be", "core", "home", "C", "core (PRC-Saltillo)"),
    ("did", "core", "home", "C", "core (PRC-Saltillo)"),
    ("was", "core", "home", "C", "core (PRC-Saltillo)"),
    ("were", "core", "home", "C", "core (PRC-Saltillo)"),
]

# Off every page on purpose, with the reason — reported as such rather than as
# a word somebody forgot.
UNPLACED_ON_PURPOSE = {
    "meals": "a category word, not a food a child asks for; left Food in session 8 "
             "so the page still fits one 12×5 screen",
}

# (word, page it would also go on, why). Reviewed by hand; see the docstring.
PROPOSALS = [
    # Body & Health: the words a child needs when something is wrong.
    ("sick", "body_health", "“I feel sick” is a health report as much as a feeling"),
    ("hurt", "body_health", "pairs with the body parts already there: “my arm hurt”"),
    ("tired", "body_health", "a body state; asked about at every check-in"),
    ("feel", "body_health", "the verb every health sentence starts with: “I feel …”"),
    ("uncomfortable", "body_health", "the word for pain that is not yet “hurt”"),
    ("doctor", "body_health", "who a health conversation is about"),
    ("bathroom", "body_health", "a body need, and one of the most urgent requests"),
    ("toilet", "body_health", "as bathroom; some families use one word, some the other"),
    # Feelings: words typed `describe` that are feelings.
    ("lonely", "feelings", "a feeling, typed describe"),
    ("surprised", "feelings", "a feeling, typed describe"),
    ("okay_", "feelings", "the answer to “how do you feel?”"),
    ("hurt", "feelings", "the emotional sense: “I’m hurt”"),
    ("feel", "feelings", "“I feel sad” needs the verb on the page that has “sad”"),
    # Food and Drinks: the mealtime core.
    ("hungry", "food", "the reason for the food page"),
    ("yummy", "food", "the first thing said about food"),
    ("yucky", "food", "the second thing said about food"),
    ("more", "food", "mealtime core: “more”"),
    ("all_done", "food", "mealtime core: “all done”"),
    ("thirsty", "drinks", "the reason for the drinks page"),
    ("more", "drinks", "mealtime core"),
    ("all_done", "drinks", "mealtime core"),
    # Places.
    ("bus", "places", "on no page; the only vehicle, and how a child gets places"),
    ("bathroom", "places", "a room, beside bedroom and kitchen"),
]


def label(key):
    """What the tile shows: the key without its sense suffix (`cold__` → `cold`)."""
    return key.rstrip("_").replace("_", " ")


def placements(scene, vocab_by_class, vocab_order):
    """page key → (ordered word keys, folder keys).

    Folders are kept apart rather than dropped. A folder is a tile too — `eat`
    is on the home page, as the link to Food — so a word that appears only as a
    folder is placed, not missing. An earlier version dropped them and reported
    `eat`, `drink` and `play` as on no page: a check that cries wolf.
    """
    out = {}
    for page in scene["pages"]:
        cells = expand(page, vocab_by_class, vocab_order)
        words = [c for c in cells if not c.startswith("→") and c != "·"]
        folders = [c[1:] for c in cells if c.startswith("→")]
        out[page["key"]] = (words, folders)
    return out


def collisions(words):
    """Labels drawn by more than one key on a page."""
    seen = {}
    for key in words:
        seen.setdefault(label(key), []).append(key)
    return {lab: keys for lab, keys in seen.items() if len(set(keys)) > 1}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--scene", default="core_first")
    args = ap.parse_args()

    scene = json.loads((SCENES / f"{args.scene}.json").read_text())
    vocab = json.loads(VOCAB.read_text())
    vocab_by_class = {t["key"]: t["wordClass"] for t in vocab}
    vocab_order = [t["key"] for t in vocab]

    placed = placements(scene, vocab_by_class, vocab_order)
    pages = {page: words for page, (words, _) in placed.items()}
    homes = {}
    for page, words in pages.items():
        for w in words:
            homes.setdefault(w, []).append(page)
    as_folder = {f for _, folders in placed.values() for f in folders}

    print(f"# Page placement — {scene['name']}\n")
    print(f"{len(vocab)} words, {len(pages)} pages.\n")

    print("## 1. On no page\n")
    # Navigation words are folder labels; they need no page of their own.
    orphans = [k for k in vocab_order
               if k not in homes and k not in as_folder and k not in NAVIGATION
               and vocab_by_class[k] != "navigation"]
    accidental = [k for k in orphans if k not in UNPLACED_ON_PURPOSE]
    print(", ".join(f"`{k}` ({vocab_by_class[k]})" for k in accidental) or "None.")
    for k in orphans:
        if k in UNPLACED_ON_PURPOSE:
            print(f"\n- `{k}`, on purpose: {UNPLACED_ON_PURPOSE[k]}")
    print()

    print("## 2. Already on more than one page\n")
    multi = sorted((k for k, ps in homes.items() if len(ps) > 1), key=vocab_order.index)
    if multi:
        print("| Word | Pages |\n|---|---|")
        for k in multi:
            print(f"| `{k}` | {', '.join(homes[k])} |")
    else:
        print("None.")
    print()

    print("## 3. Proposed second homes\n")
    print("| Word | Class | Now on | Also on | Status | Why |\n|---|---|---|---|---|---|")
    proposed = {}
    for word, target, why in PROPOSALS:
        if word not in vocab_by_class:
            status = "**no such word**"
        elif target not in pages:
            status = "**no such page**"
        elif word in pages[target]:
            status = "already there"
        else:
            status = "proposed"
            proposed.setdefault(target, []).append(word)
        now = ", ".join(homes.get(word, [])) or "—"
        print(f"| `{word}` | {vocab_by_class.get(word, '?')} | {now} | {target} | {status} | {why} |")
    print()

    print("## 4. Same label twice on one page\n")
    print("A key's label is the key with underscores turned to spaces, so `right` "
          "and `right_` both read “right”; only the picture tells them apart.\n")
    found = False
    for page, words in pages.items():
        for lab, keys in collisions(words).items():
            found = True
            print(f"- **{page}** today: “{lab}” is {', '.join(f'`{k}`' for k in keys)}")
        after = words + proposed.get(page, [])
        new = {lab: keys for lab, keys in collisions(after).items()
               if lab not in collisions(words)}
        for lab, keys in new.items():
            found = True
            print(f"- **{page}** with proposals: “{lab}” would be {', '.join(f'`{k}`' for k in keys)}")
    if not found:
        print("None, today or with the proposals applied.")
    print()

    print("## 5. Expected but missing\n")
    have = set(vocab_by_class)
    classes = set(vocab_by_class.values())
    missing = [e for e in EXPECTED if e[0] not in have]
    present = [e for e in EXPECTED if e[0] in have]
    print(f"{len(missing)} of {len(EXPECTED)} expected words are not in the vocabulary.\n")
    new_classes = sorted({c for _, c, _, _, _ in missing if c not in classes})
    new_pages = sorted({pg for _, _, pg, _, _ in missing if pg not in pages})
    if new_classes:
        print("New word classes needed: " + ", ".join(f"`{c}`" for c in new_classes) + "\n")
    if new_pages:
        print("New pages needed: " + ", ".join(f"`{pg}`" for pg in new_pages) + "\n")
    for tier in "ABC":
        rows = [e for e in missing if e[3] == tier]
        if not rows:
            continue
        print(f"### Priority {tier} ({len(rows)})\n")
        print("| Word | Class | Page | Why |\n|---|---|---|---|")
        for word, cls, page, _, why in rows:
            flag = "" if page in pages else " (new)"
            print(f"| `{word}` | {cls} | {page}{flag} | {why} |")
        print()
    if present:
        print("Already in the vocabulary: " + ", ".join(f"`{e[0]}`" for e in present) + "\n")

    print("## Proposed additions by page\n")
    for page in pages:
        if page in proposed:
            print(f"- **{page}** (+{len(proposed[page])}, "
                  f"{len(pages[page])} → {len(pages[page]) + len(proposed[page])} words): "
                  + ", ".join(f"`{w}`" for w in proposed[page]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
