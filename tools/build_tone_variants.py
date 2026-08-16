#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Build skin-tone variants of the Classic tile set as complete, standalone sets.

## Why complete sets rather than an overlay

Each tone is a **full clone of Classic** — every key present, human tiles
refined, everything else copied byte-for-byte. A set that only contains the
tiles it changed would need runtime composition, and a caregiver installing
"Classic — Medium" would be trusting two sets to stay in sync forever. Mark's
call, and it matches the installable-set design: a set is self-contained.

## Why refine rather than recolour or regenerate

**Not recolour:** Classic tiles are not flat-palette art — 6,000–10,000 distinct
colours each, since they were AI-generated rather than exported from vector. Skin
does cluster (around 237,180,130) but sits in the same hue range as bread, wood,
sand, and orange clothing, so a range-based recolour would repaint a bagel.

**Not regenerate:** a fresh generation would draw a *different person*. In AAC the
figure IS the referent — `me` and `my` showing different-looking people is a
comprehension bug, not a cosmetic one. `/v1/images/edits` is image-to-image, so
the pose, composition, and line work survive and only the skin changes.

## Cost

Classification is ~$0.0004/tile (gpt-4o-mini vision). Each refine is ~$0.044
(gpt-image-1: ~1056 output tokens at $40/1M plus image input at $10/1M).
Every phase prints its running total, and `--pilot` exists so quality is judged
before a full set is paid for.

Usage:
    python3 tools/build_tone_variants.py --classify          # who has skin? (~$0.20)
    python3 tools/build_tone_variants.py --pilot             # 6 tiles x 3 tones (~$0.80)
    python3 tools/build_tone_variants.py --build medium      # full set
    python3 tools/build_tone_variants.py --build all --yes
