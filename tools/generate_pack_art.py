#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Generate art for vocabulary-pack words in a set that doesn't have it yet.

The bundled packs (farm, tide pools, mealtime, space, dinosaurs, vehicles) add
words that are NOT in vocabulary.json, so a full-set run over the base
vocabulary misses them — 53 words at the time of writing. Any set that ships
has to cover them too, or a child using that style sees pack tiles fall back to
Playful-3D and the board becomes visually inconsistent mid-page.

`build_vocab_packs.py` hardcodes playful_3d + classic and also rewrites the
pack JSON, the catalog and the cover art, so it is the wrong tool for adding a
third style to existing packs. This does only the missing-art part, for any
set.

Subjects come from build_vocab_packs.PACKS, the same source the other two sets
used, so the three stay in step.

Usage:
    python3 tools/generate_pack_art.py --set high_contrast_v2
    python3 tools/generate_pack_art.py --set high_contrast_v2 --dry-run
"""

import argparse
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("pip install requests")

import generate_sets as gs
from build_vocab_packs import PACKS

OUTPUT_BASE = Path("tools/tile_sets")
COVER_MASTERS = OUTPUT_BASE / "packcovers"

# Prefix used for this set's cover masters, matching sync_to_app.SET_PREFIX.
# Covers live in one shared folder rather than per-set, so they need it.
from sync_to_app import SET_PREFIX  # noqa: E402


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate pack-word art for a set")
    ap.add_argument("--set", required=True, choices=list(gs.SET_STYLES))
    ap.add_argument("--sleep", type=float, default=5.0)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true",
                    help="Regenerate even where art already exists")
    ap.add_argument("--covers", action="store_true",
                    help="Also generate the six pack cover images. A set is not a peer "
                         "of the shipping sets without them — every pack picker shows a "
                         "cover, and a missing one falls back to another style.")
    args = ap.parse_args()

    api_key = gs.os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        sys.exit("Error: OPENAI_API_KEY not set")

    style_key = gs.SET_STYLES[args.set]
    out_dir = OUTPUT_BASE / args.set
    out_dir.mkdir(parents=True, exist_ok=True)

    prefix = SET_PREFIX.get(args.set, args.set)
    todo: list[tuple[str, str, str, Path]] = []     # (slug, label, subject, dest)
    for slug, pack in PACKS.items():
        for key, (_wc, _dn, subject) in pack["words"].items():
            dest = out_dir / f"{key}.png"
            if dest.exists() and not args.force:
                continue
            todo.append((slug, key, subject, dest))

    if args.covers:
        COVER_MASTERS.mkdir(parents=True, exist_ok=True)
        for slug, pack in PACKS.items():
            dest = COVER_MASTERS / f"{prefix}_{slug}.png"
            if dest.exists() and not args.force:
                continue
            todo.append((slug, f"cover:{slug}", pack["icon"], dest))

    if not todo:
        print(f"{args.set}: every pack word already has art.")
        return

    print(f"{args.set}: {len(todo)} pack word(s) to generate\n")
    session = requests.Session()
    ok, failed = 0, []

    for i, (slug, label, subject, dest) in enumerate(todo, 1):
        # Pack subjects were authored for playful_3d and carry its clay
        # wording; every other style has to have it stripped or the subject
        # fights the style prefix.
        text = subject if style_key == "playful_3d" else gs.strip_clay_words(subject)
        prompt = gs.build_prompt(text, style_key)

        if args.dry_run:
            print(f"  [DRY] {slug:10s} {label:16s} | {text[:70]}")
            ok += 1
            continue

        print(f"  ⏳ [{i}/{len(todo)}] {slug:10s} {label:16s}", end="", flush=True)
        png = gs.generate_image(prompt, api_key, session)
        if png and len(png) >= gs.MIN_IMAGE_BYTES:
            dest.write_bytes(png)
            print(f"  ✓ {len(png) // 1024} KB")
            ok += 1
        else:
            print("  FAILED")
            failed.append(label)
        time.sleep(args.sleep)

    print(f"\n{args.set}: ✓ {ok} generated  ✗ {len(failed)} failed")
    if failed:
        print("Failed:", ", ".join(failed))


if __name__ == "__main__":
    main()
