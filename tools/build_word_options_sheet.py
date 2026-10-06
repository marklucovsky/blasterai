#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""A printable cut sheet of the abstract words and the ways we could draw them.

    python3 tools/build_word_options_sheet.py --arasaac DIR --out options.pdf

For an advisor's review (Brandi, first): one row per word, one column per
option, so the choice is made by looking rather than by reading a proposal.

    shipped        what the app shows today, if anything
    new picture    a generated candidate, where one exists
    text           the word itself, set large — the WordPower convention
    symbol         a drawn mark or glyph (because / but, one)
    ARASAAC        the reference set's answer — FOR COMPARISON ONLY; its art is
                   CC BY-NC-SA and cannot ship. Fetch with the ARASAAC API into
                   --arasaac as <id>.png.

These words have no referent, so what matters is less "does the picture explain
the word" than "is it a pattern a child can learn to recognise" — which is the
question an SLP is best placed to answer.
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("pip install pillow")

# (group title, [(word, ARASAAC id or None)])
GROUPS = [
    ("Connecting and future words — new", [
        ("because", 11348), ("but", 11377), ("will", None), ("lets", None), ("one", 2627),
    ]),
    ("Possessives — a family: the same red ball; the green-shirt child is “me”", [
        ("my", 12264), ("your", 12281), ("his", 12272), ("our", 12268), ("their", 12274),
    ]),
    ("Function words shown as text today", [
        ("a", 3021), ("the", 8477), ("and", 11399), ("is", None), ("at", 7041),
    ]),
]
SYMBOLS = {"because", "but"}          # drawn by tools/render_logic_marks.py
GLYPHS = {"one": "1"}                 # GlyphTile.wordGlyphs
TEXT_SHIPPED = {"a", "the", "and", "is", "at"}

COLS = ["shipped", "new picture", "text", "symbol", "ARASAAC (reference only)"]
DPI = 150
PAGE = (int(11 * DPI), int(8.5 * DPI))   # US Letter, landscape
MARGIN, LABEL_W, CELL, HEADER = 60, 170, 220, 120

FONTS = ["/System/Library/Fonts/Supplemental/Arial Bold.ttf",
         "/System/Library/Fonts/Supplemental/Arial.ttf"]


def font(size):
    for f in FONTS:
        if Path(f).exists():
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def heic(path, tmp):
    png = tmp / (path.stem + ".png")
    subprocess.run(["sips", "-s", "format", "png", str(path), "--out", str(png)],
                   capture_output=True, check=True)
    return png


def load(path, tmp):
    if path is None or not path.exists():
        return None
    if path.suffix.lower() == ".heic":
        path = heic(path, tmp)
    im = Image.open(path).convert("RGBA")
    flat = Image.new("RGBA", im.size, "white")
    flat.alpha_composite(im)
    return flat.convert("RGB")


def text_tile(word, size=512):
    im = Image.new("RGB", (size, size), "white")
    d = ImageDraw.Draw(im)
    pt = 460
    while pt > 40:
        f = font(pt)
        box = d.textbbox((0, 0), word, font=f)
        if box[2] - box[0] < size * 0.8 and box[3] - box[1] < size * 0.62:
            break
        pt -= 10
    box = d.textbbox((0, 0), word, font=f)
    d.text(((size - (box[2] - box[0])) / 2 - box[0], (size - (box[3] - box[1])) / 2 - box[1]),
           word, font=f, fill=(17, 17, 17))
    return im


def cell_image(word, col, args, tmp):
    shipped = Path(f"claudeBlast/TileImageSets/cls_{word}.heic")
    master = Path(f"tools/tile_sets/classic/{word}.png")
    if col == "shipped":
        return load(shipped, tmp)
    if col == "new picture":
        if word in SYMBOLS or word in GLYPHS or word in TEXT_SHIPPED:
            return None
        return load(master, tmp)
    if col == "text":
        return text_tile(word)
    if col == "symbol":
        if word in GLYPHS:
            return text_tile(GLYPHS[word])
        if word in SYMBOLS:
            return load(master, tmp)
        return None
    if col.startswith("ARASAAC"):
        aid = dict(w for _, ws in GROUPS for w in ws).get(word)
        return load(args.arasaac / f"{aid}.png", tmp) if aid else None


def page(title, words, args, tmp):
    im = Image.new("RGB", PAGE, "white")
    d = ImageDraw.Draw(im)
    d.text((MARGIN, 30), "BlasterAI — abstract words: how should we draw them?", font=font(30), fill="black")
    d.text((MARGIN, 72), title, font=font(22), fill=(80, 80, 80))
    for c, col in enumerate(COLS):
        d.text((MARGIN + LABEL_W + c * CELL + 6, HEADER - 10), col, font=font(16), fill=(60, 60, 60))
    for r, (word, _) in enumerate(words):
        y = HEADER + 20 + r * CELL
        d.text((MARGIN, y + CELL // 2 - 18), word, font=font(30), fill="black")
        for c, col in enumerate(COLS):
            x = MARGIN + LABEL_W + c * CELL
            tile = cell_image(word, col, args, tmp)
            d.rectangle([x + 4, y + 4, x + CELL - 4, y + CELL - 4], outline=(200, 200, 200), width=2)
            if tile is not None:
                im.paste(tile.resize((CELL - 20, CELL - 20)), (x + 10, y + 10))
            else:
                d.text((x + CELL // 2 - 8, y + CELL // 2 - 10), "–", font=font(24), fill=(180, 180, 180))
    d.text((MARGIN, PAGE[1] - 40),
           "ARASAAC pictograms (Sergio Palao / Gobierno de Aragón, CC BY-NC-SA) shown for comparison only; "
           "they are not used in the app.", font=font(14), fill=(120, 120, 120))
    return im


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--arasaac", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()
    with tempfile.TemporaryDirectory() as t:
        pages = [page(title, words, args, Path(t)) for title, words in GROUPS]
    pages[0].save(args.out, save_all=True, append_images=pages[1:], resolution=DPI)
    print(f"{len(pages)} pages → {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
