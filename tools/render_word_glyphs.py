#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Draw the text-only tiles for function words: a, the, and, is, at.

    python3 tools/render_word_glyphs.py --sets classic,playful_3d,high_contrast

WHY TEXT AND NOT A PICTURE
--------------------------
These five have no referent. `the` is not a thing, and a picture of it is a
convention with nothing underneath — a reader either already knows what the
symbol stands for or learns nothing from looking at it.

The field is split on this and the split is informative. ARASAAC draws all of
them; measured on `vocal-flair-40.obz`, only one word in the entire 96-board set
had no symbol. But **WordPower Basic 48 — the vocabulary on the child this
project is built for — renders `a`, `the`, `is`, `to`, `can`, `do`, `have`,
`and`, `with` and `for` as plain text**, no symbol at all, while giving symbols
to everything concrete beside them. The largest installed base in this space
decided the picture was not worth drawing, and the SLP reading our board is
fluent in that convention.

So: text, set large, in the tile's own colour. Rendered rather than generated
for the same reason `GlyphTile` draws letters and `render_strips.py` draws day
strips — a glyph from a font is exact, identical across sets, and free.

THE LOCALISATION CONSTRAINT, STATED PLAINLY
-------------------------------------------
**These are the only tiles in the app whose art contains a word.** Everything
else is a language-neutral picture, which is what lets `TileModel.key` stay a
concept id that is never translated: a drawing of a cow is a cow in every
language, so a translated board reuses every existing image.

These five cannot do that. A tile reading "the" is English art, and a Spanish
board needs "el" drawn instead. That is survivable precisely because they are
*rendered*: this script takes the word to draw as data, so a language variant is
a config change and a re-run, not 5 × N images to regenerate. It is not
survivable if anyone ever generates these instead — then the English is baked
into a render nobody can reproduce.

