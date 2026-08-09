#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Measure a tile image set against its style contract.

Style prompts make promises that are mechanically checkable — "the black bleeds
to all four edges", "ONE giant subject", "no scattered small symbols". This
scores every tile against those promises so prompt iteration is measurable
instead of impressionistic, and so two generation rounds can be compared
numerically rather than by memory.

It does NOT judge whether the picture depicts the right word — that needs eyes
(or a vision model). See docs/tile-audit-p3d.md for the semantic rubric. This
tool catches the failures that repeat mechanically: frames, contamination,
clutter, washed-out contrast, off-center or undersized subjects.

Usage:
    python3 tools/analyze_set.py --set high_contrast
    python3 tools/analyze_set.py --set high_contrast --keys apple,want,i,next_page
    python3 tools/analyze_set.py --set classic --source app --worst 20
    python3 tools/analyze_set.py --set high_contrast --out tools/tile_sets/hc_r1.json
    python3 tools/analyze_set.py --set high_contrast --compare tools/tile_sets/hc_r0.json

Output:
    A per-tile table on stdout, a summary by flag, and optionally a JSON
    report (--out) that a later run can diff against (--compare).
"""

import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path

try:
    import numpy as np
except ImportError:
    sys.exit("pip install numpy")

try:
    from PIL import Image
except ImportError:
    sys.exit("pip install Pillow")

try:
    from scipy import ndimage
except ImportError:
    sys.exit("pip install scipy")

OUTPUT_BASE = Path("tools/tile_sets")
APP_DIR = Path("claudeBlast/TileImageSets")
VOCAB_FILE = Path("claudeBlast/Resources/vocabulary.json")

# Mirrors tools/sync_to_app.py SET_PREFIX — needed only for --source app.
SET_PREFIX: dict[str, str] = {
    "playful_3d": "p3d",
    "high_contrast": "hc",
    "high_contrast_v2": "hc2",
    "classic": "cls",
}


# ---------------------------------------------------------------------------
# Profiles
# ---------------------------------------------------------------------------
#
# Every set is measured against ITS OWN style contract, not one hardcoded
# ideal. That distinction matters: playful_3d promises "a clean solid-color
# background" (in practice a warm cream that varies per image), while
# high_contrast promises a specific pure #000000. Judging the first by the
# second's rule flags all 543 tiles and tells you nothing.
#
# So a profile declares what the style actually promised, and the analyzer
# checks that. Adding a set means adding a profile — which is the same work as
# writing its style prompt, and is the point at which you decide what
# "correct" means for it.

@dataclass
class Profile:
    """What a set's style prompt promises, in checkable form."""

    name: str

    # The declared background. None means "solid but unspecified" — the
    # analyzer measures the actual background and only checks it is uniform.
    bg: tuple[int, int, int] | None = None

    # How far the measured background may sit from `bg` (RGB distance, 0-441).
    bg_tolerance: float = 26.0

    # Fraction of border pixels that must match the measured background. Below
    # this there is something at the edges: a frame, a drop shadow, or
    # contamination.
    bg_uniformity_min: float = 0.90

    # How far a border pixel may sit from the modal background and still count
    # as background. A flat-white style wants this tight; a style whose
    # backgrounds are softly graded needs room, or its own gradient reads as
    # contamination. Measured, not guessed — see the calibration note in
    # docs/guides/commissioning-an-image-set.md.
    bg_match_tolerance: float = 24.0

    # A pixel is "ink" when it differs from the background by this much.
    # Distance rather than luminance, so a deep red accent on black still
    # counts as ink.
    ink_distance: float = 48.0

    # A frame, rounded-rect inset, or canvas outline all produce one
    # signature: an ink spike in the outer bands with a quiet gap behind it.
    frame_peak: float = 0.33
    frame_delta: float = 0.24

    # Subject size as a fraction of the canvas.
    ink_frac_min: float = 0.05
    ink_frac_max: float = 0.80
    bbox_frac_min: float = 0.35

    # WCAG ink-vs-background contrast. Only meaningful for a monochrome
    # contract like high_contrast — for saturated flat art on white the ratio
    # is dominated by hue and says nothing about legibility.
    check_contrast: bool = False
    contrast_min: float = 7.0

    # Connected components of ink, as a fraction of the canvas.
    component_min_frac: float = 0.005   # a real part of the subject
    fleck_min_frac: float = 0.0002      # below this is antialiasing
    components_max: int = 6
    flecks_max: int = 6

    # Centroid drift from center, in units of half-diagonal.
    centroid_max: float = 0.18