"""

import argparse
import base64
import io
import json
import os
import shutil
import ssl
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib import request as urlrequest
from urllib.error import HTTPError

try:
    from PIL import Image
except ImportError:
    sys.exit("pip install Pillow")

# python.org Python ships no CA bundle, so urllib fails every TLS handshake with
# CERTIFICATE_VERIFY_FAILED unless pointed at certifi's. Falls back to the system
# default where the interpreter is configured properly (e.g. Homebrew).
try:
    import certifi
    SSL_CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CTX = ssl.create_default_context()

SOURCE = Path("tools/tile_sets/classic")
OUT_BASE = Path("tools/tile_sets")
CLASSIFY_CACHE = Path("tools/tile_sets/classic_skin_tiles.json")

CHAT_MODEL = "gpt-4o-mini"
IMAGE_MODEL = "gpt-image-1"
COST_PER_REFINE = 0.044          # measured 2026-08-14, see docs/cost-reconciliation
COST_PER_CLASSIFY = 0.0004

# Unicode emoji skin-tone modifiers, which are themselves Fitzpatrick-based.
# Using the established scale rather than inventing names means a caregiver has
# already seen this vocabulary on their phone keyboard.
#
# The hex values are sampled from the actual Apple Color Emoji swatches (the
# modifier characters render as solid colour when standalone) — see
# tools/measure_skin_tone.py. **Naming a tone without giving its colour does not
# work**: the first pilot said "medium skin tone (Fitzpatrick IV)" and got back
# rgb(176,80,24) — terracotta, and darker than the *dark* reference. The model
# needs the target, not the label.
TONES = {
    "light":        ("🏻", "Light",        "Fitzpatrick I–II", "#FADCBC",
                     "pale, lightly warm"),
    "medium_light": ("🏼", "Medium-Light", "Fitzpatrick III",  "#E0BB95",
                     "fair, cream-toned"),
    "medium":       ("🏽", "Medium",       "Fitzpatrick IV",   "#BF8F68",
                     "moderate Mediterranean or East Asian brown"),
    "medium_dark":  ("🏾", "Medium-Dark",  "Fitzpatrick V",    "#9B643D",
                     "dark brown, South Asian or Middle Eastern"),
    "dark":         ("🏿", "Dark",         "Fitzpatrick VI",   "#594539",
                     "deeply pigmented dark brown"),
}
# Classic's existing figures read as light / medium-light, so those are the
# tones worth adding.
DEFAULT_TONES = ["medium", "medium_dark", "dark"]

PILOT_KEYS = ["happy", "eat", "me", "mom", "play", "drink"]

CLASSIFY_PROMPT = (
    "This is a pictogram from an AAC (augmentative communication) symbol set. "
    "Answer with one word, yes or no: does it depict a human being or any human "
    "body part with visible skin — a face, hand, arm, or whole figure? "
    "Answer no for animals, objects, food, places, and abstract symbols with no "
    "person in them."
)


def refine_prompt(tone_key: str) -> str:
    emoji, label, fitz, hex_target,description = TONES[tone_key]
    dark_tone = tone_key in ("medium_dark", "dark")
    r, g, b = tuple(int(hex_target[i:i + 2], 16) for i in (1, 3, 5))
    return (
        # 1. The target, as a colour rather than a label — and as explicit
        #    channel values. Hex alone still produced terracotta: the model got
        #    red right and crushed blue to less than half its target, which is
        #    precisely the difference between "brown" and "rust".
        f"Recolour the skin of the human figure(s) to exactly {hex_target} — "
        f"RGB red {r}, green {g}, blue {b}. This is a {description} tone "
        f"({label}, {fitz}, the {emoji} emoji modifier).\n"
        f"The blue channel matters most: blue must be about {round(b / r * 100)}% "
        f"of red and green about {round(g / r * 100)}% of red. A skin tone with "
        "too little blue looks orange, rust, terracotta or brick — that is wrong. "
        "This must be a soft, slightly desaturated, natural brown skin tone. "
        f"Do not go darker than {hex_target}; err lighter if anything.\n"
        # 2. Hair — the failure Mark caught in the first pilot.
        "Hair must stay clearly readable against the new skin: keep a strong "
        "value contrast between hair and face so the hairline is obvious. "
        + ("Because this skin tone is dark, hair must be dark brown or black — "
           "never blond, never light. "
           if dark_tone else
           "Keep the original hair colour unless it would blend into the new "
           "skin tone, in which case darken it. ")
        + "Do not tint hair with the skin colour.\n"
        # 3. Everything else is off limits.
        "Change NOTHING else. Same person, same pose, same facial expression, "
        "same hairstyle, same clothing and identical clothing colours, same "
        "objects, same background, same outlines and line weights, same "
        "composition and framing. Do not redraw or restyle. Do not add or remove "
        "anything. Do not recolour clothing, food, bread, wood, sand, or any "
        "object — only skin. No text anywhere."
    )


def chain_prompt(prev_key: str | None, tone_key: str) -> str:
    """Prompt for one STEP along the scale, rather than a jump from the original.

    Generating every tone from the same light Classic source asks for a large
    edit each time, and the model handles that badly at the dark end: dark came
    back ranging luma 46–201 across six tiles, sometimes *lighter* than
    medium-dark. It also has no idea the tones form an ordered scale, because
    each call sees one target in isolation.

    Chaining fixes both. Each call is a small darkening of the previous tone, and
    naming where the figure is coming FROM gives the model the relationship it
    was missing.
    """
    emoji, label, fitz, hex_target, description = TONES[tone_key]
    r, g, b = tuple(int(hex_target[i:i + 2], 16) for i in (1, 3, 5))
    if prev_key is None:
        origin = "light skin (about #F0B482)"
    else:
        p = TONES[prev_key]
        origin = f"{p[1].lower()} skin ({p[3]})"

    dark_tone = tone_key in ("medium_dark", "dark")
    return (
        f"The figure currently has {origin}. Darken the skin ONE STEP to "
        f"{hex_target} — RGB red {r}, green {g}, blue {b} — a {description} tone "
        f"({label}, {fitz}, the {emoji} emoji modifier).\n"
        f"This is a small, controlled step along a skin-tone scale, not a jump. "
        f"The result must be clearly darker than {origin} and clearly lighter "
        f"than the next step down. Land on {hex_target}: blue should be about "
        f"{round(b / r * 100)}% of red and green about {round(g / r * 100)}% of "
        "red. A tone with too little blue reads as orange, rust or terracotta, "
        "which is wrong. Keep it soft and slightly desaturated — a natural skin "
        "tone, not a saturated colour.\n"
        # Pale hair was THE failure mode in review — back_, push, read, they and
        # thirsty all came back blond on brown skin. The old rule only forbade it
        # on the dark tones, and even there the model kept yellow hair. It is now
        # unconditional and states the substitution rather than a preference.
        "HAIR: if the hair is blond, yellow, golden, light brown, or any pale "
        "colour, you MUST change it to dark brown. Pale hair on brown skin is "
        "wrong and is the most common mistake made on this task. Hair that is "
        "already dark stays exactly as it is. "
        "Keep strong value contrast at the hairline so it reads clearly against "
        "the skin, and never tint hair with the skin colour.\n"
        "Change NOTHING else. Same person, same pose, same facial expression, "
        "same hairstyle, same clothing and identical clothing colours, same "
        "objects, same background, same black outlines at the same weight, same "
        "composition. Do not redraw or restyle. Do not recolour clothing, food, "
        "bread, wood, sand, or any object — only skin. No text anywhere."
    )


def build_chain(keys: list[str], chain: list[str], api_key_value: str,
                quality: str = "medium") -> None:
    """Walk the scale, each tone generated from the previous tone's output."""
    print(f"Chained build: {len(keys)} tiles × {len(chain)} steps "
          f"≈ ${len(keys) * len(chain) * COST_PER_REFINE:.2f}  (quality={quality})",
          flush=True)

    done = [0]

    def walk(key: str) -> None:
        """One tile's full chain. The STEPS are ordered; the TILES are not, so
        tiles run in parallel while each chain stays strictly sequential."""
        prev_dir, prev_tone = SOURCE, None
        for tone in chain:
            out = OUT_BASE / f"classic_chain_{tone}"
            out.mkdir(parents=True, exist_ok=True)
            dst = out / f"{key}.png"
            src = prev_dir / f"{key}.png"
            if not dst.exists():
                fields = {"model": IMAGE_MODEL, "prompt": chain_prompt(prev_tone, tone),
                          "size": "1024x1024", "quality": quality, "n": "1"}
                files = {"image": (src.name, src.read_bytes())}
                r = with_retry(
                    lambda: post_multipart("https://api.openai.com/v1/images/edits",
                                           fields, files, api_key_value),
                    label=f"chain/{tone}/{key}")
                if not r or not r.get("data"):
                    print(f"  {key}/{tone}: FAILED — chain stops here for this tile",
                          flush=True)
                    return
                item = r["data"][0]
                if "b64_json" in item:
                    dst.write_bytes(base64.b64decode(item["b64_json"]))
                else:
                    with urlrequest.urlopen(item["url"], timeout=120, context=SSL_CTX) as u:
                        dst.write_bytes(u.read())
            prev_dir, prev_tone = out, tone
        done[0] += 1
        if done[0] % 10 == 0:
            print(f"  {done[0]}/{len(keys)} tiles  "
                  f"(~${done[0] * len(chain) * COST_PER_REFINE:.2f})", flush=True)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(walk, keys))
    print(f"  done: {done[0]}/{len(keys)} tiles complete", flush=True)


