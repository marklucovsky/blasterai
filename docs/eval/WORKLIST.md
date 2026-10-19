<!-- SPDX-License-Identifier: Apache-2.0 -->
# Eval worklist — from rejects to fixes

The open work the eval has found, grouped by cause. Each row starts from the
45 rejects in the v0 review (`reviews/2026-10-19-1531-gpt-4o-mini-v0-rejudge.claude.json`,
confirmed by Mark in `….mark.json`: 114 of 115 agreed). A fix lands as one
commit per prompt revision; its run goes in `runs/`, its review in `reviews/`,
and the row's status changes here. A row is done when its cases pass review
and the regression sample hasn't moved.

Run the cases for a row with `--cases` (substrings of ids) and `--no-judge`
while iterating; compare with `build_review.py <new> --compare <v0>`.

Case ids renamed since v0 (one tile never generates — see `cases/README.md`):
`chocolate` → `want_chocolate`, `chocolate_IV` → `want_chocolate_IV`.

## Sentences — `prompt_*` and `sentence_prompt.json`

| # | Cause | Cases | Likely root cause | Planned fix | Status |
|---|---|---|---|---|---|
| S1 | **pronoun-as-address** (6) | she_pool, her_pool, she_pizza, he_find_raptor, she_pool_IV, escalation/she_pool | he/she/they/we are `people` in vocabulary.json, and the prompt says `(people)` = who the child talks TO | Prompt: a subject-pronoun rule (pronoun = who the sentence is about; him/her for he/she). Consider a `pronoun` word class (data change, own PR). | open |
| S2 | **report-as-command** (2) | him_hit_me ("Him, hit me!"), dog_bite_me ("Dog, bite me!") | Same addressee rule applied to a pronoun and an animal; no rule that events are reported | Prompt: reports stay reports (hit, bite, hurt → "He hit me", "The dog bit me"); animals are not addressed | open |
| S3 | **negation-lost** (1) | not_want_milk | `not (describe)` reads as an adjective | Prompt: no / not / don't must survive and flip the meaning | open |
| S4 | **refusal-reversed** (1) | no_house ("No, I want to go home") | No refusal rule | Prompt: "no" + a thing or place refuses it (Aubrey: no, bed / no, home) | open |
| S5 | question-form (1) | where_mom ('"Mom, where?"') | Question words treated as tags; quotes in output | Prompt: a question word makes a full question; never wrap output in quotes | open |
| S6 | tense (1) | yesterday_park_play (II-III) | Time words ignored at II-III | Prompt: yesterday → past, tomorrow / later → future | open |
| S7 | odd-reading (3) | later_tv, tomorrow_pool, he_raptor | Time words and pronoun + animal | Mostly S1 and S6; re-check after them | open |
| S8 | want-forced (1) | i_bus_school | Self-centred-want rule over-applies to routines | Prompt: not every selection is a want; routines and comments are statements | open |
| S9 | refine-ignored (1) | refine_shorter | Refine directive doesn't outrank the stage clause | `prompt_sentence_refine.txt`: the caregiver's instruction wins | open |
| S10 | grammar-minor (3) | i_like_dog, orange_food, no_bed | Articles and plurals dropped | Prompt: natural articles / plurals; may clear with S4 for no_bed | open |

## Escalation — `prompt_sentence_escalation.txt`

| # | Cause | Cases | Likely root cause | Planned fix | Status |
|---|---|---|---|---|---|
| E1 | **escalation-flat** (4) | mom_hungry, watch_tv, go_house, want_chocolate_IV | The ladder runs out of words at rung 3+; the model leans on caps, or falls back to calm | Ladder gives new *words* per rung (need → right now → please, please → I can't wait); never drop an intensifier already used | open |
| E2 | escalation-drift (1) | where_mom | A question has no escalation pattern | A question escalates as a more urgent question ("Where is Mom? I need Mom!") | open |

## Generation — `prompt_scene_*`, `prompt_page_*`, `prompt_tile_suggest_*`

| # | Cause | Cases | Likely root cause | Planned fix | Status |
|---|---|---|---|---|---|
| G1 | **new-words-undeclared** (4) | scene/swimming (9 of 17 lost), scene/grocery_store (11 of 21), page/playground (sandbox), suggest/beach (sand) | The model places new words without declaring them in `newWords`; the app's sanitizer drops undeclared keys silently | Prompt reinforcement **and** an app fix: keep an undeclared key as a proposed new word (class from the model or "object") instead of dropping it — Swift change, own commit | open |
| G2 | **scene-thin** (7) | potty_training (7), dentist (8), birthday (9), morning_circle, bedtime (5), sensory_break (4), pancakes_long (9) | "Brainstorm 20–30" is buried; single-page + stay-topical rules dominate | Prompt: a minimum tile count up front; name what to include (people-roles, actions at the heart, describing words) | open |
| G3 | **refusal-missing** (1) | scene/shooting_range | Rule 0 ignored | Prompt: refusal rule restated next to the output schema; Tier-1 already checks it. Defence in depth: new words still pass moderation | open |
| G4 | core-leak (1) | scene/church (+ bathroom / help / dad / happy elsewhere) | Rule 2 loses to world inference | Prompt: explicit never-include list | open |
| G5 | scene-precision (3) | scene/hospital_stay, page/potty, suggest/doctor_visit | Duplicates, unrequested symptoms, junk tiles ("social", "goodbye"); tile suggestions see the unfiltered vocabulary | Prompt; and filter structural tiles from the suggestion vocabulary like the other generators (Swift) | open |
| G6 | refine-missed-ask (3) | scene_refine/farm_add_pond, potty_add_bath, zoo_only_animals | The named thing itself is skipped in favour of related items | Refine prompt: the thing named in the instruction is always included (or removed) first | open |

## Moderation — `prompt_moderation_rubric_system.txt`

| # | Cause | Cases | Likely root cause | Planned fix | Status |
|---|---|---|---|---|---|
| M1 | moderation-overblock (1) | moderation/borderline | Rubric lists "graphic violence" and has no "report words" category | Rubric: words a child needs to report harm or feelings (fight, punch, blood, hate, hurt) are "questionable" (flagged, caregiver's choice), not blocked. Decided by Mark 2026-10-19 | open |
| M2 | tiers 1–2 not covered | — | The eval runs only the rubric tier | Add the local lists and omni-moderation to the moderation surface | open |

## Data found by the cases (not prompt fixes)

| # | What | Status |
|---|---|---|
| D1 | `school` and `toilet` filed as `social`; `home` as `navigation`; `bowl` as `actions`; pronouns as `people` | open — vocabulary PR (session 14 vocabulary work, or with S1) |
| D2 | `SentencePromptBuilder.hardcodedFallback` is a stale copy of `sentence_prompt.json` | open |
| D3 | The word-class rule is stated twice in the sentence prompt | open — fold into the S-series rewrite |
