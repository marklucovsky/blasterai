#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Copy reviewed candidates into a set's master folder and record where each came from.

    python3 tools/promote_candidates.py --set classic --keys-file approved.txt

Candidates live in `tools/tile_sets/<set>_gi2/` (generate_by_reference.py,
draw_series.py) until the review page approves them. This copies each approved
key's PNG over `tools/tile_sets/<set>/<key>.png` and files the key in
`<set>_provenance.json`: under `special` with its source when
tools/board_spec/series.json says it is an edit of another tile, otherwise under
`ai` (its prompt is the prompts.json entry). A key is removed from every other
bucket first, so a tile that was rendered or preserved and is now generated is
listed once.

Rendered tiles (day strips, clocks, months, text glyphs) are not promoted: their
renderers write the master folder directly and the key goes under `rendered`
with `--rendered SCRIPT`.

Then: optimize_tiles.py and sync_to_app.py for the set, and the drift check.
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path("tools/tile_sets")
SERIES = Path("tools/board_spec/series.json")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--set", required=True)
    ap.add_argument("--keys-file", type=Path, required=True)
    ap.add_argument("--from-dir", type=Path, help="default tools/tile_sets/<set>_gi2")
    ap.add_argument("--rendered", metavar="SCRIPT",
                    help="record the keys as rendered by SCRIPT; copies nothing")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    keys = [k for k in args.keys_file.read_text().split() if k]
    src = args.from_dir or ROOT / f"{args.set}_gi2"
    dst = ROOT / args.set
    prov_path = ROOT / f"{args.set}_provenance.json"
    prov = json.loads(prov_path.read_text())
    series = {k: v for k, v in json.loads(SERIES.read_text()).items() if not k.startswith("_")}

    if args.rendered:
        missing = [k for k in keys if not (dst / f"{k}.png").exists()]
    else:
        missing = [k for k in keys if not (src / f"{k}.png").exists()]
    if missing:
        sys.exit(f"no PNG for: {' '.join(missing)}")

    for k in keys:
        for bucket in prov.values():
            if isinstance(bucket, dict):
                bucket.pop(k, None)
            elif isinstance(bucket, list) and k in bucket:
                bucket.remove(k)
        if args.rendered:
            prov.setdefault("rendered", {})[k] = args.rendered
        elif k in series:
            prov.setdefault("special", {})[k] = (
                f"draw_series.py edit of {series[k]['from']}.png (tools/board_spec/series.json); "
                f"redraw {series[k]['from']} first, then rerun draw_series.py --keys {k}.")
        else:
            prov.setdefault("ai", {})[k] = {"source": "prompts.json", "subject": "prompts.json"}
        if not args.rendered and not args.dry_run:
            shutil.copy2(src / f"{k}.png", dst / f"{k}.png")

    if not args.dry_run:
        prov_path.write_text(json.dumps(prov, indent=2) + "\n")
    verb = "recorded" if args.rendered else "promoted"
    print(f"{verb} {len(keys)} into {dst}" + (" (dry run)" if args.dry_run else ""))


if __name__ == "__main__":
    main()