def api_key() -> str:
    k = os.environ.get("OPENAI_API_KEY", "").strip()
    if not k:
        sys.exit("OPENAI_API_KEY not set.")
    return k


def post_json(url: str, payload: dict, key: str, timeout: int = 90) -> dict:
    req = urlrequest.Request(
        url, data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
    )
    with urlrequest.urlopen(req, timeout=timeout, context=SSL_CTX) as r:
        return json.loads(r.read())


def post_multipart(url: str, fields: dict, files: dict, key: str, timeout: int = 180,
                   multi_field: str | None = None, multi: list | None = None) -> dict:
    """`multi` sends several images under one repeated field name (`image[]`).

    This is what makes a tone EXEMPLAR possible: when a caregiver adds a new word
    to a tone set at runtime, there is no chain to walk — the set has to carry a
    reference. Passing the new tile plus an already-correct tile from the same set
    lets the model match the tone by example rather than from a colour description
    it demonstrably does not follow.
    """
    boundary = "----blaster" + str(int(time.time() * 1000))
    body = bytearray()
    for name, value in fields.items():
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        body += f"{value}\r\n".encode()
    for name, (fname, data) in files.items():
        body += f"--{boundary}\r\n".encode()
        body += (f'Content-Disposition: form-data; name="{name}"; '
                 f'filename="{fname}"\r\n').encode()
        body += b"Content-Type: image/png\r\n\r\n"
        body += data + b"\r\n"
    for fname, data in (multi or []):
        body += f"--{boundary}\r\n".encode()
        body += (f'Content-Disposition: form-data; name="{multi_field}"; '
                 f'filename="{fname}"\r\n').encode()
        body += b"Content-Type: image/png\r\n\r\n"
        body += data + b"\r\n"
    body += f"--{boundary}--\r\n".encode()

    req = urlrequest.Request(
        url, data=bytes(body),
        headers={"Authorization": f"Bearer {key}",
                 "Content-Type": f"multipart/form-data; boundary={boundary}"},
    )
    with urlrequest.urlopen(req, timeout=timeout, context=SSL_CTX) as r:
        return json.loads(r.read())


