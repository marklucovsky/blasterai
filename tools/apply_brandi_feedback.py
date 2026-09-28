#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Three board changes from Brandi's review of the 2026-09-27 screenshots.

    python3 tools/apply_brandi_feedback.py [--write]

Idempotent. Touches the home page's word rows only — no links move, no cell is
added or removed, no color changes.

Brandi is the SLP whose client uses WordPower Basic 48 on TouchChat, and this is
the first feedback on the reworked board from someone who teaches one daily.

1. PRONOUN ORDER
----------------
    was          now
    he  i  me    i   me  my
    she my it    he  she it
    you your that you your that

Her words: *"Switch the order (horizontal order) to: I, me, my / He, she, it /
You, your, that."* The same six words, re-laid so each ROW is one person —
first, third, second — instead of each row mixing persons. `I/me/my` is also the
row a child uses first and is now the top-left corner, which is the easiest
reach on the board.

2. `finish` -> `read`
---------------------
A straight swap on the home page. `finish` stays reachable on `actions`, where
it lives by class; `read` was already there too and is now also top-level. Note
we chose `listen` over `read` in the original rework — this is not a reversal,
it is both.

3. `yes` AND `no` GET A GAP
---------------------------
*"We often see yes and no spaced away from each other so a miss hit isn't
accidental. So maybe swap either no and keyboard or no and stop."*

Taking the second: `yes | stop | no` rather than `yes | no | stop`. A mishit on
`yes` now lands on `stop`, not on its opposite — which is the actual failure
being designed against, and the wrong answer to "do you want this?" is the most
costly mistake this board can make.

Swapping `no` with `keyboard` was the other option offered and is not taken:
`keyboard` sits deliberately in the very last cell, and moving it would put a
folder in the middle of the pronoun block and cost the invariant position.
"""

import argparse
import collections
import json
from pathlib import Path

SCENE = Path("claudeBlast/Resources/scenes/core_first.json")

# (row index within the page's `keys` blocks, old row, new row)
PRONOUNS = {
    0: (["he", "i", "me"], ["i", "me", "my"]),
    1: (["she", "my", "it"], ["he", "she", "it"]),
}
SWAP_WORD = ("finish", "read")
SWAP_CELLS = ("no", "stop")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    if not SCENE.exists():
        raise SystemExit(f"run from the repo root — {SCENE} not found")

    scene = json.loads(SCENE.read_text(), object_pairs_hook=collections.OrderedDict)
    home = next(p for p in scene["pages"] if p["key"] == scene["homePageKey"])
    rows = [t for t in home["tiles"] if "keys" in t]
    changes = []

    # 1. Pronouns — rewrite the first three cells of the first two rows.
    for index, (was, now) in PRONOUNS.items():
        keys = rows[index]["keys"]
        if keys[:3] == now:
            continue
        if keys[:3] != was:
            raise SystemExit(f"row {index} starts {keys[:3]}, expected {was} — "
                             "the board moved under this script")
        keys[:3] = now
        changes.append(f"row {index + 1}: {' '.join(was)}  ->  {' '.join(now)}")

    # 2. finish -> read, wherever it sits.
    old, new = SWAP_WORD
    for row in rows:
        if old in row["keys"]:
            row["keys"][row["keys"].index(old)] = new
            changes.append(f"{old}  ->  {new}")

    # 3. Give yes and no a tile between them.
    a, b = SWAP_CELLS
    for row in rows:
        if a in row["keys"] and b in row["keys"]:
            i, j = row["keys"].index(a), row["keys"].index(b)
            if i < j:  # only swap while `no` is still the nearer one
                row["keys"][i], row["keys"][j] = row["keys"][j], row["keys"][i]
                changes.append(f"{a} <-> {b}  (yes and no are no longer neighbours)")

    if not changes:
        print("already applied")
        return

    for line in changes:
        print(f"  {line}")

    if not args.write:
        print("\n(dry run — pass --write to apply)")
        return

    SCENE.write_text(json.dumps(scene, indent=2) + "\n")
    print(f"\nwritten — {len(changes)} change(s)")


if __name__ == "__main__":
    main()