If the app later grows runtime text tiles — drawing `TileModel.value` at display
time rather than shipping a PNG — that is strictly better and these become
unnecessary. The reason not to do it today is that every export path (PDF
board, OBF, tile-image export) asks `TileImageResolver` for pixels, so a runtime
text tile needs a rasteriser on that path too.
"""

import argparse
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("pip install pillow")

SIZE = 1024

# key -> the word to draw. Separate from the key on purpose: the key is a
# language-neutral concept id, the word is what a reader sees, and only the
# second one changes when a board is translated.
WORDS = {
    "a": "a",
    "the": "the",
    "and": "and",
    "is": "is",
    "at": "at",
    # The rest of `be`, added 2026-10-12 after Brandi asked where "am" was.
    "am": "am",
    "are": "are",
    "was": "was",
    # Session 14 word pass. Text only where the word's home page is mostly
    # text or it belongs to a text family (Mark, 2026-10-25): `an` sits with
    # `a` and `the`. Every other new small word is a picture, because the pages
    # around it are pictures; the months are render_months.py's calendar pages.
    "an": "an",
}

# The words that set the shared point size. Frozen at the original five on
# purpose: `was` is wider than `and`, so letting it vote would shrink every
# glyph already shipped and re-render art nobody asked to change. At this
# size `was` still fits with a margin (about 76% of the tile's width).
SIZING_WORDS = ["a", "the", "and", "is", "at"]

# EMPTY, and `keyboard` is the reason it exists as a concept at all.
#
# That tile was briefly drawn here as "ABC", following WordPower Basic 48's
# label for the cell. Vocal Flair draws a keyboard instead, and on this one the
# picture is the better answer: a keyboard is the same object in every language,
# where "ABC" is Latin script and would need redrawing for any board that is
# not. Since the whole reason the function words are rendered rather than
# generated is that they are the *only* tiles carrying a word, adding a sixth
# for something that has a perfectly good picture works against that.
#
# `keyboard` is therefore generated like any other object tile, from a prompt in
# tools/prompts.json that insists the keys are blank. Kept here as an empty dict
# so the distinction is recorded rather than rediscovered.
LINK_GLYPHS: dict[str, str] = {}

STYLES = {
    "classic":       dict(bg=(255, 255, 255), ink=(17, 17, 17)),
    # The skin-tone sets ship as complete sets of their own, and a word has no
    # skin, so they carry Classic's glyph unchanged.
    "classic_chain_medium":      dict(bg=(255, 255, 255), ink=(17, 17, 17)),
    "classic_chain_medium_dark": dict(bg=(255, 255, 255), ink=(17, 17, 17)),
    "high_contrast": dict(bg=(0, 0, 0), ink=(255, 255, 255)),
    # `high_contrast_v2` is the set that actually SHIPS as `hc` — see
    # SET_PREFIX in sync_to_app.py. The unversioned folder beside it is the
    # earlier generation and reaches no device. Both are listed because the
    # older one is still reviewed, but v2 is the one that matters.
    "high_contrast_v2": dict(bg=(0, 0, 0), ink=(255, 255, 255)),
    "playful_3d":    dict(bg=(255, 255, 255), ink=(92, 64, 43)),
}

FONT_CANDIDATES = [
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
]


def load_font(size):
    for path in FONT_CANDIDATES:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def shared_font_size(words, target_width, probe):
    """One point size for the whole set, chosen by the widest word.

    Fitting each word to the tile individually — which is what `GlyphTile` does
    for single letters, and what this did first — makes the letterforms
    different sizes on every tile: `a` filled the cell while `and` and `the`
    came out half the height. On a board the four sit side by side, so that
    reads as four different typefaces rather than one set.

    A letter tile can be fitted individually because every tile holds exactly
    one character. A word tile cannot. So the widest word sets the size and the
    rest inherit it, which keeps the cap height identical across all of them.
    """
    size = 10
    while size < SIZE:
        nxt = load_font(size + 6)
        widest = max(probe.textbbox((0, 0), w, font=nxt)[2]
                     - probe.textbbox((0, 0), w, font=nxt)[0] for w in words)
        tallest = max(probe.textbbox((0, 0), w, font=nxt)[3]
                      - probe.textbbox((0, 0), w, font=nxt)[1] for w in words)
        if widest > target_width or tallest > SIZE * 0.42:
            break
        size += 6
    return size


# The widest a line may run before it shrinks: `another`, `September`.
MAX_LINE = 0.86


def fitted(word, size, probe):
    """The lines to draw and the size to draw them at.

    A word that fits at the set's size keeps it, so `of` and `the` match. A
    phrase that does not fit on one line breaks at its space (`never / mind`)
    and keeps the size if both halves fit. Only then does it shrink, and only as
    far as it must: a long month is smaller than `May`, never larger.
    """
    def width(text, pt):
        f = load_font(pt)
        b = probe.textbbox((0, 0), text, font=f)
        return b[2] - b[0]

    def shrink(lines, pt):
        while pt > 40 and max(width(l, pt) for l in lines) > SIZE * MAX_LINE:
            pt -= 6
        return pt

    if width(word, size) <= SIZE * MAX_LINE:
        return [word], size
    one = shrink([word], size)
    if " " not in word:
        return [word], one
    # A phrase takes whichever layout draws it larger: `never mind` reads
    # better as two big lines than as one small one.
    lines = word.split(" ", 1)
    two = shrink(lines, size)
    return (lines, two) if two > one else ([word], one)


def render(word, style, size):
    s = STYLES[style]
    img = Image.new("RGB", (SIZE, SIZE), s["bg"])
    draw = ImageDraw.Draw(img)
    lines, size = fitted(word, size, draw)
    font = load_font(size)
    if len(lines) == 2:
        ascent, descent = font.getmetrics()
        line_h = ascent + descent
        top = (SIZE - 2 * line_h) / 2
        for i, line in enumerate(lines):
            box = draw.textbbox((0, 0), line, font=font)
            draw.text(((SIZE - (box[2] - box[0])) / 2 - box[0], top + i * line_h), line,
                      font=font, fill=s["ink"])
        return img

    # Centred on the FONT's vertical metrics, not on the word's own ink box.
    # Centring by ink puts `a` (no ascender, no descender) visually higher than
    # `the`, so a row of them sits on no common baseline. Using ascent and
    # descent gives every word the same baseline, which is what makes four
    # tiles read as one set.
    ascent, descent = font.getmetrics()
    box = draw.textbbox((0, 0), word, font=font)
    x = (SIZE - (box[2] - box[0])) / 2 - box[0]
    y = (SIZE - (ascent + descent)) / 2
    draw.text((x, y), word, font=font, fill=s["ink"])
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--sets", default=",".join(STYLES))
    ap.add_argument("--keys", default="",
                    help="comma-separated keys to draw (default: all). Drawing only "
                         "new words leaves existing masters untouched, so the drift "
                         "check doesn't see them as changed.")
    ap.add_argument("--out-root", default="tools/tile_sets",
                    help="write <out-root>/<set>/<key>.png; a staging folder for review")
    args = ap.parse_args()
    only = {k.strip() for k in args.keys.split(",") if k.strip()}
    if only - set(WORDS):
        sys.exit(f"unknown key(s): {', '.join(sorted(only - set(WORDS)))}")

    for style in [s.strip() for s in args.sets.split(",") if s.strip()]:
        if style not in STYLES:
            sys.exit(f"unknown set {style!r}; known: {', '.join(STYLES)}")
        out = Path(args.out_root) / style
        out.mkdir(parents=True, exist_ok=True)
        probe = ImageDraw.Draw(Image.new("RGB", (SIZE, SIZE)))
        size = shared_font_size([WORDS[k] for k in SIZING_WORDS], SIZE * 0.74, probe)
        for key, word in WORDS.items():
            if only and key not in only:
                continue
            render(word, style, size).save(out / f"{key}.png")
            print(f"✓ {style}/{key}.png  ({word!r}, {size}pt)")
        for key, word in LINK_GLYPHS.items():
            if only and key not in only:
                continue
            own = shared_font_size([word], SIZE * 0.74, probe)
            render(word, style, own).save(out / f"{key}.png")
            print(f"✓ {style}/{key}.png  ({word!r}, {own}pt)")


if __name__ == "__main__":
    main()
