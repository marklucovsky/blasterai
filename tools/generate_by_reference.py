#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Draw tiles in a set's style by showing the model the set's reference pack.

gpt-image-1 shuts down 2026-10-23. Its replacement, gpt-image-2, does not hold a
style from a text description alone: the Classic prompt that gave us bold flat
pictograms on gpt-image-1 comes back thin-lined and shaded, and the model takes
subject text far more literally ("cheese stretching" now means cheese strings).
Passing a few tiles from the set as references fixes the style where words did
not — apple came back nearly identical to the shipped tile.

So every set has a **reference pack**: 3-4 approved tiles, deliberately unrelated
to each other (a person, an action, an object, an abstract), frozen at 256px in
`claudeBlast/Resources/ReferencePacks/refpack_<set>__<key>.png`. Every drawing sends the subject plus the
whole pack to /v1/images/edits as repeated `image[]`. Multi-image input is
*reference composition* — "here are examples, make a picture" — which is wrong
for a skin-tone edit (see TileImageGenerator.transform) and exactly right here.

Candidates land in `tools/tile_sets/<set>_gi2/` (gitignored) for review with
`build_review_page.py --set <set>_gi2`, and replace the master only once approved.

Usage:
    python3 tools/generate_by_reference.py --set classic --key apple --key eat
    python3 tools/generate_by_reference.py --set classic --all --skip-existing
    python3 tools/generate_by_reference.py --set classic --all --dry-run
