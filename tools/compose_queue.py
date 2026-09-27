#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Build the `next` and `last` queue tiles by rearranging the figures in `first`.

    python3 tools/compose_queue.py --set classic

WHY THESE ARE NOT GENERATED
---------------------------
`first`, `next` and `last` are meant to be the same picture three times: four
identical figures in a row, every one facing left, with a single one drawn as a
child instead of a grey silhouette. Only the child's position changes.

Generating them separately cannot deliver that, and did not. Even the two passes
that came back *correct* were not the same drawing: `next` arrived with a
black-haired child and noticeably heavier outlines than `first`, so the three
tiles read as three illustrations of a similar idea rather than one idea in
three positions. On a board where a child is learning that only the position
means anything, every other difference is noise competing with the signal.

`last` was worse — five attempts, and the failures were not random:

  - asked for a left-facing line with the child at the right end, the model
    returned an entirely right-facing line, three times, twice on a grey field;
  - asked for the mirror image — child at the left end, everyone facing right,
    intending to flip it — the grey silhouettes stayed left-facing while only
    the child turned, so the flip produced three figures facing one way and the
    child facing the other.

That second failure is the informative one. The grey figures have a strong
default toward facing left and ignore instructions against it; the coloured
child complies. So any prompt asking for a right-facing line produces a
disagreement, and mirroring cannot repair it, because a horizontal flip
preserves *relative* orientation — it turns a disagreement into a different
disagreement.

There is no wording left to try that has not already failed, and the thing being
asked for is not a drawing problem at all. `first` already contains four
correctly-facing figures with the child among them. Moving that child along the
row is an image operation, so this does it as one: exact, free, repeatable, and
guaranteed to agree with `first` on every figure, because they are the same
pixels. Identical line weight, identical child, identical silhouettes — which is
the property the set is built on, and the one generation kept breaking.

Same argument `mirror_tile.py` makes for next/previous, one step further along.

`first` stays the generated original. Regenerate it and rerun this; the other
two follow.

HOW
---
Figures are separated by columns of untouched canvas, so the gaps between them
are found rather than assumed — no fixed band widths, nothing to retune if the
art is regenerated. Each figure is cropped to its own extent, the order is
rotated by one, and the four are laid out again with even gaps, bottom-aligned
so they stand on the same floor.

The canvas colour is **sampled from the corners**, not assumed. Classic is white
and High Contrast is black; a fixed "background is the light one" test works for
the first and inverts for the second, which is exactly what happened — the first
version found the entire High Contrast tile to be a single figure.

