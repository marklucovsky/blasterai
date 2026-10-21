#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Build the human review page for an eval run.

    python3 tools/eval/build_review.py docs/eval/runs/<run>
    python3 tools/eval/build_review.py docs/eval/runs/<new> --compare docs/eval/runs/<approved>

Writes `<run>/review.html` (not committed — it is rebuilt from the run) and
opens it. Each output shows its input as the child would see it (tile chips by
word class, or the caregiver's request), every Tier-1 issue, the judge's scores
and reasons if the run was judged, and Claude's verdict from
`docs/eval/reviews/<run>.claude.json` if there is one.

The reviewer approves or rejects each output, agrees or disagrees with Claude's
call, and comments. State lives in the browser (localStorage, per run) and
**Export** downloads `<run>.mark.json`; save it into `docs/eval/reviews/` and
Claude reads it back. Approved outputs become the golden set; every comment
gets a root cause.

`--compare` puts another run's output for the same case and sample beside each
one — the approved 4o-mini output next to Luna's, or v0 next to a prompt fix.
"""
import argparse
import html
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prompts as P  # noqa: E402
from calibrate import judge_pass  # noqa: E402

REVIEWS = P.ROOT / "docs/eval/reviews"


def load(run: Path) -> tuple[dict, list[dict]]:
    meta = json.loads((run / "run.json").read_text())
    results = [json.loads(l) for l in (run / "results.jsonl").read_text().splitlines() if l.strip()]
    return meta, results


def key(r: dict) -> str:
    return f"{r['surface']}/{r['case']}#{r['sample']}"


def slim(r: dict) -> dict:
    """What the page needs from one result."""
    j = r.get("judge") or {}
    out = {"key": key(r), "surface": r["surface"], "case": r["case"], "sample": r["sample"],
           "group": r.get("group"), "probe": r.get("probe"), "input": r["input"], "expect": r.get("expect"),
           "output": r["output"], "error": r.get("error"), "tier1": r["tier1"]["issues"],
           "notes": (r.get("summary") or {}).get("notes", []),
           "judge": {"scores": j.get("scores"), "reasons": j.get("reasons"), "flags": j.get("flags"),
                     "extra": j.get("extra")} if j.get("scores") else None}
    if out["judge"]:
        out["judge"]["ok"], out["judge"]["why"] = judge_pass(r, 4)
    if "summary" in r:
        out["tiles"] = r["summary"]["keys"]
        out["new_words"] = r["summary"]["new_words"]
    if "ratings" in r:
        out["ratings"] = r["ratings"]
    return out


def dedupe(items: list[dict], claude: dict) -> list[dict]:
    """One card per distinct output of a case. Samples that said the same thing
    (and drew the same Tier-1 issues and Claude verdict) are one decision; the
    card lists their judge scores once per distinct set. A verdict on the card
    is exported for every sample it stands for."""
    groups: dict[tuple, list[dict]] = {}
    for it in items:
        c = claude.get(it["key"], {})
        g = (it["surface"], it["case"], json.dumps(it["output"], sort_keys=True), it["error"],
             json.dumps(it["tier1"]), c.get("verdict"), c.get("cause"), c.get("note"))
        groups.setdefault(g, []).append(it)
    out = []
    for members in groups.values():
        head = dict(members[0])
        head["keys"] = [m["key"] for m in members]
        head["samples"] = [m["sample"] for m in members]
        judges: dict[str, dict] = {}
        for m in members:
            if m["judge"]:
                j = judges.setdefault(json.dumps(m["judge"]["scores"], sort_keys=True), dict(m["judge"], samples=[]))
                j["samples"].append(m["sample"])
        head["judges"] = list(judges.values())
        head["judge"] = {"ok": all(j["ok"] for j in judges.values())} if judges else None
        out.append(head)
    return out


# Case ids renamed since a run was reviewed (see docs/eval/WORKLIST.md), so an
# earlier verdict still finds its case.
RENAMED = {"escalation/chocolate": "escalation/want_chocolate",
           "escalation/chocolate_IV": "escalation/want_chocolate_IV",
           "sentence/outside": "sentence/mom_outside", "sentence/all_done": "sentence/all_done_mom",
           "sentence/scared": "sentence/dad_scared"}


def previous_verdicts(run_name: str) -> dict:
    """The compared run's verdict per case (any sample rejected → rejected).
    Mark's verdict wins over Claude's where he gave one."""
    def read(suffix):
        p = REVIEWS / f"{run_name}.{suffix}.json"
        if not p.exists():
            return {}
        d = json.loads(p.read_text())
        return d.get("items", d)
    claude, mark = read("claude"), read("mark")
    out = {}
    for k in set(claude) | set(mark):
        c, m = claude.get(k, {}), mark.get(k, {})
        verdict = m.get("verdict") or c.get("verdict")
        if not verdict:
            continue
        base = k.split("#")[0]
        base = RENAMED.get(base, base)
        entry = out.setdefault(base, {"verdict": "approve", "notes": []})
        if verdict == "reject":
            entry["verdict"] = "reject"
        for note in (m.get("comment"), c.get("note")):
            if note and note not in entry["notes"]:
                entry["notes"].append(note)
    return out


def mark_by_output(results: list[dict], run_name: str) -> dict:
    """Mark's verdict per (surface, case, output) in a reviewed run. An output he
    judged differently on different samples carries nothing."""
    p = REVIEWS / f"{run_name}.mark.json"
    if not p.exists():
        return {}
    d = json.loads(p.read_text())
    labels = d.get("items", d)
    out: dict[tuple, dict | None] = {}
    for r in results:
        m = labels.get(key(r), {})
        if not m.get("verdict"):
            continue
        k = (r["surface"], r["case"], json.dumps(r["output"], sort_keys=True))
        v = {"verdict": m["verdict"], "comment": m.get("comment", "")}
        out[k] = v if out.get(k, v) == v else None
    return {k: v for k, v in out.items() if v}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("run")
    ap.add_argument("--compare", default=None)
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()
    run = Path(args.run).resolve()
    meta, results = load(run)

    claude = {}
    claude_file = REVIEWS / f"{meta['name']}.claude.json"
    if not claude_file.exists() and meta.get("rejudged_from"):
        # A rejudge has the same outputs: Claude's verdicts carry over.
        claude_file = REVIEWS / f"{Path(meta['rejudged_from']).name}.claude.json"
    if claude_file.exists():
        claude = json.loads(claude_file.read_text())
    compare, compare_name, previous = {}, None, {}
    if args.compare:
        cmeta, cresults = load(Path(args.compare))
        compare_name = cmeta["name"]
        compare = {key(r): slim(r) for r in cresults}
        previous = previous_verdicts(cmeta["name"])

    items = dedupe([slim(r) for r in results], claude)
    if args.compare:
        # Mark's verdict on the exact same output in the compared run carries
        # over: he reviews only what is new, and the export still covers all.
        seen = mark_by_output(cresults, cmeta["name"])
        for it in items:
            if c := seen.get((it["surface"], it["case"], json.dumps(it["output"], sort_keys=True))):
                it["carried"] = c
    data = {"run": meta, "items": items, "outputs": len(results), "claude": claude,
            "compare": compare, "compareName": compare_name, "previous": previous,
            "classes": P.word_classes()}
    page = TEMPLATE.replace("__TITLE__", html.escape(meta["name"])).replace(
        "__DATA__", json.dumps(data, ensure_ascii=False).replace("</", "<\\/"))
    out = run / "review.html"
    out.write_text(page, encoding="utf-8")
    print(f"{out.relative_to(P.ROOT)}  ({len(results)} outputs on {len(items)} cards, Claude verdicts: {len(claude)})")
    if not args.no_open:
        subprocess.run(["open", str(out)])
    return 0


TEMPLATE = r"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Eval review — __TITLE__</title>
<style>
:root { --bg:#f6f6f4; --card:#fff; --ink:#1d1d1f; --muted:#6b6b70; --line:#e2e2e0;
        --ok:#1f7a3a; --bad:#b3261e; --warn:#9a6700; --accent:#3557c5; }
@media (prefers-color-scheme: dark) { :root { --bg:#161618; --card:#1f1f22; --ink:#ececee; --muted:#9a9aa0;
        --line:#333338; --ok:#5cc47b; --bad:#ff7b72; --warn:#e3b341; --accent:#8aa4ff; } }
* { box-sizing:border-box } body { margin:0; font:15px/1.45 -apple-system, system-ui, sans-serif; background:var(--bg); color:var(--ink) }
header { position:sticky; top:0; z-index:5; background:var(--bg); border-bottom:1px solid var(--line); padding:10px 16px }
header h1 { font-size:16px; margin:0 0 6px } .meta { color:var(--muted); font-size:13px }
.bar { display:flex; flex-wrap:wrap; gap:8px; align-items:center; margin-top:8px }
select, input[type=search], button { font:inherit; padding:5px 9px; border:1px solid var(--line); border-radius:7px; background:var(--card); color:var(--ink) }
button { cursor:pointer } button.on { border-color:var(--accent); color:var(--accent); font-weight:600 }
main { padding:12px 16px 80px; max-width:1100px; margin:0 auto }
.card { background:var(--card); border:1px solid var(--line); border-radius:12px; padding:12px 14px; margin:10px 0 }
.card.approved { border-left:5px solid var(--ok) } .card.rejected { border-left:5px solid var(--bad) }
.card.cursor { box-shadow:0 0 0 3px var(--accent) }
kbd { font:12px ui-monospace, monospace; border:1px solid var(--line); border-radius:4px; padding:0 4px }
.head { display:flex; justify-content:space-between; gap:8px; flex-wrap:wrap }
.id { font-weight:600 } .probe { color:var(--muted); font-size:13px }
.chips { display:flex; flex-wrap:wrap; gap:5px; margin:6px 0 }
.chip { padding:2px 8px; border-radius:6px; font-size:13px; border:1px solid rgba(0,0,0,.08) }
.chip.new { outline:2px dashed var(--accent); outline-offset:1px }
.out { font-size:18px; margin:8px 0; white-space:pre-wrap } .out.ladder div { font-size:16px; margin:2px 0 }
.cmp { border-top:1px dashed var(--line); margin-top:6px; padding-top:6px; color:var(--muted) }
.issues { color:var(--bad); font-size:13px; margin:4px 0 } .notes { color:var(--warn); font-size:13px }
.jpass { color:#2a7 } .judge { font-size:13px; color:var(--muted) } .judge b { color:var(--ink) } .low { color:var(--bad); font-weight:600 }
.claude { font-size:13px; margin-top:6px; padding:6px 8px; border-radius:8px; background:rgba(127,127,127,.08) }
.actions { display:flex; flex-wrap:wrap; gap:6px; margin-top:8px; align-items:center }
textarea { width:100%; min-height:38px; font:inherit; font-size:14px; padding:6px; border:1px solid var(--line); border-radius:7px; background:var(--card); color:var(--ink) }
table.r { border-collapse:collapse; font-size:14px } table.r td { padding:2px 10px 2px 0 }
.inappropriate { color:var(--bad) } .questionable { color:var(--warn) }
details summary { cursor:pointer; color:var(--muted); font-size:13px }
</style></head><body>
<header>
  <h1>Eval review — __TITLE__</h1>
  <div class="meta" id="meta"></div>
  <div class="bar">
    <select id="surface"><option value="">all surfaces</option></select>
    <select id="group"><option value="">all groups</option></select>
    <select id="status">
      <option value="">everything</option><option value="todo">not reviewed by me</option>
      <option value="new">new outputs (no verdict carried)</option>
      <option value="claude-reject">Claude rejected</option><option value="prev-reject">rejected in the compared run</option>
      <option value="tier1">Tier-1 failed</option>
      <option value="judge-fail">judge failed</option><option value="judge-vs-claude">judge ≠ Claude</option>
      <option value="judge-vs-me">judge ≠ my verdict</option>
      <option value="disagree">I disagree with Claude</option><option value="rejected">I rejected</option>
      <option value="commented">has my comment</option>
    </select>
    <input type="search" id="q" placeholder="search">
    <span id="count" class="meta"></span>
    <button id="export">Export my review</button>
  </div>
  <div class="meta" style="margin-top:6px"><kbd>n</kbd>/<kbd>p</kbd> next / previous ·
    <kbd>Enter</kbd> approve, next · <kbd>x</kbd> reject and type why ·
    <kbd>a</kbd> agree with Claude, next · <kbd>d</kbd> disagree and type why ·
    <kbd>Enter</kbd> in a comment saves it</div>
</header>
<main id="list"></main>
<script>
const DATA = __DATA__;
const RUN = DATA.run.name, STORE = "eval-review:" + RUN;
let state = {};
try { state = JSON.parse(localStorage.getItem(STORE)) || {}; } catch (e) {}
const save = () => { try { localStorage.setItem(STORE, JSON.stringify(state)); } catch (e) {} };
const esc = s => String(s ?? "").replace(/[&<>"]/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]));

const HUE = {people:"#e9d5ff", actions:"#fed7aa", describe:"#bbf7d0", feeling:"#fbcfe8", social:"#fbcfe8",
  question:"#fbcfe8", food:"#fecaca", drinks:"#bae6fd", places:"#bfdbfe", animal:"#e7d3b5", core:"#e5e7eb",
  body:"#fde2d8", health:"#fde2d8", play:"#fef08a", toy:"#fef08a", sports:"#fef08a", object:"#e2e8f0",
  colors:"#a7f3d0", plant:"#d9f99d"};
const chip = (word, cls, isNew) =>
  `<span class="chip${isNew ? " new" : ""}" style="background:${HUE[cls] || "#eee"};color:#111">${esc(word)}${cls ? ` <small>(${esc(cls)})</small>` : ""}</span>`;

document.getElementById("meta").textContent =
  `subject ${DATA.run.model}${DATA.run.effort ? " @" + DATA.run.effort : ""} · prompts ${DATA.run.prompt_rev} · ` +
  `${DATA.run.judge ? "judge " + DATA.run.judge + " ×" + DATA.run.judge_n : "no judge"} · ${DATA.outputs} outputs on ${DATA.items.length} cards` +
  (DATA.compareName ? ` · compared with ${DATA.compareName}` : "");

for (const [id, field] of [["surface", "surface"], ["group", "group"]]) {
  const el = document.getElementById(id);
  [...new Set(DATA.items.map(i => i[field]).filter(Boolean))].sort()
    .forEach(v => el.insertAdjacentHTML("beforeend", `<option>${esc(v)}</option>`));
}

function inputHTML(it) {
  const i = it.input;
  if (i.tiles) {
    let h = `<div class="chips">${i.tiles.map(t => chip(t.value, t.wordClass)).join("")}</div>` +
            `<div class="probe">Stage ${esc(i.stage)}${i.rungs ? ` · ${i.rungs} rungs` : ""}</div>`;
    if (i.history) h += `<div class="probe">earlier: ${i.history.map(esc).join(" | ")}</div>`;
    if (i.refine) h += `<div class="probe">refine "${esc(i.refine[0])}" → <b>${esc(i.refine[1])}</b></div>`;
    return h;
  }
  if (i.words) return "";
  let h = "";
  for (const k of ["description", "goal", "instruction"]) if (i[k]) h += `<div><b>${k}:</b> “${esc(i[k])}”</div>`;
  if (i.page_name) h += `<div class="probe">page: ${esc(i.page_name)}</div>`;
  if (i.current) h += `<div class="probe">board before:</div><div class="chips">${i.current.map(t =>
      chip(t.displayName || t.key, DATA.classes[t.key], !DATA.classes[t.key])).join("")}</div>`;
  if (i.scene_pages) h += `<div class="probe">scene: ${i.scene_pages.map(p => esc(p.key) + "=[" + p.tiles.map(esc).join(", ") + "]").join("; ")}</div>`;
  return h;
}

function outputHTML(it) {
  if (it.error) return `<div class="issues">call failed: ${esc(it.error)}</div>`;
  if (Array.isArray(it.output)) return `<div class="out ladder">${it.output.map((s, n) => `<div>[${n}] ${esc(s)}</div>`).join("")}</div>`;
  if (it.ratings) return `<table class="r">${Object.entries(it.ratings).map(([w, r]) =>
      `<tr><td>${esc(w)}</td><td class="${esc(r.split(" ")[0])}">${esc(r)}</td></tr>`).join("")}</table>`;
  if (it.tiles) {
    const nw = it.new_words || {};
    return `<div class="chips">${it.tiles.map(k => chip(nw[k]?.displayName || k, nw[k]?.wordClass || DATA.classes[k],
      !!nw[k])).join("")}</div><div class="probe">${it.tiles.length} tiles · dashed = new word</div>` +
      `<details><summary>raw model output</summary><pre style="white-space:pre-wrap;font-size:12px">${esc(it.output)}</pre></details>`;
  }
  return `<div class="out">${esc(it.output)}</div>`;
}

function judgeHTML(it) {
  // One row per distinct set of judge scores among the card's samples.
  const multi = it.judges.length > 1;
  return it.judges.map(j => judgeRow(it, j, multi ? `<b>#${j.samples.join(", #")}</b> · ` : "")).join("");
}

function judgeRow(it, j, label) {
  const sc = Object.entries(j.scores).map(([d, v]) => `<span class="${v <= 3 ? "low" : ""}">${d} ${v}</span>`).join(" · ");
  const why = Object.entries(j.reasons || {}).filter(([d]) => j.scores[d] <= 3).map(([d, r]) => `<div>${d}: ${esc(r)}</div>`).join("");
  const ex = j.extra || {};
  let more = "";
  if (ex.better && ex.better !== it.output) more += `<div>judge would say: <b>${esc(ex.better)}</b></div>`;
  if (ex.missing?.length) more += `<div>missing: ${ex.missing.map(esc).join(", ")}</div>`;
  if (ex.remove?.length) more += `<div>remove: ${ex.remove.map(esc).join(", ")}</div>`;
  if (ex.calls) more += `<div>steps: ${ex.calls.join(" → ")}</div>`;
  const badge = j.ok ? `<b class="jpass">judge: pass</b>` : `<b class="low">judge: fail (${esc(j.why.join(", "))})</b>`;
  return `<div class="judge">${label}${badge} · ${sc}${why}${more}</div>`;
}

function claudeHTML(it) {
  const c = DATA.claude[it.key]; if (!c) return "";
  const col = c.verdict === "reject" ? "var(--bad)" : "var(--ok)";
  return `<div class="claude"><b style="color:${col}">Claude: ${esc(c.verdict)}</b>` +
    `${c.cause ? ` · <i>${esc(c.cause)}</i>` : ""}${c.note ? ` — ${esc(c.note)}` : ""}</div>`;
}

function carriedHTML(it) {
  const c = it.carried; if (!c) return "";
  return `<div class="claude"><b style="color:${c.verdict === "reject" ? "var(--bad)" : "var(--ok)"}">` +
    `you ${c.verdict === "reject" ? "rejected" : "approved"} this exact output in ${esc(DATA.compareName)}</b>` +
    `${c.comment ? " — " + esc(c.comment) : ""} · carried over unless you mark it here</div>`;
}

function compareHTML(it) {
  const prev = DATA.previous[`${it.surface}/${it.case}`];
  const prevHTML = prev ? `<div><b style="color:${prev.verdict === "reject" ? "var(--bad)" : "var(--ok)"}">` +
    `${prev.verdict === "reject" ? "rejected" : "approved"} there</b>${prev.notes.length ? " — " + prev.notes.map(esc).join(" / ") : ""}</div>` : "";
  // The compared run may hold only sample 0 of a case, or the case under its old id.
  const o = DATA.compare[it.key] || Object.values(DATA.compare).find(x => `${x.surface}/${x.case}` === `${it.surface}/${it.case}`);
  if (!o) return prevHTML ? `<div class="cmp">${prevHTML}</div>` : "";
  const text = Array.isArray(o.output) ? o.output.join(" → ") : o.tiles ? o.tiles.join(", ") : o.ratings ? JSON.stringify(o.ratings) : o.output;
  return `<div class="cmp"><b>${esc(DATA.compareName)}:</b> ${esc(text)}${o.tier1.length ? `<div class="issues">${o.tier1.map(esc).join("; ")}</div>` : ""}${prevHTML}</div>`;
}

function card(it) {
  const s = state[it.key] || {};
  const cls = (s.verdict === "approve" ? "approved" : s.verdict === "reject" ? "rejected" : "") +
              (it.key === cursorKey ? " cursor" : "");
  const btn = (field, val, label) => `<button data-k="${esc(it.key)}" data-f="${field}" data-v="${val}" class="${s[field] === val ? "on" : ""}">${label}</button>`;
  return `<div class="card ${cls}" id="${esc(it.key)}" data-key="${esc(it.key)}">
    <div class="head"><div><span class="id">${esc(it.surface)}/${esc(it.case)}</span> <span class="probe">${it.samples.length > 1 ? `<b>×${it.samples.length}</b> same output (#${it.samples.join(", #")})` : `#${it.sample}`} · ${esc(it.group || "")}</span></div>
      <div class="probe">${esc(it.probe || "")}</div></div>
    ${inputHTML(it)}${outputHTML(it)}${compareHTML(it)}
    ${it.tier1.length ? `<div class="issues">Tier-1: ${it.tier1.map(esc).join("; ")}</div>` : ""}
    ${it.notes?.length ? `<div class="notes">${it.notes.map(esc).join("; ")}</div>` : ""}
    ${judgeHTML(it)}${claudeHTML(it)}${carriedHTML(it)}
    <div class="actions">output: ${btn("verdict", "approve", "✓ approve")}${btn("verdict", "reject", "✗ reject")}
      ${DATA.claude[it.key] ? `&nbsp; Claude's call: ${btn("claude", "agree", "agree")}${btn("claude", "disagree", "disagree")}` : ""}</div>
    <textarea data-k="${esc(it.key)}" placeholder="comment (what's wrong, what it should say)">${esc(s.comment || "")}</textarea>
  </div>`;
}

function visible(it) {
  const f = id => document.getElementById(id).value;
  const s = state[it.key] || {}, c = DATA.claude[it.key];
  if (f("surface") && it.surface !== f("surface")) return false;
  if (f("group") && it.group !== f("group")) return false;
  const st = f("status");
  if (st === "todo" && s.verdict) return false;
  if (st === "claude-reject" && c?.verdict !== "reject") return false;
  if (st === "prev-reject" && DATA.previous[`${it.surface}/${it.case}`]?.verdict !== "reject") return false;
  if (st === "new" && it.carried) return false;
  if (st === "todo" && it.carried) return false;
  if (st === "tier1" && !it.tier1.length) return false;
  const jok = it.judge ? it.judge.ok : null;
  if (st === "judge-fail" && jok !== false) return false;
  if (st === "judge-vs-claude" && (jok === null || !c || (c.verdict === "approve") === jok)) return false;
  if (st === "judge-vs-me" && (jok === null || !s.verdict || (s.verdict === "approve") === jok)) return false;
  if (st === "disagree" && s.claude !== "disagree") return false;
  if (st === "rejected" && s.verdict !== "reject") return false;
  if (st === "commented" && !s.comment) return false;
  const q = f("q").toLowerCase();
  if (q && !JSON.stringify([it.case, it.input, it.output, it.probe]).toLowerCase().includes(q)) return false;
  return true;
}

function render() {
  const items = DATA.items.filter(visible);
  document.getElementById("list").innerHTML = items.map(card).join("");
  const done = DATA.items.filter(i => state[i.key]?.verdict || i.carried).length;
  document.getElementById("count").textContent =
    `${items.length} shown · ${done}/${DATA.items.length} cards reviewed (${DATA.outputs} outputs)`;
}

function set(k, field, value, toggle) {
  const s = state[k] ||= {};
  s[field] = toggle && s[field] === value ? undefined : value;
  const theirs = DATA.claude[k]?.verdict;
  // The verdict and the agreement are one decision seen two ways: a verdict
  // records whether it matches Claude's, and agreeing adopts Claude's verdict.
  if (field === "verdict" && s.verdict && theirs) s.claude = s.verdict === theirs ? "agree" : "disagree";
  if (field === "claude" && s.claude === "agree" && theirs) s.verdict = theirs;
  save(); const y = window.scrollY; render(); window.scrollTo(0, y);
}
document.addEventListener("click", e => {
  const card = e.target.closest(".card");
  if (card) {
    cursorKey = card.dataset.key;
    document.querySelectorAll(".card.cursor").forEach(c => c.classList.remove("cursor"));
    card.classList.add("cursor");
  }
  const b = e.target.closest("button[data-k]"); if (!b) return;
  set(b.dataset.k, b.dataset.f, b.dataset.v, true);
});

// Keyboard review: a cursor walks the visible cards (same keys as the tile
// review page, plus a / d for agreeing or disagreeing with Claude's call).
let cursorKey = null;
const cards = () => [...document.querySelectorAll(".card")];
function moveCursor(card) {
  if (!card) return;
  document.querySelectorAll(".card.cursor").forEach(c => c.classList.remove("cursor"));
  card.classList.add("cursor");
  cursorKey = card.dataset.key;
  card.scrollIntoView({block: "center", behavior: "smooth"});
}
function step(delta) {
  const cs = cards(); if (!cs.length) return;
  const i = cs.findIndex(c => c.dataset.key === cursorKey);
  if (i === -1) return moveCursor(cs.find(c => !state[c.dataset.key]?.verdict) || cs[0]);
  moveCursor(cs[Math.max(0, Math.min(cs.length - 1, i + delta))]);
}
function comment(k) {
  const t = document.querySelector(`textarea[data-k="${CSS.escape(k)}"]`);
  if (t) { t.focus(); t.setSelectionRange(t.value.length, t.value.length); }
}
document.addEventListener("keydown", e => {
  if (e.target.matches("input, select, textarea")) {
    // Enter in a comment saves it and hands the keys back to the cursor;
    // Shift-Enter still makes a new line.
    if (e.key === "Enter" && !e.shiftKey && e.target.matches("textarea")) { e.preventDefault(); e.target.blur(); }
    else if (e.key === "Escape") e.target.blur();
    return;
  }
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  const k = cursorKey;
  if (e.key === "n") { e.preventDefault(); step(1); }
  else if (e.key === "p") { e.preventDefault(); step(-1); }
  else if (e.key === "Enter" && k) { e.preventDefault(); set(k, "verdict", "approve"); step(1); }
  else if (e.key === "x" && k) { e.preventDefault(); set(k, "verdict", "reject"); comment(k); }
  else if (e.key === "a" && k && DATA.claude[k]) { e.preventDefault(); set(k, "claude", "agree"); step(1); }
  else if (e.key === "d" && k && DATA.claude[k]) { e.preventDefault(); set(k, "claude", "disagree"); comment(k); }
});
document.addEventListener("input", e => {
  if (e.target.matches("textarea[data-k]")) { (state[e.target.dataset.k] ||= {}).comment = e.target.value; save(); }
});
for (const id of ["surface", "group", "status", "q"]) document.getElementById(id).addEventListener("input", render);
document.getElementById("export").addEventListener("click", () => {
  // A card stands for every sample that said the same thing: export its
  // verdict once per sample, so the review file stays per output.
  const items = {};
  for (const it of DATA.items) {
    const s = state[it.key]?.verdict ? state[it.key] : it.carried ? {...it.carried, carried: true} : state[it.key];
    if (s) for (const k of it.keys) items[k] = s;
  }
  const review = {run: RUN, exported: new Date().toISOString(), items};
  const a = document.createElement("a");
  a.href = URL.createObjectURL(new Blob([JSON.stringify(review, null, 2)], {type: "application/json"}));
  a.download = `${RUN}.mark.json`; a.click();
});
render();
</script></body></html>
"""

if __name__ == "__main__":
    sys.exit(main())
