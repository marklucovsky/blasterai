#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Find tile art with a frame or border baked into the image.

Every shipped tile is meant to be a single subject on a field that bleeds to all
four edges — `Resources/image_styles.json` says so in the generation prompt, at
length. Art generated before that wording was tightened can carry its own drawn
box, which renders as a frame inside the card's frame. It is most obvious in
print, where the card border makes the doubling explicit, but it is wrong on
screen too. `cls_help` is the one that was caught by eye; this exists because the
eye is not a search.

## How it decides

A frame is a *closed dark line*, so the test walks square rings inward from the
edge and measures what fraction of each ring is dark. A tile is flagged when

    some ring is almost entirely dark  AND  some ring is almost entirely light.

Both halves are load-bearing, and each one alone gives a wrong answer:

* **Dark ring alone** flags every full-bleed illustration. `cls_silver` (charcoal
  background) and `cls_cloud` (flat blue, which lands just under the luma
  threshold) are dark at *every* inset and are perfectly fine. Requiring a light
  ring somewhere excludes them, because a full bleed never has one.
* **A light ring alone** says nothing at all.

The two frame shapes both satisfy it, which is why the rule is written this way
rather than as "is the outermost ring dark":

* `cls_help` — a 1px black line at inset 0, white from inset 1 in.
* `cls_ocean`, `cls_dark`, `cls_tornado` — a white margin, then a rounded black
  border 25–35px in, then a full-bleed scene inside it.

**Do not downscale before measuring.** A 1px frame disappears under any
resampling, which is how `cls_help` — the tile that prompted this — survived the
first version of this audit unflagged.

Run from the repository root:

    python3 tools/audit_tile_frames.py            # every shipped set
    python3 tools/audit_tile_frames.py cls        # one shipped set
    python3 tools/audit_tile_frames.py tools/tile_sets/classic   # masters, pre-encode

Exits non-zero if anything is flagged.
"""

import os
import subprocess
import sys
import tempfile

from PIL import Image

ART = "claudeBlast/TileImageSets"

# A ring this dark is a drawn line or a filled background, not a subject that
# happens to reach the edge. `cls_eat`'s pizza tops out at 66%, so there is
# real margin here, but not an enormous amount — widen with care.
DARK_RING = 0.80
# A ring this light is paper. Its existence anywhere is what separates a framed
# tile from an honest full-bleed one.
LIGHT_RING = 0.20
# Luma below this reads as ink rather than paper.
DARK_LUMA = 140
# Frames live near the edge. 15% is past the widest border observed (~7%).
MAX_INSET = 0.15
# Sample every other pixel around each ring: a closed line is not subtle, and
# this halves an already O(insets x perimeter) scan.
STRIDE = 2


def ring_darkness(px, w: int, h: int, inset: int) -> float:
    """Fraction of the square ring at `inset` pixels that is dark."""
    values = [px[x, inset] for x in range(inset, w - inset, STRIDE)]
    values += [px[x, h - 1 - inset] for x in range(inset, w - inset, STRIDE)]
    values += [px[inset, y] for y in range(inset, h - inset, STRIDE)]
    values += [px[w - 1 - inset, y] for y in range(inset, h - inset, STRIDE)]
    if not values:
        return 0.0
    return sum(1 for v in values if v < DARK_LUMA) / len(values)


def frame_inset(path: str) -> int | None:
    """Inset of the baked frame, or None if the tile is clean."""
    img = Image.open(path).convert("L")
    w, h = img.size
    px = img.load()
    profile = [ring_darkness(px, w, h, d)
               for d in range(int(min(w, h) * MAX_INSET))]
    if not profile:
        return None
    darkest = max(profile)
    if darkest >= DARK_RING and min(profile) <= LIGHT_RING:
        return profile.index(darkest)
    return None


def audit_directory(directory: str) -> list[tuple[str, int]]:
    """Check a directory of PNG masters, pre-encode.

    The point of gating here rather than only on the bundle is that a frame
    should be caught before it is optimized, synced and committed.
    """
    names = sorted(n for n in os.listdir(directory) if n.endswith(".png"))
    if not names:
        sys.exit(f"no .png in {directory}")
    print(f"checking {len(names)} masters in {directory}…", flush=True)
    return [(n, i) for n in names
            if (i := frame_inset(f"{directory}/{n}")) is not None]


def audit_bundle(prefix: str | None) -> list[tuple[str, int]]:
    """Check the shipped HEIC set, converting through sips to read it."""
    names = sorted(
        n for n in os.listdir(ART)
        if n.endswith(".heic") and (prefix is None or n.startswith(f"{prefix}_"))
    )
    if not names:
        sys.exit(f"no art found for {prefix!r} in {ART}")

    flagged = []
    with tempfile.TemporaryDirectory() as tmp:
        print(f"converting {len(names)} images…", flush=True)
        subprocess.run(
            ["sips", "-s", "format", "png", *[f"{ART}/{n}" for n in names],
             "--out", tmp],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        for i, name in enumerate(names, 1):
            png = f"{tmp}/{name[: -len('.heic')]}.png"
            if not os.path.exists(png):
                continue
            inset = frame_inset(png)
            if inset is not None:
                flagged.append((name, inset))
            if i % 250 == 0:
                print(f"  {i}/{len(names)}", flush=True)
    return flagged


def main() -> int:
    argument = sys.argv[1] if len(sys.argv) > 1 else None
    if argument and os.path.isdir(argument):
        flagged = audit_directory(argument)
        names = os.listdir(argument)
    else:
        flagged = audit_bundle(argument)
        names = [n for n in os.listdir(ART) if n.endswith(".heic")
                 and (argument is None or n.startswith(f"{argument}_"))]

    print(f"\nframed ({len(flagged)} of {len(names)}):")
    for name, inset in sorted(flagged):
        print(f"  {name:28} border at inset {inset}px")
    if not flagged:
        print("  none")
    return 1 if flagged else 0


if __name__ == "__main__":
    sys.exit(main())