def with_retry(fn, attempts: int = 4, label: str = ""):
    """Retry on 429/5xx with backoff — image generation rate-limits readily."""
    for i in range(attempts):
        try:
            return fn()
        except HTTPError as e:
            # A 400 from the image safety system is worth retrying: it is
            # probabilistic, not a verdict. `fever` — a child with a thermometer —
            # was rejected as self-harm during the full run, then passed on an
            # identical retry. Treating it as permanent silently dropped a tile
            # from a set that is supposed to be complete.
            retryable = e.code in (429, 500, 502, 503, 504)
            if e.code == 400:
                try:
                    body = json.loads(e.read())
                    retryable = "safety" in json.dumps(body).lower()
                    e = HTTPError(e.url, e.code, json.dumps(body), e.headers, None)
                except Exception:
                    pass
            if retryable and i < attempts - 1:
                wait = 2 ** i * 3
                print(f"    {label}: HTTP {e.code}, retrying in {wait}s")
                time.sleep(wait)
                continue
            detail = ""
            try:
                detail = json.loads(e.read()).get("error", {}).get("message", "")
            except Exception:
                pass
            print(f"    {label}: HTTP {e.code} {detail}")
            return None
        except Exception as e:
            if i < attempts - 1:
                time.sleep(2 ** i * 2)
                continue
            print(f"    {label}: {e}")
            return None
    return None


# --------------------------------------------------------------------------
# Phase 1 — which tiles show skin


def classify(keys: list[str], key: str) -> dict:
    cache = json.loads(CLASSIFY_CACHE.read_text()) if CLASSIFY_CACHE.exists() else {}
    todo = [k for k in keys if k not in cache]
    if not todo:
        print(f"  all {len(keys)} tiles already classified")
        return cache

    print(f"  classifying {len(todo)} tiles (~${len(todo) * COST_PER_CLASSIFY:.2f})")

    def one(tile_key: str):
        # Downscale before upload. The masters are ~1 MB each and the question is
        # "is there a person in this", which 256px answers as well as 1024px —
        # at a fraction of the tokens and none of the upload time.
        im = Image.open(SOURCE / f"{tile_key}.png").convert("RGB")
        im.thumbnail((256, 256), Image.LANCZOS)
        buf = io.BytesIO()
        im.save(buf, "PNG", optimize=True)
        b64 = base64.b64encode(buf.getvalue()).decode()
        payload = {
            "model": CHAT_MODEL,
            "max_tokens": 3,
            "messages": [{"role": "user", "content": [
                {"type": "text", "text": CLASSIFY_PROMPT},
                {"type": "image_url",
                 "image_url": {"url": f"data:image/png;base64,{b64}", "detail": "low"}},
            ]}],
        }
        r = with_retry(lambda: post_json("https://api.openai.com/v1/chat/completions",
                                         payload, key), label=tile_key)
        if not r:
            return tile_key, None
        answer = r["choices"][0]["message"]["content"].strip().lower()
        return tile_key, answer.startswith("y")

    with ThreadPoolExecutor(max_workers=8) as pool:
        for i, (k, v) in enumerate(pool.map(one, todo), 1):
            if v is not None:
                cache[k] = v
            if i % 50 == 0:
                print(f"    {i}/{len(todo)}", flush=True)
                CLASSIFY_CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True))

    CLASSIFY_CACHE.write_text(json.dumps(cache, indent=1, sort_keys=True))
    return cache


# --------------------------------------------------------------------------
# Phase 2 — refine


def refine_tile(src: Path, dst: Path, tone_key: str, api_key: str) -> bool:
    """`api_key` is deliberately not named `key` — this module also uses `key`
    for tile keys, and the two got crossed once already, authenticating as the
    word "mom"."""
    if dst.exists():
        return True
    fields = {"model": IMAGE_MODEL, "prompt": refine_prompt(tone_key),
              "size": "1024x1024", "quality": "medium", "n": "1"}
    files = {"image": (src.name, src.read_bytes())}
    r = with_retry(lambda: post_multipart("https://api.openai.com/v1/images/edits",
                                          fields, files, api_key), label=f"{tone_key}/{src.stem}")
    if not r or not r.get("data"):
        return False
    item = r["data"][0]
    if "b64_json" in item:
        dst.write_bytes(base64.b64decode(item["b64_json"]))
    elif "url" in item:
        with urlrequest.urlopen(item["url"], timeout=120, context=SSL_CTX) as u:
            dst.write_bytes(u.read())
    else:
        return False
    return True