PROFILES: dict[str, Profile] = {
    # "pure solid #000000 black canvas that bleeds seamlessly to all four
    # edges and corners", "ONE giant subject … roughly 80% of the area",
    # "bold white with thick clean lines", accents encouraged but white
    # dominant. The strictest contract we ship, and the only monochrome one.
    "high_contrast": Profile(
        name="high_contrast",
        bg=(0, 0, 0), bg_tolerance=18.0, bg_uniformity_min=0.94,
        ink_distance=48.0,
        ink_frac_min=0.06, ink_frac_max=0.60, bbox_frac_min=0.42,
        check_contrast=True, contrast_min=10.0,
        # Separation observed between good v2 figures and baseline garbage is
        # wide: a legitimate white-on-black figure drawn with black internal
        # linework runs 2-9 components and 0-7 flecks (its "flecks" are eyes,
        # nose and mouth), while a contaminated tile runs 13-24 components and
        # 41-124 flecks. Set the bar in the empty space between them.
        components_max=10, flecks_max=12,
    ),
    # "pure flat white that bleeds seamlessly … NO frame", bold black
    # outlines, bright saturated solid colors. Colorful, so no contrast gate.
    "classic": Profile(
        name="classic",
        bg=(255, 255, 255), bg_tolerance=20.0, bg_uniformity_min=0.92,
        ink_distance=42.0,
        ink_frac_min=0.05, ink_frac_max=0.80, bbox_frac_min=0.35,
        components_max=8, flecks_max=8,
    ),
    # "Clean solid-color background" — unspecified, and in practice a warm
    # cream that drifts per image. Measured, not assumed. Subjects legitimately
    # fill the frame, and soft shadows mean a looser uniformity bar.
    "playful_3d": Profile(
        name="playful_3d",
        bg=None, bg_tolerance=40.0,
        # The prompt says "clean solid-color background", but what this set
        # actually ships — and what was reviewed and accepted — is a lit
        # gradient backdrop with a floor plane and a cast shadow. Its
        # least-uniform tiles ("understand", "hello") are good tiles. So the
        # edge-uniformity check is off here rather than flagging 259 of 543
        # against a contract the set never honoured. Subjects also sit low in
        # frame under their own shadows, hence the looser centroid bar.
        bg_uniformity_min=0.0, bg_match_tolerance=64.0, centroid_max=0.28,
        ink_distance=45.0,
        ink_frac_min=0.05, ink_frac_max=0.92, bbox_frac_min=0.30,
        components_max=8, flecks_max=8,
    ),
}
PROFILES["high_contrast_v2"] = Profile(**{**PROFILES["high_contrast"].__dict__,
                                          "name": "high_contrast_v2"})
PROFILES["arasaac"] = Profile(**{**PROFILES["classic"].__dict__, "name": "arasaac"})


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------

def relative_luminance(rgb: np.ndarray) -> np.ndarray:
    """WCAG 2.x relative luminance for an (H, W, 3) uint8 array."""
    srgb = rgb.astype(np.float64) / 255.0
    lin = np.where(srgb <= 0.04045, srgb / 12.92, ((srgb + 0.055) / 1.055) ** 2.4)
    return 0.2126 * lin[..., 0] + 0.7152 * lin[..., 1] + 0.0722 * lin[..., 2]


