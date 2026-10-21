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
| S1 | **pronoun-as-address** (6) | she_pool, her_pool, she_pizza, he_find_raptor, she_pool_IV, escalation/she_pool | he/she/they/we are `people` in vocabulary.json, and the prompt says `(people)` = who the child talks TO | Prompt: a subject-pronoun rule (pronoun = who the sentence is about; him/her for he/she). Consider a `pronoun` word class (data change, own PR). | **p1: fixed** on every sample ("She is at the pool.", "She wants pizza.", "He is finding a raptor."). Escalation side → E3 |
| S2 | **report-as-command** (2) | him_hit_me ("Him, hit me!"), dog_bite_me ("Dog, bite me!") | Same addressee rule applied to a pronoun and an animal; no rule that events are reported | Prompt: reports stay reports (hit, bite, hurt → "He hit me", "The dog bit me"); animals are not addressed | **p1: fixed** ("He hit me!", "The dog bit me!") |
| S3 | **negation-lost** (1) | not_want_milk | `not (describe)` reads as an adjective | Prompt: no / not / don't must survive and flip the meaning | **p1: fixed** ("I don't want to drink milk.") |
| S4 | **refusal-reversed** (1) | no_house ("No, I want to go home") | No refusal rule | Prompt: "no" + a thing or place refuses it (Aubrey: no, bed / no, home) | **p1: fixed** (no_house, no_bed, no_bed_no, no_bath all refuse) |
| S5 | question-form (1) | where_mom ('"Mom, where?"') | Question words treated as tags; quotes in output | Prompt: a question word makes a full question; never wrap output in quotes | **p1: fixed** ("Where is Mom?"). Mark (2026-10-20): that reading is the right one — the person isn't in the room; "Mom, where are you?" only fits a phone call. Rubric r2 says so; where_dad added; Tier-1 rejects "where are you". p4: 5/5 each |
| S6 | tense (1) | yesterday_park_play (II-III) | Time words ignored at II-III | Prompt: yesterday → past, tomorrow / later → future | **p1: fixed** — needed the exception inside the `(describe)` rule, because time words are filed as `describe` and that rule won |
| S7 | odd-reading (3) | later_tv, tomorrow_pool, he_raptor | Time words and pronoun + animal | Mostly S1 and S6; re-check after them | later_tv, tomorrow_pool **fixed in p1**; he_raptor ("He is a raptor!") **open** |
| S8 | want-forced (1) | i_bus_school | Self-centred-want rule over-applies to routines | Prompt: not every selection is a want; routines and comments are statements | **p1: fixed** ("I am on the bus to school.") — but carried by a leaked example ("i, walk, school"); with it held out, 4 of 5 said "I want the bus to school". **p4: fixed** by a general rule (a vehicle with a place says how the child travels there), 5/5. p4 side effect: tired_bed_II-III "Can I go to bed?" → "I want to go to bed." on 2 of 3, 9 words over the case's 8 — Mark to call |
| S9 | refine-ignored (1) | refine_shorter | Refine directive doesn't outrank the stage clause | `prompt_sentence_refine.txt`: the caregiver's instruction wins | **p1: 9 words.** Correction: the v0 reject was mistaken — the original was 15 words, so v0's 12 was already shorter; expectation now ≤10 |
| S10 | grammar-minor (3) | i_like_dog, orange_food, no_bed | Articles and plurals dropped | Prompt: natural articles / plurals; may clear with S4 for no_bed | **p1: fixed** ("I like dogs.", "an orange", "No! I don't want to go to bed.") |
| S11 | history-unused (new in p1 review) | history_more ("Please, I want more.") | — | Prompt: use the conversation for a bare "more" | open |

## Escalation — `prompt_sentence_escalation.txt`

