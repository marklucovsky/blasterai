#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Diff two OpenAI cost exports for one UTC day: tokens and dollars per line item.

The usage dashboard's dollars lag by hours, and chat and image usage land at
different speeds, so "spend went up by X" is not a usable check. Token counts in
the CSV export (Usage → download) are. Export once before a batch of word-adds
and once after it settles, then compare the difference with the app's own rows:

    python3 tools/diff_openai_costs.py before.csv after.csv 2026-10-10
    python3 tools/usage_log.py --since "2026-10-10 14:30"

Used 2026-10-10 to show the app logs every billed call to the token, and that
each line item's dollars ÷ tokens equals the rate in ModelPricing.swift. Days in
the export are UTC.
"""
import csv
import sys
from decimal import Decimal


def load(path: str, day: str) -> dict[str, tuple[Decimal, Decimal]]:
    out = {}
    with open(path, newline="") as f:
        for r in csv.DictReader(f):
            if r["start_time_iso"].startswith(day):
                out[r["line_item"]] = (Decimal(r["quantity"]), Decimal(r["amount_value"]))
    return out


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    before, after, day = sys.argv[1:]
    a, b = load(before, day), load(after, day)
    changed = False
    for k in sorted(set(a) | set(b)):
        qa, da = a.get(k, (Decimal(0), Decimal(0)))
        qb, db = b.get(k, (Decimal(0), Decimal(0)))
        if qb != qa or db != da:
            changed = True
            rate = f"  (${(db - da) / (qb - qa) * 1_000_000:.2f}/M)" if qb != qa and db != da else ""
            print(f"{k:45s} tokens {qb - qa:+12,.0f}   ${db - da:+.6f}{rate}")
    if not changed:
        print(f"no change on {day} (UTC) — usage may not have landed yet")


if __name__ == "__main__":
    main()
