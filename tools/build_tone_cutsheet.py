#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Full-set review sheet for the Classic skin-tone variants — every tile, one row.

## Why this is a careful surface rather than a contact sheet

Skin tone is the one thing in this project where getting it subtly wrong is worse
than not shipping it. A family who picks the tone that matches their child and
then finds a dozen tiles where the figure drifted, the hair went blond, or the
face lost its features has been told something about how much care went in. So
the sheet is built to make an unreviewed tile *visible* rather than to make the
review feel finished:

- Nothing is approved by default. The counter shows unreviewed separately, and
  export refuses to pretend a partial pass is complete.
- Judgement is per TONE, not per row — a tile can be fine at Medium and wrong at
  Medium-Dark, and collapsing that loses the thing worth knowing.
- Rejections carry a reason, because "regenerate this" without "the hair blends
  into the skin" just produces the same tile again.

Export writes `rejected.json` per set in the format `review_tiles.py` already
uses — `{key: {"reason": str, "attempts": int}}` — so a rejection list feeds the
existing regen path rather than a new one.

State lives in localStorage, so a 255-row review survives a refresh.

Usage:
    python3 tools/build_tone_cutsheet.py
    python3 tools/build_tone_cutsheet.py --no-open
"""

import argparse
import json
import os
import webbrowser
from pathlib import Path

BASE = Path("tools/tile_sets")
SOURCE = BASE / "classic"
SKIN_CACHE = BASE / "classic_skin_tiles.json"
OUT = BASE / "tone_cutsheet"

TONES = [
    ("classic_chain_medium", "medium", "🏽", "Medium"),
    ("classic_chain_medium_dark", "medium_dark", "🏾", "Medium-Dark"),
]

HTML = """<!doctype html>
<html><head><meta charset="utf-8"><title>Skin-tone review — every tile</title>
<style>
  :root {{ --bg:#f6f6f8; --panel:#fff; --ink:#16161a; --muted:#6b6b76; --line:#e2e2e8;
           --accent:#2f6df6; --ok:#15803d; --bad:#c2410c; --warn:#b45309; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg:#121216; --panel:#1c1c22; --ink:#f0f0f4; --muted:#9a9aa6;
             --line:#2c2c36; --accent:#7aa2ff; --ok:#4ade80; --bad:#fb923c; --warn:#fbbf24; }}
  }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink);
    font:14px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif; }}
  header {{ padding:20px 24px 4px; }}
  h1 {{ font-size:20px; margin:0 0 4px; letter-spacing:-.01em; }}
  .sub {{ color:var(--muted); font-size:13px; max-width:78ch; }}
  .bar {{ position:sticky; top:0; z-index:30; background:var(--bg);
    border-bottom:1px solid var(--line); padding:10px 24px;
    display:flex; gap:14px; align-items:center; flex-wrap:wrap; }}
  .counts {{ display:flex; gap:14px; font-size:13px; font-variant-numeric:tabular-nums; }}
  .counts b {{ font-weight:700; }}
  .c-ok {{ color:var(--ok); }} .c-bad {{ color:var(--bad); }} .c-todo {{ color:var(--warn); }}
  input[type=search], select, button {{ font:inherit; font-size:13px; padding:5px 9px;
    border-radius:7px; border:1px solid var(--line); background:var(--panel); color:var(--ink); }}
  button {{ cursor:pointer; }}
  button.primary {{ background:var(--accent); color:#fff; border-color:var(--accent); }}
  .wrap {{ padding:10px 24px 80px; }}
  /* The three tiles sit adjacent so the progression reads left-to-right as one
     strip; judgement controls are pulled out to the right rather than wedged
     between the images, which broke the comparison. */
  .row {{ display:grid; grid-template-columns:104px auto auto auto 1fr; gap:0;
    background:var(--panel); border:1px solid var(--line); border-radius:10px;
    margin-bottom:7px; align-items:center; }}
  .row.done {{ opacity:.62; }}
  .row.rej {{ border-color:var(--bad); }}
  .key {{ padding:9px 10px; font-size:13px; display:flex; align-items:center;
    word-break:break-word; }}
  .tile {{ border-left:1px solid var(--line); font-size:0; }}
  .tile img {{ display:block; width:138px; height:138px; object-fit:contain; }}
  .tile.strip {{ border-left:1px solid var(--line); }}
  .tile.mid, .tile.end {{ border-left:1px solid color-mix(in srgb, var(--line) 55%, transparent); }}
  .controls-cell {{ border-left:1px solid var(--line); padding:8px 12px;
    display:flex; flex-direction:column; gap:7px; justify-content:center; }}
  .judge {{ display:flex; gap:6px; align-items:center; }}
  .judge .lbl {{ width:104px; font-size:12.5px; color:var(--muted); }}
  .judge button {{ padding:4px 12px; font-size:12px; }}
  .judge button.on-ok {{ background:var(--ok); color:#fff; border-color:var(--ok); }}
  .judge button.on-bad {{ background:var(--bad); color:#fff; border-color:var(--bad); }}
  .reason {{ grid-column:1 / -1; border-top:1px solid var(--line); padding:7px 10px;
    display:none; }}
  .row.rej .reason {{ display:block; }}
  .reason textarea {{ width:100%; min-height:34px; font:inherit; font-size:13px;
    padding:5px 8px; border-radius:6px; border:1px solid var(--line);
    background:var(--bg); color:var(--ink); resize:vertical; }}
  .hdr {{ display:grid; grid-template-columns:104px 138px 138px 138px 1fr;
    font-size:11.5px; color:var(--muted); text-transform:uppercase;
    letter-spacing:.04em; padding:0 0 6px; }}
  .hdr div {{ padding:0 10px; }}
  .zoom .tile img {{ width:208px; height:208px; }}
  .zoom .hdr {{ grid-template-columns:104px 208px 208px 208px 1fr; }}
  dialog {{ border:1px solid var(--line); border-radius:12px; background:var(--panel);
    color:var(--ink); max-width:min(780px,92vw); padding:0; }}
  dialog::backdrop {{ background:rgba(0,0,0,.45); }}
  .dlg {{ padding:18px 20px; }}
  .dlg h2 {{ margin:0 0 8px; font-size:16px; }}
  pre {{ background:var(--bg); border:1px solid var(--line); border-radius:8px;
    padding:12px; overflow:auto; max-height:46vh; font:12px ui-monospace,Menlo,monospace; }}
</style></head><body>
<header>
  <h1>Skin-tone review — every tile</h1>
  <div class="sub">Judge each tone separately: a tile can be right at Medium and wrong at
  Medium-Dark. Look for the figure drifting into a different person, hair blending into the
  skin, blond hair on a dark tone, black facial features losing contrast, and clothing or
  objects being recoloured. Nothing is approved unless you approve it.</div>
</header>

<div class="bar">
  <div class="counts">
    <span class="c-ok">approved <b id="n-ok">0</b></span>
    <span class="c-bad">rejected <b id="n-bad">0</b></span>
    <span class="c-todo">unreviewed <b id="n-todo">0</b></span>
    <span class="muted">of <b id="n-all">0</b> judgements</span>
  </div>
  <input type="search" id="q" placeholder="filter words…" style="width:180px">
  <select id="filter">
    <option value="all">All</option>
    <option value="todo">Unreviewed only</option>
    <option value="rej">Rejected only</option>
  </select>
  <button id="zoom">Bigger</button>
  <button id="approve-page">Approve all shown</button>
  <button class="primary" id="export">Export…</button>
  <button id="reset">Reset</button>
</div>

<div class="wrap">
  <div class="hdr"><div>word</div><div>Classic 🏼</div><div>🏽 Medium</div><div>🏾 Medium-Dark</div><div>judge each tone</div></div>
  <div id="rows"></div>
</div>

<dialog id="dlg"><div class="dlg">
  <h2>Export</h2>
  <div class="sub" id="dlg-note"></div>
  <pre id="dlg-body"></pre>
  <div style="display:flex;gap:8px;margin-top:12px">
    <button class="primary" id="copy">Copy JSON</button>
    <button id="dl">Download rejected.json files</button>
    <button id="close">Close</button>
  </div>
</div></dialog>

<script>
const DATA = {data};
const TONES = {tones};
const KEY = 'blaster.tone.review.v1';
let state = JSON.parse(localStorage.getItem(KEY) || '{{}}');

const $ = s => document.querySelector(s);
const rowsEl = $('#rows');

function save() {{ localStorage.setItem(KEY, JSON.stringify(state)); }}
function get(k, t) {{ return (state[k] && state[k][t]) || null; }}
function reason(k) {{ return (state[k] && state[k].reason) || ''; }}

function setJudge(k, t, v) {{
  state[k] = state[k] || {{}};
  state[k][t] = (state[k][t] === v) ? null : v;   // click again to clear
  save(); render();
}}

function counts() {{
  let ok=0, bad=0, todo=0;
  for (const d of DATA) for (const t of TONES) {{
    const v = get(d.key, t.slug);
    if (v === 'ok') ok++; else if (v === 'bad') bad++; else todo++;
  }}
  return {{ok, bad, todo, all: DATA.length * TONES.length}};
}}

function visible() {{
  const q = $('#q').value.trim().toLowerCase();
  const f = $('#filter').value;
  return DATA.filter(d => {{
    if (q && !d.key.includes(q)) return false;
    const vals = TONES.map(t => get(d.key, t.slug));
    if (f === 'todo') return vals.some(v => !v);
    if (f === 'rej')  return vals.some(v => v === 'bad');
    return true;
  }});
}}

function render() {{
  const c = counts();
  $('#n-ok').textContent = c.ok; $('#n-bad').textContent = c.bad;
  $('#n-todo').textContent = c.todo; $('#n-all').textContent = c.all;

  const rows = visible().map(d => {{
    const vals = TONES.map(t => get(d.key, t.slug));
    const anyBad = vals.some(v => v === 'bad');
    const allDone = vals.every(v => v);
    // Images first, adjacent, so the eye reads Classic → Medium → Medium-Dark
    // as one uninterrupted progression.
    const strip = TONES.map((t, i) => {{
      const cls = i === TONES.length - 1 ? 'end' : 'mid';
      return d.tones[t.slug]
        ? `<div class="tile ${{cls}}"><img loading="lazy" src="${{d.tones[t.slug]}}"></div>`
        : `<div class="tile ${{cls}}"></div>`;
    }}).join('');
    // Controls stacked to the right, one line per tone, each labelled so it is
    // never ambiguous which tile a verdict applies to.
    const judges = TONES.map((t, i) => {{
      const v = vals[i];
      return `<div class="judge"><span class="lbl">${{t.emoji}} ${{t.label}}</span>
        <button class="${{v==='ok'?'on-ok':''}}" data-k="${{d.key}}" data-t="${{t.slug}}" data-v="ok">Approve</button>
        <button class="${{v==='bad'?'on-bad':''}}" data-k="${{d.key}}" data-t="${{t.slug}}" data-v="bad">Reject</button>
      </div>`;
    }}).join('');
    return `<div class="row ${{anyBad?'rej':''}} ${{allDone&&!anyBad?'done':''}}">
      <div class="key">${{d.key}}</div>
      <div class="tile strip"><img loading="lazy" src="${{d.base}}"></div>
      ${{strip}}
      <div class="controls-cell">${{judges}}</div>
      <div class="reason"><textarea data-r="${{d.key}}"
        placeholder="Why was this rejected? e.g. hair blends into skin, features lost contrast, figure changed">${{reason(d.key)}}</textarea></div>
    </div>`;
  }});
  rowsEl.innerHTML = rows.join('') || '<div class="sub">Nothing matches.</div>';
}}

rowsEl.addEventListener('click', e => {{
  const b = e.target.closest('button[data-k]');
  if (b) setJudge(b.dataset.k, b.dataset.t, b.dataset.v);
}});
rowsEl.addEventListener('input', e => {{
  const t = e.target.closest('textarea[data-r]');
  if (!t) return;
  const k = t.dataset.r;
  state[k] = state[k] || {{}};
  state[k].reason = t.value;
  save();          // no re-render: that would steal focus mid-sentence
}});

$('#q').addEventListener('input', render);
$('#filter').addEventListener('change', render);
$('#zoom').addEventListener('click', e => {{
  document.body.classList.toggle('zoom'); e.target.classList.toggle('primary');
}});
$('#approve-page').addEventListener('click', () => {{
  // Only fills BLANKS. It must never silently overturn a rejection.
  for (const d of visible()) for (const t of TONES) {{
    if (!get(d.key, t.slug)) {{ state[d.key] = state[d.key] || {{}}; state[d.key][t.slug] = 'ok'; }}
  }}
  save(); render();
}});
$('#reset').addEventListener('click', () => {{
  if (confirm('Clear every judgement?')) {{ state = {{}}; save(); render(); }}
}});
$('#close').addEventListener('click', () => $('#dlg').close());

function buildExport() {{
  const out = {{}};
  for (const t of TONES) out['classic_' + t.slug] = {{}};
  for (const d of DATA) for (const t of TONES) {{
    if (get(d.key, t.slug) === 'bad') {{
      out['classic_' + t.slug][d.key] =
        {{ reason: reason(d.key) || 'visual issue', attempts: 1 }};
    }}
  }}
  return out;
}}

$('#export').addEventListener('click', () => {{
  const c = counts();
  const ex = buildExport();
  const note = c.todo > 0
    ? `<b style="color:var(--warn)">${{c.todo}} of ${{c.all}} judgements are still unreviewed.</b>
       This export covers only what you decided — it is not a sign-off on the rest.`
    : `All ${{c.all}} judgements recorded.`;
  $('#dlg-note').innerHTML = note;
  $('#dlg-body').textContent = JSON.stringify(ex, null, 2);
  $('#dlg').showModal();
}});

$('#copy').addEventListener('click', () => {{
  navigator.clipboard.writeText($('#dlg-body').textContent);
  $('#copy').textContent = 'Copied';
  setTimeout(() => $('#copy').textContent = 'Copy JSON', 1400);
}});

$('#dl').addEventListener('click', () => {{
  // One file per set, named and shaped exactly as review_tiles.py expects.
  const ex = buildExport();
  for (const [set, rejects] of Object.entries(ex)) {{
    const blob = new Blob([JSON.stringify(rejects, null, 2) + '\\n'],
                          {{type: 'application/json'}});
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `${{set}}.rejected.json`;
    a.click();
  }}
}});

render();
</script>
</body></html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()

    if not SKIN_CACHE.exists():
        raise SystemExit("run build_tone_variants.py --classify first")
    cache = json.loads(SKIN_CACHE.read_text())
    keys = sorted(k for k, v in cache.items() if v)

    OUT.mkdir(parents=True, exist_ok=True)
    data = []
    missing = 0
    for key in keys:
        base = SOURCE / f"{key}.png"
        if not base.exists():
            continue
        tones = {}
        for d, slug, _, _ in TONES:
            p = BASE / d / f"{key}.png"
            if p.exists():
                tones[slug] = os.path.relpath(p, OUT)
            else:
                missing += 1
        data.append({"key": key, "base": os.path.relpath(base, OUT), "tones": tones})

    tones_meta = [{"slug": s, "emoji": e, "label": l} for _, s, e, l in TONES]
    html = HTML.format(data=json.dumps(data), tones=json.dumps(tones_meta))
    out = OUT / "index.html"
    out.write_text(html)

    print(f"{len(data)} tiles × {len(TONES)} tones = {len(data)*len(TONES)} judgements")
    if missing:
        print(f"  WARNING: {missing} tone tiles missing — build may still be running")
    print(f"→ {out}")
    if not args.no_open:
        webbrowser.open(f"file://{out.resolve()}")


if __name__ == "__main__":
    main()
