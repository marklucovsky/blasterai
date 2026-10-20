#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Run the eval: cases × samples through a model, Tier-1 + judge, archived.

    # What would run, and roughly what it costs — no API calls:
    python3 tools/eval/run.py --dry-run

    # Iteration: one surface, a few cases, one judge call each
    python3 tools/eval/run.py --surface sentence --cases pronoun --samples 3 --label pronoun-fix

    # Frozen baseline: everything, three judge calls per output
    python3 tools/eval/run.py --samples 5 --judge-n 3 --label baseline

    # Another model under test (the request is adapted — see models.py)
    python3 tools/eval/run.py --model gpt-6-luna --effort none --label luna-none

    # Re-grade a saved run with the current rubrics, no subject calls
    python3 tools/eval/run.py --rejudge docs/eval/runs/<run> --judge-n 3

Each run writes `docs/eval/runs/<stamp>-<model>-<label>/`:
    run.json       configuration, git commit, prompt and rubric revisions, totals
    results.jsonl  one line per output: request, output, usage, cost, Tier-1, judge
    summary.md     per-surface rollup and the outputs most worth a look

Raw outputs are the point of the archive: after a model retires, its outputs
can still be re-graded with a better judge, but never generated again.
"""
import argparse
import hashlib
import json
import statistics
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import client  # noqa: E402
import judge as J  # noqa: E402
import models  # noqa: E402
import prompts as P  # noqa: E402
import scorers as S  # noqa: E402

HERE = Path(__file__).resolve().parent
CASES = HERE / "cases"
RUNS = P.ROOT / "docs/eval/runs"
SURFACES = ["sentence", "escalation", "scene_generate", "scene_refine", "page_generate",
            "page_refine", "tile_suggest", "moderation"]
AUTHORING = {"scene_generate", "scene_refine", "page_generate", "page_refine", "tile_suggest"}


# MARK: - Cases

def _tiles(raw) -> list[dict]:
    """Tiles as {"value", "wordClass"}, or the shorthand "value:class"."""
    out = []
    for t in raw:
        if isinstance(t, str):
            value, _, wc = t.rpartition(":")
            out.append({"value": value, "wordClass": wc})
        else:
            out.append(t)
    return out


def _current(raw) -> list[dict]:
    return [{"key": t} if isinstance(t, str) else t for t in raw]


def load_cases(surfaces: list[str], filters: list[str], groups: list[str]) -> list[dict]:
    cases = []
    for surface in surfaces:
        path = CASES / f"{surface}.json"
        if not path.exists():
            continue
        for c in json.loads(path.read_text(encoding="utf-8")):
            c = {**c, "surface": surface, "input": dict(c["input"])}
            if "tiles" in c["input"]:
                c["input"]["tiles"] = _tiles(c["input"]["tiles"])
                # SentenceEngine never sends a lone tile to the model: it is
                # spoken as a word, and repeating it re-speaks the word.
                if len(c["input"]["tiles"]) < 2:
                    raise SystemExit(f"{surface}/{c['id']}: one tile never generates a sentence in the app")
            if "current" in c["input"]:
                c["input"]["current"] = _current(c["input"]["current"])
            if filters and not any(f in c["id"] for f in filters):
                continue
            if groups and c.get("group") not in groups:
                continue
            cases.append(c)
    ids = [f"{c['surface']}/{c['id']}" for c in cases]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate case ids: " + ", ".join(sorted({i for i in ids if ids.count(i) > 1})))
    return cases


def request_for(case: dict, **sentence_overrides) -> dict:
    i, s = case["input"], case["surface"]
    if s in ("sentence", "escalation"):
        return P.sentence_body(i["stage"], i["tiles"], history=i.get("history", []),
                               refine=tuple(i["refine"]) if i.get("refine") else None, **sentence_overrides)
    if s == "scene_generate":
        return P.scene_generate_body(i["description"])
    if s == "scene_refine":
        return P.scene_refine_body(i["instruction"], i["current"])
    if s == "page_generate":
        return P.page_generate_body(i["goal"], i["page_name"], i.get("scene_pages", []), i.get("home_page_key", ""))
    if s == "page_refine":
        return P.page_refine_body(i["instruction"], i["page_name"], i["current"],
                                  i.get("scene_pages", []), i.get("home_page_key", ""))
    if s == "tile_suggest":
        return P.tile_suggest_body(i["goal"])
    if s == "moderation":
        return P.moderation_rubric_body(i["words"])
    raise ValueError(s)


# MARK: - Running one output

def subject_call(body: dict, args) -> dict:
    sent, changes = models.adapt(body, args.model, args.effort)
    r = client.call(sent)
    return {**r, "request": sent, "adapted": changes}


def run_unit(case: dict, sample: int, args) -> dict:
    s = case["surface"]
    rec = {"case": case["id"], "surface": s, "group": case.get("group"), "probe": case.get("probe"),
           "input": case["input"], "expect": case.get("expect", {}), "sample": sample}
    if s == "escalation":
        rungs, calls = [], []
        for k in range(case["input"].get("rungs", 4)):
            body = request_for(case, repetition=k, prior=rungs[-1] if rungs else None)
            r = subject_call(body, args)
            calls.append(r)
            if r["error"]:
                break
            rungs.append(r["text"].strip())
        rec["calls"] = calls
        rec["output"] = rungs
        rec["error"] = next((c["error"] for c in calls if c["error"]), None)
    else:
        r = subject_call(request_for(case), args)
        rec["calls"] = [r]
        rec["output"] = r["text"].strip()
        rec["error"] = r["error"]
    score(rec)
    if args.judge and not rec["error"]:
        grade(rec, args)
    return rec


def score(rec: dict) -> None:
    s, i, out = rec["surface"], rec["input"], rec["output"]
    if rec.get("error"):
        rec["tier1"] = {"passed": False, "issues": [f"call failed: {rec['error']}"]}
        return
    if s == "sentence":
        issues = S.score_sentence(out, i["tiles"], i["stage"], rec["expect"])
    elif s == "escalation":
        levels, issues = S.score_escalation(out, i["tiles"], i["stage"], rec["expect"])
        rec["intensities"] = levels
    elif s in AUTHORING:
        current = i.get("current")
        summary, issues = S.score_authoring(s, out, rec["expect"], current)
        rec["summary"] = summary
    else:
        rec["ratings"], issues = S.score_moderation(out, i["words"], rec["expect"])
    rec["tier1"] = {"passed": not issues, "issues": issues}


def grade(rec: dict, args) -> None:
    s = rec["surface"]
    case = {"surface": s, "input": rec["input"]}
    if s == "sentence":
        prompt = J.sentence_request(case, rec["output"])
    elif s == "escalation":
        prompt = J.escalation_request(case, rec["output"])
    elif s in AUTHORING and rec.get("summary"):
        prompt = J.authoring_request(case, rec["summary"])
    else:
        return  # moderation is reviewed by people, not graded
    rec["judge"] = {"model": args.judge, "effort": args.judge_effort,
                    **J.judge(prompt, args.judge, args.judge_effort, args.judge_n)}


# MARK: - Revisions

def digest(paths) -> str:
    h = hashlib.sha256()
    for p in sorted(paths):
        h.update(p.name.encode())
        h.update(p.read_bytes())
    return h.hexdigest()[:10]


def prompt_rev() -> str:
    return digest(list(P.PROMPTS.glob("*")) + [P.RESOURCES / "sentence_prompt.json"])


def rubric_rev() -> str:
    return digest(list(J.RUBRICS.glob("*.txt")))


def git_commit() -> str:
    try:
        sha = subprocess.run(["git", "rev-parse", "--short", "HEAD"], capture_output=True, text=True,
                             cwd=P.ROOT).stdout.strip()
        dirty = subprocess.run(["git", "status", "--porcelain", "--", "claudeBlast/Resources", "tools/eval"],
                               capture_output=True, text=True, cwd=P.ROOT).stdout.strip()
        return sha + ("+dirty" if dirty else "")
    except OSError:
        return "unknown"


# MARK: - Summary

def p(values: list[float], q: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    return values[min(len(values) - 1, int(round(q * (len(values) - 1))))]


def summarize(results: list[dict], meta: dict) -> str:
    lines = [f"# Eval run {meta['name']}", "",
             f"- Subject: `{meta['model']}`" + (f" (effort `{meta['effort']}`)" if meta.get("effort") else ""),
             f"- Judge: `{meta['judge']}` × {meta['judge_n']}" if meta.get("judge") else "- Judge: none",
             f"- Commit `{meta['commit']}`, prompts `{meta['prompt_rev']}`, rubrics `{meta['rubric_rev']}`",
             f"- Samples per case: {meta['samples']}",
             f"- Cost: subject ${meta['subject_cost']:.4f}, judge ${meta['judge_cost']:.4f}", ""]
    lines += ["| Surface | Cases | Outputs | Errors | Tier-1 pass | Judge (mean of medians) | ≤3 on any | Latency p50 / p95 | $ / output |",
              "|---|---|---|---|---|---|---|---|---|"]
    for s in SURFACES:
        rs = [r for r in results if r["surface"] == s]
        if not rs:
            continue
        ok = [r for r in rs if not r.get("error")]
        t1 = sum(1 for r in ok if r["tier1"]["passed"])
        judged = [r["judge"]["scores"] for r in ok if r.get("judge", {}).get("scores")]
        dims = sorted({d for sc in judged for d in sc})
        jtext = ", ".join(f"{d} {statistics.mean(sc[d] for sc in judged if d in sc):.2f}" for d in dims) or "—"
        low = sum(1 for sc in judged if any(v <= 3 for v in sc.values()))
        lat = [c["latency_s"] for r in ok for c in r["calls"] if c.get("latency_s")]
        spend = sum(c["cost"] for r in rs for c in r["calls"])
        lines.append(
            f"| {s} | {len({r['case'] for r in rs})} | {len(rs)} | {len(rs) - len(ok)} | "
            f"{t1}/{len(ok)} | {jtext} | {low}/{len(judged) if judged else 0} | "
            f"{p(lat, .5) or 0:.2f}s / {p(lat, .95) or 0:.2f}s | ${spend / max(len(rs), 1):.5f} |")

    worth = [r for r in results if r.get("error") or not r["tier1"]["passed"]
             or any(v <= 3 for v in r.get("judge", {}).get("scores", {}).values())]
    lines += ["", f"## Worth a look ({len(worth)})", ""]
    for r in worth[:60]:
        out = r["output"] if isinstance(r["output"], str) else " → ".join(r["output"])
        if r["surface"] in AUTHORING or r["surface"] == "moderation":
            out = f"({len(r.get('summary', {}).get('keys', []))} tiles)" if r["surface"] in AUTHORING else ""
        why = r["tier1"]["issues"] + [f"{d}={v}" for d, v in r.get("judge", {}).get("scores", {}).items() if v <= 3]
        lines.append(f"- **{r['surface']}/{r['case']}** #{r['sample']}: {out[:200]}  \n  {'; '.join(why)[:300]}")
    return "\n".join(lines) + "\n"


# MARK: - Main

def plan_cost(cases: list[dict], args) -> str:
    subject_calls = sum(c["input"].get("rungs", 4) if c["surface"] == "escalation" else 1 for c in cases) * args.samples
    judged = sum(1 for c in cases if c["surface"] != "moderation") * args.samples
    judge_calls = judged * args.judge_n if args.judge else 0
    # Rough per-call costs from the 2026-10-19 calibration.
    est = subject_calls * 0.0003 + judge_calls * (0.006 if args.judge == "gpt-6.1-sol" else 0.03)
    return (f"{len(cases)} cases × {args.samples} samples → {subject_calls} subject calls, "
            f"{judge_calls} judge calls, roughly ${est:.2f}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--surface", default=",".join(SURFACES), help="comma-separated surfaces")
    ap.add_argument("--cases", default="", help="comma-separated substrings of case ids")
    ap.add_argument("--group", default="", help="comma-separated case groups")
    ap.add_argument("--model", default="gpt-4o-mini")
    ap.add_argument("--effort", default=None)
    ap.add_argument("--samples", type=int, default=1)
    ap.add_argument("--judge", default="gpt-6.1-sol")
    ap.add_argument("--judge-effort", default="low")
    ap.add_argument("--judge-n", type=int, default=1)
    ap.add_argument("--no-judge", action="store_true")
    ap.add_argument("--label", default="run")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--rejudge", default=None, help="re-grade a saved run directory")
    args = ap.parse_args()
    if args.no_judge:
        args.judge = None
    if args.judge and args.judge == args.model:
        raise SystemExit("the judge must not be the model under test")
    if args.judge:
        models.get(args.judge)
    models.get(args.model)

    if args.rejudge:
        src = Path(args.rejudge)
        old = json.loads((src / "run.json").read_text())
        results = [json.loads(l) for l in (src / "results.jsonl").read_text().splitlines() if l.strip()]
        args.model, args.effort, args.samples = old["model"], old.get("effort"), old["samples"]
        args.label = f"{old['label']}-rejudge"
        print(f"re-grading {len(results)} outputs from {src.name}")
    else:
        surfaces = [s for s in args.surface.split(",") if s]
        unknown = set(surfaces) - set(SURFACES)
        if unknown:
            raise SystemExit(f"unknown surface(s): {', '.join(unknown)}")
        cases = load_cases(surfaces, [f for f in args.cases.split(",") if f],
                           [g for g in args.group.split(",") if g])
        if not cases:
            raise SystemExit("no cases matched")
        print(plan_cost(cases, args))
        if args.dry_run:
            return 0

    stamp = datetime.now().strftime("%Y-%m-%d-%H%M")
    name = f"{stamp}-{args.model}{'-' + args.effort if args.effort else ''}-{args.label}"
    out_dir = RUNS / name
    out_dir.mkdir(parents=True, exist_ok=False)
    started = time.time()

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        if args.rejudge:
            # Re-check against the case files as they are now, so a corrected
            # expectation applies to saved outputs; a case since deleted keeps
            # the expectation it was run with.
            current = {(c["surface"], c["id"]): c for c in load_cases(SURFACES, [], [])}

            def regrade(rec):
                if (case := current.get((rec["surface"], rec["case"]))) is not None:
                    rec["expect"] = case.get("expect", {})
                if args.judge:
                    rec.pop("judge", None)
                score(rec)
                if args.judge and not rec.get("error"):
                    grade(rec, args)
                return rec
            results = list(pool.map(regrade, results))
        else:
            units = [(c, n) for c in cases for n in range(args.samples)]
            results = list(pool.map(lambda u: run_unit(u[0], u[1], args), units))

    subject_cost = sum(c["cost"] for r in results for c in r["calls"])
    judge_cost = sum(r.get("judge", {}).get("cost", 0) for r in results)
    meta = {"name": name, "label": args.label, "model": args.model, "effort": args.effort,
            "judge": args.judge, "judge_effort": args.judge_effort, "judge_n": args.judge_n,
            "samples": args.samples, "commit": git_commit(), "prompt_rev": prompt_rev(),
            "rubric_rev": rubric_rev(), "rejudged_from": args.rejudge,
            "started": datetime.fromtimestamp(started).isoformat(timespec="seconds"),
            "seconds": round(time.time() - started, 1), "outputs": len(results),
            "subject_cost": subject_cost, "judge_cost": judge_cost}
    (out_dir / "run.json").write_text(json.dumps(meta, indent=2) + "\n")
    with (out_dir / "results.jsonl").open("w") as f:
        for r in results:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    (out_dir / "summary.md").write_text(summarize(results, meta))
    subject_note = " (reused, not re-spent)" if args.rejudge else ""
    print(f"{len(results)} outputs, subject ${subject_cost:.4f}{subject_note} + judge ${judge_cost:.4f}, "
          f"{meta['seconds']}s → {out_dir.relative_to(P.ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
