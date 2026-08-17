#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Build a print proof PDF for judging tile encoding at real physical size.

Screen review answers "does this look right at 200pt". Print asks a different
question: a laminated AAC board tile is typically 2 inches square, and at that
size a 512px image is ~256 DPI — below the 300 DPI print convention. Whether
that matters is something you can only judge on paper.

Every tile is placed at EXACTLY 2.0 inches square. Each page uses one encoding
so pages can be flipped against each other, and page 1 is a lossless reference
that sets the ceiling.

**Print at 100% scale.** "Scale to fit" or "Fit to printable area" silently
resizes the page and invalidates the entire test — every page carries a ruler
bar you can check against a real ruler before trusting anything you see.

Usage:
    python3 tools/build_print_proof.py
    python3 tools/build_print_proof.py --tiles apple,happy,red,playground
    python3 tools/build_print_proof.py --dpi 300
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("pip install Pillow")

MASTERS = Path("tools/tile_sets")
OUT = Path("tools/tile_sets/encoding_review/print_proof.pdf")

SET_PREFIX = {
    "p3d": "playful_3d",
    "cls": "classic",
    "hc2": "high_contrast_v2",
}
SET_LABEL = {"p3d": "Playful 3D", "cls": "Classic", "hc2": "High Contrast v2"}

TILE_INCHES = 2.0          # the size an AAC board tile is actually laminated at
PAGE_W_IN, PAGE_H_IN = 8.5, 11.0
MARGIN_IN = 0.5
DEFAULT_TILES = ["apple", "happy", "playground", "red"]

# (label, source size, heic quality or None for lossless)
VARIANTS = [
    ("Lossless PNG · 1024px — reference ceiling", 1024, None),
    ("HEIC q65 · 512px  (256 DPI at 2 inch)", 512, "65"),
    ("HEIC q85 · 512px  (256 DPI at 2 inch)", 512, "85"),
    ("HEIC q65 · 1024px (512 DPI at 2 inch)", 1024, "65"),
    ("HEIC q85 · 1024px (512 DPI at 2 inch)", 1024, "85"),
]


def sips(src: Path, dst: Path, fmt: str, quality=None, resize=None) -> bool:
    cmd = ["sips", "-s", "format", fmt]
    if quality:
        cmd += ["-s", "formatOptions", quality]
    if resize:
        cmd += ["-Z", str(resize)]
    cmd += [str(src), "--out", str(dst)]
    return subprocess.run(cmd, capture_output=True).returncode == 0 and dst.exists()


def font(size: int):
    for p in ("/System/Library/Fonts/SFNSMono.ttf",
              "/System/Library/Fonts/Supplemental/Andale Mono.ttf",
              "/Library/Fonts/Arial.ttf"):
        if Path(p).exists():
            try:
                return ImageFont.truetype(p, size)
            except OSError:
                pass
    return ImageFont.load_default()


def render_page(tiles, prefix_order, variant, dpi, tmp: Path) -> Image.Image:
    label, src_size, quality = variant
    pw, ph = int(PAGE_W_IN * dpi), int(PAGE_H_IN * dpi)
    px = int(TILE_INCHES * dpi)
    margin = int(MARGIN_IN * dpi)

    page = Image.new("RGB", (pw, ph), "white")
    d = ImageDraw.Draw(page)
    f_title, f_small = font(int(dpi * 0.16)), font(int(dpi * 0.09))

    d.text((margin, int(margin * 0.55)), label, fill="black", font=f_title)

    # Ruler: proves the printer did not scale the page. If these marks are not
    # exactly 1 inch apart on paper, nothing else on the page can be trusted.
    ry = margin + int(dpi * 0.34)
    d.text((margin, ry - int(dpi * 0.13)), "100% scale check — marks are 1 inch apart:",
           fill="#666", font=f_small)
    for i in range(6):
        x = margin + i * dpi
        d.line([(x, ry), (x, ry + int(dpi * 0.1))], fill="black", width=max(1, dpi // 150))
    d.line([(margin, ry), (margin + 5 * dpi, ry)], fill="black", width=max(1, dpi // 150))

    gap = int(dpi * 0.28)
    top = ry + int(dpi * 0.40)
    cols = len(prefix_order)

    for row, key in enumerate(tiles):
        for col, prefix in enumerate(prefix_order):
            master = MASTERS / SET_PREFIX[prefix] / f"{key}.png"
            if not master.exists():
                continue

            base = tmp / f"b_{prefix}_{key}_{src_size}.png"
            if src_size == 1024:
                shutil.copy(master, base)
            elif not sips(master, base, "png", resize=src_size):
                continue

            if quality:
                h = tmp / f"h_{prefix}_{key}_{src_size}_{quality}.heic"
                shown = tmp / f"s_{prefix}_{key}_{src_size}_{quality}.png"
                if not (sips(base, h, "heic", quality=quality) and sips(h, shown, "png")):
                    continue
                nbytes = h.stat().st_size
            else:
                shown, nbytes = base, base.stat().st_size

            img = Image.open(shown).convert("RGB")
            # Resampling to the physical box is exactly what a printer does with
            # a 512px image asked to occupy 2 inches. Doing it here with LANCZOS
            # is a faithful stand-in, not an advantage.
            img = img.resize((px, px), Image.LANCZOS)

            x = margin + col * (px + gap)
            y = top + row * (px + gap + int(dpi * 0.22))
            if y + px > ph - margin:
                continue
            page.paste(img, (x, y))
            d.rectangle([x, y, x + px, y + px], outline="#bbb", width=max(1, dpi // 300))
            d.text((x, y + px + int(dpi * 0.04)),
                   f"{SET_LABEL[prefix]} · {key} · {nbytes/1024:.0f} KB",
                   fill="#444", font=f_small)

    d.text((margin, ph - margin), f"{TILE_INCHES}in tiles · page rendered at {dpi} DPI",
           fill="#888", font=f_small, anchor="ls")
    return page


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiles", default=",".join(DEFAULT_TILES))
    ap.add_argument("--dpi", type=int, default=300)
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()

    if shutil.which("sips") is None:
        sys.exit("sips not found — macOS only.")

    keys = [t.strip() for t in args.tiles.split(",") if t.strip()]
    prefixes = list(SET_PREFIX)
    OUT.parent.mkdir(parents=True, exist_ok=True)

    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        pages = []
        for v in VARIANTS:
            print(f"  rendering: {v[0]}")
            pages.append(render_page(keys, prefixes, v, args.dpi, tmp))

        pages[0].save(OUT, "PDF", resolution=args.dpi, save_all=True,
                      append_images=pages[1:])

    print(f"\n{len(pages)} pages · {len(keys)}×{len(prefixes)} tiles at {TILE_INCHES}in")
    print(f"→ {OUT}")
    print("\nPrint at 100% scale — NOT 'fit to page'. Check the ruler bar with a real ruler.")
    if not args.no_open:
        subprocess.run(["open", str(OUT)])


if __name__ == "__main__":
    main()
