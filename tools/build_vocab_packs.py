#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Build Blaster vocabulary packs: named, installable sets of words that EXTEND the
base vocabulary (vocabulary.json). A pack is pure vocab + art — no page, no
images carried in the manifest. Art ships as ordinary set assets (p3d_/cls_),
exactly like base vocab, so a pack word is a first-class multi-set tile.

For each pack word this ensures a p3d master (tools/tile_sets/playful_3d) and a
classic master (tools/tile_sets/classic) exist — reusing the cached starter
masters where present, generating what's missing. It then writes:
  - Resources/packs/<slug>.json   (the pack manifest: id, words)
  - Resources/packs.json          (catalog of available system packs)
  - Resources/packicon_<slug>.png (one thematic 512px icon per pack)

After running, optimize + sync the p3d and classic sets to bundle p3d_/cls_ for
the new words:
    python3 tools/optimize_tiles.py --set playful_3d && python3 tools/sync_to_app.py --set playful_3d --only-changed
    python3 tools/optimize_tiles.py --set classic    && python3 tools/sync_to_app.py --set classic --only-changed

Usage:
    export OPENAI_API_KEY=sk-...
    python3 tools/build_vocab_packs.py            # generate art + emit manifests
    python3 tools/build_vocab_packs.py --dry-run  # plan only, no API
