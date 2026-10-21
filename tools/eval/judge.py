# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Tier-2: an LLM judge scores each output, per dimension, with reasons.

The rubrics are text in `rubrics/`, because tuning them is part of the review
loop: wherever the human review disagrees with a score, the rubric is what
changes.

GPT-6 models accept no temperature, so one judge call is not repeatable. A
frozen run asks `n` times and keeps the per-dimension median; an iteration run
asks once. The judge must never be the model under test.

The previous judge (claudeBlastTests/Eval/JudgeScorers.swift, gpt-4o) scored
every sentence 5.00 while known bugs were live, partly because its rubric
rewarded "self-centered is correct here" — which is exactly what turns
"she, pool" into "She, I want…". The `subject` dimension here inverts that.
"""
import json
import statistics
from pathlib import Path

import client
import models
import prompts
import scorers

RUBRICS = Path(__file__).resolve().parent / "rubrics"


def _rubric(name: str, values: dict[str, str]) -> str:
    text = (RUBRICS / f"{name}.txt").read_text(encoding="utf-8").rstrip("\n")
    for k, v in values.items():
        text = text.replace("{{" + k + "}}", v)
    if "{{" in text:
        raise ValueError(f"rubric {name}: unfilled placeholder")
    return text


def _tiles(tiles: list[dict]) -> str:
    return ", ".join(f"{t['value']} ({t['wordClass']})" for t in tiles)


def _stage(stage: str, escalating: bool = False) -> str:
    return prompts.stages()[stage + ("/escalating" if escalating else "")]


# MARK: - Building the judge's input

def sentence_request(case: dict, output: str) -> str:
    i = case["input"]
    lines = [f"Tiles: {_tiles(i['tiles'])}"]
    if i.get("history"):
        lines.append("Earlier sentences in this conversation: " + " | ".join(i["history"]))
    if i.get("refine"):
        lines.append(f"The caregiver asked to revise \"{i['refine'][0]}\" with: \"{i['refine'][1]}\"")
    lines.append(f"Generated sentence: \"{output}\"")
    return _rubric("sentence", {"stage": _stage(i["stage"]), "context": "\n".join(lines)})


def escalation_request(case: dict, ladder: list[str]) -> str:
    i = case["input"]
    return _rubric("escalation", {
        "tiles": _tiles(i["tiles"]),
        "stage": _stage(i["stage"]),
        "ladder": "\n".join(f"[{n}] \"{s}\"" for n, s in enumerate(ladder)),
        "pairs": str(max(len(ladder) - 1, 0)),
    })


def authoring_request(case: dict, summary: dict) -> str:
    i, surface = case["input"], case["surface"]
    classes = prompts.word_classes()
    tiles = []
    for k in dict.fromkeys(summary["keys"]):
        if k in summary["new_words"]:
            w = summary["new_words"][k]
            tiles.append(f"{w.get('displayName') or k} ({w.get('wordClass')}) [new]")
        else:
            tiles.append(f"{k} ({classes.get(k, '?')})")
    if surface == "scene_generate":
        task = f"The request (a whole activity scene): \"{i['description']}\""
    elif surface == "page_generate":
        task = f"The request (one page named \"{i['page_name']}\"): \"{i['goal']}\""
    elif surface == "tile_suggest":
        task = f"The request (tiles for one topical page): \"{i['goal']}\""
    else:
        current = ", ".join(t.get("displayName") or t["key"] for t in i["current"])
        task = (f"This is a REFINE. The board already had: {current}.\n"
                f"The caregiver's instruction: \"{i['instruction']}\". The result should apply only that "
                f"change, keep the existing tiles unless told to remove them, and infer the obvious related items.")
    core_rule = ("So this set should NOT repeat those generic core words; it is only the activity's own vocabulary."
                 if surface in ("scene_generate", "scene_refine") else
                 "Core words may appear here when they are central to the request.")
    return _rubric("authoring", {"task": task, "core_rule": core_rule,
                                 "count": str(len(tiles)), "tiles": "\n".join(tiles)})


def topic_words_request(case: dict, summary: dict) -> str:
    def line(k: str) -> str:
        info = summary["words"][k]
        label = (summary["new_words"].get(k) or {}).get("displayName") or k.replace("_", " ")
        return f"{label} ({info.get('pos')}){' [new]' if info.get('new') else ''}"
    frame = prompts.FRAMES[case["input"].get("template", "home")]
    return _rubric("topic_words", {
        "budget": str(prompts.TOPIC_BUDGET),
        "description": f'"{case["input"]["description"]}"' + (
            f' — a page added to the scene "{sc["name"]}" ({sc["description"]}), whose home page has: '
            + ", ".join(w.replace("_", " ") for w in sc.get("words", []))
            + ". The page should be about the scene's version of its topic."
            if (sc := case["input"].get("scene")) else ""),
        "where": ("the HOME PAGE of a scene. The page also has a fixed frame of core words the model was told "
                  "not to repeat: " + ", ".join(w.replace("_", " ") for w in frame) + ". Don't count those as missing.")
                 if frame else "a page of its own (no frame), linked from the child's board.",
        "page_count": str(len(summary["page"])),
        "page": "\n".join(f"{n}. {line(k)}" for n, k in enumerate(summary["page"], 1)) or "(none)",
        "overflow_count": str(len(summary["overflow"])),
        "overflow": "\n".join(line(k) for k in summary["overflow"]) or "(none)",
    })


# MARK: - Calling the judge

def judge(prompt: str, model: str, effort: str | None, n: int = 1) -> dict:
    """Ask `n` times; median each score. Returns {"scores", "reasons", "flags",
    "extra", "samples", "cost", "errors"}."""
    body, _ = models.adapt({"model": model, "messages": [{"role": "user", "content": prompt}],
                            "max_tokens": 900, "response_format": {"type": "json_object"}}, model, effort)
    samples, errors, spent = [], [], 0.0
    for _ in range(n):
        r = client.call(body)
        spent += r["cost"]
        if r["error"]:
            errors.append(r["error"])
            continue
        parsed = scorers.extract_json(r["text"])
        if not parsed or not isinstance(parsed.get("scores"), dict):
            errors.append(f"unparseable judge reply: {r['text'][:200]}")
            continue
        samples.append(parsed)
    if not samples:
        return {"scores": {}, "reasons": {}, "flags": [], "extra": {}, "samples": [], "cost": spent,
                "errors": errors}
    dims = samples[0]["scores"].keys()
    scores = {d: statistics.median(s["scores"][d] for s in samples
                                   if isinstance(s["scores"].get(d), (int, float))) for d in dims}
    first = samples[0]
    extra = {k: v for k, v in first.items() if k not in ("scores", "reasons", "flags")}
    return {"scores": scores, "reasons": first.get("reasons", {}), "flags": first.get("flags", []),
            "extra": extra, "samples": samples, "cost": spent, "errors": errors}
