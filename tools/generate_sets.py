#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Generate two complete tile image sets for Blaster:
  1. playful_3d  — soft clay/plasticine 3D style, pastel-bright
  2. high_contrast — white on black, Sclera-inspired accessibility style

Usage:
    export OPENAI_API_KEY=sk-...
    python3 tools/generate_sets.py --set playful_3d [--skip-existing] [--key KEY] [--dry-run] [--batch N]
    python3 tools/generate_sets.py --set high_contrast [--skip-existing] [--key KEY] [--dry-run] [--batch N]
    python3 tools/generate_sets.py --set both [--skip-existing] [--dry-run] [--batch N]

Output:
    tools/tile_sets/playful_3d/{key}.png
    tools/tile_sets/high_contrast/{key}.png

Cost estimate: ~$0.04/image × 473 = ~$19 per set, ~$38 for both.
Time estimate: ~2 hours per set at 15s rate limit sleep.
"""

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

try:
    import requests
except ImportError:
    sys.exit("pip install requests")

OPENAI_IMAGE_URL = "https://api.openai.com/v1/images/generations"
PROMPTS_FILE = Path("tools/prompts.json")
VOCAB_FILE = Path("claudeBlast/Resources/vocabulary.json")
OUTPUT_BASE = Path("tools/tile_sets")
MIN_IMAGE_BYTES = 50_000
SLEEP_SECONDS = 15

# ---------------------------------------------------------------------------
# Style definitions
# ---------------------------------------------------------------------------
#
# Single source of truth, shared with the app: the iOS TileImageGenerator reads
# the SAME image_styles.json from its bundle, so offline-generated sets and
# in-app "Generate with AI" stay in sync. Edit image_styles.json, not here.
# (It also carries an "arasaac" style the app uses; this tool only generates the
# two non-default sets.)

STYLES_FILE = Path("claudeBlast/Resources/image_styles.json")
STYLES: dict[str, str] = json.loads(STYLES_FILE.read_text())

# A generated SET (output folder under tools/tile_sets/) maps to a STYLE key in
# image_styles.json. Usually 1:1, but our clean-room flat-pictogram set ships in
# a "classic" folder while reusing the shared "arasaac" style descriptor — the
# style is the visual recipe, the set name is the license-clean Blaster-owned set
# (the bundled ARASAAC originals stay separate and are CC BY-NC-SA).
SET_STYLES: dict[str, str] = {
    "playful_3d": "playful_3d",
    "high_contrast": "high_contrast",
    "high_contrast_v2": "high_contrast_v2",
    "classic": "classic",
}

# Per-tile subject overrides for tiles where the shared cross-style subject
# (extracted from prompts.json) doesn't translate well to high_contrast — e.g.
# abstract concepts where DALL-E improvises with secondary icons, or cases
# where the shared subject says "clay" / "pastel". Looked up by lowercase key.
HC_SUBJECT_OVERRIDES: dict[str, str] = {
    # Session 8: the shared subject came back with black faces (lost on the
    # black ground) or, for pee, a visible stream. Spelled out for HC only.
    "pee": (
        "A child standing at a child-height toilet seen from behind and slightly to the side, fully clothed, modest, nothing explicit, no liquid or stream anywhere, a small droplet icon floating above. Every figure is a WHITE shape with black line details; faces are white"
    ),
    "itchy": (
        "A child scratching their arm with the other hand, a few small red dots on the arm, wavy lines showing the itch. The child is a WHITE figure with black line details; the face is white, never black"
    ),
    "share": (
        "Two children, one handing a toy block to the other, both hands on the block, both smiling. Both children are WHITE figures with black line details; both faces are white, never black"
    ),
    "upset": (
        "A child with arms crossed, a frowning face and furrowed brows, a small scribble cloud above the head. The child is a WHITE figure with black line details; the face is white, never black"
    ),
    # Directional arrows. The shared subjects specify "bright blue color" —
    # chosen for playful_3d — and a named colour in the subject beats the
    # style's "white dominates" rule every time. strip_clay_words() removes the
    # clay wording but deliberately not colours, since most subjects need
    # theirs ("a red apple"). These are the ones that don't.
    "up": (
        "A single bold arrow pointing straight upward, drawn entirely in solid "
        "white, with a thick shaft and a large triangular arrowhead"
    ),
    "down": (
        "A single bold arrow pointing straight downward, drawn entirely in solid "
        "white, with a thick shaft and a large triangular arrowhead"
    ),
    # Words naming a visual condition are a trap: asked for fog, the model
    # renders the whole picture foggy — atmospheric, and measuring 3.0 contrast
    # in a set whose premise is 21. It illustrates the condition instead of
    # depicting the concept. Forced to a symbol here. (fog is the only weather
    # word that fell into this; the rest score 18-21.)
    "fog": (
        "A simple house with a triangular roof and a tree beside it, both as "
        "bold solid white silhouettes, with three thick straight horizontal "
        "white bars lying across them. Everything is crisp and solid — nothing "
        "is blurred, faded, soft, hazy or semi-transparent"
    ),
    # The shared subject is "a child catching a colorful ball with both hands,
    # ball just arriving in their grip" — which is playing catch, not getting.
    # Playful-3D happens to ignore its own subject here and draws a child
    # reaching up to a shelf, which is the sense we want; this makes that
    # explicit rather than lucky.
    "get": (
        "A child standing on tiptoe with one arm stretched high overhead, "
        "lifting a ball down from the top shelf of a tall bookcase. The child "
        "is reaching upward, not catching"
    ),
    # The shared subject asks for a chalkboard, which comes back as a large
    # rectangle outline that reads as a frame — the one thing this style must
    # not have — plus stray marks standing in for writing.
    "school_people": (
        "A smiling adult teacher standing beside three smiling children, the "
        "teacher clearly taller. All four face forward and all four have "
        "simple friendly faces with eyes and a smile. No blackboard, no "
        "whiteboard, no wall, no desks, nothing behind them"
    ),
    # next_page / previous_page / question — rendered deterministically by
    # render_hc_basics.py; DALL-E reliably hallucinates frames around the canvas
    # or surrounds the subject with a grid of unrelated icons.
    # For v2, next_page generates cleanly and previous_page is derived from it
    # with tools/mirror_tile.py so the pair are true mirrors.
    "food": (
        "A clean white plate seen from a slight angle, holding exactly three "
        "iconic food items: a bright red apple, a golden bread roll, and a "
        "chicken drumstick. Just these three items on the plate, nothing else "
        "anywhere in the image"
    ),
    "body_health": (
        "A single bold white silhouette of a standing person, front view, with "
        "a bright red heart shape on the center of the chest. Just the "
        "silhouette and the red heart, nothing else"
    ),
    "snack": (
        "A simple bold white bowl viewed from the front in profile, with three "
        "or four white twisted pretzel shapes resting inside the bowl. Just "
        "the bowl and the pretzels, nothing else inside the bowl, nothing "
        "around the bowl"
    ),
    "home": (
        "A single iconic house shape: a bold white square base with a triangular "
        "roof on top in bright red, one centered door, and one square window. "
        "Just the one house, nothing else"
    ),
    "popsicle": (
        "ONE single popsicle on a wooden stick, centered. The popsicle body has "
        "three horizontal stripes — bright red on top, bright orange in the "
        "middle, bright yellow on the bottom — with a small white wooden stick "
        "below. Just the one popsicle, nothing else"
    ),

    # ---- Time vocabulary (2026-09) -------------------------------------
    #
    # Nearly the whole Time set needs an override, and for one reason: these
    # subjects are *diagrams*, and a diagram states its own colours. Almost
    # every other tile in this app is an object — "a red apple" — where the
    # style's "white dominates on black" rule can take over harmlessly. A
    # diagram cannot survive that: "seven white squares with bold black
    # outlines" puts black lines on a black canvas and returns a blank field,
    # and "plain grey silhouettes on a pure white background" inverts the set's
    # premise outright.
    #
    # So each of these restates the same drawing in this set's own materials:
    # white strokes and fills on black, with the accent colours the style
    # already encourages kept for the parts that carry the meaning — the red
    # square that means *today*, the coloured neighbour that means the day
    # being named. The grammar of each family is preserved exactly; only the
    # palette changes.
    #
    # `next` and `last` are absent on purpose: they are composed from `first`
    # by tools/compose_queue.py, in this set as in Classic.

    # calendar strip
    "today": (
        "A horizontal row of seven equal squares in one single row, joined edge "
        "to edge, each square drawn as a bold WHITE outline on the black canvas. "
        "The fourth square, in the exact middle, is filled solid bright red. The "
        "other six squares are empty black inside their white outlines. No "
        "numbers, no letters"
    ),
    # A BAR, not a row of squares — and no negations.
    #
    # Two failures, in opposite directions, taught this. Described as "a
    # horizontal row of seven squares" these came back as two stacked rows of
    # four. Adding "never stacked and never two rows" made it worse: both tiles
    # returned two rows again. A negation names the thing it forbids, and naming
    # it is enough to summon it — the same way "no grey field" produced grey
    # fields in Classic.
    #
    # So neither tile mentions rows at all. A *bar* is one-dimensional by
    # definition and cannot be stacked without ceasing to be a bar, which makes
    # the constraint structural instead of stated. Same move that fixed the
    # Classic family, where "calendar" had to become "a strip of squares"
    # because the model's prior for a calendar is a month grid.
    "tomorrow": (
        "One long horizontal white bar lying flat across the middle of the "
        "canvas, much wider than it is tall, divided along its length into seven "
        "equal segments by thick white dividing lines. Two segments next to each "
        "other in the middle are filled: the left one of the two solid bright "
        "red, the right one of the two solid bright green. A bright green arrow "
        "above the bar points right. No numbers"
    ),
    "yesterday": (
        "One long horizontal white bar lying flat across the middle of the "
        "canvas, much wider than it is tall, divided along its length into seven "
        "equal segments by thick white dividing lines. Two segments next to each "
        "other in the middle are filled: the right one of the two solid bright "
        "red, the left one of the two solid bright blue. A bright blue arrow "
        "above the bar points left. No numbers"
    ),
    "week": (
        "A horizontal row of seven equal squares in one single row, joined edge "
        "to edge, each drawn as a bold WHITE outline on the black canvas, with "
        "the whole row enclosed together inside one thick bright blue rounded "
        "outline. No numbers, no letters"
    ),
    "weekend": (
        "A horizontal row of seven equal squares in one single row, joined edge "
        "to edge, each drawn as a bold WHITE outline on the black canvas. The "
        "five squares on the left are empty black inside their outlines. The two "
        "squares at the right-hand end, both of them, are filled solid bright "
        "orange. No numbers, no letters"
    ),

    # clock family
    "time": (
        "One single large round analog clock face drawn as a thick WHITE circle "
        "with bold white hour and minute hands and plain white tick marks around "
        "the edge, on the black canvas. No numerals, no letters"
    ),
    "now": (
        "One single large round analog clock face drawn as a thick WHITE circle "
        "with bold white hands and plain white tick marks, on the black canvas, "
        "with a bright red downward-pointing triangular marker resting directly "
        "on top of the clock pointing at it. No numerals"
    ),
    "later": (
        "One single large round analog clock face drawn as a thick WHITE circle "
        "with bold white hands and plain white tick marks, on the black canvas, "
        "with a thick bright blue arrow curving clockwise around the outside of "
        "the clock from the top round to the right side. No numerals"
    ),
    "soon": (
        "One single large round analog clock face drawn as a thick WHITE circle "
        "with bold white hands and plain white tick marks, on the black canvas, "
        "with a short thick bright green arrow curving clockwise around the "
        "outside of the clock covering only a small arc near the top. No numerals"
    ),
    "always": (
        "One single large round analog clock face drawn as a thick WHITE circle "
        "with bold white hands and plain white tick marks, on the black canvas, "
        "with a thick bright green arrow forming a complete unbroken circle all "
        "the way around the outside of the clock, its ends meeting. No numerals"
    ),
    "never": (
        "One single large round analog clock face drawn as a thick WHITE circle "
        "with bold white hands and plain white tick marks, on the black canvas, "
        "with a thick bright red circle-and-diagonal-slash prohibition symbol "
        "drawn boldly over the top of it. No numerals"
    ),
    "sometimes": (
        "A horizontal row of four round analog clock faces, all the same size, "
        "each drawn as a thick WHITE circle with white hands and white tick "
        "marks on the black canvas. The first and the third from the left are "
        "filled solid bright green inside; the other two are empty black inside "
        "their white outlines. No numerals"
    ),

    # sequence — three panels, grey reference becomes a white-outlined cube
    "before": (
        "Three plain square panels in a horizontal row, evenly spaced and the "
        "same size, each drawn as a bold WHITE outline on the black canvas, "
        "joined by thin white arrows pointing left to right. The MIDDLE panel "
        "contains a white cube and is the reference point. The LEFT panel "
        "contains a solid bright red ball and its outline is thick bright red. "
        "The RIGHT panel is empty"
    ),
    "after": (
        "Three plain square panels in a horizontal row, evenly spaced and the "
        "same size, each drawn as a bold WHITE outline on the black canvas, "
        "joined by thin white arrows pointing left to right. The MIDDLE panel "
        "contains a white cube and is the reference point. The RIGHT panel "
        "contains a solid bright red ball and its outline is thick bright red. "
        "The LEFT panel is empty"
    ),

    # ordinal — only `first` is generated; next/last are composed from it
    # HIGH CONTRAST DOES NOT DO PROFILES, SO THIS ONE DOES NOT ASK FOR ONE.
    #
    # Classic and Playful 3D show the queue in side view, every figure facing
    # left, which is what makes the row read as a line with a front and a back.
    # This set will not: its own descriptor calls for "ONE giant subject" in
    # "simple flat shapes", and asked for four profiles it returns four plain
    # circular heads. Pushed harder — "each head carries a small nose bump on
    # its LEFT side" — it put a nose on the coloured child only and left the
    # other three bald, which is worse than no profile at all, because now the
    # marked figure differs in two ways instead of one.
    #
    # So this set states the ordinal with position alone: four identical
    # front-facing figures, one of them coloured. Nothing about the tile claims
    # a direction, so nothing about it can contradict one. The queue reading is
    # lost here and the position reading — the part that actually carries the
    # word — survives intact.
    "first": (
        "Four identical simple humanoid pictogram figures standing in a "
        "straight horizontal row, evenly spaced, with a clear gap of black "
        "background between each pair so none of them touch or overlap. Every "
        "figure is exactly the same shape, size and posture as the others: a "
        "plain round head above a simple body, seen straight on from the front. "
        "No noses, no faces, no eyes, no mouths, no hair and no profiles — the "
        "heads are plain circles. Three of the figures are solid WHITE. The "
        "leftmost figure is the only one drawn in colour, with a bright red "
        "shirt and blue trousers, and its head is a plain circle exactly like "
        "the others. No arrows, no pointers, no markers"
    ),

    # sun and moon — object plus marker, no scene
    "day": (
        "One single large sun with bold evenly-spaced triangular rays radiating "
        "all the way around it, drawn in solid bright yellow on the black "
        "canvas. There is no sky, no ground, no horizon and no landscape — only "
        "the sun"
    ),
    "morning": (
        "A sun with bold triangular rays drawn in solid bright yellow on the "
        "black canvas, with a thick bright green arrow beside it pointing "
        "straight UP. There is no sky, no ground, no horizon and no landscape — "
        "only the sun and the arrow"
    ),
    "afternoon": (
        "A sun with bold triangular rays drawn in solid bright yellow on the "
        "black canvas, with a thick bright orange arrow beside it pointing "
        "straight DOWN. There is no sky, no ground, no horizon and no landscape "
        "— only the sun and the arrow"
    ),
    "night": (
        "A large crescent moon drawn in solid white on the black canvas, with "
        "three small bright yellow four-pointed stars around it. There is no "
        "sky, no ground, no horizon and no landscape — only the moon and the "
        "stars"
    ),
    "tonight": (
        "A large crescent moon drawn in solid white on the black canvas, with "
        "three small bright yellow four-pointed stars around it, and a bright "
        "red downward-pointing triangular marker directly above the moon. There "
        "is no sky, no ground, no horizon and no landscape — only the moon, the "
        "stars and the marker"
    ),
}


def extract_subject(prompt_text: str) -> str:
    """Extract the subject description from an existing prompt.

    Existing prompts look like:
      "AAC pictogram: a child eating food. Flat illustration, white background, ..."
    We want: "a child eating food"
    """
    # Remove the "AAC pictogram: " prefix
    text = re.sub(r"^AAC pictogram:\s*", "", prompt_text, flags=re.IGNORECASE)
    # Remove everything from "Flat illustration" onward (the old style suffix)
    text = re.split(r"\.\s*Flat illustration", text, maxsplit=1)[0]
    # Remove trailing period
    text = text.rstrip(". ")
    return text


# prompts.json subjects were authored for playful_3d and bake in clay/3D wording
# ("A 3D clay figurine child...", "made of shiny clay"). For every other set that
# language fights the style prefix, so strip it. Longest phrases first.
CLAY_PHRASES = [
    "3d clay figurine", "clay figurine", "3d clay", "clay character",
    "made of shiny clay", "made of clay", "shiny clay", "plasticine",
    "clay", "3d", "figurine",
]


def strip_clay_words(subject: str) -> str:
    """Remove playful_3d style contamination so a subject reads style-neutral."""
    out = subject
    for phrase in CLAY_PHRASES:
        out = re.sub(rf"\b{re.escape(phrase)}\b", "", out, flags=re.IGNORECASE)
    out = re.sub(r"\s{2,}", " ", out)          # collapse double spaces
    out = re.sub(r"\s+([,.])", r"\1", out)      # tidy " ," / " ."
    return out.strip(" ,")


def build_prompt(subject: str, style: str) -> str:
    """Combine a subject description with a style prefix."""
    return f"{STYLES[style]} Subject: {subject}."


def generate_image(prompt: str, api_key: str, session: requests.Session) -> bytes | None:
    # gpt-image-1 replaced dall-e-3 (April 2025+). It returns b64_json directly
    # and does not accept a `response_format` parameter. Quality values are
    # low/medium/high/auto; medium ≈ legacy "standard" pricing.
    payload = {
        "model": "gpt-image-1",
        "prompt": prompt,
        "n": 1,
        "size": "1024x1024",
        "quality": "medium",
    }
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    try:
        r = session.post(OPENAI_IMAGE_URL, json=payload, headers=headers, timeout=120)
    except requests.RequestException as e:
        print(f"  [generation error: {e}]")
        return None
    if not r.ok:
        # Surface OpenAI's error body — the previous error-swallowing made
        # a dall-e-3 deprecation invisible across 19 failed prompts.
        try:
            body = r.json().get("error", {}).get("message", r.text[:200])
        except ValueError:
            body = r.text[:200]
        print(f"  [generation error: {r.status_code} {body}]")
        return None
    try:
        b64 = r.json()["data"][0]["b64_json"]
    except (KeyError, IndexError, ValueError) as e:
        print(f"  [response parse error: {e}]")
        return None
    import base64
    try:
        return base64.b64decode(b64)
    except Exception as e:
        print(f"  [base64 decode error: {e}]")
        return None


def run_set(style_name: str, keys: list[str], prompts: dict[str, str],
            api_key: str, skip_existing: bool, dry_run: bool,
            sleep_seconds: float = SLEEP_SECONDS,
            out_root: Path | None = None) -> tuple[int, int, list[str]]:
    """Generate one full set. Returns (ok_count, skipped, failed_keys)."""
    out_dir = (out_root or OUTPUT_BASE) / style_name
    out_dir.mkdir(parents=True, exist_ok=True)
    style_key = SET_STYLES.get(style_name, style_name)

    session = requests.Session()
    ok_count = 0
    skipped = 0
    failed: list[str] = []

    for i, key in enumerate(keys):
        override = (HC_SUBJECT_OVERRIDES.get(key.lower())
                    if style_key.startswith("high_contrast") else None)
        if not override and key not in prompts:
            print(f"  ✗ {key:40s} no prompt — skipping")
            failed.append(key)
            continue

        dest = out_dir / f"{key}.png"

        # Skip read-only files (programmatically generated tiles)
        if dest.exists() and not os.access(dest, os.W_OK):
            skipped += 1
            continue

        if skip_existing and dest.exists() and dest.stat().st_size >= MIN_IMAGE_BYTES:
            skipped += 1
            if skipped <= 5 or skipped % 50 == 0:
                print(f"  → {key:40s} (exists, {dest.stat().st_size // 1024} KB)")
            continue

        subject = override if override else extract_subject(prompts[key])
        # Only playful_3d wants the clay wording — it authored it. Every other
        # style is fighting it. high_contrast was silently exempt from this
        # until Aug 2026, which is why its tiles kept coming back as 3D clay
        # renders instead of flat white-on-black shapes.
        if style_key != "playful_3d":
            subject = strip_clay_words(subject)
        prompt = build_prompt(subject, style_key)

        if dry_run:
            print(f"  [DRY] {key:40s} | {subject[:80]}")
            ok_count += 1
            continue

        progress = f"[{i+1}/{len(keys)}]"
        print(f"  ⏳ {progress:10s} {key:40s}", end="", flush=True)
        png_bytes = generate_image(prompt, api_key, session)

        if png_bytes and len(png_bytes) >= MIN_IMAGE_BYTES:
            dest.write_bytes(png_bytes)
            print(f"  ✓ {len(png_bytes) // 1024} KB")
            ok_count += 1
        else:
            print("  FAILED")
            failed.append(key)

        time.sleep(sleep_seconds)

    return ok_count, skipped, failed


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Blaster tile image sets")
    parser.add_argument("--set", required=True, choices=[*SET_STYLES, "both"])
    parser.add_argument("--skip-existing", action="store_true")
    parser.add_argument("--key", metavar="KEY", action="append", default=None,
                        help="Process only this tile key (repeatable)")
    parser.add_argument("--keys-file", type=Path, default=None,
                        help="File of tile keys, one per line. Generation is serial, so "
                             "sharding a full set across a few processes over disjoint key "
                             "files is the way to cut wall-clock.")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--batch", type=int, default=0,
                        help="Process only N tiles (for testing)")
    parser.add_argument("--sleep", type=float, default=SLEEP_SECONDS,
                        help=f"Seconds between requests (default {SLEEP_SECONDS}). The default "
                             "dates from DALL-E 3 Tier 1 (5 images/min); on a higher tier it is "
                             "the single biggest speedup available on a full-set run.")
    parser.add_argument("--out-dir", type=Path, default=None,
                        help="Write to <out-dir>/<set>/<key>.png instead of the master "
                             "folder — for candidates that must not overwrite an approved "
                             "tile until they are compared against it "
                             "(tools/compare_tiles.py) and chosen.")
    parser.add_argument("--prompts-file", type=Path, default=None,
                        help="JSON of key → prompt laid over tools/prompts.json for this "
                             "run only, to try a new prompt without committing to it.")
    args = parser.parse_args()

    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        sys.exit("Error: OPENAI_API_KEY not set")

    raw_prompts: dict[str, str] = json.loads(PROMPTS_FILE.read_text())

    # Two keys that differ only in case are a silent bug, not a style nit.
    # The fold below keeps whichever entry comes LAST in the file, so which
    # prompt actually ships depends on key order and nothing says a word was
    # dropped. A legacy capitalized block sat on top of eleven live prompts
    # that way. Fail loudly rather than pick one.
    folded: dict[str, str] = {}
    for k in raw_prompts:
        if k.lower() in folded:
            sys.exit(f"{PROMPTS_FILE}: {folded[k.lower()]!r} and {k!r} collide when "
                     f"lowercased — one silently shadows the other. Keys must be "
                     f"unique and lowercase.")
        folded[k.lower()] = k

    if args.prompts_file:
        raw_prompts.update(json.loads(args.prompts_file.read_text()))

    # Build case-insensitive lookup: lowercase key → original prompt text
    prompts: dict[str, str] = {}
    for k, v in raw_prompts.items():
        prompts[k.lower()] = v
    # Also keep originals for exact match
    prompts.update(raw_prompts)

    vocab: list[dict] = json.loads(VOCAB_FILE.read_text())
    keys = [tile["key"] for tile in vocab]

    selected = list(args.key or [])
    if args.keys_file:
        selected += [ln.strip() for ln in args.keys_file.read_text().splitlines() if ln.strip()]

    if selected:
        missing = [k for k in selected if k not in keys]
        if missing:
            sys.exit(f"Keys not in vocabulary: {missing}")
        keys = selected
    elif args.batch > 0:
        keys = keys[:args.batch]

    sets_to_run = ["playful_3d", "high_contrast"] if args.set == "both" else [args.set]

    for style_name in sets_to_run:
        print(f"\n{'='*60}")
        print(f"Generating: {style_name} ({len(keys)} tiles)")
        print(f"{'='*60}\n")

        ok, skip, failed = run_set(
            style_name, keys, prompts, api_key,
            skip_existing=args.skip_existing, dry_run=args.dry_run,
            sleep_seconds=args.sleep, out_root=args.out_dir,
        )

        print(f"\n{style_name}: ✓ {ok} generated  → {skip} skipped  ✗ {len(failed)} failed")

        if failed:
            failed_path = OUTPUT_BASE / f"{style_name}_failed.txt"
            failed_path.write_text("\n".join(failed) + "\n")
            print(f"Failed keys: {failed_path}")


if __name__ == "__main__":
    main()
