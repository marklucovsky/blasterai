#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Add prompts for the Time vocabulary to tools/prompts.json. Idempotent.

    python3 tools/time_prompts.py [--force]

WHY TIME IS THE HARDEST BRIEF SO FAR
------------------------------------
Every other word on this board has a referent. A cow looks like a cow. None of
these do: `before`, `never` and `soon` are relations between events, and a
picture of a relation is a diagram rather than a likeness.

The AAC field solved this by convention rather than by depiction, and the
conventions are consistent enough across symbol sets to be worth following:

  - a CALENDAR row with one cell marked -> a named day (today/tomorrow/yesterday)
  - a CLOCK face with a region or hand marked -> a point or span (now/later/soon)
  - a LINE OF FIGURES with one indicated -> ordinal position (first/next/last)
  - a red X or slash over any of the above -> its negation (never)
  - SUN or MOON -> part of the day (morning/afternoon/night)

These are learned, not recognised, and that is fine — so is a red octagon
meaning stop. What matters is that the same visual language is used for every
word in the group, so learning one teaches the rest.

WHAT THE FIRST PASS GOT WRONG (2026-09-25 review)
-------------------------------------------------
All 22 generated cleanly and most were usable, but five faults were worth a
second pass, and four of them are the same mistake: **a family only teaches if
its members differ in exactly one thing.**

1. **The anchor moved.** today/tomorrow/yesterday each drew the red cell
   somewhere different, so "red" did not reliably mean *today* — the one thing
   the family exists to establish. The red cell is now fixed dead centre in all
   three and never moves; tomorrow and yesterday mark the cell to its right or
   left. Same calendar, one difference.

2. **before/after had no visible reference.** Two panels and an arrow left the
   reader working out which block was the fixed point. Three panels with the
   grey reference always in the MIDDLE makes it positional: before is the one
   on the left, after is the one on the right, and the middle never changes.

3. **first/next/last were four different drawings.** Different postures,
   different facings, different casts. Now: four identical figures, all facing
   right, only the target rendered as a real child and the rest flat grey
   silhouettes. The arrow and the colour move; nothing else does.

   The grey silhouettes are also a tone-chain decision. Only one figure carries
   skin, so only one region is a candidate for tone variants — which is what
   keeps these three tiles out of the failure mode where a tone pass repaints
   whatever is nearest the skin it found.

4. **week/weekend had five cells.** Seven now, Monday-first, which is what makes
   "the weekend is the last two" true rather than decorative.

5. **The sky tiles sat on a coloured panel.** Classic is a floating subject on
   plain white — `beach` and `park` keep white margins, and the `not` prompt
   spends a whole clause refusing panels. Those five now say so explicitly.
   `day` was also nearly identical to `afternoon`; it is now the bare sun disc
   with no landscape at all, and afternoon keeps the scene with a descending sun.

