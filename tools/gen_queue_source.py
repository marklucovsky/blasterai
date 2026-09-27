#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Generate a `first` tile until it is one `compose_queue.py` can actually use.

    python3 tools/gen_queue_source.py --set playful_3d [--tries 5]

WHY A RETRY LOOP INSTEAD OF A BETTER PROMPT
-------------------------------------------
`compose_queue.py` derives `next` and `last` by moving the marked figure along
the row, which requires finding four separate figures in the source. Whether it
can depends on how tightly the model happened to pack the line, and that varies
between renders of the *same* prompt: measured across passes of the Playful 3D
queue, neighbouring figures came out 35px apart in one render, 7px in the next
and about 200 in another. The prompt asks for a wide gap either way.

Nothing in the wording fixes this, because it is not a comprehension failure —
the layout is simply not something the prompt fully determines. What does fix it
is checking: generate, measure, keep it if the figures separate, otherwise spend
another four cents. Cheaper than a person looking at it, and it cannot be
fooled by a thumbnail, which is how several of these got through before.

The check is the same measurement `compose_queue` will make, deliberately — a
source that passes here is a source that composes, with no second opinion
involved.
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

try:
    import numpy as np
    from PIL import Image
    from compose_queue import empty_column, BG_TOLERANCE
except ImportError as exc:
    sys.exit(f"{exc} — run from the repo root with pillow and numpy installed")


def separable(path):
    """(ok, spans) — does the head band split into exactly four figures?"""
    px = np.asarray(Image.open(path).convert("RGB"), dtype=np.int16)
    h, w = px.shape[:2]
    ref = empty_column(px)
    is_bg = np.abs(px - ref[:, None, :]).max(axis=2) <= BG_TOLERANCE
    band = ~is_bg[int(h * 0.20):int(h * 0.55)].all(axis=0)

    spans, start = [], None
    for x, v in enumerate(band):
        if v and start is None:
            start = x
        elif not v and start is not None:
            spans.append([start, x - 1])
            start = None
    if start is not None:
        spans.append([start, len(band) - 1])

    while len(spans) > 4:                       # reunite a detached nose
        gaps = [spans[i + 1][0] - spans[i][1] for i in range(len(spans) - 1)]
        i = gaps.index(min(gaps))
        spans[i][1] = spans[i + 1][1]
        del spans[i + 1]

    return len(spans) == 4, spans


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--set", required=True)
    ap.add_argument("--tries", type=int, default=5)
    args = ap.parse_args()

    dest = Path("tools/tile_sets") / getattr(args, "set") / "first.png"
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as fh:
        fh.write("first\n")
        keys_file = fh.name

    for attempt in range(1, args.tries + 1):
        dest.unlink(missing_ok=True)
        subprocess.run([sys.executable, "tools/generate_sets.py",
                        "--set", getattr(args, "set"), "--keys-file", keys_file],
                       check=True, stdout=subprocess.DEVNULL)
        if not dest.exists():
            print(f"  attempt {attempt}: generation failed")
            continue
        ok, spans = separable(dest)
        gaps = [spans[i + 1][0] - spans[i][1] for i in range(len(spans) - 1)]
        print(f"  attempt {attempt}: {len(spans)} figures, gaps={gaps}"
              f"{'  ✓ usable' if ok else '  ✗ not separable'}")
        if ok:
            print(f"\n✓ {dest} is composable — run:\n"
                  f"    python3 tools/compose_queue.py --set {getattr(args, 'set')} --bands")
            return 0

    print(f"\n✗ no usable source after {args.tries} attempts")
    return 1


if __name__ == "__main__":
    sys.exit(main())
