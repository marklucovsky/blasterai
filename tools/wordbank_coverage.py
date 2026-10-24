#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""How much of the words toddlers actually say does BlasterAI 60 carry, and where.

    python3 tools/wordbank_coverage.py                 # summary by CDI category
    python3 tools/wordbank_coverage.py --missing       # every CDI word we lack, by age
    python3 tools/wordbank_coverage.py --csv out.csv   # one row per CDI word

WHY THE CDI
-----------
Brandi (2026-10-23) named the MacArthur-Bates CDI as the authority on which
early words matter. The forms themselves are copyrighted (CDI Advisory Board,
sold by Brookes), so we do not copy them. Wordbank publishes the data collected
WITH them — tens of thousands of American English Words & Sentences forms —
under CC BY 4.0, including each word's age of acquisition: the age in months at
which half of children produce it. That is more useful than the bare list,
because it ranks the gaps.

`tools/data/wordbank/english_american_ws_aoa.csv` is the English (American) WS
slice of Wordbank's `aoa` table (Redivis dataset datapages.wordbank v3.4,
doi:10.57761/t38b-5y26). Cite: Frank, Braginsky, Yurovsky & Marchman (2017),
"Wordbank: An open repository for developmental vocabulary data", Journal of
Child Language 44(3), 677–694. Ages past 30 months (the form's top age) are
extrapolated by Wordbank's fit; an empty `aoa_produces` means the fit found no
age at which half of children produce the word.

MATCHING
--------
A CDI item is matched to a vocabulary key by its definition with any sense
note dropped ("drink (beverage)" → drink), spaces as underscores, and each
alternative of a slash ("inside/in"). `ALIASES` covers the rest by hand. Sense
notes are NOT distinguished: "slide (object)" and "slide (action)" both match
our one `slide` tile, which is what a child pressing it gets.
"""
import argparse
import csv
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from show_page_grid import expand  # noqa: E402

DATA = Path("tools/data/wordbank/english_american_ws_aoa.csv")
VOCAB = Path("claudeBlast/Resources/vocabulary.json")
SCENE = Path("claudeBlast/Resources/scenes/core_first.json")

# CDI wording → our key, where the mechanical rule cannot find it. Items mapped
# to None are placeholders a board cannot carry ("child's own name").
ALIASES = {
    "mommy*": "mom", "daddy*": "dad", "grandma*": "grandma", "grandpa*": "grandpa",
    "tv": "tv", "soda/pop": "soda", "potty": "toilet", "owie/boo boo": "hurt",
    "child's own name": None, "babysitter's name": None, "pet's name": None,
    "gonna get you!": None, "uh oh": "uh_oh", "all gone": "all_gone",
    "thank you": "thank_you", "night night": "night_night", "please": "please",
    "french fries": "french_fries", "ice cream": "ice_cream",
    "peanut butter": "peanut_butter", "potato chip": "chips",
    "high chair": "high_chair", "rocking chair": "rocking_chair",
    "washing machine": "washing_machine", "play dough": "playdoh",
    "teddybear": "teddy_bear", "lawn mower": "lawn_mower",
    "gas station": "gas_station", "living room": "living_room",
    "swimming pool": "pool", "pool": "pool",
    # Same word on the child's side, different wording on the form.
    "yum yum": "yummy", "night night": "goodnight", "all gone": "all_done",
    "kitty": "cat", "puppy": "dog", "go potty": "potty", "bath": "bathe",
    "french fries": "fries", "firetruck": "fire_truck", "beans": "green_beans",
    "wanna/want to": "want", "buttocks/bottom": "bottom", "shopping": "shop",
    "camping": "camp", "yard": "backyard", "fix": "fixed",
}


def candidates(definition: str) -> list[str]:
    d = definition.strip().lower().replace("*", "")
    if d in ALIASES:
        return [ALIASES[d]] if ALIASES[d] else []
    d = re.sub(r"\s*\(.*?\)", "", d).strip()
    if d in ALIASES:
        return [ALIASES[d]] if ALIASES[d] else []
    out = []
    for alt in d.split("/"):
        alt = alt.strip().replace(" ", "_")
        for a in dict.fromkeys([alt, alt.replace("'", "")]):
            out += [a, a + "s", a + "es"] + ([a[:-1]] if a.endswith("s") and len(a) > 3 else [])
    return out


def load():
    vocab = json.loads(VOCAB.read_text())
    keys = {v["key"] for v in vocab}
    labels = {v["label"].lower().replace(" ", "_"): v["key"] for v in vocab if v.get("label")}
    by_class = {v["key"]: v["wordClass"] for v in vocab}
    order = [v["key"] for v in vocab]
    scene = json.loads(SCENE.read_text())
    pages = defaultdict(list)
    for page in scene["pages"]:
        for cell in expand(page, by_class, order):
            if cell != "·":
                pages[cell.lstrip("→")].append(page["key"])
    rows = []
    for r in csv.DictReader(DATA.open()):
        key = None
        for c in candidates(r["item_definition"]):
            if c in keys:
                key = c
                break
            if c in labels:
                key = labels[c]
                break
        aoa = int(r["aoa_produces"]) if r["aoa_produces"] else None
        rows.append({**r, "aoa": aoa, "key": key or "",
                     "pages": ",".join(pages.get(key, [])) if key else ""})
    return rows


def band(aoa):
    if aoa is None or aoa > 30:
        return ">30"
    return "≤18" if aoa <= 18 else "19–24" if aoa <= 24 else "25–30"


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--missing", action="store_true")
    ap.add_argument("--csv")
    args = ap.parse_args()
    rows = load()

    if args.csv:
        with open(args.csv, "w", newline="") as f:
            fields = ["item_definition", "category", "aoa", "key", "pages"]
            w = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
            w.writeheader()
            w.writerows(sorted(rows, key=lambda r: (r["aoa"] or 99, r["item_definition"])))
        print(f"wrote {args.csv}")
        return

    if args.missing:
        for r in sorted(rows, key=lambda r: (r["aoa"] or 99, r["category"])):
            if not r["key"]:
                print(f"{r['aoa'] or '>30':>4}  {r['category']:<18} {r['item_definition']}")
        return

    have = sum(1 for r in rows if r["key"])
    print(f"CDI Words & Sentences (American English): {have}/{len(rows)} words in vocabulary\n")
    print("By age of acquisition (50% of children say it by):")
    for b in ["≤18", "19–24", "25–30", ">30"]:
        sub = [r for r in rows if band(r["aoa"]) == b]
        got = sum(1 for r in sub if r["key"])
        print(f"  {b:>6} months  {got:>3}/{len(sub):<3} ({100 * got // max(len(sub), 1)}%)")
    print("\nBy CDI category:")
    cats = defaultdict(list)
    for r in rows:
        cats[r["category"]].append(r)
    for cat, sub in sorted(cats.items(), key=lambda kv: -len(kv[1])):
        got = sum(1 for r in sub if r["key"])
        early = sorted((r for r in sub if not r["key"] and r["aoa"] and r["aoa"] <= 24),
                       key=lambda r: r["aoa"])
        tail = ", ".join(re.sub(r"\s*\(.*?\)", "", r["item_definition"]) for r in early[:8])
        print(f"  {cat:<18} {got:>3}/{len(sub):<3}  missing by 24 mo: {tail}")


if __name__ == "__main__":
    main()
