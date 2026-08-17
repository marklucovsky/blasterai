#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Review skin-tone variants against the Classic original.

The question this page has to answer is NOT "is the skin tone right" — that part
is easy to see. It is **"is this still the same person, drawn the same way"**.
In AAC the figure is the referent, so if `me` and `my` end up with different
faces, or the line weight drifts between tones, the set is broken in a way that
a per-tile glance will not catch.

So tiles are laid out one row per word, original first, tones after — scan
ACROSS a row to check the person survived, and DOWN a column to check the tone
is consistent across the set.

Usage:
    python3 tools/build_tone_review.py
    python3 tools/build_tone_review.py --no-open
"""

import argparse
import json
import os
import webbrowser
from pathlib import Path

BASE = Path("tools/tile_sets")
SOURCE = BASE / "classic"
OUT = BASE / "tone_review"

TONES = [
    ("classic_chain_medium", "🏽", "Medium (chained)"),
    ("classic_chain_medium_dark", "🏾", "Medium-Dark (chained)"),
    ("classic_chain_dark", "🏿", "Dark (chained)"),
]

# Raw model output, before the deterministic colour correction. Shown alongside
# so the correction's effect is visible rather than asserted — the model's own
# colours are the terracotta ones.
AI_SUFFIX = ""  # correction dropped — the sets ARE the model output

HTML = """<!doctype html>
<html><head><meta charset="utf-8"><title>Classic skin-tone variants</title>
<style>
  :root {{ --bg:#f6f6f8; --panel:#fff; --ink:#16161a; --muted:#6b6b76; --line:#e2e2e8; --accent:#2f6df6; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg:#121216; --panel:#1c1c22; --ink:#f0f0f4; --muted:#9a9aa6; --line:#2c2c36; --accent:#7aa2ff; }}
  }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink);
    font:15px/1.5 -apple-system,BlinkMacSystemFont,system-ui,sans-serif; }}
  header {{ padding:26px 28px 10px; }}
  h1 {{ font-size:22px; margin:0 0 6px; letter-spacing:-.01em; }}
  .sub {{ color:var(--muted); font-size:13.5px; max-width:74ch; }}
  .wrap {{ padding:14px 28px 60px; }}
  .row {{ background:var(--panel); border:1px solid var(--line); border-radius:12px;
    margin-bottom:16px; overflow:hidden; }}
  .row h3 {{ margin:0; padding:10px 14px; font-size:14px; border-bottom:1px solid var(--line); }}
  .cells {{ display:grid; grid-template-columns:repeat({ncols},1fr); }}
  .cell {{ border-right:1px solid var(--line); }}
  .cell:last-child {{ border-right:none; }}
  .cell img {{ display:block; width:100%; height:auto; }}
  .cap {{ font-size:12px; padding:7px 10px; color:var(--muted); text-align:center;
    border-top:1px solid var(--line); }}
  .cap.orig {{ color:var(--ink); font-weight:600; }}
  .controls {{ position:sticky; top:0; z-index:5; background:var(--bg);
    padding:10px 28px; border-bottom:1px solid var(--line); display:flex; gap:14px; align-items:center; }}
  button {{ font:inherit; font-size:13px; padding:5px 10px; border-radius:7px;
    border:1px solid var(--line); background:var(--panel); color:var(--ink); cursor:pointer; }}
  button.on {{ background:var(--accent); color:#fff; border-color:var(--accent); }}
  .zoom .cell img {{ image-rendering:pixelated; transform:scale(2.4); transform-origin:50% 38%; }}
  .zoom .cell {{ overflow:hidden; aspect-ratio:1; }}
  .hint {{ font-size:12.5px; color:var(--muted); padding:8px 28px 0; }}
</style></head><body>
<header>
  <h1>Classic — skin-tone variants</h1>
  <div class="sub">The tone itself is the easy part to judge. The question that matters is
  <b>whether it is still the same person, drawn the same way</b> — same face, same pose, same
  hair, same clothing colours, same line weight. In AAC the figure is the referent, so a
  variant that quietly redraws the character breaks the set.
  <b>Scan across a row</b> to check the person survived; <b>scan down a column</b> to check the
  tone is consistent set-wide.</div>
</header>
<div class="controls">
  <button id="zoom">Zoom 2.4×</button>
  <span class="sub" style="margin:0">Refined via <code>/v1/images/edits</code> (image-to-image), so the original is the literal input.</span>
</div>
<div class="hint">Watch specifically for: hair recoloured along with skin, clothing shifting hue,
outlines thickening, and the face subtly changing identity between tones.</div>
<div class="wrap">{rows}</div>
<script>
document.getElementById('zoom').addEventListener('click', e => {{
  document.querySelector('.wrap').classList.toggle('zoom');
  e.target.classList.toggle('on');
}});
</script>
</body></html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    available = [(d, e, l) for d, e, l in TONES if (BASE / d).exists()]
    if not available:
        raise SystemExit("No tone sets found — run build_tone_variants.py --pilot first.")

    keys = sorted({p.stem for d, _, _ in available for p in (BASE / d).glob("*.png")})
    rows = []
    for key in keys:
        cells = []
        orig = SOURCE / f"{key}.png"
        if orig.exists():
            cells.append(
                f'<div class="cell"><img loading="lazy" src="{os.path.relpath(orig, OUT)}">'
                f'<div class="cap orig">Classic (original)</div></div>')
        for d, emoji, label in available:
            p = BASE / d / f"{key}.png"
            if not p.exists():
                continue
            # One column per tone. An earlier version showed a "raw model" column
            # beside a "corrected" one; when the correction was dropped both
            # pointed at the same file, so the page displayed each tile twice and
            # labelled one of them as something it wasn't.
            cells.append(
                f'<div class="cell"><img loading="lazy" src="{os.path.relpath(p, OUT)}">'
                f'<div class="cap">{emoji} {label}</div></div>')
        rows.append(f'<div class="row"><h3>{key}</h3><div class="cells">{"".join(cells)}</div></div>')

    html = HTML.format(rows="\n".join(rows), ncols=len(available) + 1)
    out = OUT / "index.html"
    out.write_text(html)
    print(f"{len(keys)} words × {len(available)} tones → {out}")
    if not args.no_open:
        webbrowser.open(f"file://{out.resolve()}")


if __name__ == "__main__":
    main()
