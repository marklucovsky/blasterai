#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Measure the skin tone a tile actually uses, and compare it to the emoji reference.

## Why measure rather than look

"Is medium too dark?" is not answerable by eye across 255 tiles, and the whole
point of naming the tones after emoji modifiers is that a caregiver already knows
what those look like. So the target is objective: the colours Apple actually
renders for U+1F3FB..U+1F3FF, sampled from the system emoji font (they display as
solid swatches when standalone).

## How skin pixels are found

For a *variant*, by diffing against the Classic original: the pixels the model
changed ARE the skin. This needs no hue heuristic, which matters because Classic's
skin band overlaps bread, wood and sand — the reason a range-based recolour was
rejected in the first place.

For an *original* (no variant to diff against), by a deliberately tight skin
gamut. Less precise, and used only to answer the coarse question "is the existing
set uniform or diverse", never to drive a recolour.

Usage:
    python3 tools/measure_skin_tone.py --variants                  # pilot vs reference
    python3 tools/measure_skin_tone.py --variants --tiles mom
    python3 tools/measure_skin_tone.py --uniformity                # is Classic uniform?
"""

import argparse
import collections
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

BASE = Path("tools/tile_sets")
SOURCE = BASE / "classic"
SKIN_CACHE = BASE / "classic_skin_tiles.json"
EMOJI_FONT = "/System/Library/Fonts/Apple Color Emoji.ttc"

TONE_ORDER = ["light", "medium_light", "medium", "medium_dark", "dark"]
TONE_CHAR = {
    "light": "\U0001F3FB", "medium_light": "\U0001F3FC", "medium": "\U0001F3FD",
    "medium_dark": "\U0001F3FE", "dark": "\U0001F3FF",
}
# Fallback if the emoji font can't be read; these are what it renders on macOS.
FALLBACK_REF = {
    "light": (250, 220, 188), "medium_light": (224, 187, 149),
    "medium": (191, 143, 104), "medium_dark": (155, 100, 61), "dark": (89, 69, 57),
}


def luma(c) -> float:
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]


def emoji_reference() -> dict:
    """Sample the real swatches from the system emoji font."""
    try:
        font = ImageFont.truetype(EMOJI_FONT, 96)
    except Exception:
        return dict(FALLBACK_REF)
    out = {}
    for tone, ch in TONE_CHAR.items():
        try:
            im = Image.new("RGB", (136, 136), "white")
            ImageDraw.Draw(im).text((10, 10), ch, font=font, embedded_color=True)
            c = collections.Counter(im.getdata())
            top = [col for col, _ in c.most_common(6)
                   if col != (255, 255, 255) and col != (204, 204, 204)]
            out[tone] = top[0] if top else FALLBACK_REF[tone]
        except Exception:
            out[tone] = FALLBACK_REF[tone]
    return out


def modal_changed_colour(orig: Path, variant: Path, step: int = 3):
    """Dominant colour among pixels the refine actually changed."""
    o = Image.open(orig).convert("RGB")
    v = Image.open(variant).convert("RGB")
    if o.size != v.size:
        v = v.resize(o.size, Image.LANCZOS)
    op, vp = o.load(), v.load()
    w, h = o.size
    c = collections.Counter()
    for y in range(0, h, step):
        for x in range(0, w, step):
            a, b = op[x, y], vp[x, y]
            if sum(abs(a[i] - b[i]) for i in range(3)) < 40:
                continue
            # Skip outlines and paper — neither is skin, and both move slightly.
            if sum(b) < 120 or sum(b) > 720:
                continue
            c[(b[0] // 8 * 8, b[1] // 8 * 8, b[2] // 8 * 8)] += 1
    if not c:
        return None, 0
    col, n = c.most_common(1)[0]
    return col, n


def dominant_skin_gamut(path: Path, step: int = 3):
    """Dominant colour within a tight skin gamut. Coarse — see module doc."""
    im = Image.open(path).convert("RGB")
    p = im.load()
    w, h = im.size
    c = collections.Counter()
    for y in range(0, h, step):
        for x in range(0, w, step):
            r, g, b = p[x, y]
            if not (60 < r < 260 and 40 < g < 210 and 30 < b < 190):
                continue
            if not (r > g > b):                      # skin is red>green>blue
                continue
            if r - b < 25 or r - b > 130:            # too grey, or too saturated
                continue
            if sum((r, g, b)) > 700:
                continue
            c[(r // 8 * 8, g // 8 * 8, b // 8 * 8)] += 1
    if not c:
        return None, 0
    return c.most_common(1)[0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variants", action="store_true")
    ap.add_argument("--uniformity", action="store_true")
    ap.add_argument("--tiles", default="")
    args = ap.parse_args()

    ref = emoji_reference()
    print("Emoji reference (sampled from Apple Color Emoji):")
    for t in TONE_ORDER:
        c = ref[t]
        print(f"  {TONE_CHAR[t]} {t:13} rgb{c}  #{c[0]:02X}{c[1]:02X}{c[2]:02X}  luma {luma(c):5.1f}")
    print()

    if args.variants:
        tones = [t for t in TONE_ORDER if (BASE / f"classic_{t}").exists()]
        for tone in tones:
            d = BASE / f"classic_{tone}"
            keys = ([k.strip() for k in args.tiles.split(",") if k.strip()]
                    or sorted(p.stem for p in d.glob("*.png")))
            r = ref[tone]
            print(f"--- classic_{tone}   target rgb{r} luma {luma(r):.1f}")
            for k in keys:
                v = d / f"{k}.png"
                o = SOURCE / f"{k}.png"
                if not (v.exists() and o.exists()):
                    continue
                col, n = modal_changed_colour(o, v)
                if not col:
                    print(f"    {k:8} no changed pixels found")
                    continue
                dl = luma(col) - luma(r)
                verdict = "TOO DARK" if dl < -12 else "too light" if dl > 12 else "on target"
                print(f"    {k:8} rgb{col} luma {luma(col):5.1f}  Δluma {dl:+6.1f}  {verdict}")
            print()

    if args.uniformity:
        if not SKIN_CACHE.exists():
            raise SystemExit("run build_tone_variants.py --classify first")
        cache = json.loads(SKIN_CACHE.read_text())
        people = sorted(k for k, v in cache.items() if v)
        print(f"Sampling existing Classic skin colour across {len(people)} tiles with people…")
        lumas, samples = [], []
        for k in people:
            p = SOURCE / f"{k}.png"
            if not p.exists():
                continue
            col, n = dominant_skin_gamut(p)
            if col and n > 40:
                lumas.append(luma(col))
                samples.append((k, col, luma(col)))
        if not lumas:
            raise SystemExit("no samples")
        lumas.sort()
        n = len(lumas)
        print(f"  usable samples: {n}")
        print(f"  luma  min {lumas[0]:.1f}  p10 {lumas[n//10]:.1f}  median {lumas[n//2]:.1f}"
              f"  p90 {lumas[9*n//10]:.1f}  max {lumas[-1]:.1f}")
        band = lumas[9*n//10] - lumas[n//10]
        gap = luma(ref["light"]) - luma(ref["medium"])
        print(f"  p10–p90 spread: {band:.1f} luma")
        print(f"  one emoji band (light→medium) spans: {gap:.1f} luma")
        print(f"  → Classic is {'DIVERSE — spans more than an emoji band' if band > gap else 'broadly UNIFORM — within one emoji band'}")
        samples.sort(key=lambda s: s[2])
        print("\n  darkest:", ", ".join(f"{k}({l:.0f})" for k, _, l in samples[:6]))
        print("  lightest:", ", ".join(f"{k}({l:.0f})" for k, _, l in samples[-6:]))


if __name__ == "__main__":
    main()
