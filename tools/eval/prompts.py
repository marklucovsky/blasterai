# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Render the app's chat-completions requests in Python, exactly as Swift does.

The prose comes from the same files the app ships — `claudeBlast/Resources/
Prompts/prompt_*.txt`, `prompt_stages.json` and `sentence_prompt.json` — and the
values the app derives in code (class list, vocabulary blocks) come from
`claudeBlastTests/Fixtures/prompts/_inputs.json`, which `PromptFixtureTests`
keeps current. What is left here is assembly: which template, which values,
which message order, which sampling settings.

That assembly is a copy of Swift logic, so it can drift. It can't drift
silently: `check_prompt_parity.py` renders the cases `PromptFixtureTests` pins
and fails on any difference. Run it after touching either side.

Each `*_body` function mirrors one Swift `requestBody`:

    sentence_body          OpenAISentenceProvider.requestBody (+ SentenceEngine assembly)
    scene_generate_body    SceneGeneratorService.requestBody
    scene_refine_body      SceneRefinerService.requestBody
    page_generate_body     PageGeneratorService.requestBody
    page_refine_body       PageGeneratorService.refineRequestBody
    tile_suggest_body      TileSuggestionService.requestBody
    moderation_rubric_body WordModerationService.rubricRequestBody

    topic_words_body       TopicWordsService.requestBody — ranked words for
                           any page: a scene's home page (with the frame) or
                           a leaf page (without); docs/eval/scenes.md

and one the app doesn't ship, in tools/eval/candidates/:

    topic_review_body      a second pass over a topic page's first draft