| # | Cause | Cases | Likely root cause | Planned fix | Status |
|---|---|---|---|---|---|
| E1 | **escalation-flat** (4) | mom_hungry, watch_tv, go_house, want_chocolate_IV | The ladder runs out of words at rung 3+; the model leans on caps, or falls back to calm | Ladder gives new *words* per rung (need → right now → please, please → I can't wait); never drop an intensifier already used | **p2: fixed** — every ladder climbs in words to the top on 3/3 samples. Two causes, both needed: (1) the old ladder asked rung 3+ for capitals, which TTS can't voice; (2) positional — the directive sat above the conversation and the last turn read as a fresh request, so rungs snapped back to the calm wording. Fix: words-only ladder, the previous rung quoted in the directive, and a repeat note in the user turn |
| E4 | escalation-duplication (new in p2) | watch_tv #2 rung 4 | The ladder had no top: rung 4+ was told to "add another", so it stacked "I can't wait" or repeated the whole sentence | Mark (2026-10-19): "never do more than a single Please, please! I can't wait". Rung 3 is the top; from repeat #4 the user-turn note switches to a hold note (`prompt_sentence_escalation_hold.txt`, chosen by count in `SentencePromptBuilder.topRung`); each insisting phrase at most once. Tier-1: "insisting phrase stacked", and "rung N repeats rung N-1" below the top | **p3: fixed** — watch_tv rung 4 holds on 3/3; 0 of 30 stacked. Two dead ends on the way, kept for the next prompt change: (1) one note that said "hold if you're already at the top" let statements and questions stall at rung 2 — hence the note chosen by count; (2) a named bad example ("I need her to be at the pool" is wrong) primed exactly that sentence on she_pool — naming the failure made it more likely |
| E5 | escalation-formulaic (new in p2) | all want ladders | Every want ladder tops out "Please, please! I can't wait!" — audible but identical | Mark: fine, as long as it appears once (→ E4) | **closed** — accepted. Minor, not a failure: some rung 1s only add "!" (go_house, want_chocolate_IV) |
| E6 | refusal under escalation (new cases in p3) | no_home, no_bed | — | Cases added at Mark's request; `expect` now holds on every rung | **p3: passes** 10/10 — the no survives every rung, never flips to a want. Accepted by Mark. Minor: a sentence sometimes repeats its own clause; "I can't go to bed!" at the top; refusals borrow the want ladder (no refusal ladder of their own) → **p4: fixed** by E7 — refusals climb with more no's ("No, no, no! … Please, no!"), never by repeating the clause |
| E7 | ladder bleed (new in p3) | she_pool, where_mom, what_eat (new case), no_home, no_bed | One shared top ("Please, please! I can't wait!") pulled statements, questions and refusals onto the want ladder | Mark (2026-10-20): each kind gets a distinct top. The prompt makes the model pick ONE kind (want, statement, report, instruction, feeling, question, refusal) and climb only that ladder, by repeat count | **p4: fixed** — baseline 13 cases × 5, Mark approved 65/65, judge agrees 100%. Minor slips, accepted: where_mom borrows "Listen!" on 3/5; one doubled "Please, please!"; he_hit_me "It really happened!" for "hurt" once (Mark: acceptable) |
| E2 | escalation-drift (1) | where_mom | A question has no escalation pattern | A question escalates as a more urgent question ("Where is Mom? I need Mom!") | **p2: fixed** ("Where is Mom? I really need to know right now! Please, please!") |
| E3 | escalation-statement (new in p1) | she_pool, he_hit_me (new case) | With S1 fixed, rung 0 is a statement ("She is at the pool."), and the ladder had nothing to climb | Mark (2026-10-19): a repeated statement is about being HEARD, not a new want. Reports climb to asking for help | **p2: fixed** ("Listen to me! She IS at the pool, right now!"; "He hit me! It really hurt! Help me, please!") |

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
| D1 | `school` and `toilet` filed as `social`; `home` as `navigation`; `bowl` as `actions`; pronouns as `people` | **school, toilet, bathroom → `places`** (2026-10-20): as `social`, "school, i, bus" opened like a greeting ("School, I ride the bus.", 5/5) — Mark saw tap order change the sentence in the app. Now 5/5 "I go to school on the bus." in either order; cache v6. `home` was already split (`home` the button, `home_` the place). Open: `bowl` (verb and noun), pronouns, the folder tiles `social` / `places` filed as their own classes |
| D2 | `SentencePromptBuilder.hardcodedFallback` is a stale copy of `sentence_prompt.json` | open |
| D3 | The word-class rule is stated twice in the sentence prompt | p1: the duplicate "(people) is who the child is speaking TO" sentence removed from the MOST IMPORTANT rule; the rest stays |
| D4 | Time words (now, today, tomorrow, yesterday, later, again) are filed as `describe` | worked around in the prompt (p1); a `time` class would be cleaner — vocabulary PR |
| D5 | `object` is a junk drawer (43 words): 11 vehicles, 8 clothes, 7 time words (morning, night, week…), 5 folder tiles (animals, feelings, groups, things, vehicles) next to cup and spoon | Split by **sentence frame**, not by meaning: a class earns its place only if it changes how the sentence is built — `vehicle` (ride / go by: "I go to the store in the car"), `clothing` (wear / put on), `time` (when, with D4). Folder tiles → `navigation`. Then the p4 vehicle rule can go. Sense ambiguity (glasses to drink from vs to wear) is the concept key's job, not the class's: two keys, same label. Vocabulary PR, with cases for each new class |
