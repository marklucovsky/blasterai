#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Sync optimized tile images into the app bundle directory.

Workflow:
    1. Review and iterate on tiles using the review tool + generate_sets.py
    2. Run optimize_tiles.py to resize masters to 512×512
    3. Run this script to copy optimized tiles into the Xcode project

Usage:
    python3 tools/sync_to_app.py --set playful_3d [--dry-run]
    python3 tools/sync_to_app.py --set playful_3d --only-changed  # only tiles modified since last sync

This script:
    - Reads from tools/tile_sets/optimized/{set_name}/
    - Prefixes filenames (playful_3d → p3d_{key}.png)
    - Copies to claudeBlast/TileImageSets/
    - Reports what changed
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

OPTIMIZED_BASE = Path("tools/tile_sets/optimized")
APP_BUNDLE_DIR = Path("claudeBlast/TileImageSets")

SET_PREFIX = {
    "playful_3d": "p3d",
    "high_contrast": "hc",
    "high_contrast_v2": "hc2",
    "classic": "cls",
}


def load_approved(review_path: Path) -> set[str]:
    """Keys marked approved in a review export from build_review_page.py.

    The review page has always been able to export a full verdict manifest, and
    nothing ever read it — so a rejected tile still shipped if anyone ran a
    plain sync. Passing --review here is what makes human approval actually
    gate the bundle rather than advise it.
    """
    try:
        review = json.loads(review_path.read_text())
    except Exception as e:
        sys.exit(f"Could not read review file {review_path}: {e}")

    approved = {k for k, v in review.items() if v.get("status") == "approved"}
    rejected = sum(1 for v in review.values() if v.get("status") == "rejected")
    unreviewed = len(review) - len(approved) - rejected
    print(f"Review {review_path.name}: {len(approved)} approved, "
          f"{rejected} rejected, {unreviewed} unreviewed")
    if not approved:
        sys.exit("No approved tiles in the review file — nothing to sync.")
    return approved


def sync_set(set_name: str, dry_run: bool, only_changed: bool,
             approved: set[str] | None = None) -> None:
    src_dir = OPTIMIZED_BASE / set_name
    prefix = SET_PREFIX.get(set_name)

    if not prefix:
        sys.exit(f"Unknown set: {set_name}. Known sets: {list(SET_PREFIX.keys())}")
    if not src_dir.exists():
        sys.exit(f"Source not found: {src_dir}\nRun: python3 tools/optimize_tiles.py --set {set_name}")

    APP_BUNDLE_DIR.mkdir(parents=True, exist_ok=True)

    tiles = sorted(src_dir.glob("*.png"))
    if not tiles:
        sys.exit(f"No PNGs in {src_dir}")

    added = 0
    updated = 0
    unchanged = 0
    withheld = 0

    for src in tiles:
        if approved is not None and src.stem not in approved:
            withheld += 1
            continue

        dst = APP_BUNDLE_DIR / f"{prefix}_{src.name}"

        # Skip unchanged files
        if dst.exists():
            if only_changed and dst.stat().st_mtime >= src.stat().st_mtime:
                unchanged += 1
                continue
            # Check if content actually changed (by size as quick heuristic)
            if dst.stat().st_size == src.stat().st_size:
                unchanged += 1
                continue

        if dry_run:
            action = "UPDATE" if dst.exists() else "ADD"
            print(f"  [{action}] {dst.name}")
        else:
            shutil.copy2(src, dst)

        if dst.exists():
            updated += 1
        else:
            added += 1

    total = added + updated + unchanged
    print(f"\n{set_name}: {added} added, {updated} updated, {unchanged} unchanged ({total} total)")
    if withheld:
        print(f"{withheld} withheld — not approved in the review file.")

    if not dry_run and (added + updated) > 0:
        print(f"\nFiles synced to {APP_BUNDLE_DIR}/")
        print("Rebuild in Xcode to pick up the changes.")


def main():
    parser = argparse.ArgumentParser(description="Sync tile images into app bundle")
    parser.add_argument("--set", required=True, choices=list(SET_PREFIX.keys()) + ["both"])
    parser.add_argument("--dry-run", action="store_true", help="Show what would change without copying")
    parser.add_argument("--only-changed", action="store_true", help="Only sync tiles newer than current bundle")
    parser.add_argument("--review", type=Path, default=None,
                        help="Review export from build_review_page.py (Export Full Review). "
                             "Only tiles marked approved are synced; everything else is withheld.")
    args = parser.parse_args()

    approved = load_approved(args.review) if args.review else None
    sets = list(SET_PREFIX.keys()) if args.set == "both" else [args.set]
    for s in sets:
        sync_set(s, args.dry_run, args.only_changed, approved)


if __name__ == "__main__":
    main()