"""
import json
from functools import cache
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROMPTS = ROOT / "claudeBlast/Resources/Prompts"
RESOURCES = ROOT / "claudeBlast/Resources"
FIXTURES = ROOT / "claudeBlastTests/Fixtures/prompts"
CANDIDATES = Path(__file__).resolve().parent / "candidates"

# The model each job ships with — mirrors `ModelID` in ModelPricing.swift. The
# `*_body` functions still render the gpt-4o-mini shape (temperature,
# max_tokens), which is what `run.py` adapts to any `--model`; check_prompt_parity
# adapts it to the job's own model, which is what the app sends, and compares
# that with the fixtures — so a ModelID change on one side only fails it.
APP_MODELS = {
    "sentence": "gpt-6-luna",
    "scene_authoring": "gpt-6.1-sol",
    "tile_suggest": "gpt-6.1-sol",
    "word_audit": "gpt-6-luna",
}


# MARK: - Templates (mirrors PromptTemplate.swift)

# Read once per process: a run renders requests as it goes, so without this an
# edit made while a run is in flight would split it across two prompts
# (2026-10-20: 40 of 72 outputs of a Luna run).
@cache
def raw(name: str, folder: Path = PROMPTS) -> str:
    text = (folder / f"prompt_{name}.txt").read_text(encoding="utf-8")
    return text[:-1] if text.endswith("\n") else text


def render(name: str, values: dict[str, str] | None = None, folder: Path = PROMPTS) -> str:
    text = raw(name, folder)
    for key, value in (values or {}).items():
        token = "{{" + key + "}}"
        if token not in text:
            raise ValueError(f"prompt_{name}: unused value {key}")
        text = text.replace(token, value)
    if "{{" in text:
        raise ValueError(f"prompt_{name}: unfilled placeholder")
    return text


@cache
def stages() -> dict[str, str]:
    return json.loads((PROMPTS / "prompt_stages.json").read_text(encoding="utf-8"))


@cache
def sentence_base() -> list[str]:
    return json.loads((RESOURCES / "sentence_prompt.json").read_text(encoding="utf-8"))


@cache
def app_inputs() -> dict:
    return json.loads((FIXTURES / "_inputs.json").read_text(encoding="utf-8"))


@cache
def word_classes() -> dict[str, str]:
    """Bundled vocabulary key → wordClass, for the page scene listing."""
    vocab = json.loads((RESOURCES / "vocabulary.json").read_text(encoding="utf-8"))
    out: dict[str, str] = {}
    for t in vocab:
        out.setdefault(t["key"], t["wordClass"])
    return out


def _chat(model: str, temperature: float, messages: list[dict], max_tokens: int | None) -> dict:
    body = {"model": model, "temperature": temperature, "messages": messages}
    if max_tokens is not None:
        body["max_tokens"] = max_tokens
    return body


def _two(system: str, user: str) -> list[dict]:
    return [{"role": "system", "content": system}, {"role": "user", "content": user}]


def _class_values() -> dict[str, str]:
    i = app_inputs()
    return {"class_list": i["class_list"], "class_guidance": i["class_guidance"]}


def _listing(tiles: list[dict]) -> str:
    """`key — what it shows`, one per line (the refine prompts' current tiles).
    A tile is {"key", optional "displayName"}."""
    return "\n".join(
        f"{t['key']} — {t.get('displayName') or t['key'].replace('_', ' ')}" for t in tiles)


# MARK: - Sentences

TOP_RUNG = 3  # SentencePromptBuilder.topRung

def sentence_body(stage: str, tiles: list[dict], history: list[str] = (),
                  repetition: int = 0, prior: str | None = None,
                  refine: tuple[str, str] | None = None) -> dict:
    """`tiles` are {"value", "wordClass"}. `refine` is (original, instruction).
    `prior` is the sentence an escalation climbs from (used only when
    repetition > 0, as SentenceEngine does)."""
    escalating = repetition > 0
    descriptor = stages()[stage + ("/escalating" if escalating else "")]
    base = sentence_base()
    system = [m.replace("{stage}", descriptor) for m in base]
    system.append(raw("sentence_category_rule"))
    if escalating:
        system.append(render("sentence_escalation", {"count": str(repetition), "previous": prior or ""}))
    if refine and refine[1].strip():
        system.append(render("sentence_refine", {"previous": refine[0], "instruction": refine[1]}))

    # SentencePromptBuilder.formatUserPrompt, then .context
    user_prompt = ", ".join(f"{t['value']} ({t['wordClass']})" for t in tiles)
    if escalating:
        note = "sentence_escalation_hold" if repetition > TOP_RUNG else "sentence_escalation_note"
        user_prompt += "\n" + render(note, {"count": str(repetition)})
    context = list(history)
    if escalating and prior is not None:
        context.append(prior)
    if refine and refine[0].strip():
        context.append(refine[0])
    context.append(user_prompt)

    # OpenAISentenceProvider.requestBody: context entries are assistant turns,
    # and the last one is replaced by the user turn.
    messages = [{"role": "system", "content": s} for s in system]
    messages += [{"role": "assistant", "content": c} for c in context]
    messages[-1] = {"role": "user", "content": user_prompt}
    return _chat("gpt-4o-mini", 0.3, messages, 500)


# MARK: - Authoring

def scene_generate_body(description: str) -> dict:
    system = render("scene_generate_system", _class_values())
    user = render("scene_generate_user",
                  {"description": description, "vocab_block": app_inputs()["vocab_block"]})
    return _chat("gpt-4o-mini", 0.5, _two(system, user), 3000)


def scene_refine_body(instruction: str, current_topical: list[dict]) -> dict:
    system = render("scene_refine_system", {"current_tiles": _listing(current_topical), **_class_values()})
    user = render("scene_refine_user",
                  {"instruction": instruction, "vocab_block": app_inputs()["vocab_block"]})
    return _chat("gpt-4o-mini", 0.5, _two(system, user), 3000)


def _page_user(goal: str, page_name: str, scene_pages: list[dict], home_page_key: str) -> str:
    """`scene_pages` are {"key", "tiles": [key, ...]}."""
    classes = word_classes()
    block = "\n".join(
        f"page '{p['key']}'{' [home]' if p['key'] == home_page_key else ''}: "
        + ", ".join(f"{k} ({classes.get(k, '?')})" for k in p["tiles"])
        for p in scene_pages)
    section = f"\nCurrent scene (existing pages and their tiles):\n{block}\n" if block else ""
    return render("page_user", {"page_name": page_name, "goal": goal, "scene_section": section,
                                "vocab_block": app_inputs()["vocab_block"]})


def page_generate_body(goal: str, page_name: str, scene_pages: list[dict] = (),
                       home_page_key: str = "") -> dict:
    system = render("page_generate_system", {"class_list": app_inputs()["class_list"]})
    return _chat("gpt-4o-mini", 0.4,
                 _two(system, _page_user(goal, page_name, list(scene_pages), home_page_key)), 800)


def page_refine_body(instruction: str, page_name: str, current_tiles: list[dict],
                     scene_pages: list[dict] = (), home_page_key: str = "") -> dict:
    system = render("page_refine_system", {"current_tiles": _listing(current_tiles), **_class_values()})
    return _chat("gpt-4o-mini", 0.4,
                 _two(system, _page_user(instruction, page_name, list(scene_pages), home_page_key)), 800)


def tile_suggest_body(goal: str) -> dict:
    system = render("tile_suggest_system", _class_values())
    # Unlike the other generators, suggestions list the vocabulary unfiltered.
    user = render("tile_suggest_user", {"goal": goal, "vocab_block": app_inputs()["vocab_block_all"]})
    return _chat("gpt-4o-mini", 0.4, _two(system, user), 700)


def moderation_rubric_body(words: list[str]) -> dict:
    return _chat("gpt-4o-mini", 0, _two(raw("moderation_rubric_system"), ", ".join(words)), None)


# MARK: - Topic words (TopicWordsService)

# One prompt for every page (Mark, 2026-10-20): the words are the same kind
# for a scene's home page and a leaf page; the template differs, and is code.
# The home template's frame (docs/eval/scenes.md) is BlasterAI 60's level-1
# words minus the three that are folders on its home; a leaf page has none.
FRAMES = {"home": ["i", "you", "want", "more", "go", "stop", "help", "yes", "no", "all_done"], "leaf": []}
TOPIC_BUDGET = 25
TOPIC_MAX = 32


def scene_context(scene: dict | None) -> str:
    """For a page added to an existing scene: the scene's name, the summary the
    model wrote when it made the scene (`BlasterScene.descriptionText`, which
    syncs — the caregiver's own prompt stays on the device), and its home
    page's words. Empty for a page that starts a scene."""
    if not scene:
        return ""
    words = ", ".join(w.replace("_", " ") for w in scene.get("words", []))
    return render("topic_scene_context", {"scene_name": scene["name"], "scene_description": scene["description"],
                                          "scene_words": words})


def topic_words_body(description: str, template: str = "home", scene: dict | None = None) -> dict:
    frame = FRAMES[template]
    exclude = ("\n\nThis page already has these words, always in the same place — never return them: "
               + ", ".join(w.replace("_", " ") for w in frame) + ".") if frame else ""
    system = render("topic_words_system", {
        "budget": str(TOPIC_BUDGET), "max_words": str(TOPIC_MAX),
        "class_list": app_inputs()["class_list"]})
    user = render("topic_words_user", {"description": description, "vocab_block": app_inputs()["vocab_block"],
                                       "exclude_rule": exclude, "scene_context": scene_context(scene)})
    return _chat("gpt-4o-mini", 0.5, _two(system, user), 3000)


# MARK: - Candidates (not in the app)

def topic_review_body(first: dict, draft_text: str, description: str) -> dict:
    """A second pass over the first draft (`first` is the first request):
    the same conversation, the draft as the assistant's turn, then a review."""
    draft = draft_text
    try:
        import scorers  # late: scorers imports prompts
        parsed = scorers.extract_json(draft_text) or {}
        words = [w.get("word") for w in parsed.get("words") or [] if isinstance(w, dict)]
        if words:
            draft = ", ".join(f"{n}. {w}" for n, w in enumerate(words, 1))
    except Exception:
        pass
    review = render("topic_review_user", {"description": description, "draft": draft,
                                          "budget": str(TOPIC_BUDGET)}, CANDIDATES)
    messages = first["messages"] + [{"role": "assistant", "content": draft_text},
                                    {"role": "user", "content": review}]
    return {**first, "messages": messages}
