# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Does the judge agree with us? Compare its pass/fail with the human verdicts.

    python3 tools/eval/calibrate.py docs/eval/runs/<judged run> [<run> ...]
    python3 tools/eval/calibrate.py <runs> --threshold 3 --out docs/eval/calibration.md

The labels for a run are `docs/eval/reviews/<run>.mark.json` (Mark's verdict
wins where he gave one) over `<run>.claude.json`. A rejudged run is labelled by
the run it was rejudged from (`rejudged_from` in its run.json), since the
outputs are the same.

The judge "passes" an output when every score is at least `--threshold`, and,
for an escalation ladder, no rung pair is called "regresses". A "flat" call
alone does not fail a ladder: the rubric already scores one weak step as a 4,
and counting the call on top double-penalised ladders we approve (2026-10-19
calibration: 13 of 15 p3 disagreements were that and nothing else).

Prints a confusion matrix per surface and every disagreement with the judge's
low scores, reasons and flags next to our note — the input for fixing the
rubric, not the prompts.
"""
import argparse
import json
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
REVIEWS = ROOT / "docs/eval/reviews"


def labels(run_dir: Path) -> dict[str, dict]:
    meta = json.loads((run_dir / "run.json").read_text())
    name = run_dir.name
    if not list(REVIEWS.glob(f"{name}.*.json")) and meta.get("rejudged_from"):
        name = Path(meta["rejudged_from"]).name
    out: dict[str, dict] = {}
    claude = REVIEWS / f"{name}.claude.json"
    if claude.exists():
        for k, v in json.loads(claude.read_text()).items():
            out[k] = {"verdict": v["verdict"], "who": "claude", "note": v.get("note", ""),
                      "cause": v.get("cause", "")}
    mark = REVIEWS / f"{name}.mark.json"
    if mark.exists():
        for k, v in json.loads(mark.read_text())["items"].items():
            if v.get("verdict"):
                prev = out.get(k, {})
                out[k] = {"verdict": v["verdict"], "who": "mark",
                          "note": v.get("comment") or prev.get("note", ""), "cause": prev.get("cause", "")}
    return out


def judge_pass(rec: dict, threshold: float) -> tuple[bool | None, list[str]]:
    j = rec.get("judge") or {}
    scores = j.get("scores") or {}
    if not scores:
        return None, []
    why = [f"{d} {s:g}" for d, s in scores.items() if isinstance(s, (int, float)) and s < threshold]
    calls = (j.get("extra") or {}).get("calls") or []
    why += [f"rung {i + 1} regresses" for i, c in enumerate(calls) if c == "regresses"]
    return not why, why


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("runs", nargs="+")
    ap.add_argument("--threshold", type=float, default=4)
    ap.add_argument("--out", default=None)
    args = ap.parse_args()

    matrix = defaultdict(lambda: defaultdict(int))  # surface → (human, judge) → n
    disagree, unlabelled, unjudged = [], 0, 0
    for run in args.runs:
        run_dir = Path(run).resolve()
        lab = labels(run_dir)
        for line in (run_dir / "results.jsonl").read_text().splitlines():
            rec = json.loads(line)
            key = f"{rec['surface']}/{rec['case']}#{rec['sample']}"
            if rec["surface"] == "moderation":
                continue
            human = lab.get(key)
            ok, why = judge_pass(rec, args.threshold)
            if human is None:
                unlabelled += 1
                continue
            if ok is None:
                unjudged += 1
                continue
            h = human["verdict"] == "approve"
            matrix[rec["surface"]][(h, ok)] += 1
            if h != ok:
                j = rec.get("judge") or {}
                disagree.append({"run": run_dir.name, "key": key, "human": human, "judge_ok": ok, "why": why,
                                 "output": rec["output"], "reasons": j.get("reasons") or {},
                                 "flags": j.get("flags") or [],
                                 "better": (j.get("extra") or {}).get("better")})

    lines = [f"# Judge calibration (pass = every score ≥ {args.threshold:g})", "",
             "| Surface | Agree | Judge too strict | Judge too lenient | Agreement |", "|---|---|---|---|---|"]
    tot = defaultdict(int)
    for s, m in sorted(matrix.items()):
        agree = m[(True, True)] + m[(False, False)]
        strict, lenient = m[(True, False)], m[(False, True)]
        n = agree + strict + lenient
        for k, v in (("agree", agree), ("strict", strict), ("lenient", lenient), ("n", n)):
            tot[k] += v
        lines.append(f"| {s} | {agree} | {strict} | {lenient} | {agree / n:.0%} |")
    if tot["n"]:
        lines.append(f"| **all** | {tot['agree']} | {tot['strict']} | {tot['lenient']} | "
                     f"**{tot['agree'] / tot['n']:.0%}** |")
    lines += ["", f"{unlabelled} outputs without a human label, {unjudged} labelled but not judged.", ""]

    for kind, rows in (("Judge too strict (we approved, judge failed)", [d for d in disagree if not d["judge_ok"]]),
                       ("Judge too lenient (we rejected, judge passed)", [d for d in disagree if d["judge_ok"]])):
        lines += [f"## {kind} — {len(rows)}", ""]
        for d in rows:
            out = d["output"] if isinstance(d["output"], str) else " → ".join(d["output"]) \
                if isinstance(d["output"], list) else json.dumps(d["output"], ensure_ascii=False)[:300]
            lines.append(f"- **{d['key']}** ({d['run']}): {out[:400]}")
            lines.append(f"  - us ({d['human']['who']}): {d['human']['verdict']}"
                         f"{' — ' + d['human']['cause'] if d['human']['cause'] else ''}"
                         f"{' — ' + d['human']['note'] if d['human']['note'] else ''}")
            if d["why"]:
                low = [w.split()[0] for w in d["why"]]
                reasons = "; ".join(f"{k}: {v}" for k, v in d["reasons"].items() if k in low)
                lines.append(f"  - judge: {', '.join(d['why'])}" + (f" — {reasons}" if reasons else ""))
            if d["flags"]:
                lines.append(f"  - flags: {', '.join(d['flags'])}")
            if d["better"] and d["better"] != d["output"]:
                lines.append(f"  - judge would say: {d['better']}")
        lines.append("")

    text = "\n".join(lines)
    if args.out:
        Path(args.out).write_text(text + "\n")
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
