#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Build the bundled "Verified Starter Scenes" for Blaster.

These MATCH what the real AI generator produces: the topical tiles wrapped in the
Core board. We replicate SceneNavigation.scaffold here
(claudeBlast/Services/SceneNavigation.swift) — a deterministic, topic-independent
core board. Ships the Focused profile by default (topical + a lean needs strip +
the body & health page); pass --full to build the full familiar board instead.

Each starter is emitted as Resources/starter_<id>.json (.blasterscene format;
SceneImporter ignores the extension). New topical words get bundled Playful-3D
art; ONE per scene is intentionally left imageless so the caregiver can walk the
"generate art for new words" flow once (no-key path nudges them to add a key).

Usage:
    export OPENAI_API_KEY=sk-...
    python3 tools/build_starter_scenes.py            # generate art + emit bundles
    python3 tools/build_starter_scenes.py --dry-run  # validate + show plan, no API
"""

import argparse
import base64
import io
import json
import sys
import time
from pathlib import Path

import generate_sets as gs  # reuse generate_image / build_prompt / STYLES

try:
    import requests
except ImportError:
    sys.exit("pip install requests")

try:
    from PIL import Image
except ImportError:
    sys.exit("pip install pillow")

VOCAB_FILE = Path("claudeBlast/Resources/vocabulary.json")
RES_DIR = Path("claudeBlast/Resources")
ART_RECORD_DIR = Path("tools/tile_sets/starter")
MEDIA_TYPE = "application/vnd.claudeblast.scene+json"
VERSION = "1.0.0"
ART_STYLE = "playful_3d"
SLEEP_SECONDS = 15

# ---------------------------------------------------------------------------
# Core board — mirrors SceneNavigation.swift (.full profile). Keep in sync.
# ---------------------------------------------------------------------------
HOME_LINK_TOKEN = "<home>"
HOME_TILE_KEY = "home"
HOME_CLUSTER = [
    "i", "you", "me", "my", "he", "she", "we", "they", "teacher", "mom", "dad", "friend",
    "help", "hungry", "thirsty", "bathroom",
    "happy", "sad", "tired", "hurt", "sick", "scared",
    "yes", "no", "more", "want", "please", "all_done", "look",
]
HOME_CLUSTER_LINKS = [("eat", "food"), ("drink", "drinks")]
# Lean needs strip for the Focused board — mirrors SceneNavigation.focusedClusterKeys.
# No eat/drink links (hungry/thirsty stand in), and only body_health is bundled.
FOCUSED_CLUSTER = [
    "i", "you", "want",
    "help", "more", "hungry", "thirsty", "bathroom",
    "happy", "sad", "tired", "hurt", "sick", "scared",
    "yes", "no", "all_done", "look",
]
CORE_CATEGORIES = [
    {"pageKey": "people", "iconKey": "people", "wordClasses": {"people"}, "crossLinks": []},
    {"pageKey": "food", "iconKey": "food",
     "wordClasses": {"food"}, "crossLinks": ["drinks"]},
    {"pageKey": "drinks", "iconKey": "drinks", "wordClasses": {"drinks"}, "crossLinks": ["food"]},
    {"pageKey": "body_health", "iconKey": "body_health",
     "wordClasses": {"body", "health"}, "crossLinks": []},
]

# ---------------------------------------------------------------------------
# Scene definitions. `topical` is the ordered home-page topical set (mix of new
# and existing vocab); `new` maps key -> (wordClass, displayName, subject|None).
# A None subject ships imageless (the demo word).
# ---------------------------------------------------------------------------
SCENES = [
    {
        "id": "farm",
        "name": "Farm Visit",
        "description": "Animals and adventures at the farm — point to them, name them, and ask to see more.",
        "prompt": "A visit to the farm: animals like the cow, pig, chicken, and horse, plus a tractor — point to them, name them, and ask to see more.",
        "blurb": "Animals, a tractor, and asking to see more.",
        "topical": ["cow", "pig", "horse", "chicken", "sheep", "rooster",
                    "tractor", "barn", "farmer", "egg", "hay"],
        "new": {
            "cow": ("animal", "Cow", "a cow standing, black and white spots, side view, friendly"),
            "pig": ("animal", "Pig", "a pink pig standing, side view, friendly"),
            "horse": ("animal", "Horse", "a brown horse standing, side view"),
            "chicken": ("animal", "Chicken", "a white hen chicken standing"),
            "sheep": ("animal", "Sheep", "a fluffy white sheep standing, side view"),
            "rooster": ("animal", "Rooster", None),
            "tractor": ("object", "Tractor", "a red farm tractor, side view"),
            "barn": ("object", "Barn", "a classic red barn with a peaked roof and white trim"),
            "farmer": ("people", "Farmer", "a friendly farmer wearing denim overalls and a straw hat, half body"),
            "egg": ("food", "Egg", "a single smooth white egg"),
            "hay": ("plant", "Hay", "a golden round bale of hay"),
        },
    },
    {
        "id": "tidepools",
        "name": "Tide Pools",
        "description": "Exploring the seashore — crabs, shells, and what we find in the water.",
        "prompt": "Exploring tide pools at the beach: crabs, starfish, shells, and seaweed — describing what I find in the water.",
        "blurb": "Crabs, shells, and seashore discoveries.",
        "topical": ["crab", "starfish", "shell", "seaweed", "fish", "snail",
                    "anemone", "ocean", "beach", "water"],
        "new": {
            "crab": ("animal", "Crab", "a red crab with two claws, top view"),
            "starfish": ("animal", "Starfish", "an orange starfish with five arms, top view"),
            "shell": ("object", "Shell", "a spiral seashell, peach and white"),
            "seaweed": ("plant", "Seaweed", "green seaweed strands underwater"),
            "fish": ("animal", "Fish", "a small orange fish, side view"),
            "snail": ("animal", "Snail", "a sea snail with a brown spiral shell"),
            "anemone": ("animal", "Anemone", None),
        },
    },
    {
        "id": "mealtime",
        "name": "Mealtime",
        "description": "Asking for food and drinks at the table, and saying when you're all done.",
        "prompt": "Mealtime at the table: asking for foods like pizza and spaghetti and drinks, saying please, more, and all done.",
        "blurb": "Asking for food and drinks at the table.",
        "topical": ["spaghetti", "plate", "fork", "cup", "napkin",
                    "pizza", "apple", "banana", "milk", "cookie"],
        "new": {
            "spaghetti": ("food", "Spaghetti", "a plate of spaghetti noodles with red tomato sauce"),
            "plate": ("object", "Plate", "an empty round white dinner plate, top view"),
            "fork": ("object", "Fork", "a single metal fork, top view"),
            "cup": ("object", "Cup", "a cup with a handle"),
            "napkin": ("object", "Napkin", None),
        },
    },
]


def write_sidecar(key: str, png_bytes: bytes) -> str:
    """Downscale to <=512px and write Resources/starterart_<key>.png (a readable
    bundled sidecar). Returns the filename. Keeps the bundle JSON image-free."""
    im = Image.open(io.BytesIO(png_bytes)).convert("RGBA")
    im.thumbnail((512, 512), Image.LANCZOS)
    out = io.BytesIO()
    im.save(out, format="PNG", optimize=True)
    path = RES_DIR / f"starterart_{key}.png"
    path.write_bytes(out.getvalue())
    return path.name


def page_tile(key, link="", audible=True):
    return {"key": key, "isAudible": audible, "link": link}


def scaffold_pages(scene, vocab, valid_keys, focused=True):
    """Replicate SceneNavigation.scaffold. Focused (default, what we ship): topical
    tiles + a lean needs strip, with only the body & health category page. Full:
    topical + the full core cluster, eat/drink links, and every category page. The
    scene editor can flip Focused off at runtime (re-scaffolds to full)."""
    home_key = scene["id"]
    home_tiles = [page_tile(k) for k in scene["topical"]]

    cluster = FOCUSED_CLUSTER if focused else HOME_CLUSTER
    for k in cluster:
        if k in valid_keys:
            home_tiles.append(page_tile(k))
    if not focused:
        for k, to in HOME_CLUSTER_LINKS:
            if k in valid_keys:
                home_tiles.append(page_tile(k, link=to))

    categories = ([c for c in CORE_CATEGORIES if c["pageKey"] == "body_health"]
                  if focused else CORE_CATEGORIES)

    category_pages = []
    for cat in categories:
        if cat["pageKey"] == home_key:
            continue
        content = [t["key"] for t in vocab if t.get("wordClass") in cat["wordClasses"]]
        if not content:
            continue
        tiles = [page_tile(HOME_TILE_KEY, link=HOME_LINK_TOKEN, audible=False)]
        for sib in cat["crossLinks"]:
            if sib != home_key:
                tiles.append(page_tile(sib, link=sib, audible=False))
        tiles += [page_tile(k) for k in content]
        category_pages.append({"key": cat["pageKey"], "tiles": tiles})
        icon = cat["iconKey"] if cat["iconKey"] in valid_keys else cat["pageKey"]
        home_tiles.append(page_tile(icon, link=cat["pageKey"], audible=False))

    return [{"key": home_key, "tiles": home_tiles}] + category_pages


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--full", action="store_true",
                        help="Build the full familiar board instead of the shipped Focused board")
    args = parser.parse_args()

    vocab = json.loads(VOCAB_FILE.read_text())
    valid_keys = {t["key"] for t in vocab}

    # Validate every referenced key resolves (topical-new excepted).
    errors = []
    for scene in SCENES:
        pages = scaffold_pages(scene, vocab, valid_keys, focused=not args.full)
        for page in pages:
            for t in page["tiles"]:
                k = t["key"]
                if k not in valid_keys and k not in scene["new"]:
                    errors.append(f"{scene['id']}: '{k}' is neither vocab nor a declared new word")
    if errors:
        sys.exit("Validation failed:\n  " + "\n  ".join(sorted(set(errors))))
    print(f"✓ Validation passed for {len(SCENES)} scenes")

    api_key = gs.os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        sys.exit("Error: OPENAI_API_KEY not set")

    ART_RECORD_DIR.mkdir(parents=True, exist_ok=True)
    session = requests.Session()
    manifest = []

    for scene in SCENES:
        print(f"\n=== {scene['id']} ({scene['name']}) ===")
        tiles_json = []
        for key, (word_class, display, subject) in scene["new"].items():
            if subject is None:
                print(f"  ○ {key:12s} imageless (demo word)")
            elif args.dry_run:
                print(f"  [DRY] {key:12s} | {subject}")
            else:
                master = ART_RECORD_DIR / f"{key}.png"
                if master.exists() and master.stat().st_size >= gs.MIN_IMAGE_BYTES:
                    png = master.read_bytes()
                    print(f"  → {key:12s} (cached master)")
                else:
                    prompt = gs.build_prompt(subject, ART_STYLE)
                    print(f"  ⏳ {key:12s}", end="", flush=True)
                    png = None
                    for attempt in range(4):
                        png = gs.generate_image(prompt, api_key, session)
                        if png and len(png) >= gs.MIN_IMAGE_BYTES:
                            break
                        wait = 10 * (attempt + 1)
                        print(f"  retry {attempt+1} in {wait}s…", end="", flush=True)
                        time.sleep(wait)
                    if not png or len(png) < gs.MIN_IMAGE_BYTES:
                        sys.exit(f"\n  FAILED to generate {key} after retries")
                    master.write_bytes(png)
                    print(f"  ✓ {len(png)//1024} KB")
                    time.sleep(SLEEP_SECONDS)
                write_sidecar(key, png)
            # Image-free, human-readable tile entry. Art is resolved at load time
            # from the bundled Resources/starterart_<key>.png sidecar.
            tiles_json.append({
                "key": key,
                "wordClass": word_class,
                "displayName": display,
            })

        pages = scaffold_pages(scene, vocab, valid_keys, focused=not args.full)
        bundle = {
            "@type": MEDIA_TYPE,
            "_comment": "Blaster starter scene (bundled). Edit the prompt to generate a fresh scene.",
            "version": VERSION,
            "name": scene["name"],
            "description": scene["description"],
            "homePageKey": scene["id"],
            "tiles": tiles_json,
            "pages": pages,
        }

        if not args.dry_run:
            out = RES_DIR / f"starter_{scene['id']}.json"
            out.write_text(json.dumps(bundle, indent=2) + "\n")
            total_tiles = sum(len(p["tiles"]) for p in pages)
            print(f"  wrote {out} ({out.stat().st_size//1024} KB, {len(pages)} pages, {total_tiles} tiles)")

        imageless = [k for k, v in scene["new"].items() if v[2] is None]
        manifest.append({
            "id": scene["id"],
            "title": scene["name"],
            "blurb": scene["blurb"],
            "prompt": scene["prompt"],
            "bundle": f"starter_{scene['id']}",
            "imagelessWords": imageless,
        })

    if not args.dry_run:
        (RES_DIR / "starter_scenes.json").write_text(json.dumps(manifest, indent=2) + "\n")
        print(f"\n✓ wrote manifest {RES_DIR / 'starter_scenes.json'}")
    print("\nDone.")


if __name__ == "__main__":
    main()
