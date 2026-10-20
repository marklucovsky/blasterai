# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Each Tier-1 check fires on the output it exists for, and stays quiet on a
good one. Offline and free.

    python3 -m unittest discover -s tools/eval -p 'test_*.py'

The bad outputs here are real ones from boards, not invented: a check that
can't catch its own motivating example is not a check.
"""
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import models  # noqa: E402
import scorers as S  # noqa: E402


def tiles(*spec):
    return [{"value": v, "wordClass": c} for v, c in (s.split(":") for s in spec)]


MOM_WANT_EAT_PIZZA = tiles("mom:people", "want:actions", "eat:actions", "pizza:food")
SHE_POOL = tiles("she:people", "pool:places")


class SentenceChecks(unittest.TestCase):
    def test_tile_list_read_back(self):
        # App Store sentence shot, 2026-10-16.
        issues = S.score_sentence("I want mom, want, eat, and pizza", MOM_WANT_EAT_PIZZA, "II-III")
        self.assertIn("tile list read back instead of a sentence", issues)
        self.assertIn("'want' tile doubled into the frame", issues)

    def test_good_request_passes(self):
        self.assertEqual(S.score_sentence("Mom, can I have some pizza please?", MOM_WANT_EAT_PIZZA, "II-III"), [])

    def test_pronoun_turned_into_address(self):
        # Build 7, 2026-10-15.
        issues = S.score_sentence("She, I want to go to the pool", SHE_POOL, "II-III")
        self.assertIn("chosen subject 'she' turned into a form of address", issues)
        self.assertEqual(S.score_sentence("She wants to go to the pool.", SHE_POOL, "II-III"), [])
        # Smoke run 2026-10-19, Stage IV+.
        self.assertIn("chosen subject 'she' turned into a form of address",
                      S.score_sentence("She, can we go to the pool?", SHE_POOL, "IV+"))

    def test_addressing_a_person_is_fine(self):
        self.assertEqual(S.score_sentence("Mom, I am tired.", tiles("mom:people", "tired:feeling"), "II-III"), [])

    def test_word_class_echo(self):
        self.assertIn("word-class annotation leaked into the sentence",
                      S.score_sentence("I want snack bar (food).", tiles("snack bar:food"), "II-III"))

    def test_raw_echo_only_at_stage_four(self):
        t = tiles("dad:people", "help:actions")
        self.assertEqual(S.score_sentence("Dad, help!", t, "II-III"), [])
        self.assertIn("raw echo of the tiles", S.score_sentence("Dad, help!", t, "IV+"))

    def test_degenerate(self):
        self.assertEqual(S.score_sentence(" ?! ", SHE_POOL, "II-III"), ["empty or degenerate output"])

    def test_expectations(self):
        e = {"must_include": [["slide", "slides"]], "must_not_include": ["go"], "question": True,
             "subject": "I", "max_words": 6}
        good = S.expectation_issues("Can I play on the slide?", e)
        self.assertEqual(good, [])
        bad = S.expectation_issues("I want to go to the park now please dad.", e)
        self.assertIn("missing 'slide / slides'", bad)
        self.assertIn("contains 'go'", bad)
        self.assertIn("not a question", bad)
        self.assertIn("10 words, over 6", bad)

    def test_negation(self):
        self.assertEqual(S.expectation_issues("I don't want carrots.", {"negation": True}), [])
        self.assertEqual(S.expectation_issues("I want carrots.", {"negation": True}), ["negation lost"])

    def test_subject_is_a_whole_word(self):
        self.assertEqual(S.expectation_issues("He hit me.", {"subject": "he"}), [])
        self.assertEqual(S.expectation_issues("The dog is here.", {"subject": "he"}), ["subject 'he' missing"])


class EscalationChecks(unittest.TestCase):
    def test_flat_ladder(self):
        # The 2026-06-20 baseline, before the escalation fix.
        _, issues = S.score_escalation(["I want chocolate!"] * 4, tiles("chocolate:food"), "II-III")
        self.assertTrue(any("no escalation" in i for i in issues))

    def test_regressing_rung(self):
        ladder = ["I want to go home.", "I want to go home now!", "I want to go home!"]
        _, issues = S.score_escalation(ladder, tiles("go:actions", "home:places"), "II-III")
        self.assertTrue(any("rung 2 less insistent" in i for i in issues))

    def test_climbing_ladder_passes(self):
        ladder = ["Can I have chocolate?", "I really want chocolate now.", "I NEED CHOCOLATE NOW!!!"]
        _, issues = S.score_escalation(ladder, tiles("chocolate:food"), "II-III")
        self.assertEqual(issues, [])


def scene(tiles_, new_words=()):
    return json.dumps({"name": "x", "description": "x", "homePageKey": "p",
                       "newWords": [{"key": k, "displayName": k, "wordClass": c} for k, c in new_words],
                       "pages": [{"key": "p", "tiles": [{"key": k, "isAudible": True, "link": ""} for k in tiles_]}]})


class AuthoringChecks(unittest.TestCase):
    def test_not_json(self):
        self.assertEqual(S.score_authoring("scene_generate", "Here are some ideas: potty, pee")[1],
                         ["output is not valid JSON"])

    def test_undeclared_and_unused_new_words(self):
        out = scene(["toilet", "zzpotty_chair"], new_words=[("wipe", "object")])
        _, issues = S.score_authoring("scene_generate", out)
        self.assertTrue(any("undeclared key" in i and "zzpotty_chair" in i for i in issues))
        self.assertTrue(any("declared but not placed: wipe" in i for i in issues))

    def test_core_leak_on_scenes_only(self):
        out = scene(["toilet", "mom", "yes"])
        self.assertTrue(any("core-board" in i for i in S.score_authoring("scene_generate", out)[1]))

    def test_required_words_tolerate_plural(self):
        out = scene(["toilet", "zzwipes"], new_words=[("zzwipes", "object")])
        _, issues = S.score_authoring("scene_generate", out, {"must_include_keys": ["zzwipe", ["zzflush", "flush"]]})
        self.assertEqual(issues, ["missing 'zzflush / flush'"])

    def test_bad_class_and_shadowing(self):
        out = scene(["zzthing", "toilet"], new_words=[("zzthing", "stuff"), ("toilet", "object")])
        summary, issues = S.score_authoring("scene_generate", out)
        self.assertTrue(any("unknown wordClass: zzthing" in i for i in issues))
        # Harmless in the app (the existing word wins), so a note, not a failure.
        self.assertFalse(any("already in vocabulary" in i for i in issues))
        self.assertTrue(any("already in vocabulary" in n and "toilet" in n for n in summary["notes"]))

    def test_refine_keeps_current_tiles(self):
        out = scene(["bath"], new_words=[])
        _, issues = S.score_authoring("scene_refine", out, {}, current=[{"key": "toilet"}, {"key": "bath"}])
        self.assertTrue(any("dropped current tile(s) it was not asked to: toilet" in i for i in issues))

    def test_refine_carried_new_words_are_declared(self):
        # Smoke run 2026-10-19: barn/hay/tractor came back undeclared, but the
        # app carries a refine's proposed words forward, so they are not dropped.
        out = scene(["cow", "barn", "zzpond"], new_words=[("zzpond", "places")])
        current = [{"key": "cow"}, {"key": "barn", "displayName": "barn"}]
        _, issues = S.score_authoring("scene_refine", out, {}, current=current)
        self.assertEqual(issues, [])

    def test_keys_normalized_like_the_app(self):
        out = json.dumps({"pages": [{"key": "p", "tiles": [{"key": "Toilet"}, {"key": "zz Potty Chair"}]}],
                          "newWords": [{"key": "zz potty chair", "displayName": "potty chair", "wordClass": "object"}]})
        summary, issues = S.score_authoring("scene_generate", out)
        self.assertEqual(summary["keys"], ["toilet", "zz_potty_chair"])
        self.assertEqual(issues, [])

    def test_refusal(self):
        refused = json.dumps({"name": "x", "description": "Let's pick a different topic", "pages": []})
        self.assertEqual(S.score_authoring("scene_generate", refused, {"refused": True})[1], [])
        self.assertTrue(S.score_authoring("scene_generate", scene(["toilet"]), {"refused": True})[1])

    def test_bare_string_tiles_accepted(self):
        out = json.dumps({"pages": [{"key": "p", "tiles": ["toilet", {"key": "bath"}]}]})
        self.assertEqual(S.score_authoring("scene_generate", out)[0]["keys"], ["toilet", "bath"])

    def test_suggestions_shape(self):
        out = json.dumps({"keys": ["toilet", "zzpotty"], "newWords": [{"key": "zzpotty", "displayName": "potty",
                                                                      "wordClass": "object"}]})
        self.assertEqual(S.score_authoring("tile_suggest", out)[1], [])

    def test_suggestion_keys_normalized(self):
        # v0 run 2026-10-19: "T-rex" in keys, "t-rex" in newWords — the app matches them.
        out = json.dumps({"keys": ["T-rex"], "newWords": [{"key": "t-rex", "displayName": "T-rex",
                                                           "wordClass": "animal"}]})
        self.assertEqual(S.score_authoring("tile_suggest", out)[1], [])


class ModerationChecks(unittest.TestCase):
    def test_missing_rating_fails_open(self):
        ratings, issues = S.score_moderation('{"ratings": {"puppy": "appropriate"}}', ["puppy", "beer"])
        self.assertTrue(ratings["beer"].startswith("appropriate"))
        self.assertEqual(issues, ["no rating for 'beer'"])

    def test_expected_rating(self):
        _, issues = S.score_moderation('{"ratings": {"beer": "appropriate"}}', ["beer"],
                                       {"ratings": {"beer": "inappropriate"}})
        self.assertEqual(issues, ["'beer' rated appropriate, expected inappropriate"])


class ModelAdaptation(unittest.TestCase):
    BODY = {"model": "gpt-4o-mini", "temperature": 0.3, "max_tokens": 500, "messages": []}

    def test_4o_mini_unchanged(self):
        self.assertEqual(models.adapt(self.BODY, "gpt-4o-mini"), (self.BODY, []))

    def test_luna_drops_temperature(self):
        body, changes = models.adapt(self.BODY, "gpt-6-luna")
        self.assertNotIn("temperature", body)
        self.assertEqual(body["reasoning_effort"], "none")
        self.assertEqual(body["max_completion_tokens"], 500)
        self.assertTrue(any("dropped temperature" in c for c in changes))

    def test_sol_rejects_none(self):
        with self.assertRaises(SystemExit):
            models.adapt(self.BODY, "gpt-6.1-sol", "none")

    def test_cost_counts_cache(self):
        usage = {"prompt_tokens": 2000, "completion_tokens": 100,
                 "prompt_tokens_details": {"cached_tokens": 1000, "cache_write_tokens": 500}}
        expected = (500 * 0.10 + 1000 * 0.01 + 500 * 0.125 + 100 * 0.50) / 1e6
        self.assertAlmostEqual(models.cost("gpt-6-luna", usage), expected)


class HeldOutCases(unittest.TestCase):
    """A prompt example that is also an eval case teaches to the test: the case
    passes because the answer is in the prompt, and proves nothing about the
    selections families actually make. Prompt examples use other words."""

    def test_sentence_prompt_examples_are_not_cases(self):
        import re
        root = Path(__file__).resolve().parents[2]
        messages = json.loads((root / "claudeBlast/Resources/sentence_prompt.json").read_text())
        text = " ".join(messages) + " ".join(p.read_text() for p in (root / "claudeBlast/Resources/Prompts").glob("prompt_sentence_*.txt"))
        examples = {m.lower() for m in re.findall(r'"([A-Za-z ]+(?:, [A-Za-z ]+)+)"', text)}
        cases = []
        for name in ("sentence", "escalation"):
            cases += json.loads((Path(__file__).resolve().parent / "cases" / f"{name}.json").read_text())
        selections = {", ".join(t.rsplit(":", 1)[0].lower() for t in c["input"]["tiles"]) for c in cases}
        self.assertTrue(examples, "found no examples in the prompt — the pattern is broken")
        self.assertEqual(sorted(examples & selections), [])


if __name__ == "__main__":
    unittest.main()
