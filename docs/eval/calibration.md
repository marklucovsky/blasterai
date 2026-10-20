<!-- SPDX-License-Identifier: Apache-2.0 -->
# Judge calibration

Does the judge (`gpt-6.1-sol`, effort low) agree with the human verdicts? It
has to, before its scores can stand in for review on a model we haven't
labelled (Luna). Regenerate with:

    python3 tools/eval/calibrate.py docs/eval/runs/<judged runs with reviews>

Labels are `docs/eval/reviews/<run>.mark.json` over `<run>.claude.json`. A pass
is every score ≥ 4 and no escalation rung called "regresses".

## 2026-10-20 — sentence baseline, frozen

`runs/2026-10-20-1049-gpt-4o-mini-baseline-sentence`: 68 cases × 5 samples,
judge × 3, prompts `585b4e7282` (p4), rubrics `605e7a9d0a` (r2 with Mark's
where and length calls). Reviewed by Mark on the deduplicated page (75 cards):
330 approved, 10 rejected (he_raptor, history_more — both open in the
worklist), and he agreed with every one of Claude's 340 calls.

| Surface | Agree | Judge too strict | Judge too lenient | Agreement |
|---|---|---|---|---|
| sentence | 335 | 5 | 0 | **99%** |

The 5 are tv_stop ("I want to stop the TV."), a taste call we approve and the
judge scores naturalness 3 ("turn off the TV"). The judge passed nothing we
rejected. **This is the sentence baseline**: a later model or prompt is
compared with it by the judge, and re-reviewed only where they differ.

For the record, the shipping prompt (v0) says "No, I want my bed" for no, bed;
the baseline says "No! I don't want to go to bed." on every sample.

## 2026-10-19 — rubric r2

Labelled set: the v0, p1, p2, p3 and p3-refusal runs, 409 judged outputs
(moderation is checked by Tier-1, not judged).

| Surface | Agree | Judge too strict | Judge too lenient | Agreement |
|---|---|---|---|---|
| sentence | 258 | 9 | 1 | 96% |
| escalation | 95 | 11 | 0 | 90% |
| scene_generate | 12 | 2 | 0 | 86% |
| scene_refine | 4 | 2 | 0 | 67% |
| page_generate | 3 | 1 | 0 | 75% |
| page_refine | 3 | 0 | 0 | 100% |
| tile_suggest | 3 | 5 | 0 | 38% |
| **all** | 378 | 30 | 1 | **92%** |

What r1 got wrong, and the fix (r1 was 80% on the same set):

- **Policy the rubric didn't know.** Mark's escalation decisions — a statement
  escalates by being heard ("Listen!"), a hurt report by asking for help, the
  ladder holds at the top — read to r1 as an invented want or a flat step. "We"
  for an outing read as an invented group; one purpose phrase ("to play on the
  slide") as too complex for Stage II–III. r2 states each.
- **The pass rule double-counted.** A "flat" rung call failed a ladder even when
  every score was ≥ 4; r2 already scores one weak step as a 4. 13 of 15 p3
  disagreements were only that. Calls are now informational except "regresses".
- **The rubric spelled out the cases.** r1's examples were the cases' own
  answers ("mom, hungry" → "Mom, I'm hungry.", "she, pool", "Mom, can I have a
  cookie?") — a judge shown the answer matches instead of judging. All swapped
  for held-out words; `test_example_sentences_dont_spell_out_a_case` now fails
  on a leak in a rubric or a sentence prompt. The same test found one in the
  shipped prompt ("i, walk, school"), which had been carrying i_bus_school:
  without it 4 of 5 samples said "I want the bus to school" (fixed in p4).

What is left:

- **Sentences (10):** taste calls where the judge has a point and we approved
  with a comment (tv_stop "I want to stop the TV", see_cat "I want to see the
  cat") and where_mom. Mark (2026-10-20): "where, mom" asks about someone who
  isn't in the room — "Where is Mom?"; "Mom, where are you?" only fits a phone
  call. The rubric now says so, and where_mom / where_dad fail Tier-1 on
  "where are you". One lenient: v0 tomorrow_pool "Tomorrow is a
  pool day."
- **Escalation (11):** p1/p2 ladders with a capitals-only step, which we
  approved as climbing overall and the judge scores audible 3. On today's
  prompts (p3) the only disagreements are the two refusal ladders that repeat
  their own clause — a flaw we noted and accepted. The judge is arguably right.
- **Authoring surfaces:** too few labels to calibrate (only v0, 26 outputs), and
  the prompts change next (G1–G6). Calibrate them with that work.

So for sentences and escalation the judge is usable: it agrees 90–96%, it
errs strict, and it has passed only one output we rejected.