def contrast_ratio(l1: float, l2: float) -> float:
    hi, lo = max(l1, l2), min(l1, l2)
    return (hi + 0.05) / (lo + 0.05)


def border_pixels(rgb: np.ndarray, frac: float = 0.04) -> np.ndarray:
    """The outer ring of the canvas, as an (N, 3) array.

    Every style prompt promises a background that "bleeds seamlessly from
    center to all four edges and corners". This ring is where that promise
    breaks first — and it is also the most reliable sample of what the
    background actually is.
    """
    h, w = rgb.shape[:2]
    b = max(1, int(min(h, w) * frac))
    return np.concatenate([
        rgb[:b, :].reshape(-1, 3), rgb[-b:, :].reshape(-1, 3),
        rgb[b:-b, :b].reshape(-1, 3), rgb[b:-b, -b:].reshape(-1, 3),
    ])


def measure_background(rgb: np.ndarray, match_tolerance: float = 24.0) -> tuple[np.ndarray, float]:
    """Return the actual background colour and how uniform the border is.

    The modal border colour, found by coarse quantization, survives a subject
    that runs off one edge — a mean would be dragged toward the subject.
    Uniformity is the share of border pixels close to that mode; a frame,
    drop shadow, gradient, or edge contamination all drive it down.
    """
    ring = border_pixels(rgb)
    buckets, counts = np.unique((ring // 16).astype(np.int16), axis=0, return_counts=True)
    modal_bucket = buckets[counts.argmax()]
    near = np.all(np.abs((ring // 16).astype(np.int16) - modal_bucket) <= 1, axis=1)
    bg = ring[near].mean(axis=0) if near.any() else ring.mean(axis=0)
    uniformity = float(np.mean(np.linalg.norm(ring.astype(np.float64) - bg, axis=1) <= match_tolerance))
    return bg, uniformity


def band_profile(ink: np.ndarray, bands: int = 40) -> list[float]:
    """Ink fraction in concentric square bands, outermost first.

    A frame, a rounded-rectangle inset, or a canvas outline all produce the
    same signature: a spike in the outer bands with a quiet gap behind it.
    A subject that merely touches an edge does not.
    """
    h, w = ink.shape
    steps = np.linspace(0, min(h, w) // 2, bands + 1).astype(int)
    profile: list[float] = []
    for i in range(bands):
        a, b = steps[i], steps[i + 1]
        if b <= a:
            profile.append(0.0)
            continue
        outer = ink[a:h - a, a:w - a]
        inner = ink[b:h - b, b:w - b]
        n = outer.size - inner.size
        profile.append(float((outer.sum() - inner.sum()) / n) if n > 0 else 0.0)
    return profile


def frame_signature(profile: list[float]) -> tuple[float, float]:
    """Return (outer peak ink fraction, drop to the quietest interior band)."""
    n = len(profile)
    outer = profile[: max(1, int(n * 0.20))]
    interior = profile[int(n * 0.20): int(n * 0.50)] or [0.0]
    peak = max(outer)
    return peak, peak - min(interior)


@dataclass
class TileMetrics:
    key: str
    ok: bool = True
    error: str = ""
    bg: tuple[int, int, int] = (0, 0, 0)
    bg_delta: float = 0.0          # distance from the declared background
    bg_uniformity: float = 1.0     # share of border matching the measured bg
    frame_peak: float = 0.0
    frame_delta: float = 0.0
    ink_frac: float = 0.0
    bbox_frac: float = 0.0
    contrast: float = 0.0
    components: int = 0
    flecks: int = 0
    largest_frac: float = 0.0
    centroid_offset: float = 0.0
    chroma_frac: float = 0.0
    flags: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        d = {
            "bg": list(self.bg),
            "bg_delta": round(self.bg_delta, 2),
            "bg_uniformity": round(self.bg_uniformity, 3),
            "frame_peak": round(self.frame_peak, 3),
            "frame_delta": round(self.frame_delta, 3),
            "ink_frac": round(self.ink_frac, 4),
            "bbox_frac": round(self.bbox_frac, 3),
            "contrast": round(self.contrast, 2),
            "components": self.components,
            "flecks": self.flecks,
            "largest_frac": round(self.largest_frac, 4),
            "centroid_offset": round(self.centroid_offset, 3),
            "chroma_frac": round(self.chroma_frac, 3),
        }
        return {"metrics": d, "flags": self.flags, "ok": self.ok, "error": self.error}


def analyze(path: Path, key: str, p: Profile) -> TileMetrics:
    m = TileMetrics(key=key)
    try:
        img = Image.open(path).convert("RGB")
    except Exception as e:  # unreadable / truncated / LFS pointer
        m.ok, m.error = False, str(e)[:80]
        return m

    rgb = np.asarray(img, dtype=np.uint8)

    bg, m.bg_uniformity = measure_background(rgb, p.bg_match_tolerance)
    m.bg = tuple(int(round(c)) for c in bg)
    if p.bg is not None:
        m.bg_delta = float(np.linalg.norm(bg - np.array(p.bg, dtype=np.float64)))

    # Ink is measured against the background the image actually has, so a
    # subject stays a subject even when the background drifted.
    ink = np.linalg.norm(rgb.astype(np.float64) - bg, axis=2) > p.ink_distance

    m.ink_frac = float(ink.mean())
    m.frame_peak, m.frame_delta = frame_signature(band_profile(ink))

    lum = relative_luminance(rgb)
    if ink.any() and (~ink).any():
        m.contrast = contrast_ratio(float(lum[ink].mean()), float(lum[~ink].mean()))

    # Chroma: how much of the ink is a coloured accent vs plain white/grey.
    if ink.any():
        px = rgb[ink].astype(np.float64)
        mx, mn = px.max(axis=1), px.min(axis=1)
        m.chroma_frac = float((np.divide(mx - mn, np.maximum(mx, 1e-6)) > 0.35).mean())

    # Components on a downsampled mask: 256² labels fast, and area-averaging
    # plus a closing pass keeps thin line art from shattering into "clutter".
    # Thresholds are fractions, so the scale change is transparent.
    small = np.asarray(
        Image.fromarray((ink * 255).astype(np.uint8)).resize((256, 256), Image.BOX)
    ) > 96
    small = ndimage.binary_closing(small, structure=np.ones((3, 3), dtype=bool))
    labels, count = ndimage.label(small, structure=np.ones((3, 3), dtype=int))
    total = small.size
    if count:
        sizes = np.bincount(labels.ravel())[1:] / total
        m.components = int((sizes >= p.component_min_frac).sum())
        m.flecks = int(((sizes >= p.fleck_min_frac) & (sizes < p.component_min_frac)).sum())
        m.largest_frac = float(sizes.max())

        # Bounding box and centroid over the real parts only — a stray sparkle
        # in a corner must not inflate the subject's apparent size.
        keep = np.isin(labels, np.nonzero(sizes >= p.component_min_frac)[0] + 1)
        if keep.any():
            ys, xs = np.nonzero(keep)
            m.bbox_frac = ((ys.max() - ys.min() + 1) * (xs.max() - xs.min() + 1)) / total
            m.centroid_offset = float(
                np.hypot((ys.mean() - 128) / 128, (xs.mean() - 128) / 128) / np.sqrt(2)
            )

    m.flags = derive_flags(m, p)
    return m


def derive_flags(m: TileMetrics, p: Profile) -> list[str]:
    flags: list[str] = []
    if p.bg is not None and m.bg_delta > p.bg_tolerance:
        flags.append("bgcolor")
    if m.bg_uniformity < p.bg_uniformity_min:
        flags.append("edges")
    if m.frame_peak > p.frame_peak and m.frame_delta > p.frame_delta:
        flags.append("frame")
    if m.ink_frac < p.ink_frac_min:
        flags.append("thin")
    elif m.ink_frac > p.ink_frac_max:
        flags.append("dense")
    if m.bbox_frac < p.bbox_frac_min:
        flags.append("small")
    if p.check_contrast and m.contrast < p.contrast_min:
        flags.append("contrast")
    if m.flecks > p.flecks_max:
        flags.append("clutter")
    if m.components > p.components_max:
        flags.append("multi")
    if m.centroid_offset > p.centroid_max:
        flags.append("offcenter")
    return flags


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

HEADER = (
    f"{'key':24s} {'bgΔ':>5s} {'unif':>5s} {'frame':>6s} {'ink%':>6s} "
    f"{'bbox%':>6s} {'contr':>6s} {'cmp':>4s} {'flk':>4s} {'off':>5s}  flags"
)


def row(m: TileMetrics) -> str:
    if not m.ok:
        return f"{m.key:24s} — unreadable: {m.error}"
    return (
        f"{m.key:24s} {m.bg_delta:5.1f} {m.bg_uniformity:5.2f} "
        f"{m.frame_peak:6.2f} {m.ink_frac * 100:6.1f} {m.bbox_frac * 100:6.1f} "
        f"{m.contrast:6.1f} {m.components:4d} {m.flecks:4d} "
        f"{m.centroid_offset:5.2f}  {','.join(m.flags)}"
    )


def resolve_paths(set_name: str, source: str, keys: list[str] | None) -> list[tuple[str, Path]]:
    if source == "app":
        prefix = SET_PREFIX.get(set_name)
        if not prefix:
            sys.exit(f"No app prefix known for set '{set_name}' — add one to SET_PREFIX.")
        base, pattern = APP_DIR, f"{prefix}_{{key}}.png"
    else:
        base, pattern = OUTPUT_BASE / set_name, "{key}.png"

    if not base.exists():
        sys.exit(f"No such directory: {base}")

    if keys is None:
        if source == "app":
            found = sorted(p.stem[len(SET_PREFIX[set_name]) + 1:] for p in base.glob(f"{SET_PREFIX[set_name]}_*.png"))
        else:
            found = sorted(p.stem for p in base.glob("*.png"))
        keys = found

    return [(k, base / pattern.format(key=k)) for k in keys]


def main() -> None:
    ap = argparse.ArgumentParser(description="Measure a tile set against its style contract")
    ap.add_argument("--set", required=True, help="Set name (folder under tools/tile_sets, or an app prefix set)")
    ap.add_argument("--source", choices=["master", "app"], default="master",
                    help="master = tools/tile_sets/<set>/, app = claudeBlast/TileImageSets/<prefix>_*")
    ap.add_argument("--profile", default=None, choices=sorted(PROFILES),
                    help="Style contract to measure against (default: same name as --set)")
    ap.add_argument("--keys", default=None, help="Comma-separated subset of keys")
    ap.add_argument("--vocab-only", action="store_true", help="Restrict to keys in vocabulary.json")
    ap.add_argument("--worst", type=int, default=0, help="Print only the N most-flagged tiles")
    ap.add_argument("--flagged", action="store_true", help="Print only flagged tiles")
    ap.add_argument("--out", type=Path, default=None, help="Write a JSON report here")
    ap.add_argument("--compare", type=Path, default=None, help="Diff against an earlier JSON report")
    args = ap.parse_args()

    profile_name = args.profile or args.set
    if profile_name not in PROFILES:
        sys.exit(f"No profile for '{profile_name}'. Known: {', '.join(sorted(PROFILES))}.\n"
                 f"Add one to PROFILES, or pass --profile to borrow an existing contract.")
    p = PROFILES[profile_name]

    keys = [k.strip() for k in args.keys.split(",") if k.strip()] if args.keys else None
    if args.vocab_only and keys is None:
        keys = [tile["key"] for tile in json.loads(VOCAB_FILE.read_text())]

    targets = resolve_paths(args.set, args.source, keys)
    missing = [k for k, p in targets if not p.exists()]
    targets = [(k, p) for k, p in targets if p.exists()]

    bg_desc = f"bg {p.bg}" if p.bg else "bg measured per tile"
    print(f"\nSet: {args.set} ({args.source}) vs profile '{p.name}' ({bg_desc}) — {len(targets)} tiles")
    if missing:
        print(f"Missing art: {len(missing)} — {', '.join(missing[:12])}"
              + (" …" if len(missing) > 12 else ""))
    print()

    results = [analyze(path, key, p) for key, path in targets]

    shown = [m for m in results if m.flags or not m.ok] if (args.flagged or args.worst) else results
    if args.worst:
        shown = sorted(shown, key=lambda m: (-len(m.flags), m.contrast))[: args.worst]

    if shown:
        print(HEADER)
        print("-" * len(HEADER))
        for m in sorted(shown, key=lambda m: (-len(m.flags), m.key)):
            print(row(m))

    # Summary
    flagged = [m for m in results if m.flags]
    unreadable = [m for m in results if not m.ok]
    by_flag: dict[str, int] = {}
    for m in flagged:
        for f in m.flags:
            by_flag[f] = by_flag.get(f, 0) + 1

    print(f"\n{'='*60}")
    print(f"clean {len(results) - len(flagged) - len(unreadable)}  "
          f"flagged {len(flagged)}  unreadable {len(unreadable)}  of {len(results)}")
    if by_flag:
        print("  " + "  ".join(f"{k}={v}" for k, v in sorted(by_flag.items(), key=lambda kv: -kv[1])))
    print(f"{'='*60}")

    report = {
        "set": args.set,
        "source": args.source,
        "profile": p.__dict__,
        "summary": {
            "total": len(results),
            "clean": len(results) - len(flagged) - len(unreadable),
            "flagged": len(flagged),
            "unreadable": len(unreadable),
            "missing": len(missing),
            "by_flag": by_flag,
        },
        "tiles": {m.key: m.as_dict() for m in results},
    }

    if args.compare:
        diff_against(report, json.loads(args.compare.read_text()), args.compare)

    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(report, indent=2) + "\n")
        print(f"\nReport → {args.out}")


def diff_against(now: dict, before: dict, path: Path) -> None:
    """Show what a round of prompt iteration actually changed."""
    print(f"\nCompared to {path}:")
    b_sum, n_sum = before["summary"], now["summary"]
    print(f"  clean   {b_sum['clean']:4d} → {n_sum['clean']:4d}  ({n_sum['clean'] - b_sum['clean']:+d})")
    print(f"  flagged {b_sum['flagged']:4d} → {n_sum['flagged']:4d}  ({n_sum['flagged'] - b_sum['flagged']:+d})")

    all_flags = set(b_sum["by_flag"]) | set(n_sum["by_flag"])
    for f in sorted(all_flags):
        b, n = b_sum["by_flag"].get(f, 0), n_sum["by_flag"].get(f, 0)
        if b != n:
            print(f"    {f:10s} {b:3d} → {n:3d}  ({n - b:+d})")

    fixed, broke = [], []
    for key, entry in now["tiles"].items():
        prior = before["tiles"].get(key)
        if not prior:
            continue
        was, is_ = set(prior["flags"]), set(entry["flags"])
        if was and not is_:
            fixed.append(key)
        elif is_ - was:
            broke.append(f"{key}({','.join(sorted(is_ - was))})")

    if fixed:
        print(f"  fixed ({len(fixed)}): {', '.join(sorted(fixed)[:15])}"
              + (" …" if len(fixed) > 15 else ""))
    if broke:
        print(f"  REGRESSED ({len(broke)}): {', '.join(sorted(broke)[:15])}"
              + (" …" if len(broke) > 15 else ""))


if __name__ == "__main__":
    main()
