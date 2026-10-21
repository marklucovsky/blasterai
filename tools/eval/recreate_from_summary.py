#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Can a scene be re-created from the summary the model wrote for it?

A scene keeps the model's own one-line summary (`BlasterScene.descriptionText`),
not the caregiver's prompt. For each page in a saved topic_words run this asks
the same model for the page again with the summary as the topic, and compares
the two pages' words. The yardstick is how far two samples of the ORIGINAL
prompt already differ (sample 0 vs sample 1): a re-creation as close as that is
as good as asking again.

    python3 tools/eval/recreate_from_summary.py docs/eval/runs/<run> [<run> ...]
"""
import argparse
import json
import statistics
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import client
import models
import prompts as P
import scorers as S


def page(text: str, template: str) -> set[str]:
    summary, _ = S.score_topic_words(text, template, {})
    return set((summary or {}).get("page") or [])


def overlap(a: set, b: set) -> float:
    return len(a & b) / len(a | b) if a | b else 1.0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--out", help="write the per-case table here (markdown)")
    args = ap.parse_args()

    items = []
    for run in args.runs:
        meta = json.loads((Path(run) / "run.json").read_text())
        recs = [json.loads(l) for l in (Path(run) / "results.jsonl").read_text().splitlines()]
        by = {(r["case"], r["sample"]): r for r in recs}
        for (case, n), r in by.items():
            j = S.extract_json(r.get("output") or "") or {}
            if n != 0 or j.get("refused") or r["input"].get("scene") or not j.get("description"):
                continue
            items.append((meta, r, by.get((case, 1)), j["description"]))

    def one(item):
        meta, r, r1, summary = item
        template = r["input"].get("template", "home")
        sent, _ = models.adapt(P.topic_words_body(summary, template), meta["model"], meta.get("effort"))
        text = client.call(sent)["text"]
        orig = page(r["output"], template)
        return {"case": r["case"], "prompt": r["input"]["description"], "summary": summary,
                "recreated": overlap(orig, page(text, template)),
                "resampled": overlap(orig, page(r1["output"], template)) if r1 else None,
                "lost": sorted(orig - page(text, template))}

    with ThreadPoolExecutor(8) as ex:
        rows = list(ex.map(one, items))
    rec = [r["recreated"] for r in rows]
    res = [r["resampled"] for r in rows if r["resampled"] is not None]
    lines = ["| Case | Prompt | Summary | Re-created | Re-sampled | Lost on re-creation |", "|---|---|---|---|---|---|"]
    for r in sorted(rows, key=lambda r: r["recreated"]):
        lines.append(f"| {r['case']} | {r['prompt'][:60]} | {r['summary'][:80]} | {r['recreated']:.0%} | "
                     f"{'' if r['resampled'] is None else format(r['resampled'], '.0%')} | {', '.join(r['lost'][:8])} |")
    lines.append(f"\nWord overlap with the original page (Jaccard), median: re-created from the summary "
                 f"**{statistics.median(rec):.0%}**, re-sampled from the original prompt **{statistics.median(res):.0%}** "
                 f"({len(rows)} pages).")
    text = "\n".join(lines)
    if args.out:
        Path(args.out).write_text(text + "\n")
    print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
