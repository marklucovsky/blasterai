#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Print the app's per-call AI usage log from a booted simulator.

The Activity tab shows totals; this shows every row behind them — tokens split
into text input, image input and output, and the cost the app computed — so a
batch of word-adds can be checked against OpenAI's usage dashboard line by line.

    python3 tools/usage_log.py                    # every row
    python3 tools/usage_log.py --since "2026-10-10 14:30"
    python3 tools/usage_log.py --csv > usage.csv

Reads `APIUsageEvent` from the app's DeviceLocal.store, read-only. Simulator
only; on a device, use Share report.
"""
import argparse
import csv
import sqlite3
import subprocess
import sys
from pathlib import Path

BUNDLE_ID = "app.blasterai.ios"
APPLE_EPOCH = 978307200   # Core Data timestamps count from 2001-01-01 UTC


def store_path(device: str) -> Path:
    r = subprocess.run(["xcrun", "simctl", "get_app_container", device, BUNDLE_ID, "data"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"no app container on {device!r}: {r.stderr.strip()}")
    return Path(r.stdout.strip()) / "Library/Application Support/DeviceLocal.store"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", default="booted", help="simulator UDID (default: booted)")
    ap.add_argument("--since", help="local time, e.g. '2026-10-10 14:30'")
    ap.add_argument("--csv", action="store_true")
    args = ap.parse_args()

    db = sqlite3.connect(f"file:{store_path(args.device)}?mode=ro", uri=True)
    where, params = "", []
    if args.since:
        where = "WHERE datetime(ZTIMESTAMP + ?, 'unixepoch', 'localtime') >= ?"
        params = [APPLE_EPOCH, args.since]
    rows = db.execute(f"""
        SELECT datetime(ZTIMESTAMP + {APPLE_EPOCH}, 'unixepoch', 'localtime'),
               ZCAUSERAW, COALESCE(ZDETAIL, ''), ZMODEL,
               ZPROMPTTOKENS - ZIMAGEINPUTTOKENS - ZCACHEDPROMPTTOKENS,
               ZIMAGEINPUTTOKENS, ZCOMPLETIONTOKENS, ZCOSTMICROS
        FROM ZAPIUSAGEEVENT {where} ORDER BY ZTIMESTAMP""", params).fetchall()
    header = ["time", "cause", "detail", "model", "text_in", "image_in", "output", "cost_usd"]
    out = [list(r[:7]) + [r[7] / 1e6] for r in rows]

    if args.csv:
        w = csv.writer(sys.stdout)
        w.writerow(header)
        w.writerows(out)
        return
    for r in out:
        print(f"{r[0]}  {r[1]:18s} {r[2]:20s} {r[4]:>7} {r[5]:>7} {r[6]:>6}  ${r[7]:.4f}")
    totals = [sum(r[i] for r in out) for i in (4, 5, 6)]
    print(f"\n{len(out)} calls   text_in {totals[0]:,}   image_in {totals[1]:,}   "
          f"output {totals[2]:,}   ${sum(r[7] for r in out):.4f}")


if __name__ == "__main__":
    main()
