#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Check docs/app-store-listing.md against App Store Connect's field limits.

    python3 tools/check_listing.py
    python3 tools/check_listing.py --export build/listing   # plain text to paste

App Store Connect rejects some over-long fields at save time and truncates
others silently, and the copy is written here first — so the limits are
checked here, where fixing them costs nothing.

It reads the table rows for Name and Subtitle and the quoted (`> `) blocks
under each `###` heading. Exits non-zero if anything is over, or if a field it
expects is missing — "could not find it" is never reported as "fits".
"""

import re
import sys
from pathlib import Path

DOC = Path(__file__).resolve().parent.parent / "docs/app-store-listing.md"

TABLE_FIELDS = {"Name": 30, "Subtitle": 30}
QUOTED_FIELDS = {"Promotional Text": 170, "Description": 4000,
                 "Keywords": 100, "Notes": 4000}


def quoted_block(text: str, heading: str) -> str | None:
    """The `> ` lines under `### <heading>`, joined the way ASC would hold them."""
    m = re.search(rf"^### {re.escape(heading)}\b.*?$(.*?)(?=^##)", text, re.M | re.S)
    if not m:
        return None
    lines = [l[2:] if l.startswith("> ") else "" for l in m.group(1).splitlines()
             if l.startswith(">")]
    if not lines:
        return None
    # Consecutive quoted lines are one paragraph; a bare ">" is a paragraph break.
    paras, cur = [], []
    for l in lines:
        if l == "":
            if cur:
                paras.append(" ".join(cur))
            cur = []
        else:
            cur.append(l.strip())
    if cur:
        paras.append(" ".join(cur))
    return "\n\n".join(paras)


SECTION_HEADS = ["A BOARD THAT BEHAVES LIKE A BOARD", "FIVE ART STYLES, EVERY WORD DRAWN",
                 "BUILT FOR THE PEOPLE WHO SET IT UP", "SEE WHICH WORDS ACTUALLY GET REACHED",
                 "AI WHEN YOU WANT IT", "PRIVATE BY DESIGN"]


def export(text: str, out: Path) -> None:
    """Write each quoted field as plain text, ready to paste into App Store Connect.

    Copying the fields out of a terminal mangled them on 2026-10-07 — whole
    phrases dropped mid-paragraph, and App Store Connect then refused to save
    with no message at all. A file opened in an editor copies cleanly. Bullets
    become `- `, the description's section heads get their own lines, and the
    review walk's numbered steps each start a line.
    """
    out.mkdir(parents=True, exist_ok=True)
    for field in QUOTED_FIELDS:
        t = quoted_block(text, field)
        if t is None:
            continue
        t = t.replace(" • ", "\n- ").replace("• ", "- ")
        for head in SECTION_HEADS:
            t = t.replace(head + " ", head + "\n")
        t = re.sub(r" (\d)\. ", r"\n\1. ", t)
        path = out / (field.lower().replace(" ", "-") + ".txt")
        path.write_text(t + "\n")
        print(f"  wrote {path}  ({len(t)} chars)")


def main() -> int:
    text = DOC.read_text()
    if len(sys.argv) == 3 and sys.argv[1] == "--export":
        export(text, Path(sys.argv[2]))
    failed = False
    for field, limit in TABLE_FIELDS.items():
        m = re.search(rf"^\| \*\*{field}\*\* \| (.+?) \|$", text, re.M)
        if not m:
            print(f"  ??  {field}: not found in the table"); failed = True; continue
        n = len(m.group(1))
        ok = n <= limit
        failed |= not ok
        print(f"  {'ok' if ok else 'OVER'}  {field}: {n}/{limit}  {m.group(1)!r}")
    for field, limit in QUOTED_FIELDS.items():
        block = quoted_block(text, field)
        if block is None:
            print(f"  ??  {field}: no quoted block under '### {field}'"); failed = True; continue
        n = len(block)
        ok = n <= limit
        failed |= not ok
        print(f"  {'ok' if ok else 'OVER'}  {field}: {n}/{limit}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
