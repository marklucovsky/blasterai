#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""One page showing a set of words drawn in every style, side by side.

    python3 tools/build_style_review.py --keys-file /tmp/timekeys.txt --out build/style_review.html
    python3 tools/build_style_review.py --keys now,later,soon --sets classic,playful_3d
    python3 tools/build_style_review.py --keys-file k.txt --reference /path/to/refs

WHY A ROW PER WORD, NOT A SHEET PER SET
---------------------------------------
`review_tiles.py sheets` builds one contact sheet per set, which is the right
shape for "is this set finished". It is the wrong shape for the question that
matters when a word exists in several styles: **do these three pictures mean the
same thing?**

A style is allowed to redraw a subject — High Contrast inverts, Playful 3D adds
depth — but it is not allowed to change what the tile *says*. A child who learns
`before` in Classic and then moves to High Contrast has to find the same idea
there. Catching a divergence needs the versions adjacent on one line, and
flipping between three separate sheets is exactly how a divergence survives
review.

It also surfaces the failure this project keeps hitting: a subject written for
one style quietly breaking in another. The Time tiles are diagrams that state
their own colours, and "white squares with black outlines" renders as a blank
field on High Contrast's black canvas. Side by side that is instant; sheet by
sheet it reads as "the High Contrast set looks a bit dark".

THE REFERENCE COLUMN
--------------------
`--reference DIR` adds a final column from a folder of `<key>.png|svg`, for
comparing against a published symbol set during design. Those files are
typically CC BY-NC-SA or CC BY-SA and must not enter this repo — point at a
scratch directory, and the page prints the warning alongside them.
"""

import argparse
import html
import json
import os
import sys
from pathlib import Path

TILE_SETS = Path("tools/tile_sets")
# Shown in this order. Only sets that exist on disk are rendered.
#
# `high_contrast_v2`, not `high_contrast`: the unversioned folder is the earlier
# generation and reaches no device — `sync_to_app.py` maps the shipped `hc`
# prefix to v2. Reviewing the wrong one is easy to do and hard to notice, since
# both are full sets of plausible High Contrast art.
DEFAULT_SETS = ["classic", "playful_3d", "high_contrast_v2"]


def resolve(root, key):
    for ext in ("png", "svg", "jpg"):
        p = root / f"{key}.{ext}"
        if p.exists():
            return p
    return None


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--keys", help="comma-separated keys")
    ap.add_argument("--keys-file", type=Path, help="one key per line")
    ap.add_argument("--sets", default=",".join(DEFAULT_SETS),
                    help=f"comma-separated set folders (default: {','.join(DEFAULT_SETS)})")
    ap.add_argument("--reference", type=Path,
                    help="folder of reference images, shown as a final column")
    ap.add_argument("--out", type=Path, default=Path("build/style_review.html"))
    args = ap.parse_args()

    if args.keys_file:
        keys = [k.strip() for k in args.keys_file.read_text().split() if k.strip()]
    elif args.keys:
        keys = [k.strip() for k in args.keys.split(",") if k.strip()]
    else:
        ap.error("pass --keys or --keys-file")

    sets = [s.strip() for s in args.sets.split(",") if s.strip()]
    present = [s for s in sets if (TILE_SETS / s).is_dir()]
    missing = [s for s in sets if s not in present]
    if not present:
        sys.exit(f"none of {sets} exist under {TILE_SETS}")

    ref_manifest = {}
    if args.reference:
        mf = args.reference / "_manifest.json"
        if mf.exists():
            ref_manifest = json.loads(mf.read_text())

    args.out.parent.mkdir(parents=True, exist_ok=True)
    out_dir = args.out.parent

    def rel(p):
        """Path for the page, stamped with the file's mtime.

        The stamp is not decoration. Tiles are regenerated in place, under the
        same filename, over and over — so the browser serves whatever it cached
        the first time and the page silently shows yesterday's art while the
        HTML around it is current. That is worse than no page: it looks like a
        review and is not one. `?v=<mtime>` changes whenever the file does, so a
        reload can only ever show what is on disk.
        """
        p = Path(p).resolve()
        # A RELATIVE path, even when the file sits outside the page's directory.
        #
        # The first version fell back to an absolute file:// URI for anything it
        # could not express relative to the output folder, and the page rendered
        # blank: this repo's worktrees live under `.claude/`, and browsers refuse
        # to load local subresources through a dot-directory. Relative paths dodge
        # that entirely and are also what lets the page be served over HTTP, which
        # is the reliable way to view it.
        href = os.path.relpath(p, out_dir.resolve())
        return html.escape(f"{href}?v={int(p.stat().st_mtime)}")

    cols = len(present) + (1 if args.reference else 0)
    rows = []
    gaps = []
    for key in keys:
        cells = []
        for s in present:
            p = resolve(TILE_SETS / s, key)
            if p:
                cells.append(f"<div class='cell'><img src='{rel(p)}'>"
                             f"<div class='cap'>{html.escape(s)}</div></div>")
            else:
                gaps.append((key, s))
                cells.append(f"<div class='cell'><div class='none'>not in {html.escape(s)}</div>"
                             f"<div class='cap'>{html.escape(s)}</div></div>")
        if args.reference:
            p = resolve(args.reference, key)
            if p:
                meta = ref_manifest.get(key, {})
                cred = " · ".join(filter(None, [meta.get("author"), meta.get("license")]))
                cells.append(f"<div class='cell'><img src='{rel(p)}'>"
                             f"<div class='cap'>{html.escape(cred or 'reference')}</div></div>")
            else:
                cells.append("<div class='cell'><div class='none'>no reference</div>"
                             "<div class='cap'>reference</div></div>")
        rows.append(f"<div class='row'><div class='word'>{html.escape(key)}</div>"
                    f"{''.join(cells)}</div>")

    warn = ""
    if args.reference:
        warn = ("<p class='warn'>Reference images are third-party and typically carry NC or SA "
                "terms. They are here for comparison only and must never enter the repo.</p>")
    if missing:
        warn += (f"<p class='warn'>Not found on disk, skipped: "
                 f"{html.escape(', '.join(missing))}</p>")

    args.out.write_text(f"""<!DOCTYPE html>
