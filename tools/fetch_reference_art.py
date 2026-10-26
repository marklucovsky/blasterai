#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Fetch ARASAAC pictograms as a REVIEW reference, never as art.

    python3 tools/fetch_reference_art.py puppy cousin firefighter
    python3 tools/fetch_reference_art.py --keys-file keys.txt

Writes `tools/reference_art/arasaac/{key}.png` (gitignored), the column
`compare_tiles.py` puts beside a candidate: ARASAAC is the symbol set an SLP
already reads, so "does ours say what theirs says" is the first review question.

ARASAAC is CC BY-NC-SA 4.0. It left the app in July 2026 (see NOTICE) and must
not come back through this folder: nothing here is synced, optimized or shipped.

A key's label (`belly_button` → "belly button") is searched with `bestsearch`,
then `search`. A word with no hit is listed at the end; for those the fallback
reference is an Avaz screenshot, cropped by hand.
"""
import argparse
import json
import sys
import urllib.parse
from pathlib import Path

try:
    import requests  # urllib fails certificate checks on python.org builds
except ImportError:
    sys.exit("pip install requests")

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tools/reference_art/arasaac"
VOCAB = ROOT / "claudeBlast/Resources/vocabulary.json"
API = "https://api.arasaac.org/api/pictograms/en"
PIC = "https://static.arasaac.org/pictograms/{id}/{id}_500.png"


def get_json(url):
    try:
        r = requests.get(url, timeout=15)
        return r.json() if r.ok else []
    except (requests.RequestException, ValueError):
        return []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("keys", nargs="*")
    ap.add_argument("--keys-file", type=Path)
    ap.add_argument("--force", action="store_true", help="refetch keys already downloaded")
    args = ap.parse_args()
    keys = list(args.keys) + (args.keys_file.read_text().split() if args.keys_file else [])
    labels = {t["key"]: t.get("label") for t in json.loads(VOCAB.read_text())}
    OUT.mkdir(parents=True, exist_ok=True)
    missed = []
    for key in keys:
        dest = OUT / f"{key}.png"
        if dest.exists() and not args.force:
            continue
        term = (labels.get(key) or key.rstrip("_").replace("_", " ")).lower()
        q = urllib.parse.quote(term)
        hits = get_json(f"{API}/bestsearch/{q}") or get_json(f"{API}/search/{q}")
        if not hits:
            missed.append(key)
            continue
        pid = hits[0]["_id"]
        r = requests.get(PIC.format(id=pid), timeout=30)
        r.raise_for_status()
        dest.write_bytes(r.content)
        print(f"{key:20} {term!r} → {pid}")
    if missed:
        print("no ARASAAC match (use an Avaz crop):", " ".join(missed))


if __name__ == "__main__":
    main()
