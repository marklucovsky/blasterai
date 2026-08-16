#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Build an HTML page for judging tile re-encoding quality (session 2B, bundle slim).

The app ships 1,577 PNGs at 512x512 with no alpha, totalling 273 MB. Re-encoding
to HEIC cuts that by roughly 90%. Whether the loss is acceptable is a judgement
call about how the art LOOKS, so this page puts original and candidate side by
side at 1:1 and at 4x, with an A/B flip that swaps them in place -- the only
reliable way to spot compression artifacts.

Candidates are derived from the 1024x1024 masters in tools/tile_sets/, not from
the shipped 512 PNGs, so a 1024 candidate is a true higher-resolution encode
rather than an upscale.

HEIC is decoded back to PNG for display: Safari renders HEIC but Chrome does
not, and the page has to be trustworthy in both. **The size shown is always the
HEIC file's size**; the PNG next to it is only how that HEIC decodes.

Usage:
    python3 tools/build_encoding_review.py
    python3 tools/build_encoding_review.py --tiles apple,happy,playground
    python3 tools/build_encoding_review.py --quality 80,65,50 --no-open
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import webbrowser
from pathlib import Path

APP_TILES = Path("claudeBlast/TileImageSets")
MASTERS = Path("tools/tile_sets")
OUT_DIR = Path("tools/tile_sets/encoding_review")

# App filename prefix -> master directory. Mirrors tools/sync_to_app.py.
#
# `hc2` (High Contrast v2) is the approved 546-tile set built 2026-08-12. It is
# in LFS and NOT in the app, so it has no shipped 512 counterpart — which is
# exactly why the reference pane below is derived from the master rather than
# from what ships. v1 is included only for comparison; **v2 is the set any
# decision here should be judged against**, since it is what would ship.
SET_PREFIX = {
    "p3d": "playful_3d",
    "cls": "classic",
    "hc2": "high_contrast_v2",
    "hc": "high_contrast",
}

SET_LABEL = {
    "p3d": "Playful 3D",
    "cls": "Classic",
    "hc2": "High Contrast v2",
    "hc": "High Contrast v1 (superseded)",
}

# Chosen to stress different failure modes rather than to look good:
#   smooth gradients (where blocking shows), flat colour fields (where banding
#   shows), fine detail (where ringing shows), and faces (where we are most
#   sensitive to any of it).
DEFAULT_TILES = [
    "apple",        # simple subject, large flat areas + gradient
    "happy",        # face — highest perceptual sensitivity
    "playground",   # fine detail, many edges
    "water",        # smooth gradient, transparency-like shading
    "red",          # near-uniform colour field, worst case for banding
    "bathroom",     # hard geometric edges
]


def sips(src: Path, dst: Path, fmt: str, quality: str | None = None,
         resize: int | None = None) -> bool:
    cmd = ["sips", "-s", "format", fmt]
    if quality:
        cmd += ["-s", "formatOptions", quality]
    if resize:
        cmd += ["-Z", str(resize)]
    cmd += [str(src), "--out", str(dst)]
    r = subprocess.run(cmd, capture_output=True)
    return r.returncode == 0 and dst.exists()


def kb(n: int) -> str:
    return f"{n / 1024:.0f} KB" if n < 1024 * 1024 else f"{n / 1048576:.1f} MB"


def build_variants(prefix: str, key: str, qualities: list[str],
                   sizes: list[int]) -> dict | None:
    """Encode one tile at every (size, quality), against a same-size reference.

    The reference is a **lossless PNG at the candidate's own resolution, derived
    from the 1024 master** — not the shipped 512 PNG. Comparing against what
    ships would conflate two different losses (the downscale and the lossy
    encode) and make a 1024 candidate look better for the wrong reason. It also
    would not work at all for High Contrast v2, which has no shipped counterpart.
    """
    master = MASTERS / SET_PREFIX[prefix] / f"{key}.png"
    if not master.exists():
        return None

    tile_dir = OUT_DIR / f"{prefix}_{key}"
    tile_dir.mkdir(parents=True, exist_ok=True)

    shipped = APP_TILES / f"{prefix}_{key}.png"
    entry = {
        "key": key,
        "prefix": prefix,
        "set": SET_LABEL[prefix],
        "shipped_bytes": shipped.stat().st_size if shipped.exists() else 0,
        "master_bytes": master.stat().st_size,
        "refs": {},
        "variants": [],
    }

    for size in sizes:
        ref = tile_dir / f"ref_{size}.png"
        if size == 1024:
            shutil.copy(master, ref)
        elif not sips(master, ref, "png", resize=size):
            continue
        entry["refs"][str(size)] = {
            "img": f"{prefix}_{key}/ref_{size}.png",
            "bytes": ref.stat().st_size,
        }

        for q in qualities:
            heic = tile_dir / f"c_{size}_q{q}.heic"
            if not sips(ref, heic, "heic", quality=q):
                continue
            # Decode for display — Chrome cannot render HEIC.
            png = tile_dir / f"c_{size}_q{q}.png"
            if not sips(heic, png, "png"):
                continue
            entry["variants"].append({
                "size": size,
                "quality": int(q),
                "bytes": heic.stat().st_size,
                "img": f"{prefix}_{key}/c_{size}_q{q}.png",
                "pct": heic.stat().st_size / ref.stat().st_size * 100,
            })

    return entry