def build_tone(tone_key: str, skin_keys: list[str], all_keys: list[str],
               api_key: str, copy_rest: bool) -> None:
    emoji, label = TONES[tone_key][0], TONES[tone_key][1]
    out = OUT_BASE / f"classic_{tone_key}"
    out.mkdir(parents=True, exist_ok=True)
    print(f"\n{emoji} Classic — {label}  →  {out}")

    if copy_rest:
        copied = 0
        for k in all_keys:
            if k in skin_keys:
                continue
            d = out / f"{k}.png"
            if not d.exists():
                shutil.copy(SOURCE / f"{k}.png", d)
                copied += 1
        print(f"  copied {copied} unchanged tiles (a set must be complete)")

    todo = [k for k in skin_keys if not (out / f"{k}.png").exists()]
    print(f"  refining {len(todo)} tiles with people (~${len(todo) * COST_PER_REFINE:.2f})")

    done = fail = 0
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = pool.map(
            lambda k: refine_tile(SOURCE / f"{k}.png", out / f"{k}.png", tone_key, api_key), todo)
        for i, ok in enumerate(results, 1):
            done += ok
            fail += not ok
            if i % 10 == 0:
                print(f"    {i}/{len(todo)}  (${done * COST_PER_REFINE:.2f})")
    print(f"  done: {done} refined, {fail} failed  ≈ ${done * COST_PER_REFINE:.2f}")


# --------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--classify", action="store_true")
    ap.add_argument("--pilot", action="store_true")
    ap.add_argument("--build", help="tone name, or 'all'")
    ap.add_argument("--chain", action="store_true",
                    help="generate each tone from the previous tone's output")
    ap.add_argument("--quality", default="medium", help="gpt-image-1 quality")
    ap.add_argument("--tones", default=",".join(DEFAULT_TONES))
    ap.add_argument("--tiles", default="", help="pilot on these keys instead of PILOT_KEYS")
    ap.add_argument("--yes", action="store_true", help="skip the cost confirmation")
    args = ap.parse_args()

    if not SOURCE.exists():
        sys.exit(f"missing {SOURCE}")
    key = api_key()
    all_keys = sorted(p.stem for p in SOURCE.glob("*.png"))

    if args.classify:
        cache = classify(all_keys, key)
        skin = [k for k, v in cache.items() if v]
        print(f"\n{len(skin)} of {len(cache)} tiles show a person "
              f"({len(skin)/max(1,len(cache))*100:.0f}%)")
        print(f"→ {CLASSIFY_CACHE}")
        print(f"\nA full tone set would cost ~${len(skin) * COST_PER_REFINE:.2f}; "
              f"{len(DEFAULT_TONES)} tones ≈ ${len(skin) * COST_PER_REFINE * len(DEFAULT_TONES):.2f}")
        return

    if not CLASSIFY_CACHE.exists():
        sys.exit("Run --classify first.")
    cache = json.loads(CLASSIFY_CACHE.read_text())
    skin_keys = sorted(k for k, v in cache.items() if v)
    tones = [t.strip() for t in args.tones.split(",") if t.strip() in TONES]

    if args.chain:
        requested = [k.strip() for k in args.tiles.split(",") if k.strip()]
        if args.build == "all":
            targets = skin_keys          # every tile with a person in it
        else:
            targets = requested or [k for k in PILOT_KEYS if k in skin_keys] or skin_keys[:6]
        cost = len(targets) * len(tones) * COST_PER_REFINE
        if len(targets) > 20 and not args.yes:
            print(f"Full chained build: {len(targets)} tiles × {len(tones)} tones ≈ ${cost:.2f}")
            if input("Proceed? [y/N] ").strip().lower() != "y":
                sys.exit("aborted")
        build_chain(targets, tones, key, quality=args.quality)
        print("\nMeasure with:  python3 tools/measure_skin_tone.py --variants")
        return

    if args.pilot:
        requested = [k.strip() for k in args.tiles.split(",") if k.strip()]
        pilot = requested or [k for k in PILOT_KEYS if k in skin_keys] or skin_keys[:6]
        cost = len(pilot) * len(tones) * COST_PER_REFINE
        print(f"Pilot: {len(pilot)} tiles × {len(tones)} tones ≈ ${cost:.2f}")
        for t in tones:
            build_tone(t, pilot, all_keys, key, copy_rest=False)
        print("\nReview with:  python3 tools/build_tone_review.py")
        return

    if args.build:
        chosen = tones if args.build == "all" else [args.build]
        cost = len(skin_keys) * len(chosen) * COST_PER_REFINE
        print(f"Full build: {len(skin_keys)} tiles × {len(chosen)} tones ≈ ${cost:.2f}")
        if not args.yes:
            if input("Proceed? [y/N] ").strip().lower() != "y":
                sys.exit("aborted")
        for t in chosen:
            build_tone(t, skin_keys, all_keys, key, copy_rest=True)
        return

    ap.print_help()


if __name__ == "__main__":
    main()
