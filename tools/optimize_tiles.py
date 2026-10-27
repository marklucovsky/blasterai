#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Optimize tile images for app bundle inclusion.

Resizes full-resolution DALL-E masters (1024×1024) to app-ready size (512×512)
with PNG optimization. Output goes to tools/tile_sets/optimized/{set_name}/.

Usage:
    python3 tools/optimize_tiles.py --set playful_3d
    python3 tools/optimize_tiles.py --set high_contrast
    python3 tools/optimize_tiles.py --set both
    python3 tools/optimize_tiles.py --set both --size 256  # smaller for testing
"""

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    sys.exit("pip install Pillow")

sys.path.insert(0, str(Path(__file__).resolve().parent))
from render_word_glyphs import WORDS as WORD_GLYPHS  # noqa: E402

INPUT_BASE = Path("tools/tile_sets")
OUTPUT_BASE = Path("tools/tile_sets/optimized")
DEFAULT_SIZE = 512

# Sets whose art ships with its white ground cut away, so a tile draws it
# straight on the tile's colour. The masters stay white — they are what we
# edit, review and print — and the cut is made here, on the way to the bundle,
# by the same TileCutout.swift the app uses on art it generates.
#
# Only Classic and its tones, whose black outlines give the cut an edge to stop
# at. Playful 3D's clay has no outlines: a cream egg or cloud on white paper
# was cut into (2026-10-26), so it ships uncut on a framed white plate. High
# Contrast's figures are white on black; it keeps its black plate, framed.
CUT_SETS = {"classic", "classic_chain_medium", "classic_chain_medium_dark"}
CUTTER = Path("tools/cutout/.build/cutout")
CUT_SPEC = Path("tools/board_spec/cutout.json")
CUT_CACHE = INPUT_BASE / "cut"      # gitignored: <set>/<key>.png + _vision.json


def cut_spec(set_name: str) -> dict:
    """The review's decisions for one set (tools/cutout_review.py): the holes
    confirmed per tile, and the tiles left uncut.

    The tone sets are Classic redrawn in a different skin, so they take
    Classic's decisions; the art is the same picture in the same place. Their
    points were measured on Classic's master, so that is the drawing checked
    for a redraw (`reviewed`), not the tone's own.
    """
    spec = json.loads(CUT_SPEC.read_text()) if CUT_SPEC.exists() else {}
    base = "classic" if set_name.startswith("classic") else set_name
    return {"holes": spec.get("holes", {}).get(base, {}),
            "opaque": set(spec.get("opaque", {}).get(base, [])),
            "reviewed": lambda key: INPUT_BASE / base / f"{key}.png"}


SNAP_RADIUS = 0.03    # of the tile: a tone redraw moves a line by a few pixels


def snap_to_ground(src: Path, point: list[float]) -> list[float]:
    """A Classic hole point moved onto the tone's paper.

    A tone is Classic redrawn, not recoloured, so a line can drift onto the
    point the review measured: a hole point that lands on ink cuts nothing
    (Medium's jump rope and front bike wheel, 2026-10-26). Take the nearest
    near-white pixel within a small radius; if there is none, keep the point.
    """
    im = Image.open(src).convert("RGB")
    w, h = im.size
    px = im.load()
    cx, cy = int(point[0] * w), int(point[1] * h)
    r_max = int(SNAP_RADIUS * w)
    for r in range(r_max + 1):
        ring = [(cx + dx, cy + dy) for dx in range(-r, r + 1) for dy in (-r, r)] + \
               [(cx + dx, cy + dy) for dx in (-r, r) for dy in range(-r + 1, r)]
        for x, y in ring:
            if 0 <= x < w and 0 <= y < h and min(px[x, y]) >= 232:
                return [round((x + .5) / w, 4), round((y + .5) / h, 4)]
    return point


def cut_master(src: Path, set_name: str, decisions: dict) -> Path:
    """Cut one master; returns the path to encode from."""
    key = src.stem
    if key in decisions["opaque"]:
        return src        # ships with its white; the app frames it
    out = CUT_CACHE / set_name / f"{key}.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = [str(CUTTER), str(src), str(out)]
    entry = decisions["holes"].get(key)
    if key in WORD_GLYPHS:
        cmd.append("--all-white")        # the holes in "a" and "e" are not paper
    elif entry and entry["master"] != hashlib.sha1(decisions["reviewed"](key).read_bytes()).hexdigest()[:10]:
        # The points were measured on a drawing that has since been replaced.
        print(f"  {key}: master changed since its holes were reviewed; edge cut only "
              f"until tools/cutout_review.py --set {set_name} reviews it again")
    elif entry:
        points = entry["points"]
        if decisions["reviewed"](key) != src:
            points = [snap_to_ground(src, p) for p in points]
        cmd += ["--holes", ";".join(f"{x},{y}" for x, y in points)]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip()[:200] or "cutout failed")
    return out


def optimize_set(set_name: str, target_size: int,
                 fmt: str = "png", quality: int = 65) -> None:
    src_dir = INPUT_BASE / set_name
    dst_dir = OUTPUT_BASE / set_name
    dst_dir.mkdir(parents=True, exist_ok=True)
    cutting = fmt == "heic" and set_name in CUT_SETS
    if cutting and not CUTTER.exists():
        sys.exit(f"{CUTTER} missing: run tools/cutout/build.sh")
    decisions = cut_spec(set_name) if cutting else {}
    # A change to the decisions, or to the cutter, re-cuts the whole set.
    newest_input = max((p.stat().st_mtime for p in (CUT_SPEC, CUTTER) if p.exists()), default=0) if cutting else 0

    if not src_dir.exists():
        print(f"  Source not found: {src_dir}")
        return

    tiles = sorted(src_dir.glob("*.png"))
    if not tiles:
        print(f"  No PNGs in {src_dir}")
        return

    optimized = 0
    skipped = 0
    total_src = 0
    total_dst = 0

    for src in tiles:
        dst = dst_dir / (src.stem + "." + fmt)

        # Skip if optimized version is newer than source
        if dst.exists() and dst.stat().st_mtime >= max(src.stat().st_mtime, newest_input):
            skipped += 1
            continue

        try:
            if fmt == "heic":
                encode_from = src
                if cutting:
                    encode_from = cut_master(src, set_name, decisions)
                # Pillow cannot write HEIC without pillow-heif; sips is already a
                # dependency of the review tooling and does the resize in the same
                # pass. Reviewed and approved at 512/q65 on 2026-08-15 — printed
                # proofs at 2in were indistinguishable from lossless. HEIC keeps
                # the cut's alpha (measured: about +31% bytes per tile).
                r = subprocess.run(
                    ["sips", "-Z", str(target_size), "-s", "format", "heic",
                     "-s", "formatOptions", str(quality), str(encode_from), "--out", str(dst)],
                    capture_output=True)
                if r.returncode != 0 or not dst.exists():
                    raise RuntimeError(r.stderr.decode()[:200] or "sips failed")
            else:
                img = Image.open(src)
                img = img.convert("RGB")
                img = img.resize((target_size, target_size), Image.LANCZOS)
                img.save(dst, "PNG", optimize=True)

            src_kb = src.stat().st_size // 1024
            dst_kb = dst.stat().st_size // 1024
            total_src += src.stat().st_size
            total_dst += dst.stat().st_size
            optimized += 1

        except Exception as e:
            print(f"  ERROR {src.name}: {e}")

    if cutting:
        print(f"  {set_name}: cut off white; {len(decisions['holes'])} tile(s) with confirmed holes, "
              f"{len(decisions['opaque'])} left uncut (tools/board_spec/cutout.json)")
    print(f"  {set_name}: {optimized} optimized, {skipped} skipped (up to date)")
    if optimized > 0:
        ratio = (1 - total_dst / total_src) * 100 if total_src > 0 else 0
        print(f"  Size: {total_src // 1024 // 1024}MB → {total_dst // 1024 // 1024}MB ({ratio:.0f}% reduction)")


def main():
    parser = argparse.ArgumentParser(description="Optimize tiles for app bundle")
    parser.add_argument("--set", required=True,
                        choices=["playful_3d", "high_contrast", "high_contrast_v2", "classic",
                                 "classic_chain_medium", "classic_chain_medium_dark", "both"])
    parser.add_argument("--size", type=int, default=DEFAULT_SIZE, help=f"Target size in px (default {DEFAULT_SIZE})")
    parser.add_argument("--format", default="png", choices=["png", "heic"],
                        help="heic ships in the bundle; png for interop/print")
    parser.add_argument("--quality", type=int, default=65,
                        help="heic quality (512/q65 approved 2026-08-15)")
    args = parser.parse_args()

    sets = ["playful_3d", "high_contrast"] if args.set == "both" else [args.set]

    print(f"Optimizing to {args.size}×{args.size} {args.format}"
          + (f" q{args.quality}" if args.format == "heic" else "") + "…")
    for s in sets:
        optimize_set(s, args.size, args.format, args.quality)

    print(f"\nOutput: {OUTPUT_BASE}/")
    print("These optimized tiles are committed to git and used by the app.")


if __name__ == "__main__":
    main()
