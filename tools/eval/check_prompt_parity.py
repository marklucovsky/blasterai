#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Python renders every request exactly as the app does.

    python3 tools/eval/check_prompt_parity.py          # report each fixture
    python3 tools/eval/check_prompt_parity.py --quiet  # exit code only

Renders the same inputs `PromptFixtureTests.swift` pins, through
`tools/eval/prompts.py`, and compares each with its fixture in
`claudeBlastTests/Fixtures/prompts/`. Exits non-zero on any difference, naming
the first field and message that differ.

The Swift suite proves the app renders the fixtures; this proves Python does.
Between them, a prompt that changes on one side only fails one of the two.
Run it after editing a template, `prompts.py`, or a Swift prompt builder (and
after re-recording the fixtures).

Offline and free: no API call.
"""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import prompts as P  # noqa: E402
import models  # noqa: E402


def job(name: str) -> str:
    """Which `ModelID` job a fixture's request belongs to."""
    if name.startswith("sentence__"):
        return "sentence"
    if name.startswith("tile_suggest__"):
        return "tile_suggest"
    if name.startswith("moderation_rubric__"):
        return "word_audit"
    return "scene_authoring"


def shipped(name: str, body: dict) -> dict:
    """The body as the app sends it: adapted to the job's model, as ChatRequest does."""
    return models.adapt(body, P.APP_MODELS[job(name)])[0]

# Inputs mirrored from PromptFixtureTests.swift — keep the two in step.
MOM_EAT_PIZZA = [{"value": "mom", "wordClass": "people"}, {"value": "eat", "wordClass": "actions"},
                 {"value": "pizza", "wordClass": "food"}]
TOPICAL = [{"key": "toilet"}, {"key": "flush", "displayName": "flush"}]
SCENE_PAGES = [{"key": "home", "tiles": ["car", "bus", "eat"]}, {"key": "potty", "tiles": ["toilet"]}]

CASES = {
    "sentence__mom_eat_pizza__II-III": lambda: P.sentence_body("II-III", MOM_EAT_PIZZA),
    "sentence__mom_eat_pizza__IV+": lambda: P.sentence_body("IV+", MOM_EAT_PIZZA),
    "sentence__she_pool__history": lambda: P.sentence_body(
        "II-III", [{"value": "she", "wordClass": "people"}, {"value": "pool", "wordClass": "places"}],
        history=["Mom, I am hungry.", "Can I have some juice?"]),
    "sentence__chocolate__escalate_1": lambda: P.sentence_body(
        "II-III", [{"value": "chocolate", "wordClass": "food"}], repetition=1, prior="I want chocolate!"),
    "sentence__chocolate__escalate_3": lambda: P.sentence_body(
        "II-III", [{"value": "chocolate", "wordClass": "food"}], repetition=3, prior="I want chocolate!"),
    "sentence__chocolate__escalate_4": lambda: P.sentence_body(
        "II-III", [{"value": "chocolate", "wordClass": "food"}], repetition=4, prior="I want chocolate!"),
    "sentence__mom_eat_pizza__refine": lambda: P.sentence_body(
        "II-III", MOM_EAT_PIZZA, refine=("Mom, I want pizza.", "make it a question")),
    "scene_generate__potty_training": lambda: P.scene_generate_body(
        "Potty training at home: asking to go, saying when done, washing hands."),
    "scene_refine__add_bath": lambda: P.scene_refine_body("add bath time", TOPICAL),
    "page_generate__potty": lambda: P.page_generate_body("potty training", "potty"),
    "page_generate__vehicles_from_home": lambda: P.page_generate_body(
        "the vehicles from the home page", "vehicles", SCENE_PAGES, "home"),
    "page_refine__add_bath": lambda: P.page_refine_body("add bath time", "potty", TOPICAL, SCENE_PAGES, "home"),
    "topic_words__home": lambda: P.topic_words_body("visiting the fire station with my class", "home"),
    "topic_words__leaf": lambda: P.topic_words_body("fire trucks", "leaf"),
    "topic_words__addpage": lambda: P.topic_words_body(
        "costumes", "leaf", {"name": "Halloween Night", "description": "Trick-or-treating with the family.",
                             "words": ["pumpkin", "trick_or_treat", "candy"]}),
    "tile_suggest__dentist": lambda: P.tile_suggest_body("a visit to the dentist"),
    "moderation_rubric__mixed": lambda: P.moderation_rubric_body(["puppy", "poop", "beer", "toy gun"]),
}


def first_difference(got: dict, want: dict) -> str | None:
    for key in sorted(set(got) | set(want)):
        if key == "messages":
            continue
        if got.get(key) != want.get(key):
            return f"{key}: python={got.get(key)!r} swift={want.get(key)!r}"
    gm, wm = got.get("messages", []), want.get("messages", [])
    for i, (g, w) in enumerate(zip(gm, wm)):
        if g != w:
            if g["role"] != w["role"]:
                return f"messages[{i}].role: python={g['role']} swift={w['role']}"
            gc, wc = g["content"], w["content"]
            at = next((j for j, (a, b) in enumerate(zip(gc, wc)) if a != b), min(len(gc), len(wc)))
            return (f"messages[{i}] ({w['role']}) differs at char {at}:\n"
                    f"  python: {gc[max(0, at - 40):at + 40]!r}\n  swift:  {wc[max(0, at - 40):at + 40]!r}")
    if len(gm) != len(wm):
        return f"message count: python={len(gm)} swift={len(wm)}"
    return None


def main() -> int:
    quiet = "--quiet" in sys.argv
    recorded = {p.stem for p in P.FIXTURES.glob("*.json")} - {"_inputs"}
    failures = 0
    for name in sorted(set(CASES) | recorded):
        if name not in CASES:
            print(f"MISSING  {name}: fixture has no Python case — add it to CASES")
            failures += 1
            continue
        path = P.FIXTURES / f"{name}.json"
        if not path.exists():
            print(f"MISSING  {name}: no fixture — record PromptFixtureTests")
            failures += 1
            continue
        diff = first_difference(shipped(name, CASES[name]()),json.loads(path.read_text(encoding="utf-8")))
        if diff:
            failures += 1
            print(f"DIFFERS  {name}\n  {diff}")
        elif not quiet:
            print(f"ok       {name}")
    if not quiet:
        print(f"\n{len(CASES) - failures if failures <= len(CASES) else 0} of {len(CASES)} match")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