"""

import argparse
import io
import json
import shutil
import sys
import time
from pathlib import Path

import generate_sets as gs

try:
    import requests
except ImportError:
    sys.exit("pip install requests")
try:
    from PIL import Image
except ImportError:
    sys.exit("pip install pillow")

RES_DIR = Path("claudeBlast/Resources")
P3D_DIR = Path("tools/tile_sets/playful_3d")
CLASSIC_DIR = Path("tools/tile_sets/classic")
STARTER_DIR = Path("tools/tile_sets/starter")   # cached p3d masters from prior runs
APP_TILES = Path("claudeBlast/TileImageSets")   # bundled p3d_/cls_ app art
COVER_MASTERS = Path("tools/tile_sets/packcovers")  # 1024 cover masters (LFS)
ID_HOST = "vocab.blaster.app"
SLEEP_SECONDS = 15

# slug -> {displayName, version, icon subject, words {key: (wordClass, displayName, p3d subject)}}
PACKS = {
    "farm": {
        "displayName": "Farm", "version": "1.0.0",
        "icon": "a fun farm scene with a red barn, a cow, and green fields",
        "words": {
            "cow": ("animal", "Cow", "a cow standing, black and white spots, side view, friendly"),
            "pig": ("animal", "Pig", "a pink pig standing, side view, friendly"),
            "horse": ("animal", "Horse", "a brown horse standing, side view"),
            "chicken": ("animal", "Chicken", "a white hen chicken standing"),
            "sheep": ("animal", "Sheep", "a fluffy white sheep standing, side view"),
            "rooster": ("animal", "Rooster", "a colorful rooster with a red comb, side view"),
            "tractor": ("object", "Tractor", "a red farm tractor, side view"),
            "barn": ("object", "Barn", "a classic red barn with a peaked roof and white trim"),
            "farmer": ("people", "Farmer", "a friendly farmer in denim overalls and a straw hat, half body"),
            "egg": ("food", "Egg", "a single smooth white egg"),
            "hay": ("plant", "Hay", "a golden round bale of hay"),
        },
    },
    "tidepools": {
        "displayName": "Tide Pools", "version": "1.0.0",
        "icon": "a fun tide-pool scene with a crab and a starfish in a rocky pool",
        "words": {
            "crab": ("animal", "Crab", "a red crab with two claws, top view"),
            "starfish": ("animal", "Starfish", "an orange starfish with five arms, top view"),
            "shell": ("object", "Shell", "a spiral seashell, peach and white"),
            "seaweed": ("plant", "Seaweed", "green seaweed strands underwater"),
            "fish": ("animal", "Fish", "a small orange fish, side view"),
            "snail": ("animal", "Snail", "a sea snail with a brown spiral shell"),
            "anemone": ("animal", "Anemone", "a pink sea anemone with waving tentacles"),
        },
    },
    "mealtime": {
        "displayName": "Mealtime", "version": "1.0.0",
        "icon": "a fun mealtime scene with a plate of food and a cup on a table",
        "words": {
            "spaghetti": ("food", "Spaghetti", "a plate of spaghetti noodles with red tomato sauce"),
            "plate": ("object", "Plate", "an empty round white dinner plate, top view"),
            "fork": ("object", "Fork", "a single metal fork, top view"),
            "cup": ("object", "Cup", "a cup with a handle"),
            "napkin": ("object", "Napkin", "a folded white napkin"),
        },
    },
    "space": {
        "displayName": "Space", "version": "1.0.0",
        "icon": "a fun outer-space scene with a ringed planet, bright stars, and a rocket",
        "words": {
            "rocket": ("object", "Rocket", "a cartoon rocket ship blasting off with flames"),
            "astronaut": ("people", "Astronaut", "a friendly astronaut in a white spacesuit and helmet"),
            "planet": ("object", "Planet", "a ringed planet like Saturn, purple and blue"),
            "moon": ("object", "Moon", "a pale grey crescent moon"),
            "comet": ("object", "Comet", "a comet with a glowing tail streaking across"),
            "alien": ("object", "Alien", "a friendly little green alien with big eyes"),
            "spaceship": ("object", "Spaceship", "a silver flying-saucer spaceship"),
            "telescope": ("object", "Telescope", "a telescope on a tripod pointed up at the sky"),
            "satellite": ("object", "Satellite", "a space satellite with solar panels"),
            "galaxy": ("object", "Galaxy", "a purple and blue spiral galaxy of stars"),
        },
    },
    "dinosaurs": {
        "displayName": "Dinosaurs", "version": "1.0.0",
        "icon": "a fun dinosaur scene with a friendly green dinosaur and a volcano",
        "words": {
            "dinosaur": ("animal", "Dinosaur", "a friendly green cartoon dinosaur"),
            "trex": ("animal", "T-Rex", "a friendly Tyrannosaurus Rex dinosaur, green, standing"),
            "triceratops": ("animal", "Triceratops", "a triceratops dinosaur with three horns"),
            "stegosaurus": ("animal", "Stegosaurus", "a stegosaurus dinosaur with plates on its back"),
            "pterodactyl": ("animal", "Pterodactyl", "a pterodactyl flying dinosaur with wings"),
            "brontosaurus": ("animal", "Brontosaurus", "a long-necked brontosaurus dinosaur"),
            "raptor": ("animal", "Raptor", "a small velociraptor dinosaur"),
            "fossil": ("object", "Fossil", "a dinosaur skeleton fossil"),
            "volcano": ("object", "Volcano", "an erupting volcano with orange lava"),
            "dino_egg": ("object", "Dino Egg", "a large spotted dinosaur egg"),
        },
    },
    "vehicles": {
        "displayName": "Vehicles", "version": "1.0.0",
        "icon": "a fun scene with a red car, a fire truck, and an airplane",
        "words": {
            "car": ("object", "Car", "a red cartoon car, side view"),
            "truck": ("object", "Truck", "a blue delivery truck, side view"),
            "train": ("object", "Train", "a colorful train engine, side view"),
            "airplane": ("object", "Airplane", "a passenger airplane flying"),
            "boat": ("object", "Boat", "a small sailboat on blue water"),
            "bicycle": ("object", "Bicycle", "a child's bicycle, side view"),
            "helicopter": ("object", "Helicopter", "a helicopter with a spinning top rotor"),
            "fire_truck": ("object", "Fire Truck", "a red fire truck with a ladder"),
            "ambulance": ("object", "Ambulance", "a white ambulance with a red cross and lights"),
            "police_car": ("object", "Police Car", "a police car with blue lights on top"),
        },
    },
}


def gen(prompt_subject: str, style: str, api_key: str, session) -> bytes:
    """Generate one image (with retry), returning PNG bytes."""
    prompt = gs.build_prompt(
        gs.strip_clay_words(prompt_subject) if style == "classic" else prompt_subject,
        style,
    )
    for attempt in range(4):
        png = gs.generate_image(prompt, api_key, session)
        if png and len(png) >= gs.MIN_IMAGE_BYTES:
            return png
        time.sleep(10 * (attempt + 1))
    sys.exit(f"  FAILED to generate ({style}) {prompt_subject[:50]}")


def ensure_master(key: str, subject: str, out_dir: Path, style: str,
                  api_key: str, session, dry: bool) -> None:
    dest = out_dir / f"{key}.png"
    if dest.exists() and dest.stat().st_size >= gs.MIN_IMAGE_BYTES:
        return
    # p3d may already exist as a cached starter master — reuse it.
    if style == "playful_3d":
        cached = STARTER_DIR / f"{key}.png"
        if cached.exists() and cached.stat().st_size >= gs.MIN_IMAGE_BYTES:
            if not dry:
                shutil.copy2(cached, dest)
            print(f"    {style:11s} {key:14s} (reused starter master)")
            return
    if dry:
        print(f"    [DRY] {style:11s} {key:14s}")
        return
    print(f"    ⏳ {style:11s} {key:14s}", end="", flush=True)
    dest.write_bytes(gen(subject, style, api_key, session))
    print("  ✓")
    time.sleep(SLEEP_SECONDS)


def _downscale_write(png: bytes, dest: Path) -> None:
    im = Image.open(io.BytesIO(png)).convert("RGBA")
    im.thumbnail((512, 512), Image.LANCZOS)
    buf = io.BytesIO(); im.save(buf, format="PNG", optimize=True)
    dest.write_bytes(buf.getvalue())


def write_cover(slug: str, subject: str, api_key: str, session, dry: bool) -> None:
    """A thematic pack cover in BOTH sets, so a pack page's page_link image
    switches with the active set like any pack word:
        TileImageSets/p3d_packcover_<slug>.png  +  cls_packcover_<slug>.png
    p3d reuses the page_<slug> starter master (or a prior packicon); classic is
    generated. 1024 masters kept in tools/tile_sets/packcovers (LFS)."""
    COVER_MASTERS.mkdir(parents=True, exist_ok=True)

    # p3d cover (reuse existing art where possible)
    p3d_out = APP_TILES / f"p3d_packcover_{slug}.png"
    if not p3d_out.exists():
        master = COVER_MASTERS / f"p3d_{slug}.png"
        png = master.read_bytes() if master.exists() else None
        if png is None:
            for src in (STARTER_DIR / f"page_{slug}.png", RES_DIR / f"packicon_{slug}.png"):
                if src.exists() and src.stat().st_size >= 1000:
                    png = src.read_bytes(); print(f"    cover/p3d {slug:12s} (reused)"); break
            if png is None and not dry:
                print(f"    ⏳ cover/p3d {slug:12s}", end="", flush=True)
                png = gen(subject, "playful_3d", api_key, session); print("  ✓"); time.sleep(SLEEP_SECONDS)
            if png is not None:
                master.write_bytes(png)
        if png is not None and not dry:
            _downscale_write(png, p3d_out)

    # classic cover (generated)
    cls_out = APP_TILES / f"cls_packcover_{slug}.png"
    if not cls_out.exists():
        master = COVER_MASTERS / f"cls_{slug}.png"
        if master.exists():
            png = master.read_bytes()
        elif dry:
            print(f"    [DRY] cover/cls {slug}"); png = None
        else:
            print(f"    ⏳ cover/cls {slug:12s}", end="", flush=True)
            png = gen(subject, "classic", api_key, session); print("  ✓"); time.sleep(SLEEP_SECONDS)
            master.write_bytes(png)
        if png is not None and not dry:
            _downscale_write(png, cls_out)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    api_key = gs.os.environ.get("OPENAI_API_KEY", "")
    if not api_key and not args.dry_run:
        sys.exit("Error: OPENAI_API_KEY not set")
    P3D_DIR.mkdir(parents=True, exist_ok=True)
    CLASSIC_DIR.mkdir(parents=True, exist_ok=True)
    session = requests.Session()
    catalog = []

    for slug, pack in PACKS.items():
        print(f"\n=== {slug} ({pack['displayName']}) ===")
        for key, (_wc, _dn, subject) in pack["words"].items():
            ensure_master(key, subject, P3D_DIR, "playful_3d", api_key, session, args.dry_run)
            ensure_master(key, subject, CLASSIC_DIR, "classic", api_key, session, args.dry_run)
        write_cover(slug, pack["icon"], api_key, session, args.dry_run)

        pack_id = f"{ID_HOST}/{slug}"
        manifest = {
            "id": pack_id, "slug": slug, "displayName": pack["displayName"],
            "version": pack["version"], "icon": slug,
            "words": [{"key": k, "wordClass": wc, "displayName": dn}
                      for k, (wc, dn, _s) in pack["words"].items()],
        }
        if not args.dry_run:
            out = RES_DIR / f"pack_{slug}.json"
            out.write_text(json.dumps(manifest, indent=2) + "\n")
            print(f"  wrote {out} ({len(pack['words'])} words)")
        catalog.append({"id": pack_id, "slug": slug, "displayName": pack["displayName"],
                        "version": pack["version"], "file": f"pack_{slug}"})

    if not args.dry_run:
        (RES_DIR / "packs.json").write_text(json.dumps(catalog, indent=2) + "\n")
        print(f"\n✓ wrote catalog {RES_DIR / 'packs.json'} ({len(catalog)} packs)")
    print("\nDone. Next: optimize_tiles + sync_to_app for playful_3d and classic.")


if __name__ == "__main__":
    main()
