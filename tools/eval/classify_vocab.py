# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""How well does the moderation rubric classify words? Scored against the
hand-classified bundled vocabulary.

Sends the bundled words (those whose class a model may give — not core,
navigation, question or folder words) through a rubric prompt that also asks
for a class, in batches the size the app might send, and compares each answer
with `vocabulary.json`. Prints accuracy overall and by class, and the most
common confusions.

    OPENAI_API_KEY=… python3 tools/eval/classify_vocab.py [--batch 20] [--limit N] [--out rows.json]

The prompt is the app's own (`prompt_moderation_rubric_system.txt`), the
request is `prompts.moderation_rubric_body` — exactly what the app sends.

First runs, 2026-11-08, gpt-6-luna, 951 words: 85.4% of classes matched the
hand labels (91.7% the same colour); with the "More on choosing" guidance,
88.9% (93.7%). Most remaining misses are labels a person could argue either
way (help: actions or social; soap: object or health).
"""
import argparse
import json
import random
import sys
from collections import Counter, defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import client  # noqa: E402
import models  # noqa: E402
import prompts  # noqa: E402

MODEL = prompts.APP_MODELS.get("word_audit", "gpt-6-luna")


def default_parts() -> dict[str, str | None]:
    """Class → its default part of speech: the colour a new word of that class draws."""
    data = json.loads((prompts.RESOURCES / "word_classes.json").read_text())
    classes = data if isinstance(data, list) else data.get("classes", data)
    return {c["name"]: c.get("partOfSpeech") for c in classes}


def words_to_score() -> list[tuple[str, str]]:
    vocab = json.loads((prompts.RESOURCES / "vocabulary.json").read_text())
    allowed = set(prompts.app_inputs()["class_list"].split(", "))
    out = []
    for w in vocab:
        if w["wordClass"] not in allowed:
            continue
        name = w.get("label") or w["key"].replace("_", " ")
        out.append((name, w["wordClass"]))
    return out


def classify(batch: list[str]) -> dict[str, str]:
    body, _ = models.adapt(prompts.moderation_rubric_body(batch), MODEL)
    r = client.call(body)
    if r["error"]:
        print("error:", r["error"], file=sys.stderr)
        return {}
    text = r["text"]
    try:
        payload = json.loads(text[text.index("{"):])
    except (ValueError, json.JSONDecodeError):
        print("unparseable:", text[:200], file=sys.stderr)
        return {}
    return {k: str(v).lower() for k, v in (payload.get("classes") or {}).items()}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--batch", type=int, default=20)
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    words = words_to_score()
    random.Random(args.seed).shuffle(words)
    if args.limit:
        words = words[:args.limit]
    truth = dict(words)
    batches = [[w for w, _ in words[i:i + args.batch]] for i in range(0, len(words), args.batch)]
    with ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(classify, batches))
    got = {}
    for r in results:
        got.update(r)

    per = defaultdict(lambda: [0, 0])
    confusions = Counter()
    rows = []
    missing = 0
    for word, cls in words:
        answer = got.get(word)
        if answer is None:
            missing += 1
            continue
        per[cls][1] += 1
        if answer == cls:
            per[cls][0] += 1
        else:
            confusions[(cls, answer)] += 1
        rows.append({"word": word, "hand": cls, "model": answer})
    scored = sum(t for _, t in per.values())
    right = sum(r for r, _ in per.values())
    print(f"model {MODEL} · {len(words)} words · batch {args.batch} · missing {missing}")
    parts = default_parts()
    same_colour = sum(parts.get(x["hand"]) == parts.get(x["model"]) for x in rows)
    invalid = Counter(x["model"] for x in rows if x["model"] not in parts)
    print(f"accuracy {right}/{scored} = {right / max(scored, 1):.1%}"
          f" · same colour {same_colour / max(len(rows), 1):.1%}"
          f" · not a class {sum(invalid.values())} {dict(invalid)}\n")
    print("by class (hand label):")
    for cls, (r, t) in sorted(per.items(), key=lambda kv: kv[1][0] / kv[1][1]):
        print(f"  {cls:10} {r:3}/{t:<3} {r / t:6.1%}")
    print("\nmost common confusions (hand → model):")
    for (a, b), n in confusions.most_common(25):
        examples = [x["word"] for x in rows if x["hand"] == a and x["model"] == b][:6]
        print(f"  {a:9} → {b:9} {n:3}  {', '.join(examples)}")
    if args.out:
        Path(args.out).write_text(json.dumps(rows, indent=1))


if __name__ == "__main__":
    main()