<meta charset='utf-8'><title>Tile styles — {len(keys)} words</title>
<style>
 body{{font:14px -apple-system,sans-serif;margin:24px;background:#fafafa;color:#222}}
 h1{{font-size:20px;margin-bottom:4px}} .sub{{color:#666;margin-top:0}}
 .warn{{color:#8a5a00;background:#fff6e5;border:1px solid #f0dcae;
        padding:8px 12px;border-radius:6px;max-width:70em}}
 .row,.hdr{{display:grid;grid-template-columns:110px repeat({cols},1fr);
            gap:14px;align-items:center}}
 .row{{background:#fff;border:1px solid #e3e3e3;border-radius:8px;
       padding:10px 12px;margin:8px 0}}
 .hdr{{padding:0 12px;font-weight:650;color:#444;margin-top:14px}}
 .word{{font-weight:650;font-size:16px}}
 .cell img,.none{{width:100%;max-width:200px;aspect-ratio:1;object-fit:contain;
                  background:#fff;border:1px solid #eee;border-radius:6px;display:block}}
 .none{{display:flex;align-items:center;justify-content:center;color:#aaa;font-size:12px}}
 .cap{{font-size:11px;color:#888;margin-top:4px}}
</style>
<h1>Tile styles — {len(keys)} words</h1>
<p class='sub'>Same word across {len(present)} style{'s' if len(present) != 1 else ''}.
A style may redraw a subject; it may not change what the tile says.</p>
{warn}
<div class='hdr'><div></div>{''.join(f"<div>{html.escape(s)}</div>" for s in present)}
{"<div>reference</div>" if args.reference else ""}</div>
{''.join(rows)}
""")

    print(f"wrote {args.out}  ({len(keys)} words × {len(present)} sets)")
    if gaps:
        print(f"\n{len(gaps)} tile(s) not yet drawn:")
        for key, s in gaps:
            print(f"  {key:12s} missing from {s}")


if __name__ == "__main__":
    main()
