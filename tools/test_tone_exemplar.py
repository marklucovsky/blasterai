#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""
Test adding a NEW word to a tone set by showing the model an exemplar.

## The problem this has to solve

Chaining fixed set construction — each tone generated as a small step from the
previous one. But chaining is unavailable at runtime. When a caregiver on the
Medium-Dark set adds "policeman", there is no chain to walk: the app has one new
tile and must land it on the right tone first try. Describing the tone in words
does not work — that is the whole reason chaining was needed.

Mark's proposal: pass an already-correct tile from the same set as a reference,
and ask the model to match it. `gpt-image-1` edits accepts multiple images, so
the request carries the new word plus the exemplar.

If this works it settles the installable-set contract: a set ships its art, its
style prompt, AND a tone exemplar — and on-device additions match by example
rather than by description.

Usage:
    python3 tools/test_tone_exemplar.py --tone medium_dark --word drink --exemplar mom
"""

import argparse
import base64
import os
import ssl
import sys
from pathlib import Path
from urllib import request as urlrequest

sys.path.insert(0, str(Path(__file__).parent))
from build_tone_variants import (SSL_CTX, TONES, api_key, post_multipart,  # noqa: E402
                                 post_json, with_retry, IMAGE_MODEL)

BASE = Path("tools/tile_sets")
SOURCE = BASE / "classic"


def exemplar_prompt(tone_key: str) -> str:
    emoji, label, fitz, hex_target, description = TONES[tone_key]
    return (
        "You are given two images. The FIRST is the tile to modify and is the ONLY "
        "image you are producing output for. The SECOND is a COLOUR SWATCH ONLY.\n"
        # The first attempt copied the reference's hairstyle onto a bald figure.
        # The exemplar teaches tone and, unless forbidden in these terms, content.
        "Treat the SECOND image purely as a paint sample. Do NOT copy anything "
        "from it — not its hair, not its hairstyle, not its face, not its "
        "expression, not its clothing, not its pose, not its subject. The person "
        "in the second image must not appear in your output in any way. If the "
        "person in the FIRST image has no hair, they still have no hair. If they "
        "are facing away, they still face away.\n"
        f"Your only task: recolour the skin of the person in the FIRST image to "
        f"the skin tone sampled from the SECOND image — the {label} tone "
        f"({emoji}, {fitz}, approximately {hex_target}).\n"
        "Hair must stay clearly readable against the new skin, with strong value "
        "contrast at the hairline, and must never be blond on a dark tone.\n"
        "Change NOTHING else in the first image. Same person, same pose, same "
        "expression, same hairstyle, same clothing and clothing colours, same "
        "objects, same background, same black outlines at the same weight. Keep "
        "the black facial features clearly readable against the skin. Do not "
        "redraw or restyle. No text anywhere."
    )


def generate_new_word(word: str, out: Path) -> bool:
    """Generate a brand-new word in Classic style, as the app would on-device.

    Uses the set's own style prompt from Resources/image_styles.json — the same
    string the app passes — so this is the real first half of the caregiver flow:
    a word that exists in no set, drawn to match the set it is being added to.
    """
    import json
    styles = json.loads(Path("claudeBlast/Resources/image_styles.json").read_text())
    style = styles["classic"]
    prompt = (f"{style}\n\nSubject: {word.replace('_', ' ')}. "
              "A single clear figure, centered, no text.")
    # /v1/images/generations is JSON; only /v1/images/edits is multipart.
    body = {"model": IMAGE_MODEL, "prompt": prompt, "size": "1024x1024",
            "quality": "medium", "n": 1}
    r = with_retry(
        lambda: post_json("https://api.openai.com/v1/images/generations",
                          body, api_key(), timeout=180),
        label=f"generate/{word}")
    if not r or not r.get("data"):
        return False
    item = r["data"][0]
    if "b64_json" in item:
        out.write_bytes(base64.b64decode(item["b64_json"]))
    else:
        with urlrequest.urlopen(item["url"], timeout=120, context=SSL_CTX) as u:
            out.write_bytes(u.read())
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--new-word", help="generate this word in Classic style first")
    ap.add_argument("--tone", required=True)
    ap.add_argument("--word", default="", help="existing word from Classic")
    ap.add_argument("--exemplar", required=True, help="already-correct tile in that tone")
    ap.add_argument("--chain-dir", default="classic_chain_",
                    help="prefix of the set holding the exemplar")
    args = ap.parse_args()

    if args.new_word:
        new_dir = BASE / "new_words"
        new_dir.mkdir(parents=True, exist_ok=True)
        src = new_dir / f"{args.new_word}.png"
        if not src.exists():
            print(f"generating new word '{args.new_word}' in Classic style…")
            if not generate_new_word(args.new_word, src):
                sys.exit("generation failed")
            print(f"  → {src}")
        args.word = args.new_word
    else:
        src = SOURCE / f"{args.word}.png"

    ref = BASE / f"{args.chain_dir}{args.tone}" / f"{args.exemplar}.png"
    for p in (src, ref):
        if not p.exists():
            sys.exit(f"missing {p}")

    out_dir = BASE / f"exemplar_{args.tone}"
    out_dir.mkdir(parents=True, exist_ok=True)
    dst = out_dir / f"{args.word}.png"

    print(f"new word '{args.word}' → {args.tone}, matching '{args.exemplar}'")
    fields = {"model": IMAGE_MODEL, "prompt": exemplar_prompt(args.tone),
              "size": "1024x1024", "quality": "medium", "n": "1"}
    r = with_retry(
        lambda: post_multipart(
            "https://api.openai.com/v1/images/edits", fields, {}, api_key(),
            multi_field="image[]",
            multi=[(src.name, src.read_bytes()), (ref.name, ref.read_bytes())]),
        label=f"exemplar/{args.tone}/{args.word}")
    if not r or not r.get("data"):
        sys.exit("failed")
    item = r["data"][0]
    if "b64_json" in item:
        dst.write_bytes(base64.b64decode(item["b64_json"]))
    else:
        with urlrequest.urlopen(item["url"], timeout=120, context=SSL_CTX) as u:
            dst.write_bytes(u.read())
    print(f"→ {dst}")


if __name__ == "__main__":
    main()
