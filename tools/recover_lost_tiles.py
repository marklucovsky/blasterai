#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Recover tiles that shipped before the HEIC re-encode but are absent after it.

## Why this is needed

`sync_to_app.py` copies from `tools/tile_sets/<set>/`, so it can only ship what
the masters contain. Some tiles that were in the app bundle are NOT in any master
directory:

- **Pack covers** (`packcover_*`) live in `tools/tile_sets/packcovers/`, a
  separate folder synced by a different path.
- **Four Playful-3D vocabulary tiles** — `between`, `middle`, `not`, `under` —
  exist only in the old bundle. They were presumably generated straight into the
  app and never written back to the masters.

Re-encoding therefore silently dropped ten tiles: four vocabulary words and every
pack cover. Nothing would have crashed — Classic is the universal backfill and
covers the words — but the packs UI would have shown placeholder art, which is
exactly the kind of regression that survives a green build.

This recovers each missing tile from git HEAD and encodes it with the same
settings as everything else (512, HEIC q65).

**The underlying gap remains:** the masters are not a complete record of what
ships. Worth closing separately by writing these tiles back to the masters.

Usage:
    python3 tools/recover_lost_tiles.py            # report only
    python3 tools/recover_lost_tiles.py --apply
"""

import argparse
import os
import subprocess
import sys
import tempfile
from pathlib import Path

BUNDLE = Path("claudeBlast/TileImageSets")
SIZE = "512"
QUALITY = "65"
# High Contrast v1 was retired in favour of the complete v2 set; its tiles are
# meant to be gone, so they must not be resurrected by a blanket recovery.
RETIRED_PREFIXES = ("hc_",)


def git_tracked_pngs() -> set[str]:
    r = subprocess.run(["git", "ls-tree", "-r", "--name-only", "HEAD", str(BUNDLE)],
                       capture_output=True, text=True)
    return {os.path.basename(f).rsplit(".", 1)[0]
            for f in r.stdout.split() if f.endswith(".png")}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()

    if not BUNDLE.exists():
        sys.exit(f"missing {BUNDLE}")

    before = git_tracked_pngs()
    now = {p.stem for p in BUNDLE.iterdir() if p.is_file()}
    missing = sorted(before - now)

    retired = [m for m in missing if m.startswith(RETIRED_PREFIXES)]
    recoverable = [m for m in missing if not m.startswith(RETIRED_PREFIXES)]

    print(f"shipped before: {len(before)}   present now: {len(now)}")
    print(f"missing: {len(missing)}  ({len(retired)} retired, {len(recoverable)} to recover)")
    for m in recoverable:
        print(f"  {m}")
    if not args.apply:
        print("\n(report only — pass --apply to recover)")
        return

    tmp = Path(tempfile.mkdtemp())
    ok = 0
    for name in recoverable:
        blob = subprocess.run(["git", "show", f"HEAD:{BUNDLE}/{name}.png"],
                              capture_output=True)
        if blob.returncode != 0:
            print(f"  not in HEAD: {name}")
            continue
        src = tmp / f"{name}.png"
        src.write_bytes(blob.stdout)
        dst = BUNDLE / f"{name}.heic"
        r = subprocess.run(["sips", "-Z", SIZE, "-s", "format", "heic",
                            "-s", "formatOptions", QUALITY, str(src), "--out", str(dst)],
                           capture_output=True)
        if r.returncode == 0 and dst.exists():
            ok += 1
        else:
            print(f"  encode failed: {name}")
    print(f"\nrecovered {ok}/{len(recoverable)}")


if __name__ == "__main__":
    main()
