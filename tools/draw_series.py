#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Draw a series tile by editing one existing tile, so only the meaning changes.

    python3 tools/draw_series.py --set classic --keys above,below,next_to
    python3 tools/draw_series.py --set classic --all

A series is words a child tells apart by one difference: where the ball is
(`on`, `above`, `below`), how big the thing is. Drawn separately, every tile
gets a different ball and a different box, and the difference that carries the
meaning drowns in differences that carry none (compose_queue.py's argument for
first / next / last). So each word here is an image EDIT of its series' source
tile, with an instruction that moves or changes one thing and keeps the rest.

The series and their instructions are data, in tools/board_spec/series.json:
`{key: {"from": source_key, "edit": "..."}}`. The source is the set's master.
Output goes to the set's candidate folder (`<set>_gi2`) for review, like any
other drawing.
"""
import argparse
import base64
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_by_reference import EDITS_URL, MODEL, post_multipart, with_retry  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
SERIES = ROOT / "tools/board_spec/series.json"
TILE_SETS = ROOT / "tools/tile_sets"

KEEP = ("Edit this AAC pictogram tile. Keep the drawing style, the outline weight, the "
        "colours and every object exactly as they are, the same size and the same shape. "
        "Change only this: {edit} Keep the background colour exactly as it is (High "
        "Contrast tiles are drawn on black), no text, square.")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--set", default="classic")
    ap.add_argument("--keys", default="")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--quality", default="medium")
    ap.add_argument("--out-dir", type=Path)
    ap.add_argument("--from-dir", type=Path,
                    help="read sources here first, then the master folder: a series whose "
                         "source is itself a new candidate (tiny from the new huge)")
    args = ap.parse_args()
    series = {k: v for k, v in json.loads(SERIES.read_text()).items() if not k.startswith("_")}
    keys = list(series) if args.all else [k.strip() for k in args.keys.split(",") if k.strip()]
    unknown = [k for k in keys if k not in series]
    if unknown or not keys:
        sys.exit(f"not in series.json: {unknown}" if unknown else "no keys")
    api_key = os.environ.get("OPENAI_API_KEY", "").strip() or sys.exit("OPENAI_API_KEY not set")
    out = args.out_dir or TILE_SETS / f"{args.set}_gi2"
    out.mkdir(parents=True, exist_ok=True)

    def one(key):
        spec = series[key]
        src = TILE_SETS / args.set / f"{spec['from']}.png"
        if args.from_dir and (args.from_dir / f"{spec['from']}.png").exists():
            src = args.from_dir / f"{spec['from']}.png"
        fields = {"model": MODEL, "prompt": KEEP.format(edit=spec["edit"]),
                  "size": "1024x1024", "quality": args.quality, "n": "1"}
        r = with_retry(lambda: post_multipart(EDITS_URL, fields, {}, api_key,
                                              multi_field="image[]", multi=[(src.name, src.read_bytes())]),
                       label=key)
        if r and r.get("data") and r["data"][0].get("b64_json"):
            (out / f"{key}.png").write_bytes(base64.b64decode(r["data"][0]["b64_json"]))
            print(f"✓ {key}  (from {spec['from']})", flush=True)
        else:
            print(f"✗ {key}", flush=True)

    with ThreadPoolExecutor(4) as pool:
        list(pool.map(one, keys))


if __name__ == "__main__":
    main()