NO TEXT, EVER
-------------
Every prompt says "no text". This is a localisation rule, not an aesthetic one.
A drawn word is English baked into a bitmap, and `TileModel.key` is a
language-neutral concept id precisely so that translating a board never means
regenerating its art. A calendar whose cells are blank works in every language;
one reading "MON TUE WED" works in one. It is also why "week starts on Monday"
can only be expressed structurally — as *the last two cells are the weekend* —
rather than by labelling anything.
"""

import argparse
import json
from pathlib import Path

PROMPTS = Path("tools/prompts.json")

# Shared tail, matching the house style of every other entry in prompts.json.
TAIL = ("Flat illustration, white background, single clear subject centered, "
        "bold saturated colors, no text, square.")

# Classic floats its subject. Spelled out because the model reaches for a
# coloured backing shape whenever the subject is a scene rather than an object.
NO_PANEL = ("The subject floats directly on a plain pure white background: no panel, "
            "no card, no rounded rectangle, no coloured backing shape, no border, "
            "no frame of any kind behind it. ")

# The strip the whole day-family shares. The red square is TODAY and does not move.
#
# The word "calendar" is deliberately absent. Pass 2 said "a wall calendar with a
# grid of seven cells in a single horizontal row" and got a month grid three
# different times — the model's prior for *calendar* is a month page, and it wins
# over any instruction about rows. `sometimes` drew a clean row of four clocks
# without argument, so the shape is easy to get as long as nothing invokes the
# wrong object. Describing a strip of squares, and never naming it, is the fix.
CALENDAR = ("AAC pictogram: A horizontal strip of seven equal squares in one single row, joined "
            "edge to edge like a row of stamps, with bold dark outlines. Count them: there are "
            "seven squares, no more and no fewer, all in one row — it is a plain row of squares, "
            "not a calendar page and not a month grid. No numbers, no letters, no writing "
            "anywhere. The fourth square, in the exact middle of the row, is filled solid bright "
            "red. The strip floats on a plain pure white background with nothing behind it: no "
            "grey field, no shading, no surface, no shadow, no panel. ")


def _queue(arrangement):
    """One of first/next/last. Identical figures; only the marked one is a person.

    The line faces LEFT and the leftmost figure is FIRST, so the two readings
    agree: the head of the queue is also the start of the row in reading order.
    Facing right would have put the front of the queue at the right-hand end
    while `first` still had to be on the left, which asks a child to hold two
    opposite orderings at once.

    NO ARROW. Earlier passes put a coloured arrow above the target, and it
    landed over the wrong figure twice while the colouring itself was always
    correct. The arrow was never carrying meaning the colour did not already
    carry — one child among three grey silhouettes is unambiguous — so it was
    a second thing to get wrong in exchange for nothing. Dropping it also drops
    the last per-tile variable: these three now differ in exactly one respect,
    which is the property the whole set is built on.
    """
    # "Facing LEFT in profile" was not enough: `first` obeyed it and `next` and
    # `last` came back mirrored, which is invisible in a contact sheet and
    # obvious at full size. Naming the body parts and the edge they point at is
    # concrete where "profile" is abstract — the model can mirror a profile
    # without violating anything it was told, but it cannot put a nose against
    # the left edge and also face right.
    return ("AAC pictogram: Four identical simple humanoid figures standing in a straight "
            "horizontal row, evenly spaced, all the same height and the same posture, seen "
            "from the side. Every single figure faces the LEFT edge of the image: each one's "
            "nose, chin and the front of its face point LEFT, and the back of its head points "
            "RIGHT. All four look the same direction as each other — none of them is turned "
            "around. It is a queue whose front is at the left-hand end. Three of the four are "
            "plain solid grey silhouettes seen in strict side profile, each with a small nose "
            "bump on the LEFT side of its head so the direction it faces is unmistakable, but "
            "with no eyes, no mouth, no hair and no skin colour. The four figures stand WELL "
            "APART from each other, spread evenly across the full width of the image, with a "
            "wide empty gap between each pair about as wide as a figure itself — they are "
            "clearly separated, never touching, never overlapping and never standing behind "
            "one another. One "
            "single figure is drawn as a real child, with skin, hair, a face and colourful "
            f"clothes, and its nose points LEFT exactly like the others. {arrangement} There "
            "are no arrows, no pointers, no markers and no highlights anywhere in the "
            "image. ") + TAIL


TIME_PROMPTS = {
    # --- calendar convention: a named day. Red = today, fixed centre. ---
    "today": CALENDAR + "The other six squares are plain white and nothing else is marked. " + TAIL,
    # Two lessons, both learned the expensive way.
    #
    # ADJACENCY IS A SHAPE, NOT AN INDEX. "The fifth square, the one directly
    # touching the red square" left a white gap twice: indices and
    # neighbour-relations both ask the model to count, and it does not. Naming
    # the coloured pair as one unit — an adjacent pair sitting in the strip —
    # worked first try.
    #
    # LENGTH COSTS THE BACKGROUND. That fix arrived on a grey field, twice,
    # despite carrying the same "no grey, no shading" clause that keeps `today`
    # clean. The clause is not weak; the prompt around it got long, and the
    # trailing clauses stopped landing. Short, with the white stated first, is
    # what holds. Every clause added here is paid for somewhere else.
    # Both halves FILLED, so the pair is one two-tone block rather than a fill
    # beside an outline. An outlined neighbour still reads as a separate
    # annotation and the model kept floating it one square away; two solid
    # colours meeting at an edge is a single shape, and it stops drifting.
    # Red is today in both, so the second colour is always the day being named.
    "tomorrow": ("AAC pictogram: On a pure white background, a horizontal row of seven equal "
        "white squares with bold black outlines, joined edge to edge. In the middle of the row, "
        "two neighbouring squares share an edge and form one two-colour block: its left half is "
        "solid bright red and its right half, touching it, is solid bright green. A bright green "
        "arrow above points right, from the red square to the green one. No numbers, no "
        "letters. ") + TAIL,
    "yesterday": ("AAC pictogram: On a pure white background, a horizontal row of seven equal "
        "white squares with bold black outlines, joined edge to edge. In the middle of the row, "
        "two neighbouring squares share an edge and form one two-colour block: its right half is "
        "solid bright red and its left half, touching it, is solid bright blue. A bright blue "
        "arrow above points left, from the red square to the blue one. No numbers, no "
        "letters. ") + TAIL,
    "week": ("AAC pictogram: A horizontal strip of exactly seven equal plain white squares in one "
        "single row, joined edge to edge like a row of stamps, with bold dark outlines, and the "
        "whole strip enclosed together inside one thick bright blue rounded outline. It is a "
        "plain row of seven squares, not a calendar page, not a month grid, and there is never "
        "more than one row. No numbers, no letters, no writing anywhere. ") + TAIL,
    "weekend": ("AAC pictogram: A horizontal strip of seven equal squares in one single row, "
        "joined edge to edge like a row of stamps, with bold dark outlines. Count them: there "
        "are seven squares, no more and no fewer, all in one row. The first five squares from "
        "the left are plain white. The last TWO squares — both of them, the sixth and the "
        "seventh, the pair at the right-hand end — are filled solid bright orange. Two orange "
        "squares side by side, not one. It is a plain row of squares, not a calendar page and "
        "not a month grid. No numbers, no letters, no writing anywhere. The strip floats on a "
        "plain pure white background with nothing behind it. ") + TAIL,

    # --- clock convention: a point or span (unchanged — these worked) ---
    "time": "AAC pictogram: A single large round analog clock face with a thick dark outline, bold black hour and minute hands, and plain tick marks around the edge. No numerals, no letters, no writing. " + TAIL,
    "now": "AAC pictogram: A single large round analog clock face with plain tick marks and no numerals, with a bright red downward-pointing triangular marker resting directly on top of the clock pointing at it, emphasising this exact moment. " + TAIL,
    "later": "AAC pictogram: A single large round analog clock face with plain tick marks and no numerals, with a thick bright blue arrow curving clockwise around the outside of the clock from the top around to the right side, indicating time moving forward. " + TAIL,
    "soon": "AAC pictogram: A single large round analog clock face with plain tick marks and no numerals, with a short thick bright green arrow curving clockwise around the outside of the clock covering only a small arc near the top, indicating a brief wait. " + TAIL,
    "always": "AAC pictogram: A single large round analog clock face with plain tick marks and no numerals, with a thick bright green arrow forming a complete unbroken circle all the way around the outside of the clock, ends meeting, indicating every time without exception. " + TAIL,
    "never": "AAC pictogram: A single large round analog clock face with plain tick marks and no numerals, with a thick bright red circle-and-diagonal-slash prohibition symbol drawn boldly over the top of the clock. " + TAIL,
    "sometimes": "AAC pictogram: A horizontal row of four round analog clock faces with plain tick marks and no numerals, all the same size, where the first and the third from the left are filled solid bright green and the other two are plain white. " + TAIL,

    # --- sequence: three panels, grey reference always in the middle ---
    "before": ("AAC pictogram: Three plain square outlined panels in a horizontal row, evenly "
        "spaced and identical in size, joined by thin grey arrows pointing left to right. The "
        "MIDDLE panel contains a plain grey cube and is the reference point. The LEFT panel "
        "contains a solid bright red ball and is outlined in thick bright red. The RIGHT panel "
        "is empty and plain. ") + TAIL,
    "after": ("AAC pictogram: Three plain square outlined panels in a horizontal row, evenly "
        "spaced and identical in size, joined by thin grey arrows pointing left to right. The "
        "MIDDLE panel contains a plain grey cube and is the reference point. The RIGHT panel "
        "contains a solid bright red ball and is outlined in thick bright red. The LEFT panel "
        "is empty and plain. ") + TAIL,

    # --- ordinal: one line, one difference ---
    # `first` is the only one of the three that is generated. `next` and `last`
    # are composed from it:
    #
    #     python3 tools/review_tiles.py regen --set classic     # if `first` changed
    #     python3 tools/compose_queue.py --set classic          # rebuilds both
    #
    # Their prompts below are kept as the specification — they say what each tile
    # must look like — but running them does not produce these tiles.
    "first": _queue("The child stands at the far LEFT end of the row, and all three grey silhouettes stand to its right."),

    # `next` generated *correctly* and was still replaced. The drawing was right:
    # four left-facing figures, child second. But it came back with a black-haired
    # child and heavier outlines than `first`, so the two tiles read as two
    # illustrations of a similar idea rather than one idea in two positions. On a
    # board teaching that only position carries meaning, every other difference is
    # noise competing with the signal.
    "next": _queue("Exactly ONE grey silhouette stands to the left of the child, and TWO grey silhouettes stand to its right, so the child is the second figure in the row."),

    # `last` never generated correctly at all. Five attempts:
    #
    #   - asked for a left-facing line with the child at the right end, the model
    #     returned an entirely RIGHT-facing line, three times, twice on a grey field;
    #   - asked for the mirror image (child at the left end, everyone facing right)
    #     intending to flip it, the grey silhouettes stayed LEFT-facing while only
    #     the child turned — so the flip gave three figures facing one way and the
    #     child facing the other.
    #
    # That last failure is the diagnosis: the grey figures have a hard default
    # toward facing left and ignore instructions against it, while the coloured
    # child complies. Any prompt asking for a right-facing line therefore yields a
    # disagreement, and mirroring cannot repair one — a horizontal flip preserves
    # *relative* orientation.
    #
    # `first` already contains four correctly-facing figures with the child among
    # them, so moving that child to the end of the row is an image operation, not a
    # drawing problem. Composing it also makes the two tiles share pixels, so the
    # figures are identical rather than merely similar — better than a successful
    # generation would have been.
    "last": _queue("The child stands at the far RIGHT end of the row, and all three grey silhouettes stand to its left."),

    # --- sun and moon: no panel, and day is not afternoon ---
    # Object plus marker, never a scene. Pass 2 asked for a sun "above a strip of
    # ground" and got an olive-black field behind it: drop the panel and the model
    # supplies atmosphere instead, because a horizon implies a sky to fill. `day`
    # and `night` came back clean in that same pass precisely because they name no
    # scene at all, so these now borrow the clock family's grammar — one object,
    # one marker, nothing else in the frame.
    "morning": ("AAC pictogram: A bright yellow sun with bold triangular rays, with a thick "
        "bright green arrow beside it pointing straight UP to show the sun rising. There is no "
        "sky, no ground, no horizon, no clouds and no landscape at all — only the sun and the "
        "arrow. " + NO_PANEL) + TAIL,
    "afternoon": ("AAC pictogram: A bright yellow sun with bold triangular rays, with a thick "
        "bright orange arrow beside it pointing straight DOWN to show the sun going down. There "
        "is no sky, no ground, no horizon, no clouds and no landscape at all — only the sun and "
        "the arrow. " + NO_PANEL) + TAIL,
    "night": ("AAC pictogram: A white crescent moon with three small yellow four-pointed stars "
        "around it. There is no sky, no ground, no horizon and no landscape at all — only the "
        "moon and the stars. " + NO_PANEL) + TAIL,
    "tonight": ("AAC pictogram: A white crescent moon with three small yellow four-pointed "
        "stars around it, and a bright red downward-pointing triangular marker directly above "
        "the moon. There is no sky, no ground, no horizon and no landscape at all — only the "
        "moon, the stars and the red marker. " + NO_PANEL) + TAIL,
    "day": ("AAC pictogram: One single large bright yellow sun disc with bold evenly-spaced "
        "triangular rays radiating all the way around it. There is no sky, no ground, no "
        "horizon, no clouds and no landscape at all — only the sun. " + NO_PANEL) + TAIL,
}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--force", action="store_true",
                    help="overwrite prompts that already exist")
    args = ap.parse_args()

    if not PROMPTS.exists():
        raise SystemExit(f"run from the repo root — {PROMPTS} not found")

    prompts = json.loads(PROMPTS.read_text())
    added = skipped = replaced = 0
    for key, text in TIME_PROMPTS.items():
        if key in prompts and not args.force:
            skipped += 1
            continue
        replaced += key in prompts
        added += key not in prompts
        prompts[key] = text

    PROMPTS.write_text(json.dumps(dict(sorted(prompts.items())), indent=2,
                                  ensure_ascii=False) + "\n")
    print(f"prompts.json: +{added} added, {replaced} replaced, {skipped} already present "
          f"-> {len(prompts)} total")


if __name__ == "__main__":
    main()