def set_totals(qualities: list[str], sizes: list[int]) -> list[dict]:
    """Project whole-set sizes by scaling a per-set sample of 10 tiles."""
    rows = []
    for prefix, master_dir in SET_PREFIX.items():
        src = MASTERS / master_dir
        if not src.exists():
            continue
        masters = sorted(src.glob("*.png"))
        if not masters:
            continue
        # Tile count comes from the MASTERS, not the app: High Contrast v2 has
        # 546 tiles and ships none of them yet, so counting shipped files would
        # project it as zero.
        shipped = sorted(APP_TILES.glob(f"{prefix}_*.png"))
        shipped_total = sum(p.stat().st_size for p in shipped)
        sample = masters[::max(1, len(masters) // 10)][:10]
        if not sample:
            continue

        tmp = OUT_DIR / "_tmp"
        tmp.mkdir(parents=True, exist_ok=True)
        proj = {}
        for size in sizes:
            for q in qualities:
                total = 0
                ok = 0
                for m in sample:
                    base = tmp / "b.png"
                    if size == 1024:
                        shutil.copy(m, base)
                    elif not sips(m, base, "png", resize=size):
                        continue
                    h = tmp / "b.heic"
                    if sips(base, h, "heic", quality=q):
                        total += h.stat().st_size
                        ok += 1
                if ok:
                    proj[f"{size}_{q}"] = int(total / ok * len(masters))
        shutil.rmtree(tmp, ignore_errors=True)
        rows.append({
            "prefix": prefix, "set": SET_LABEL[prefix], "count": len(masters),
            "shipped": shipped_total, "proj": proj,
        })
    return rows


HTML = """<!doctype html>
<html><head><meta charset="utf-8"><title>Tile encoding review — session 2B</title>
<style>
  :root {{
    --bg:#f6f6f8; --panel:#fff; --ink:#16161a; --muted:#6b6b76; --line:#e2e2e8;
    --accent:#2f6df6; --warn:#c2410c; --good:#15803d;
  }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg:#121216; --panel:#1c1c22; --ink:#f0f0f4; --muted:#9a9aa6;
             --line:#2c2c36; --accent:#7aa2ff; --warn:#fb923c; --good:#4ade80; }}
  }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink);
    font:15px/1.5 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif; }}
  header {{ padding:24px 28px 8px; }}
  h1 {{ font-size:22px; margin:0 0 6px; letter-spacing:-.01em; }}
  .sub {{ color:var(--muted); font-size:13.5px; max-width:70ch; }}
  .wrap {{ padding:0 28px 60px; }}
  .card {{ background:var(--panel); border:1px solid var(--line); border-radius:12px;
    padding:18px 20px; margin:18px 0; }}
  table {{ border-collapse:collapse; width:100%; font-size:13.5px; }}
  th,td {{ text-align:right; padding:7px 10px; border-bottom:1px solid var(--line); }}
  th:first-child, td:first-child {{ text-align:left; }}
  th {{ color:var(--muted); font-weight:600; font-size:12px; text-transform:uppercase;
    letter-spacing:.04em; }}
  tfoot td {{ font-weight:700; border-bottom:none; }}
  .controls {{ display:flex; gap:18px; flex-wrap:wrap; align-items:center;
    position:sticky; top:0; z-index:20; background:var(--bg);
    padding:12px 28px; border-bottom:1px solid var(--line); }}
  .controls label {{ font-size:13px; color:var(--muted); margin-right:6px; }}
  select,button {{ font:inherit; font-size:13px; padding:5px 9px; border-radius:7px;
    border:1px solid var(--line); background:var(--panel); color:var(--ink); }}
  button {{ cursor:pointer; }}
  button.on {{ background:var(--accent); color:#fff; border-color:var(--accent); }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(430px,1fr)); gap:18px; }}
  .tile {{ background:var(--panel); border:1px solid var(--line); border-radius:12px;
    overflow:hidden; }}
  .tile h3 {{ margin:0; padding:11px 14px; font-size:14px; border-bottom:1px solid var(--line);
    display:flex; justify-content:space-between; align-items:baseline; gap:10px; }}
  .tile h3 span {{ color:var(--muted); font-weight:400; font-size:12px; }}
  .pair {{ display:grid; grid-template-columns:1fr 1fr; }}
  .pane {{ position:relative; }}
  .pane img {{ display:block; width:100%; height:auto; background:#888; }}
  .pane .tag {{ position:absolute; top:7px; left:7px; font-size:11px; padding:2px 7px;
    border-radius:20px; background:rgba(0,0,0,.66); color:#fff; letter-spacing:.02em; }}
  .pane.b .tag {{ background:var(--accent); }}
  .meta {{ display:flex; justify-content:space-between; padding:9px 14px; font-size:12.5px;
    border-top:1px solid var(--line); color:var(--muted); }}
  .meta b {{ color:var(--ink); font-weight:600; }}
  .save {{ color:var(--good); font-weight:600; }}
  /* Pixel-peep: 4x nearest-neighbour so artifacts are visible, not smoothed away. */
  .zoom .pane img {{ image-rendering:pixelated; transform:scale(4); transform-origin:50% 40%; }}
  .zoom .pane {{ overflow:hidden; aspect-ratio:1; }}
  .flip .pane.a {{ display:none; }}
  .flip .pane {{ grid-column:1 / -1; }}
  .hint {{ font-size:12.5px; color:var(--muted); padding:0 28px 10px; }}
  code {{ font:12px ui-monospace,SFMono-Regular,Menlo,monospace;
    background:var(--bg); padding:1px 5px; border-radius:4px; }}
</style></head><body>
<header>
  <h1>Tile encoding review</h1>
  <div class="sub">Session 2B, bundle slim. Every shipped tile is 512×512 PNG with no alpha —
  273&nbsp;MB across three sets. Candidates are encoded from the 1024×1024 masters, so a
  1024 candidate is a genuine higher-resolution encode rather than an upscale.
  <b>The left pane is a lossless PNG at the candidate's own resolution</b>, not the shipped
  512 — comparing against what ships would mix the downscale loss into the encode loss and
  flatter 1024 for the wrong reason.
  <b>The size shown is always the HEIC file</b>; the image beside it is only how that HEIC
  decodes, displayed as PNG because Chrome cannot render HEIC.
  <b>High Contrast v2</b> (546 tiles, approved 2026-08-12) is in LFS and ships nothing today —
  judge HC against v2, not the superseded v1.</div>
</header>

<div class="controls">
  <div><label>Size</label><select id="size">{size_opts}</select></div>
  <div><label>Quality</label><select id="qual">{qual_opts}</select></div>
  <div><label>Set</label><select id="set"><option value="">All</option>{set_opts}</select></div>
  <button id="zoom">Pixel-peep 4×</button>
  <button id="flip">A/B flip</button>
</div>
<div class="hint">
  <b>A/B flip</b> shows one image at a time in the same position — hold your eye still and toggle;
  artifacts jump out that side-by-side hides. <b>Pixel-peep</b> magnifies 4× with no smoothing.
</div>

<div class="wrap">
  <div class="card">
    <h2 style="font-size:15px;margin:0 0 10px">Projected bundle size</h2>
    <table id="totals"><thead><tr>
      <th>Set</th><th>Tiles</th><th>Ships today</th><th>Candidate</th><th>Saved</th>
    </tr></thead><tbody></tbody>
    <tfoot><tr><td>Total</td><td id="tc"></td><td id="ts"></td><td id="tp"></td><td id="tv"></td></tr></tfoot>
    </table>
    <div class="sub" style="margin-top:10px">Projected by encoding a 10-tile sample per set and
    scaling by tile count. The asset catalog (19&nbsp;MB) is separate and unaffected.</div>
  </div>

  <div class="grid" id="grid"></div>
</div>

<script>
const DATA = {data};
const TOTALS = {totals};

const $ = s => document.querySelector(s);
const grid = $('#grid');

function currentKey() {{ return $('#size').value + '_' + $('#qual').value; }}

function renderTotals() {{
  const k = currentKey();
  const tb = $('#totals tbody'); tb.innerHTML = '';
  let count=0, ship=0, proj=0;
  for (const r of TOTALS) {{
    const p = r.proj[k]; if (p === undefined) continue;
    count += r.count; ship += r.shipped; proj += p;
    // High Contrast v2 ships nothing today, so a "% saved" against zero is
    // meaningless — show what it would ADD instead of a fake saving.
    const cell = r.shipped
      ? `<td class="save">−${{((1 - p / r.shipped) * 100).toFixed(0)}}%</td>`
      : `<td style="color:var(--warn)">+${{fmt(p)}} new</td>`;
    tb.insertAdjacentHTML('beforeend',
      `<tr><td>${{r.set}}</td><td>${{r.count}}</td>
       <td>${{r.shipped ? fmt(r.shipped) : '—'}}</td><td>${{fmt(p)}}</td>${{cell}}</tr>`);
  }}
  $('#tc').textContent = count; $('#ts').textContent = fmt(ship);
  $('#tp').textContent = fmt(proj);
  $('#tv').innerHTML = `<span class="save">−${{((1-proj/ship)*100).toFixed(0)}}%</span>`;
}}

function fmt(n) {{
  return n < 1048576 ? (n/1024).toFixed(0)+' KB' : (n/1048576).toFixed(1)+' MB';
}}

function renderTiles() {{
  const k = currentKey(), setF = $('#set').value;
  grid.innerHTML = '';
  for (const t of DATA) {{
    if (setF && t.prefix !== setF) continue;
    const v = t.variants.find(x => x.size + '_' + x.quality === k);
    const ref = t.refs[$('#size').value];
    if (!v || !ref) continue;
    grid.insertAdjacentHTML('beforeend', `
      <div class="tile">
        <h3>${{t.key}} <span>${{t.set}}</span></h3>
        <div class="pair">
          <div class="pane a"><span class="tag">lossless ${{v.size}}px</span><img src="${{ref.img}}" loading="lazy"></div>
          <div class="pane b"><span class="tag">HEIC q${{v.quality}} · ${{v.size}}px</span><img src="${{v.img}}" loading="lazy"></div>
        </div>
        <div class="meta">
          <span>lossless <b>${{fmt(ref.bytes)}}</b></span>
          <span>HEIC <b>${{fmt(v.bytes)}}</b></span>
          <span class="save">${{v.pct.toFixed(0)}}% of lossless</span>
        </div>
      </div>`);
  }}
}}

function rerender() {{ renderTotals(); renderTiles(); }}
['size','qual','set'].forEach(id => $('#'+id).addEventListener('change', rerender));
$('#zoom').addEventListener('click', e => {{
  grid.classList.toggle('zoom'); e.target.classList.toggle('on');
}});
$('#flip').addEventListener('click', e => {{
  grid.classList.toggle('flip'); e.target.classList.toggle('on');
}});
// A/B flip needs a toggle to be useful — click any tile to swap which pane shows.
grid.addEventListener('click', ev => {{
  const tile = ev.target.closest('.tile'); if (!tile || !grid.classList.contains('flip')) return;
  const a = tile.querySelector('.pane.a'), b = tile.querySelector('.pane.b');
  const showingB = a.style.display === 'none' || getComputedStyle(a).display === 'none';
  a.style.display = showingB ? 'block' : 'none';
  b.style.display = showingB ? 'none' : 'block';
}});
rerender();
</script>
</body></html>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiles", default=",".join(DEFAULT_TILES))
    ap.add_argument("--quality", default="85,80,65")
    ap.add_argument("--sizes", default="512,1024")
    ap.add_argument("--no-open", action="store_true")
    args = ap.parse_args()

    if shutil.which("sips") is None:
        sys.exit("sips not found — this tool is macOS-only.")

    qualities = [q.strip() for q in args.quality.split(",") if q.strip()]
    sizes = [int(s) for s in args.sizes.split(",") if s.strip()]
    keys = [t.strip() for t in args.tiles.split(",") if t.strip()]

    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    entries = []
    for key in keys:
        for prefix in SET_PREFIX:
            e = build_variants(prefix, key, qualities, sizes)
            if e:
                entries.append(e)
            else:
                print(f"  skip {prefix}_{key} (missing master or shipped tile)")

    print("Projecting whole-set sizes…")
    totals = set_totals(qualities, sizes)

    size_opts = "".join(f'<option value="{s}"{" selected" if s == sizes[0] else ""}>{s}px</option>'
                        for s in sizes)
    qual_opts = "".join(f'<option value="{q}"{" selected" if q == qualities[1 if len(qualities) > 1 else 0] else ""}>q{q}</option>'
                        for q in qualities)
    set_opts = "".join(f'<option value="{p}">{SET_LABEL[p]}</option>' for p in SET_PREFIX)

    html = HTML.format(data=json.dumps(entries), totals=json.dumps(totals),
                       size_opts=size_opts, qual_opts=qual_opts, set_opts=set_opts)
    out = OUT_DIR / "index.html"
    out.write_text(html)

    print(f"\n{len(entries)} tiles · {len(qualities)} qualities · {len(sizes)} sizes")
    print(f"→ {out}")
    if not args.no_open:
        webbrowser.open(f"file://{out.resolve()}")


if __name__ == "__main__":
    main()
