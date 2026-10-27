#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Confirm how a set's art is cut off its white ground, before it ships.

    python3 tools/cutout_review.py --set classic                        # propose, build two pages
    python3 tools/cutout_review.py --set classic --apply-holes rej.json # record holes verdicts
    python3 tools/cutout_review.py --set classic --apply-guard rej.json # record edge verdicts

`optimize_tiles.py` cuts the white ground touching a tile's edge. Two things
about that are judgements no pixel can make, so the cutter proposes (Vision,
`cutout --propose`) and a person decides, each tile shown on its own light
tile colour:

- **Holes.** Ground *enclosed* by the picture: the inside of a cup handle is
  background, a pillow is a white thing on the same white. The holes page cuts
  the proposed holes against the edge cut alone. Approve and the points go to
  `tools/board_spec/cutout.json` → `holes.<set>`; reject and the tile keeps the
  edge cut only.
- **Edges.** A white shape whose outline stops short of the frame (a doctor's
  coat) flows into the paper and is cut with it. The edge page shows the edge
  cut against the master for every tile where Vision says the cut removes part
  of the picture. Approve and it is cut as usual; reject and it ships uncut on
  a framed plate (`opaque`) until it is redrawn with closed outlines.

Only recorded decisions are applied, so a later run, a new OS or a different
Vision model cannot change what ships. Decided tiles are not proposed again;
delete a tile's entry to review it afresh.
"""

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

from PIL import Image

ROOT = Path("tools/tile_sets")
CUTTER = Path("tools/cutout/.build/cutout")
SPEC = Path("tools/board_spec/cutout.json")
POS = Path("claudeBlast/Resources/parts_of_speech.json")
sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_core_board import COLOR  # noqa: E402
from render_word_glyphs import WORDS as WORD_GLYPHS  # noqa: E402

TINT_MIX = 0.55      # the tile tint Mark picked (2026-10-26): 55% toward white


def tint(part: str) -> tuple[int, int, int]:
    h = COLOR.get(part, COLOR["noun"])
    r, g, b = (int(h[i:i + 2], 16) for i in (1, 3, 5))
    return tuple(round(c + (255 - c) * TINT_MIX) for c in (r, g, b))


def on_tint(png: Path, colour, out: Path) -> None:
    art = Image.open(png).convert("RGBA").resize((512, 512), Image.LANCZOS)
    tile = Image.new("RGBA", art.size, colour + (255,))
    tile.alpha_composite(art)
    tile.convert("RGB").save(out)


def cut(src: Path, out: Path, holes) -> None:
    cmd = [str(CUTTER), str(src), str(out)]
    if holes:
        cmd += ["--holes", ";".join(f"{x},{y}" for x, y in holes)]
    subprocess.run(cmd, check=True, capture_output=True)


def master_id(path: Path) -> str:
    """Fingerprint of a master, so recorded points die with the drawing they
    were measured on: a redraw puts the cup handle somewhere else."""
    return hashlib.sha1(path.read_bytes()).hexdigest()[:10]


def load_spec() -> dict:
    return json.loads(SPEC.read_text())


def save_spec(spec: dict) -> None:
    """Indented, but one tile per line: a review changes a few tiles, and the
    diff should show exactly those."""
    lines = ["{"]
    keys = list(spec)
    for i, top in enumerate(keys):
        value = spec[top]
        comma = "," if i < len(keys) - 1 else ""
        if not isinstance(value, dict):
            lines.append(f"  {json.dumps(top)}: {json.dumps(value)}{comma}")
            continue
        lines.append(f"  {json.dumps(top)}: {{")
        sets = list(value)
        for j, s in enumerate(sets):
            inner = value[s]
            c2 = "," if j < len(sets) - 1 else ""
            if isinstance(inner, dict):
                lines.append(f"    {json.dumps(s)}: {{")
                tiles = list(inner)
                for t, k in enumerate(tiles):
                    c3 = "," if t < len(tiles) - 1 else ""
                    lines.append(f"      {json.dumps(k)}: {json.dumps(inner[k])}{c3}")
                lines.append(f"    }}{c2}")
            else:
                lines.append(f"    {json.dumps(s)}: {json.dumps(inner)}{c2}")
        lines.append(f"  }}{comma}")
    lines.append("}")
    SPEC.write_text("\n".join(lines) + "\n")


# Share of a tile the edge cut may remove from what Vision counts as the
# picture before the tile is sent to the edge review. Measured on Classic
# (2026-10-26): clean tiles sit at 0–0.2% (outline rims); the doctor's coat
# that ran into the paper was 0.9%, the dentist's 5%. The app applies the same
# limit to art it generates (`TileCutout.edgeGuard`), with no review behind it.
EDGE_GUARD = 0.002


def page(name: str, keys: list[str], label: str, compare: str, work: Path) -> None:
    keys_file = work / f"_{name}_keys.txt"
    keys_file.write_text("\n".join(keys) + "\n")
    subprocess.run([sys.executable, "tools/build_review_page.py", "--set", f"cutreview_{name}_gi2",
                    "--keys-file", str(keys_file), "--compare", compare, "--label", label], check=True)


def build(set_name: str) -> None:
    spec = load_spec()
    # A tile is decided only for the drawing it was decided on.
    recorded = spec.get("holes", {}).get(set_name, {})
    decided = {k for k, v in recorded.items()
               if (ROOT / set_name / f"{k}.png").exists() and v["master"] == master_id(ROOT / set_name / f"{k}.png")}
    decided |= set(spec.get("decided", {}).get(set_name, []))
    opaque = set(spec.get("opaque", {}).get(set_name, []))
    edges_ok = set(spec.get("edgesChecked", {}).get(set_name, []))
    # Code-drawn tiles (calendars, day strips, clocks, shapes) are drawn on
    # purpose: every white in them is a cell or a face, never a hole. Mark
    # rejected every calendar's proposals on Classic for exactly that.
    prov = ROOT / f"{set_name}_provenance.json"
    rendered = set(json.loads(prov.read_text()).get("rendered", {})) if prov.exists() else set()
    work = ROOT / "cut" / set_name
    work.mkdir(parents=True, exist_ok=True)
    proposals, guard = {}, {}
    masters = sorted((ROOT / set_name).glob("*.png"))
    for i, p in enumerate(masters, 1):
        k = p.stem
        if k in opaque or k in WORD_GLYPHS:
            continue
        r = subprocess.run([str(CUTTER), "--propose", str(p)], capture_output=True, text=True, check=True)
        found = json.loads(r.stdout)
        if found["holes"] and k not in decided and k not in rendered:
            proposals[k] = found["holes"]
        if found["edgeOnSubject"] > EDGE_GUARD and k not in edges_ok:
            guard[k] = found["edgeOnSubject"]
        if i % 100 == 0:
            print(f"  proposed {i}/{len(masters)}", flush=True)
    (work / "_proposals.json").write_text(json.dumps(proposals, indent=1) + "\n")
    (work / "_edge_guard.json").write_text(json.dumps(guard, indent=1) + "\n")

    part = {k: p for p, ks in json.loads(POS.read_text()).items() for k in ks}
    holes_dir, edge_dir = ROOT / f"cutreview_{set_name}_holes_gi2", ROOT / f"cutreview_{set_name}_edge"
    guard_dir, master_dir = ROOT / f"cutreview_{set_name}_guard_gi2", ROOT / f"cutreview_{set_name}_master"
    for d in (holes_dir, edge_dir, guard_dir, master_dir):
        d.mkdir(parents=True, exist_ok=True)
    for k in sorted(set(proposals) | set(guard)):
        colour = tint(part.get(k, "noun"))
        src = ROOT / set_name / f"{k}.png"
        cut(src, work / f"_edge_{k}.png", [])
        on_tint(work / f"_edge_{k}.png", colour, edge_dir / f"{k}.png")
        if k in proposals:
            cut(src, work / f"_holes_{k}.png", proposals[k])
            on_tint(work / f"_holes_{k}.png", colour, holes_dir / f"{k}.png")
        if k in guard:
            on_tint(work / f"_edge_{k}.png", colour, guard_dir / f"{k}.png")
            Image.open(src).convert("RGB").resize((512, 512), Image.LANCZOS).save(master_dir / f"{k}.png")
    if proposals:
        page(f"{set_name}_holes", sorted(proposals), "Proposed holes cut", f"{edge_dir.name}:Edge cut only", work)
    if guard:
        page(f"{set_name}_guard", sorted(guard, key=lambda k: -guard[k]), "Edge cut", f"{master_dir.name}:Master", work)
    print(f"{len(proposals)} tile(s) with proposed holes: reject a tile if any cut takes a real part "
          f"of the picture (it keeps the edge cut only). {len(guard)} tile(s) where the edge cut may "
          f"reach into the picture: reject one and it ships uncut, framed. Then --apply-holes / --apply-guard.")


def rejected(path: Path) -> set[str]:
    text = path.read_text().strip()
    return set(json.loads(text)) if text else set()


def apply_holes(set_name: str, rejects: set[str]) -> None:
    spec = load_spec()
    proposals = json.loads((ROOT / "cut" / set_name / "_proposals.json").read_text())
    holes = spec.setdefault("holes", {}).setdefault(set_name, {})
    decided = set(spec.setdefault("decided", {}).setdefault(set_name, []))
    for k, pts in proposals.items():
        if k in rejects:
            holes.pop(k, None)
            decided.add(k)
        else:
            holes[k] = {"master": master_id(ROOT / set_name / f"{k}.png"), "points": pts}
            decided.discard(k)
    spec["holes"][set_name] = dict(sorted(holes.items()))
    spec["decided"][set_name] = sorted(decided)
    save_spec(spec)
    n = len(rejects & set(proposals))
    print(f"{set_name}: {len(proposals) - n} tile(s) get their holes cut, {n} keep the edge cut only.")


def apply_guard(set_name: str, rejects: set[str]) -> None:
    spec = load_spec()
    guard = json.loads((ROOT / "cut" / set_name / "_edge_guard.json").read_text())
    opaque = set(spec.setdefault("opaque", {}).setdefault(set_name, []))
    checked = set(spec.setdefault("edgesChecked", {}).setdefault(set_name, []))
    for k in guard:
        if k in rejects:
            opaque.add(k)
            checked.discard(k)
        else:
            checked.add(k)
            opaque.discard(k)
    spec["opaque"][set_name] = sorted(opaque)
    spec["edgesChecked"][set_name] = sorted(checked)
    save_spec(spec)
    n = len(rejects & set(guard))
    print(f"{set_name}: {len(guard) - n} tile(s) cut as usual, {n} ship uncut (framed). "
          "Redraw those with closed outlines to bring them back.")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--set", required=True)
    ap.add_argument("--apply-holes", type=Path, metavar="REJECTS_JSON",
                    help="the holes page's exported rejects")
    ap.add_argument("--apply-guard", type=Path, metavar="REJECTS_JSON",
                    help="the edge page's exported rejects")
    args = ap.parse_args()
    if args.apply_holes:
        apply_holes(args.set, rejected(args.apply_holes))
    if args.apply_guard:
        apply_guard(args.set, rejected(args.apply_guard))
    if not (args.apply_holes or args.apply_guard):
        build(args.set)


if __name__ == "__main__":
    main()