"""

import argparse
import base64
import json
import os
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from build_tone_variants import QuotaExhausted, post_multipart, with_retry  # noqa: E402
from generate_sets import extract_subject, strip_clay_words  # noqa: E402

TILE_SETS = Path("tools/tile_sets")
# Shipped in the app bundle so a word added on device is drawn from the same
# references as the bundled set. Flat names: the bundle has no subdirectories.
PACKS = Path("claudeBlast/Resources/ReferencePacks")
PROMPTS_FILE = Path("tools/prompts.json")
STYLES_FILE = Path("claudeBlast/Resources/image_styles.json")
# tools/tile_sets/<set>_provenance.json: how each key's art is made. Keys that are
# code-rendered, composited, special or preserved from review are copied from the
# master unchanged; the `ai` bucket supplies subjects that are not in prompts.json.


def provenance_file(set_name: str) -> Path:
    return TILE_SETS / f"{set_name}_provenance.json"
EDITS_URL = "https://api.openai.com/v1/images/edits"
MODEL = "gpt-image-2"
# Measured 2026-10-10 with the 256px pack (256 input tokens per reference; a
# 512px one costs 1,024 and held the style no better). Output dominates: medium
# returns 1,756 tokens, low 196. Estimates for the confirmation prompt, not a bill.
COST_PER_TILE = {"low": 0.016, "medium": 0.062}

# The cheapest quality each style survives at, from a 2026-10-10 review of the
# same words at both: flat pictogram styles lose little at low (Classic: 3 of 47
# tiles failed — teeth, pizza, a metallic shine), so a set is drawn at low and the
# rejects redrawn with `--quality medium`. Playful 3D's depth is what low throws
# away (9 of 45 failed — skin, gradients, cloth drape, liquid), so it is always
# medium. Styles not listed default to medium.
DEFAULT_QUALITY = {"classic": "low", "high_contrast_v2": "low", "playful_3d": "medium"}

PROMPT = (
    "The reference images are tiles from one AAC pictogram symbol set. Draw ONE new tile "
    "for this set showing: {subject}.\n\n"
    "Match the references' drawing style exactly: the same outline weight, the same flat "
    "colors, the same level of simplicity, and people drawn the same way the references draw "
    "them. Keep only what is needed to read the subject — drop small decorative details. "
    "Do not copy any reference's subject into the new tile.\n\n"
    "The set's style, for reference: {style}"
)


def load_subjects(prov: Path, extra: Path | None) -> dict[str, str]:
    """Subject text per key: prompts.json, then the provenance file's non-prompts.json
    subjects (pack words, function words), then an optional per-run overlay."""
    subjects = {k.lower(): extract_subject(v)
                for k, v in json.loads(PROMPTS_FILE.read_text()).items()}
    if prov.exists():
        for k, v in json.loads(prov.read_text()).get("ai", {}).items():
            if v.get("subject") and v["subject"] != "prompts.json":
                subjects[k] = extract_subject(v["subject"])
    if extra:
        subjects.update({k: extract_subject(v) for k, v in json.loads(extra.read_text()).items()})
    return subjects


def copied_keys(prov: Path) -> set[str]:
    if not prov.exists():
        return set()
    p = json.loads(prov.read_text())
    return set(p.get("rendered", {})) | set(p.get("special", {})) | set(p.get("preserved", {}))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--set", required=True, help="style key; also the master folder and pack name")
    ap.add_argument("--key", action="append", default=[])
    ap.add_argument("--keys-file", type=Path)
    ap.add_argument("--all", action="store_true", help="every key in the set's master folder")
    ap.add_argument("--out-dir", type=Path, help="default tools/tile_sets/<set>_gi2")
    ap.add_argument("--subjects-file", type=Path,
                    help="JSON key → subject (or full prompt) laid over the defaults, this run only")
    ap.add_argument("--skip-existing", action="store_true")
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--model", default=MODEL)
    ap.add_argument("--quality", help="low | medium | high; default per style, see "
                                      "DEFAULT_QUALITY — redraw rejects with medium")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--yes", action="store_true", help="skip the cost confirmation")
    args = ap.parse_args()
    args.quality = args.quality or DEFAULT_QUALITY.get(args.set, "medium")

    master = TILE_SETS / args.set
    out = args.out_dir or TILE_SETS / f"{args.set}_gi2"
    pack = sorted(PACKS.glob(f"refpack_{args.set}__*.png"))
    if not pack:
        sys.exit(f"no reference pack for {args.set} in {PACKS}")
    style = json.loads(STYLES_FILE.read_text())[args.set]
    prov = provenance_file(args.set)
    subjects = load_subjects(prov, args.subjects_file)

    keys = list(args.key)
    if args.keys_file:
        keys += [k.strip() for k in args.keys_file.read_text().split() if k.strip()]
    if args.all:
        keys += sorted(p.stem for p in master.glob("*.png"))
    keys = list(dict.fromkeys(keys))
    if not keys:
        sys.exit("no keys: pass --key, --keys-file or --all")

    copy = copied_keys(prov) & set(keys)
    draw = [k for k in keys if k not in copy]
    if args.skip_existing:
        draw = [k for k in draw if not (out / f"{k}.png").exists()]
    missing = [k for k in draw if k not in subjects]
    if missing:
        sys.exit(f"{len(missing)} keys have no subject (add them to the provenance file or "
                 f"--subjects-file): {', '.join(missing[:20])}")

    print(f"{args.set}: draw {len(draw)}, copy {len(copy)} from master, "
          f"pack {[p.stem.split("__")[1] for p in pack]}, model {args.model}, "
          f"quality {args.quality}, ≈ ${len(draw) * COST_PER_TILE.get(args.quality, 0.062):.2f}")
    if args.dry_run:
        for k in draw[:10]:
            print(f"  {k:24s} {subjects[k][:90]}")
        return
    if len(draw) > 25 and not args.yes and input("Proceed? [y/N] ").strip().lower() != "y":
        sys.exit("aborted")

    api_key = os.environ.get("OPENAI_API_KEY", "").strip() or sys.exit("OPENAI_API_KEY not set")
    out.mkdir(parents=True, exist_ok=True)
    for k in copy:
        src = master / f"{k}.png"
        if src.exists() and not (out / f"{k}.png").exists():
            (out / f"{k}.png").write_bytes(src.read_bytes())

    refs = [(p.name, p.read_bytes()) for p in pack]
    lock, done, failed = threading.Lock(), [0], []
    out_of_credits = threading.Event()
    start = time.time()

    def one(key: str) -> None:
        if out_of_credits.is_set():
            with lock:
                failed.append(key)
            return
        subject = subjects[key]
        if args.set != "playful_3d":
            subject = strip_clay_words(subject)
        fields = {"model": args.model, "prompt": PROMPT.format(subject=subject, style=style),
                  "size": "1024x1024", "quality": args.quality, "n": "1"}
        try:
            r = with_retry(lambda: post_multipart(EDITS_URL, fields, {}, api_key,
                                                  multi_field="image[]", multi=refs), label=key)
        except QuotaExhausted:
            if not out_of_credits.is_set():
                print("  OpenAI account is out of credits — stopping; rerun with --skip-existing",
                      flush=True)
            out_of_credits.set()
            r = None
        ok = bool(r and r.get("data") and r["data"][0].get("b64_json"))
        if ok:
            (out / f"{key}.png").write_bytes(base64.b64decode(r["data"][0]["b64_json"]))
        with lock:
            done[0] += 1
            if not ok:
                failed.append(key)
            if not ok or done[0] % 10 == 0 or done[0] == len(draw):
                rate = (time.time() - start) / done[0]
                print(f"  {done[0]}/{len(draw)}  {'FAILED ' + key if not ok else ''}"
                      f"  ~{rate * (len(draw) - done[0]) / 60:.0f} min left", flush=True)

    with ThreadPoolExecutor(args.workers) as pool:
        list(pool.map(one, draw))

    (out / "_run.json").write_text(json.dumps({
        "model": args.model, "quality": args.quality, "pack": [p.stem.split("__")[1] for p in pack],
        "drawn": len(draw) - len(failed), "copied": sorted(copy), "failed": sorted(failed),
        "finished": time.strftime("%Y-%m-%d %H:%M"),
    }, indent=2))
    print(f"\ndone: {len(draw) - len(failed)} drawn, {len(copy)} copied, {len(failed)} failed"
          + (f": {' '.join(sorted(failed))}  (rerun with --skip-existing)" if failed else ""))
    print(f"review: python3 tools/build_review_page.py --set {out.name}")


if __name__ == "__main__":
    main()