NOT USABLE ON PLAYFUL 3D. That set renders a photographic clay scene: the
figures overlap, cast shadows onto each other and stand on a floor that meets
the backdrop, so there are no separating columns to find. Its three queue tiles
are generated independently and cannot be pixel-identical to each other. That is
a property of the style, not a defect to chase.
"""

import argparse
import sys
from pathlib import Path

try:
    import numpy as np
    from PIL import Image
except ImportError:
    sys.exit("pip install pillow numpy")

# How far a pixel may stray from the background colour and still count as
# background. Generous, because both grounds carry a little compression noise.
BG_TOLERANCE = 28
# Wider, for repainting the background after a band reorder — see band_compose.
FLATTEN_TOLERANCE = 46


def background_colour(img):
    """The canvas colour, taken from the four corners.

    Sampled rather than assumed. Classic is white and High Contrast is black, so
    a fixed "light is background" test works for one and inverts for the other —
    the first version of this looked for columns with no dark pixels and found
    the entire High Contrast canvas to be one figure.
    """
    w, h = img.size
    corners = [img.getpixel(p) for p in ((2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3))]
    return tuple(sum(c[i] for c in corners) // len(corners) for i in range(3))


def empty_column(px, margin=6):
    """A column of pure background, taken from the outer edges of the canvas.

    Compared against a *column*, not a single colour, because Playful 3D's
    backdrop meets a floor: the background varies top to bottom but is uniform
    left to right. A flat-colour test calls the whole canvas foreground there,
    which is what defeated the first two versions of this. Classic and High
    Contrast have uniform grounds, so their empty column is a constant and the
    same test still holds.
    """
    edges = np.concatenate([px[:, :margin], px[:, -margin:]], axis=1)
    return np.median(edges, axis=1)


def figure_boxes(img):
    """Bounding boxes of each figure, left to right, split on background-only columns."""
    px = np.asarray(img, dtype=np.int16)
    ref = empty_column(px)                       # (h, 3)
    is_bg = np.abs(px - ref[:, None, :]).max(axis=2) <= BG_TOLERANCE
    has_ink = ~is_bg.all(axis=0)
    spans, start = [], None
    for x, inked in enumerate(has_ink):
        if inked and start is None:
            start = x
        elif not inked and start is not None:
            spans.append((start, x - 1))
            start = None
    if start is not None:
        spans.append((start, len(has_ink) - 1))

    boxes = []
    for x0, x1 in spans:
        band = ~is_bg[:, x0:x1 + 1]
        rows = np.where(band.any(axis=1))[0]
        boxes.append((x0, int(rows[0]), x1 + 1, int(rows[-1]) + 1))
    return boxes


def band_compose(src, order):
    """Reorder full-height vertical bands. The path for rendered styles.

    Playful 3D cannot be segmented the way Classic and High Contrast can: its
    figures cast contact shadows onto the floor, which bridge the gaps between
    them, and raising the tolerance to break those bridges starts fragmenting
    the figures on their own clay texture. Measured on its `first`: 1 figure
    found at tolerance 28, 2 at 45, 9 at 60. There is no usable threshold.

    Two facts rescue it. The figures are separable *above* the floor — heads and
    torsos have clear background between them — and the backdrop is uniform
    left to right, so any vertical band of it is interchangeable with any other.

    So detection runs on a horizontal slice through the heads, the cuts are made
    at the midpoints of the gaps found there, and whole floor-to-ceiling bands
    are swapped. Each figure travels with its own shadow because the shadow is
    inside its band, and the backdrop-to-floor gradient survives untouched
    because no background pixel is ever repainted — only moved sideways to an
    identical neighbour.
    """
    px = np.asarray(src, dtype=np.int16)
    h, w = px.shape[:2]
    ref = empty_column(px)
    is_bg = np.abs(px - ref[:, None, :]).max(axis=2) <= BG_TOLERANCE

    # Heads and upper torsos: below the top margin, above the floor contact.
    slice_ink = ~is_bg[int(h * 0.20):int(h * 0.55)].all(axis=0)
    spans, start = [], None
    for x, inked in enumerate(slice_ink):
        if inked and start is None:
            start = x
        elif not inked and start is not None:
            spans.append((start, x - 1))
            start = None
    if start is not None:
        spans.append((start, len(slice_ink) - 1))

    # Merge spans separated by less than a figure's width.
    #
    # A protruding nose is its own span: at some rows there is clear background
    # between the tip and the cheek, so the detector returned FIVE spans for
    # four figures — a 22px nose, then two real figures, then the remaining two
    # merged into one 457px block because the count was already off. The layout
    # that came out of that had the child hard against one edge and a hole
    # beside it, which is the spacing fault this was supposed to fix.
    #
    # Merged by rank, not by a threshold: while there are more than four spans,
    # join whichever adjacent pair is closest together.
    #
    # A fixed minimum gap cannot work here. Measured across two renders of the
    # same prompt, the gaps between neighbouring figures were 35, 4 and 13 px in
    # one and around 200 in another — the model spaces the line however it
    # likes, so any constant is simultaneously too big for one render and too
    # small for the next. A threshold of w/16 turned a correct four-span split
    # into a single blob.
    #
    # What is stable is the count. There are four figures; a nose that detached
    # from its own face is by definition nearer to it than any two figures are
    # to each other, so collapsing the smallest gaps first always reunites the
    # nose before it starts merging real neighbours.
    spans = [list(s) for s in spans]
    while len(spans) > 4:
        gaps = [spans[i + 1][0] - spans[i][1] for i in range(len(spans) - 1)]
        i = gaps.index(min(gaps))
        spans[i][1] = spans[i + 1][1]
        del spans[i + 1]
    spans = [tuple(s) for s in spans]
    if len(spans) != 4:
        sys.exit(f"expected 4 figures across the head band, found {len(spans)}: {spans}")

    # Each band is cropped to its own figure, then laid out with EQUAL GAPS.
    #
    # Two earlier versions got this wrong in opposite directions. Cutting at the
    # midpoints of the gaps gave unequal bands, so each figure carried its share
    # of blank canvas with it: invisible in `first`, where the widest band sits
    # on the end, and glaring in `next` and `last`, where that surplus opens a
    # hole right in front of the marked figure. Fixed quarter-width bands fixed
    # the spacing and started shearing noses off, because a figure is wider than
    # a quarter of the canvas once its nose and heels are counted.
    #
    # So the width comes from the figure and the spacing comes from the layout.
    # Regions are bounded by the gap midpoints; within each region the figure's
    # true extent is measured over the full height, so nothing is clipped; then
    # the four crops are placed with one gap size shared by all of them.
    mids = [0] + [(spans[i][1] + spans[i + 1][0]) // 2 for i in range(3)] + [w]
    bands, widths, boxes_x = [], [], []
    for i in range(4):
        region = ~is_bg[:, mids[i]:mids[i + 1]]
        cols = np.where(region.any(axis=0))[0]
        x0 = mids[i] + int(cols[0])
        x1 = mids[i] + int(cols[-1]) + 1
        bands.append(src.crop((x0, 0, x1, h)))
        widths.append(x1 - x0)
        boxes_x.append((x0, x1))

    # Placed by HEAD CENTRE, not by bounding box.
    #
    # Laying the crops out with equal gaps between their bounding boxes looked
    # even in code and uneven on screen: measured at head height the gaps came
    # out [36, 5, 15] on one tile and [111, 19, 15] on another. A crop is tight
    # to the figure's widest point, which for these figures is the feet, so a
    # figure with splayed feet gets a wide box and appears to stand further from
    # its neighbour than one that does not. The eye reads the space between
    # heads and bodies; the bounding box measures something else.
    #
    # So the boxes still define the crops — nothing may be clipped — while the
    # head centre defines where each one goes. Heads end up evenly spaced, which
    # is what the rhythm of a queue actually is.
    # Each figure is placed so its HEAD CENTRE lands on the slot the source
    # already used. Two earlier layouts failed here and both failed the same
    # way — by inventing positions.
    #
    # Equal gaps between bounding boxes looked even in code and uneven on
    # screen: a crop is tight to the figure's widest point, which for these is
    # the feet, so splayed feet push a figure away from its neighbour. Measured
    # at head height the gaps came out [36, 5, 15] and [111, 19, 15].
    #
    # Evenly spaced head centres at w/4 intervals then made the figures overlap,
    # because a crop is wider than a quarter canvas once shadows are included.
    #
    # The source's own four slots are known to fit four of these figures with
    # this much shadow, because they already do. Reusing them means `next` and
    # `last` inherit whatever rhythm `first` has — identical by construction,
    # rather than normalised toward an ideal that may not fit.
    head_centres = [(a + b) // 2 for a, b in spans]
    lefts = [b[0] for b in boxes_x]
    offsets = [head_centres[i] - lefts[i] for i in range(4)]

    # Pasted through a MASK, not as rectangles.
    #
    # A crop is a rectangle around a figure, and the figures are not the same
    # width — the marked child is wider than a grey silhouette. Moving it into a
    # slot that held a narrower figure makes its rectangle overlap its new
    # neighbours, and a plain paste writes that rectangle's background over
    # them: the verifier saw four figures collapse into one. Masking to the
    # non-background pixels means only the figure and its shadow are drawn, so
    # rectangles may overlap freely while the figures themselves do not.
    canvas = np.repeat(ref[:, None, :], w, axis=1).astype("uint8")
    out = Image.fromarray(canvas, "RGB")
    for slot, i in enumerate(order):
        x0, x1 = boxes_x[i]
        x = head_centres[slot] - offsets[i]
        x = max(0, min(w - widths[i], x))         # never hang off the canvas
        mask = Image.fromarray((~is_bg[:, x0:x1]).astype("uint8") * 255, "L")
        out.paste(bands[i], (x, 0), mask)

    # Flatten the background to the reference column.
    #
    # The bands come from different x positions, and the render's backdrop is
    # very slightly brighter in the middle than at the edges. Butted together
    # that lands as a hard vertical seam at every join — mechanically correct
    # and obviously wrong to look at. Repainting every background pixel with
    # its row's reference colour removes the horizontal variation entirely, so
    # the joins disappear while the vertical backdrop-to-floor gradient stays.
    # Flattened at a wider tolerance than detection uses. A soft contact shadow
    # sits just outside BG_TOLERANCE, so the narrow mask left half of one behind
    # as a pale rectangle where a band had been cut through it. Treating the
    # near-background as background removes those remnants; the figures are far
    # enough from the backdrop colour to be untouched either way.
    arr = np.asarray(out, dtype=np.int16)
    bg_mask = np.abs(arr - ref[:, None, :]).max(axis=2) <= FLATTEN_TOLERANCE
    arr[bg_mask] = np.broadcast_to(ref[:, None, :], arr.shape)[bg_mask]
    return Image.fromarray(arr.astype("uint8"), "RGB")


def compose(src, order, size):
    """Lay the cropped figures out in `order`, evenly spaced, bottom-aligned."""
    boxes = figure_boxes(src)
    if len(boxes) != 4:
        sys.exit(f"expected 4 figures in the source, found {len(boxes)} — "
                 "the figures must be separated by clear background-only columns")

    crops = [src.crop(boxes[i]) for i in order]
    widths = [c.width for c in crops]

    # Keep the source's own proportions: same margin and gap ratio it already had.
    gap = (boxes[-1][2] - boxes[0][0] - sum(b[2] - b[0] for b in boxes)) // 3
    total = sum(widths) + gap * 3

    # The canvas is the source's own empty column, repeated across the width, so
    # a backdrop-and-floor gradient is reproduced rather than flattened to one
    # colour. For Classic and High Contrast that column is a constant and this
    # is just a white or black fill.
    ref = empty_column(np.asarray(src, dtype=np.int16))
    out = Image.fromarray(
        np.repeat(ref[:, None, :], size, axis=1).astype("uint8"), "RGB")
    x = (size - total) // 2
    baseline = max(b[3] for b in boxes)
    for crop in crops:
        out.paste(crop, (x, baseline - crop.height))
        x += crop.width + gap
    return out


# Where the child ends up, given that it leads the row in `first`.
# The grey figures keep their relative order in every case; only the child moves.
DERIVED = {
    # `first` IS NOT AN OUTPUT. It was, briefly, so that all three tiles came
    # out of the same layout code — and that made the tool destroy its own
    # input: the second run composed from the already-composed tile, whose
    # figures had been moved and no longer separated, and the source was gone.
    #
    # It is also unnecessary. The derivatives reuse the source's own slot
    # positions, so whatever rhythm `first` has, the other two have exactly.
    # Consistency comes from copying the source rather than from normalising
    # all three toward an ideal.
    "next": ([1, 0, 2, 3], "child moved to position 2"),
    "last": ([1, 2, 3, 0], "child moved to the end"),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--set", required=True, help="set folder under tools/tile_sets")
    ap.add_argument("--from", dest="source", default="first")
    ap.add_argument("--to", dest="dest", choices=sorted(DERIVED),
                    help="build just this one (default: both)")
    ap.add_argument("--bands", action="store_true",
                    help="reorder full-height bands instead of cropping figures "
                         "(needed for rendered styles such as playful_3d)")
    args = ap.parse_args()

    base = Path("tools/tile_sets") / getattr(args, "set")
    src_path = base / f"{args.source}.png"
    if not src_path.exists():
        sys.exit(f"no source at {src_path}")

    src = Image.open(src_path).convert("RGB")
    # Held in memory: `first` is both the source and one of the outputs, so
    # rewriting it first must not change what the other two are built from.
    for dest in ([args.dest] if args.dest else ["next", "last"]):
        order, what = DERIVED[dest]
        out = (band_compose(src, order) if args.bands
               else compose(src, order=order, size=src.width))
        out.save(base / f"{dest}.png")
        print(f"✓ {dest}.png  ←  {args.source}.png ({what}, {out.size[0]}×{out.size[1]})")


if __name__ == "__main__":
    main()
