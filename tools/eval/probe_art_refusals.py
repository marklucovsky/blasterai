#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Which words does the image safety system refuse to draw?

A topic page that is specific — Bluey, Elsa, a Happy Meal — asks the art
pipeline for named characters, brands and real people, and gpt-image-2 can
refuse those. This sends each word in `cases/art_refusals.json` through the
app's own request (`TileImageGenerator.referencePrompt`: the set's reference
pack + `<word> (<wordClass>)` to /v1/images/edits) several times, because a
refusal is probabilistic (`fever` was refused once and drawn on retry).

    python3 tools/eval/probe_art_refusals.py --attempts 2
    python3 tools/eval/probe_art_refusals.py --group character --attempts 3

Writes `docs/eval/runs/<stamp>-art-refusals/` (results.jsonl, summary.md) and
the drawn tiles to `tools/tile_sets/art_probe_gi2/` (gitignored) — a drawn
tile is not automatically a usable one, so look at them.
"""
import argparse
import base64
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path
from urllib.error import HTTPError

import prompts as P

sys.path.insert(0, str(P.ROOT / "tools"))
from build_tone_variants import post_multipart  # noqa: E402
from generate_by_reference import EDITS_URL, PACKS, PROMPT, STYLES_FILE  # noqa: E402

CASES = Path(__file__).parent / "cases/art_refusals.json"
IMAGES = P.ROOT / "tools/tile_sets/art_probe_gi2"


def attempt(fields: dict, refs: list, key: str) -> dict:
    """One request; a refusal is a result, not an error. Rate limits and 5xx retry."""
    for i in range(4):
        t = time.time()
        try:
            r = post_multipart(EDITS_URL, fields, {}, key, multi_field="image[]", multi=refs)
            return {"status": "drawn", "b64": r["data"][0]["b64_json"], "seconds": round(time.time() - t, 1)}
        except HTTPError as e:
            body = e.read().decode(errors="replace")
            if e.code in (429, 500, 502, 503, 504) and "insufficient_quota" not in body and i < 3:
                time.sleep(3 * 2 ** i)
                continue
            try:
                err = json.loads(body).get("error", {})
            except ValueError:
                err = {"message": body[:300]}
            return {"status": "refused" if e.code == 400 else f"http {e.code}",
                    "code": err.get("code"), "message": err.get("message", ""),
                    "seconds": round(time.time() - t, 1)}
        except Exception as e:  # network
            if i < 3:
                time.sleep(2 * 2 ** i)
                continue
            return {"status": "error", "message": str(e)}
    return {"status": "error", "message": "retries exhausted"}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", default="classic")
    ap.add_argument("--quality", default="low")
    ap.add_argument("--attempts", type=int, default=2)
    ap.add_argument("--group", help="comma-separated groups")
    ap.add_argument("--workers", type=int, default=6)
    args = ap.parse_args()

    words = json.loads(CASES.read_text())["words"]
    if args.group:
        words = [w for w in words if w["group"] in args.group.split(",")]
    style = json.loads((P.ROOT / STYLES_FILE).read_text())[args.set]
    refs = [(p.name, p.read_bytes()) for p in sorted((P.ROOT / PACKS).glob(f"refpack_{args.set}__*.png"))]
    key = os.environ.get("OPENAI_API_KEY", "").strip() or sys.exit("OPENAI_API_KEY not set")

    name = f"{datetime.now():%Y-%m-%d-%H%M}-art-refusals"
    out = P.ROOT / "docs/eval/runs" / name
    out.mkdir(parents=True)
    IMAGES.mkdir(parents=True, exist_ok=True)
    jobs = [(w, n) for w in words for n in range(args.attempts)]
    print(f"{len(words)} words × {args.attempts} attempts = {len(jobs)} images, {args.set} @ {args.quality}")

    def run_and_save(job):
        w, n = job
        subject = w.get("subject") or f"{w['word']} ({w['wordClass']})"
        fields = {"model": "gpt-image-2", "prompt": PROMPT.format(subject=subject, style=style),
                  "size": "1024x1024", "quality": args.quality, "n": "1"}
        r = attempt(fields, refs, key)
        stem = f"{w['group'].replace(' ', '_')}__{w['word']}__{n}".replace("/", "_").replace(" ", "_")
        b64 = r.pop("b64", None)
        if b64:
            (IMAGES / f"{stem}.png").write_bytes(base64.b64decode(b64))
            r["image"] = str((IMAGES / f"{stem}.png").relative_to(P.ROOT))
        print(f"  {w['group']:12} {subject[:50]:50} {r['status']}", flush=True)
        return {**w, "subject": subject, "attempt": n, **r}

    with ThreadPoolExecutor(args.workers) as ex:
        results = list(ex.map(run_and_save, jobs))
    (out / "results.jsonl").write_text("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in results))

    rows, by_group = {}, {}
    for r in results:
        k = (r["group"], r["subject"])
        rows.setdefault(k, []).append(r)
    lines = [f"# Art refusals — {name}", "", f"gpt-image-2, {args.set} reference pack, quality {args.quality}, "
             f"{args.attempts} attempts per word.", "", "| Group | Subject | Drawn | Refusal message |",
             "|---|---|---|---|"]
    for (g, s), rs in rows.items():
        drawn = sum(r["status"] == "drawn" for r in rs)
        msg = next((r.get("message", "") for r in rs if r["status"] != "drawn"), "")
        lines.append(f"| {g} | {s} | {drawn}/{len(rs)} | {msg[:140]} |")
        a, t = by_group.get(g, (0, 0))
        by_group[g] = (a + (drawn == len(rs)), t + 1)
    lines += ["", "Words drawn on every attempt, by group:", ""]
    lines += [f"- {g}: {a}/{t}" for g, (a, t) in by_group.items()]
    (out / "summary.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[-len(by_group):]))
    print(out.relative_to(P.ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
