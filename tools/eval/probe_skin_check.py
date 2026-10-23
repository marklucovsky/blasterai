#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Does a model answer the app's skin check the way the shipped tiles were classified?

    python3 tools/eval/probe_skin_check.py --models gpt-4o-mini,gpt-6-luna --n 20

Before a tone transform the app asks a chat model "does this tile show human
skin?" (`TileImageGenerator.depictsSkin`), and copies the tile untouched on a
no. `tools/tile_sets/classic_skin_tiles.json` holds the answer for every Classic
tile, recorded when the tone variants were built. This sends `--n` tiles of each
answer, with the app's exact prompt, image detail and token limit, and reports
where each model disagrees with the record.

A wrong yes costs a transform (~6¢) and can redraw an object; a wrong no leaves a
person in the default skin tone. Both are listed. ~$0.0004 per call.
"""
import argparse
import base64
import json
import random
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import client  # noqa: E402
import models  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
TRUTH = ROOT / "tools/tile_sets/classic_skin_tiles.json"
TILES = ROOT / "tools/tile_sets/classic"

# Mirrors TileImageGenerator.classifyPrompt and its token limit — keep them in step.
PROMPT = ("This is a pictogram from an AAC (augmentative communication) symbol set. "
          "Answer with one word, yes or no: does it depict a human being or any "
          "human body part with visible skin — a face, hand, arm, or whole figure? "
          "Answer no for animals, objects, food, places, and abstract symbols with "
          "no person in them.")


def body(key: str) -> dict:
    png = base64.b64encode((TILES / f"{key}.png").read_bytes()).decode()
    classic = {"model": "gpt-4o-mini", "temperature": 0, "max_tokens": 16, "messages": [{
        "role": "user", "content": [
            {"type": "text", "text": PROMPT},
            {"type": "image_url", "image_url": {"url": f"data:image/png;base64,{png}", "detail": "low"}}]}]}
    return classic


def ask(model: str, key: str) -> tuple[str, str, bool | None, str]:
    b, _ = models.adapt(body(key), model)
    r = client.call(b)
    text = (r["text"] or "").strip().lower()
    # The app treats anything starting "yes" as yes; everything else, including a failure, is no.
    return model, key, text.startswith("yes") if not r["error"] else None, r["error"] or text


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--models", default="gpt-4o-mini,gpt-6-luna")
    ap.add_argument("--n", type=int, default=20, help="tiles per answer (yes and no)")
    ap.add_argument("--seed", type=int, default=7)
    args = ap.parse_args()
    truth = {k: v for k, v in json.loads(TRUTH.read_text()).items() if (TILES / f"{k}.png").exists()}
    rng = random.Random(args.seed)
    keys = (rng.sample(sorted(k for k, v in truth.items() if v), args.n)
            + rng.sample(sorted(k for k, v in truth.items() if not v), args.n))
    jobs = [(m, k) for m in args.models.split(",") for k in keys]
    with ThreadPoolExecutor(8) as pool:
        answers = list(pool.map(lambda j: ask(*j), jobs))
    for model in args.models.split(","):
        rows = [a for a in answers if a[0] == model]
        wrong = [(k, got, raw) for _, k, got, raw in rows if got is not truth[k]]
        print(f"{model}: {len(rows) - len(wrong)}/{len(rows)} agree with the record")
        for k, got, raw in wrong:
            print(f"    {k:16} record={'yes' if truth[k] else 'no':3}  answered {raw!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
