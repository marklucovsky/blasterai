#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Merge runs of the same cases into one run, for a side-by-side review.

    python3 tools/eval/merge_runs.py --label topic-models --samples 1 \\
        docs/eval/runs/<gpt-4o-mini run> docs/eval/runs/<luna run> docs/eval/runs/<sol run>
    python3 tools/eval/build_review.py docs/eval/runs/<stamp>-merged-topic-models

Each record keeps its own output, Tier-1 and judge, and its surface becomes
`<surface>/<model>` so the review page's surface filter picks one model; the
cards for one case sit next to each other. A run's model comes from its
run.json, with the effort and any label suffix after the model's own label
(a "-review" run is shown as `<model>+review`).
"""
import argparse
import json
from datetime import datetime
from pathlib import Path

import prompts as P

RUNS = P.ROOT / "docs/eval/runs"


def tag(meta: dict) -> str:
    t = meta["model"] + (f"-{meta['effort']}" if meta.get("effort") else "")
    return t + ("+review" if "review" in meta.get("label", "") else "")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--label", required=True)
    ap.add_argument("--samples", type=int, default=1, help="samples kept per case per run")
    args = ap.parse_args()

    merged, sources = [], []
    for run in args.runs:
        run = Path(run)
        meta = json.loads((run / "run.json").read_text())
        sources.append({"run": meta["name"], "tag": tag(meta), "judge": meta.get("judge")})
        for line in (run / "results.jsonl").read_text().splitlines():
            r = json.loads(line)
            if r["sample"] < args.samples:
                merged.append({**r, "surface": f"{r['surface']}/{tag(meta)}"})
    order = {c: n for n, c in enumerate(dict.fromkeys(r["case"] for r in merged))}
    merged.sort(key=lambda r: (order[r["case"]], r["surface"], r["sample"]))

    name = f"{datetime.now():%Y-%m-%d-%H%M}-merged-{args.label}"
    out = RUNS / name
    out.mkdir(parents=True)
    (out / "results.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in merged))
    (out / "run.json").write_text(json.dumps({"name": name, "label": args.label, "merged_from": sources,
                                              "samples": args.samples, "outputs": len(merged)}, indent=1) + "\n")
    print(f"{out.relative_to(P.ROOT)}  ({len(merged)} outputs from {len(sources)} runs)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
