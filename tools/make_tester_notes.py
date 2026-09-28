#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Turn the tester walk into the two things it has to be: plain text, and a PDF.

    Usage:
        python3 tools/make_tester_notes.py                 # both, into build/
        python3 tools/make_tester_notes.py --check         # limits only, no output

Produces, from `docs/beta-review-notes.md`:

  build/what-to-test.txt         paste into App Store Connect → What to Test
  build/beta-review-notes.txt    paste into Beta App Review Information
  build/BlasterAI-TestFlight.pdf email to a tester ahead of the invite

WHY THE PLAIN TEXT IS CHECKED
-----------------------------
Both App Store Connect fields are **4,000 characters of plain text**. The walk
came in at 3,963 the first time it was measured — 37 characters of headroom, so
an ordinary edit silently breaks it. This script fails when either section is
over, and prints the headroom when it is not, because the field truncates rather
than refusing and you would find out from a tester.

WHY A PDF AT ALL
----------------
The ASC field is a wall of text in a small box inside TestFlight. Someone being
asked to spend half an hour on an unfamiliar app deserves better than that, and
the PDF can go out with the invite email rather than being found after it.

WHY IT IS WRITTEN BY HAND
-------------------------
No pandoc, no reportlab, and `cupsfilter` has no HTML filter on macOS — it will
render plain text, monospaced, which is not a first impression to give a
clinician. PDF's text model with the base-14 fonts is simple enough to emit
directly, and doing so costs no dependency and cannot break on someone else's
machine. Helvetica is guaranteed present in every PDF reader, so nothing is
embedded.
"""

import argparse
import re
import sys
import textwrap
from pathlib import Path

SOURCE = Path("docs/beta-review-notes.md")
OUT = Path("build")
ASC_LIMIT = 4000

# Page geometry, in points (72 per inch). US Letter with generous margins —
# this is read on a screen more often than printed.
PAGE_W, PAGE_H = 612, 792
MARGIN_X, MARGIN_TOP, MARGIN_BOTTOM = 72, 72, 64
BODY_SIZE, BODY_LEAD = 10.5, 15.5
H1_SIZE, H2_SIZE = 20, 13

# Helvetica averages a little over half the point size per character. Wrapping
# by column count rather than measured width keeps this dependency-free; the
# column is chosen conservatively so a line of wide characters still fits.
BODY_COLS = 92


# Lines between these markers reach the PDF but not the App Store Connect text.
#
# The two have different jobs and only one of them has a 4,000-character wall.
# The ASC field is what a tester reads inside TestFlight for THIS build, so it
# carries what changed and why we care; the PDF is the half-hour walk that goes
# out with the invitation and has no reason to be short. Before this split the
# walk sat at 3,930 of 4,000 — 70 characters of headroom — and the next real
# addition to it silently truncated in the field rather than failing here.
PDF_ONLY_OPEN = "<!-- pdf-only -->"
PDF_ONLY_CLOSE = "<!-- /pdf-only -->"


def extract(doc: str, title: str, until: str, *, for_pdf: bool) -> str:
    """One blockquoted section, as the plain text the ASC field wants."""
    body = doc.split(title, 1)[1].split(until, 1)[0]
    out = []
    skipping = False
    for line in body.splitlines():
        marker = line.strip()
        if marker == PDF_ONLY_OPEN:
            skipping = not for_pdf
            continue
        if marker == PDF_ONLY_CLOSE:
            skipping = False
            continue
        if skipping:
            continue
        if line.startswith("> "):
            line = line[2:]
        elif line.strip() == ">":
            line = ""
        else:
            continue
        line = re.sub(r"\*\*(.+?)\*\*", r"\1", line)
        line = re.sub(r"\*(.+?)\*", r"\1", line)
        out.append(line)
    return "\n".join(out).strip() + "\n"


# --- PDF ---------------------------------------------------------------------


def esc(text: str) -> str:
    """PDF strings escape backslash and both parens, and are Latin-1."""
    text = text.replace("\\", r"\\").replace("(", r"\(").replace(")", r"\)")
    # Typographic characters the source uses freely, folded to what Helvetica's
    # standard encoding reliably draws.
    for a, b in [("—", "-"), ("–", "-"), ("'", "'"), ("'", "'"),
                 ("“", '"'), ("”", '"'), ("→", "->"), ("…", "...")]:
        text = text.replace(a, b)
    return text.encode("latin-1", "replace").decode("latin-1")


def layout(markdown_body: str) -> list[list[tuple]]:
    """Fold the section into pages of (font, size, x_indent, text) lines."""
    pages, page, y = [], [], PAGE_H - MARGIN_TOP

    def emit(font, size, indent, text, lead):
        nonlocal page, y
        if y - lead < MARGIN_BOTTOM:
            pages.append(page)
            page, y = [], PAGE_H - MARGIN_TOP
        page.append((font, size, indent, text, y))
        y -= lead

    emit("H", H1_SIZE, 0, "BlasterAI — TestFlight", H1_SIZE * 1.5)
    emit("B", BODY_SIZE, 0,
         "What to try, and what we would like to hear back.", BODY_LEAD * 1.6)

    # Re-flow into logical blocks first.
    #
    # The markdown is hard-wrapped, so one step is several source lines and one
    # paragraph is several more. Laying out line by line put every continuation
    # back at the margin — "1." hung over nothing, and prose came out in short
    # ragged lines. Joining first means the wrap is ours.
    #
    # Two things must survive the join: a nested bullet under a numbered step is
    # its own block even though it is indented like a continuation, and a blank
    # line always ends whatever was being built.
    blocks: list[tuple[str, str, int]] = []      # (kind, text, first-line indent)
    for raw in markdown_body.splitlines():
        stripped = raw.strip()
        if not stripped:
            blocks.append(("gap", "", 0))
            continue
        if raw.startswith("### "):
            blocks.append(("h2", stripped[4:], 0))
            continue
        if stripped.startswith("- "):
            # Indented in the source means nested under the step above it.
            blocks.append(("bullet", stripped, 18 if raw[:1].isspace() else 0))
            continue
        if re.match(r"^\d+\.\s", stripped):
            blocks.append(("step", stripped, 0))
            continue
        if blocks and blocks[-1][0] in ("step", "bullet", "para"):
            kind, text, lead = blocks[-1]
            blocks[-1] = (kind, f"{text} {stripped}", lead)
            continue
        blocks.append(("para", stripped, 0))

    for kind, text, lead in blocks:
        if kind == "gap":
            y -= BODY_LEAD * 0.45
            continue
        if kind == "h2":
            y -= BODY_LEAD * 0.55
            emit("H", H2_SIZE, 0, text, H2_SIZE * 1.45)
            continue
        # Wrapped lines hang under the first character of the text rather than
        # under the marker, so a step reads as one thing.
        hang = lead + {"step": 18, "bullet": 14, "para": 0}[kind]
        for i, chunk in enumerate(textwrap.wrap(text, BODY_COLS - hang // 5) or [""]):
            emit("B", BODY_SIZE, lead if i == 0 else hang, chunk, BODY_LEAD)

    pages.append(page)
    return pages


def write_pdf(pages: list, path: Path) -> None:
    objects: list[bytes] = []

    def add(body: bytes) -> int:
        objects.append(body)
        return len(objects)          # PDF object numbers are 1-based

    font_b = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
                 b"/Encoding /WinAnsiEncoding >>")
    font_h = add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold "
                 b"/Encoding /WinAnsiEncoding >>")
    pages_id = len(objects) + 1 + 2 * len(pages)   # reserved; filled in below

    page_ids = []
    for lines in pages:
        parts = ["BT"]
        for font, size, indent, text, y in lines:
            parts.append(f"/F{'H' if font == 'H' else 'B'} {size} Tf")
            parts.append(f"1 0 0 1 {MARGIN_X + indent} {y:.1f} Tm")
            parts.append(f"({esc(text)}) Tj")
        parts.append("ET")
        stream = "\n".join(parts).encode("latin-1", "replace")
        content = add(b"<< /Length %d >>\nstream\n" % len(stream) + stream +
                      b"\nendstream")
        page_ids.append(add(
            b"<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %d %d] "
            b"/Resources << /Font << /FB %d 0 R /FH %d 0 R >> >> "
            b"/Contents %d 0 R >>" % (pages_id, PAGE_W, PAGE_H,
                                      font_b, font_h, content)))

    kids = b" ".join(b"%d 0 R" % i for i in page_ids)
    tree = add(b"<< /Type /Pages /Kids [%s] /Count %d >>" % (kids, len(page_ids)))
    assert tree == pages_id, "page-tree id was reserved wrongly"
    root = add(b"<< /Type /Catalog /Pages %d 0 R >>" % tree)

    out, offsets = bytearray(b"%PDF-1.4\n"), []
    for n, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % n + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += (b"trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n"
            % (len(objects) + 1, root, xref))
    path.write_bytes(bytes(out))


# --- driver ------------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Build the tester notes as plain text and a PDF.")
    ap.add_argument("--check", action="store_true",
                    help="only verify the App Store Connect length limits")
    args = ap.parse_args()

    if not SOURCE.exists():
        sys.exit(f"missing {SOURCE} — run from the repo root")
    doc = SOURCE.read_text()

    # One entry per App Store Connect text box, keyed by the file it becomes.
    # `beta-app-description` is shown to testers in the TestFlight app and is a
    # different thing from `what-to-test`, which is attached to each build — a
    # distinction the form makes and it is easy to miss.
    sections = {
        "beta-app-description": extract(doc, "### Beta App Description",
                                        "## 1. Review Notes", for_pdf=False),
        "review-notes": extract(doc, "## 1. Review Notes", "## 2. What to Test",
                                for_pdf=False),
        "what-to-test": extract(doc, "## 2. What to Test", "## 3. Invite email",
                                for_pdf=False),
    }
    # The PDF is the same section with nothing held back.
    walk = extract(doc, "## 2. What to Test", "## 3. Invite email", for_pdf=True)

    over = False
    for name, text in sections.items():
        n = len(text)
        room = ASC_LIMIT - n
        status = f"{room} to spare" if room >= 0 else f"OVER by {-room}"
        print(f"  {name:22s} {n:5d} / {ASC_LIMIT}   {status}")
        if room < 0:
            over = True
        elif room < 150:
            print(f"  {'':22s} ⚠️  very little headroom — an ordinary edit "
                  "will break this")
    if over:
        print("\nApp Store Connect truncates rather than refusing, so this "
              "would be found by a tester.")
        return 1
    if args.check:
        return 0

    OUT.mkdir(exist_ok=True)
    for name, text in sections.items():
        (OUT / f"{name}.txt").write_text(text)
        print(f"  wrote {OUT / f'{name}.txt'}")

    pdf = OUT / "BlasterAI-TestFlight.pdf"
    write_pdf(layout(walk), pdf)
    print(f"  wrote {pdf}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
