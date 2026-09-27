#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Decide what color every page link should be, and write it into the scene.

    python3 tools/resolve_link_colors.py            # show what would change
    python3 tools/resolve_link_colors.py --write    # write it
    python3 tools/resolve_link_colors.py --check    # fail if committed != computed

Idempotent. Touches `linkColor` on `link` commands and nothing else.

WHY THE COLORS ARE COMMITTED RATHER THAN COMPUTED ON DEVICE
-----------------------------------------------------------
A folder that changed color because a caregiver added three nouns to the page
behind it would be a moving target, and motor planning needs invariants — the
same argument that pins Home to cell 0. So the answer is worked out once, here,
and written into `core_first.json`; the app reads it and never recomputes.

The cost of committing a derived value is that it can go stale silently, which
is exactly the failure `check_tileset_drift.py` exists for on the art side. So
`--check` is the same idea: it recomputes and fails when the committed colors no
longer match, which puts the decision in front of a person instead of letting
the board quietly drift away from its own rule.

THE ALGORITHM, AND WHY IT IS NOT A PLAIN COUNT
-----------------------------------------------
Mirror of `LinkColorResolver.swift` — read that file for the full reasoning; the
short version is that nouns are 36% of the vocabulary and swamp a plain count,
so each part of speech's share of the destination page is divided by its share
of the whole vocabulary and the largest ratio wins. Two guards: a part of speech
under 15% of the page is noise (one `when` was painting Time purple), and a page
with fewer than 4 words is not evidence of anything (the `keyboard` placeholder).
A page that is mostly links is wayfinding.

TWO IMPLEMENTATIONS OF ONE RULE
-------------------------------
Swift needs it for in-app authoring; Python needs it because the bundled board
is resolved offline. Neither is trusted alone: `--check` fails when the
committed JSON disagrees with Python, and `LinkColorResolverTests` fails when it
disagrees with Swift. Both are pinned to the same committed artifact, so a
divergence cannot pass quietly.
"""

import argparse
import collections
import json
import sys
from pathlib import Path

VOCAB = Path("claudeBlast/Resources/vocabulary.json")
POS = Path("claudeBlast/Resources/parts_of_speech.json")
SCENES = Path("claudeBlast/Resources/scenes")

MIN_SHARE = 0.15
MIN_WORDS = 4
WAYFINDING = "wayfinding"


def load_parts():
    table = json.loads(POS.read_text())
    return {word: part for part, words in table.items() for word in words}


def page_tiles(page, vocab_by_class, vocab_order):
    """The words and links a page ends up holding, in DSL order.

    A trimmed-down `SceneMaterializer`: enough to count what is on a page, and
    deliberately not enough to build one. `remove` and `space` are honored
    because both change the count.
    """
    words, links = [], []
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
                if key not in words and key not in links:
                    words.append(key)
        elif "keys" in cmd:
            for key in cmd["keys"]:
                if key not in words and key not in links:
                    words.append(key)
        elif "link" in cmd:
            key = cmd["link"]
            if key in words:
                words.remove(key)
            if key not in links:
                links.append(key)
        elif "remove" in cmd:
            key = cmd["remove"]
            if key in words:
                words.remove(key)
            if key in links:
                links.remove(key)
        # `space` adds holes, which are not tiles and must not dilute the page.
    return words, links


def resolve(words, links, parts, background):
    if len(links) > len(words):
        return WAYFINDING

    counts = collections.Counter()
    for word in words:
        part = parts.get(word)
        if part:
            counts[part] += 1

    total = sum(counts.values())
    if total < MIN_WORDS:
        return WAYFINDING

    background_total = sum(background.values())
    if not background_total:
        return WAYFINDING

    ranked = []
    for part, count in counts.items():
        on_page = count / total
        if on_page < MIN_SHARE:
            continue
        overall = max(background.get(part, 1), 1) / background_total
        ranked.append((on_page / overall, part))

    if not ranked:
        return WAYFINDING
    # Highest lift wins; ties break on the raw name so both implementations and
    # every run agree. Dict order is not a decision.
    ranked.sort(key=lambda r: (-r[0], r[1]))
    return ranked[0][1]


def process(path, parts, vocab_by_class, vocab_order, background):
    scene = json.loads(path.read_text(), object_pairs_hook=collections.OrderedDict)
    pages = {p["key"]: p for p in scene["pages"]}
    changes, stale = [], []

    for page in scene["pages"]:
        for cmd in page["tiles"]:
            if "link" not in cmd:
                continue
            target = pages.get(cmd["to"])
            if target is None:
                continue  # check_scene.py owns that error
            words, links = page_tiles(target, vocab_by_class, vocab_order)
            computed = resolve(words, links, parts, background)
            current = cmd.get("linkColor")
            if current == computed:
                continue
            label = f'{page["key"]}/{cmd["link"]} -> {cmd["to"]}'
            if current in (None, "auto"):
                changes.append((cmd, computed, label, current))
            else:
                stale.append((cmd, computed, label, current))
    return scene, changes, stale


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="write the resolved colors")
    ap.add_argument("--check", action="store_true",
                    help="exit non-zero if any committed color is not what the rule says")
    args = ap.parse_args()

    if not VOCAB.exists():
        raise SystemExit(f"run from the repo root — {VOCAB} not found")

    parts = load_parts()
    vocab = json.loads(VOCAB.read_text())
    vocab_by_class = {t["key"]: t["wordClass"] for t in vocab}
    vocab_order = [t["key"] for t in vocab]
    background = collections.Counter(
        parts[t["key"]] for t in vocab if t["key"] in parts)

    failed = False
    for path in sorted(SCENES.glob("*.json")):
        scene, changes, stale = process(path, parts, vocab_by_class,
                                        vocab_order, background)
        if not changes and not stale:
            print(f"[ok] {path}")
            continue

        print(f"\n{path}")
        for _, computed, label, current in changes:
            was = "unset" if current is None else current
            print(f"  {label:44} {was:12} -> {computed}")
        for _, computed, label, current in stale:
            print(f"  {label:44} {current:12} != {computed}   <-- STALE")

        if args.check:
            failed = True
        elif args.write:
            for cmd, computed, _, _ in changes + stale:
                cmd["linkColor"] = computed
            path.write_text(json.dumps(scene, indent=2) + "\n")
            print(f"  written: {len(changes) + len(stale)} link(s)")

    if args.check and failed:
        print("\nCommitted link colors disagree with the rule that produced them.")
        print("Either re-run with --write, or say in the PR why the board is")
        print("deliberately ahead of its own algorithm.")
        sys.exit(1)
    if not args.write and not args.check:
        print("\n(dry run — pass --write to apply)")


if __name__ == "__main__":
    main()
