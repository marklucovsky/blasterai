# Escalation quality baseline — 2026-06-20

Captured by the A2 eval harness (`LiveTier2EvalTests.captureQualityBaseline`).
Subject = `gpt-4o-mini` (production model), Judge = `gpt-4o`.

## Rollup

| Surface | Tier-1 pass | Judge | Notes |
|---|---|---|---|
| Sentence | 100% | 5.00/5 | Sentence generation is solid. |
| **Escalation** | **0%** | **escalate-rate 38%, regressions 3** | **Broken — the milestone target.** |

## Diagnosis — the ladders

The model escalates **one notch on the first repeat, then flattens or wobbles**.
It is not building cumulatively on the previous rung.

```
chocolate      intensities [3,3,3,3]   calls [flat, flat, flat]
  [0] I want chocolate!
  [1] I want chocolate!          ← identical
  [2] I want chocolate!          ← identical
  [3] I want chocolate!          ← identical

mom_hungry     intensities [0,3,2,2]   calls [escalates, regresses, escalates]
  [0] Mom, I'm hungry.
  [1] Mom, I'm really hungry!
  [2] Mom, I'm hungry!           ← REGRESSES (drops "really")
  [3] Mom, I'm super hungry!

pinkfong_video intensities [1,4,3,4,4] calls [escalates, regresses, escalates, flat]
  [0] I want to play Pinkfong and watch a video.
  [1] ... and watch a video now!
  [2] ... and play a video!      ← regresses (drops "now!")
  [3] ... and play a video now!
  [4] ... and play a video now!  ← flat (identical to [3])

go_home        intensities [1,4,3,3]   calls [escalates, regresses, flat]
  [0] I want to go home.
  [1] I want to go home now!
  [2] I want to go home!         ← regresses
  [3] I want to go home!         ← flat
```

## Root causes (in `SentencePromptBuilder.escalationPrompt`)

1. **Not cumulative.** Each repeat says "make it urgent" against a generic
   baseline, not "make it MORE intense than the previous sentence." So the model
   lands at roughly the same intensity each time → flat.
2. **Only 3 buckets (1, 2, 3+)**, and 2 vs 3+ aren't clearly more intense than 1.
3. **Fixed "mom, hungry" few-shot** anchors outputs (mom_hungry literally
   regressed toward the example).
4. **No concrete intensity ladder** (louder → emphatic words → ALL-CAPS →
   exclamation) tied to the repeat count, so the model has no axis to climb.

## A3 target

Rewrite the escalation prompt so each rung is explicitly hotter than the prior
one, re-run this capture, and beat the baseline: Tier-1 escalation pass-rate up
from 0%, judge escalate-rate up from 38%, regressions down from 3.

## A3 result — 2026-06-20

Rewrote `escalationPrompt` to be cumulative + graduated with a neutral example
(see SentencePromptBuilder). Re-ran the capture:

| Surface | Baseline | After A3 |
|---|---|---|
| Sentence Tier-1 / judge | 100% / 5.00 | 100% / 5.00 (unchanged) |
| Escalation Tier-1 pass | 0% | 100% |
| Escalation judge escalate-rate | 38% | 85% |
| Escalation regressions | 3 | 1 |

Ladders now climb instead of flatlining (e.g. chocolate: "I want chocolate!" →
"I WANT CHOCOLATE!!!" → "I WANT CHOCOLATE NOW!!!").

### Known residual — the intensity ceiling
Once a ladder reaches maximum intensity (ALL-CAPS + multiple "!"), deeper rungs
have nowhere higher to go, so the final rung of the deepest ladder
(pinkfong_video, 4 extra steps) occasionally plateaus or dips a little run-to-run.
This is a ceiling effect, not the old broken behavior. The live escalation Tier-1
floor is strict (any drop fails), so that one ladder can intermittently flag —
acceptable since it's opt-in and the judge confirms the overall ramp is healthy.
Minor wording nits remain (e.g. "I need HUNGRY now") from the blunt CAPS rule.

---

# Brown's Stages replace the grade level — 2026-08-24

Session 3 (3E/3F) swapped the birthday-derived US grade level out of the system
prompt for the child's **Brown's Stage**. The eval's subject stage is now
`SubjectRunner.brownsStage`, defaulting to **II-III** — the first stage that
generates at all, since Stage I is single-word mode and makes no API call.

The prompt change broke escalation, and the eval is how we found it.

## What broke, and how we knew it was the change

| Eval stage | Escalation failures | Top-rung intensity |
|---|---|---|
| II-III (new default) | `pinkfong_video` **and** `go_home` | collapsed to **3** (from 19-20) |
| IV+ | `pinkfong_video` only | 23 < 32 — the known ceiling effect |
| 2026-06-20 baseline ("2nd grade") | `pinkfong_video` only, intermittent | ceiling effect |

Running the same eval at Stage IV+ reproduced the recorded baseline exactly. That
is what pinned the cause on the stage rather than on model drift: `go_home` had
never regressed before and failed on **every** II-III run.

**Root cause — the ladder contradicted the stage.** The escalation prompt climbs
by *adding words* ("really", "right now", "I need …"). Stage II-III instructs a
mean utterance length of 2-3 words and "keep sentences short". Told to be both
briefer and wordier, the model obeys the stage ceiling and the ramp flatlines.

## The path not taken — emphasis-only escalation

The first fix escalated by emphasis alone: same words, louder — `!`, then CAPS,
then both, then repeating a word the child already chose. Utterance length never
grew, so the stage and the ladder stopped fighting, and **the eval went green.**

It was still wrong, and the eval could not see why. `AVSpeechSynthesizer` barely
inflects on "!" and does nothing useful with capitals — some voices read a short
ALL-CAPS token letter by letter. Every rung *sounded identical*. Tier-1 scores
intensity as `exclamations × 2 + capsWords × 3 + urgencyTerms`, so a purely
typographic ramp scores beautifully and communicates nothing. In a
speech-generating device, escalation a listener cannot hear is not escalation.

**Recorded because the metric endorsed it.** A green Tier-1 is not evidence that
escalation works; it is evidence that the intensity proxy went up. Mark caught
this by reading the sentences.

## The fix — escalation is exempt from the length ceiling

`BrownsStage.promptDescriptor(escalating:)` keeps the vocabulary and grammar level
but **drops the brevity clause while a repeat is in flight**, and the escalation
message says outright that the sentence may grow.

Placement mattered more than wording. An exemption stated only in the escalation
message lost to the base prompt's absolute "match that level exactly": deep rungs
collapsed back to baseline —

```
go_home     [2] "I NEED TO GO HOME NOW!!!"  →  [3] "I want to GO HOME!"
mom_hungry  [2] "Mom, I need HUNGRY now!"   →  [3] "Mom, I'm hungry."
```

Applying the exemption where the rule itself is written fixed both.

This is deliberate: the generated sentence is read by the **caregiver**, while the
child's own loop is the tiles and the speech. "I need chocolate NOW" tells an adult
*he really means it*; "chocolate!!!" does not. When prosody escalation lands —
driving rate, pitch and volume from the repeat count — the audible ramp moves into
the TTS layer and this ladder can get shorter again. Until then the words carry it.

## Result — Stage II-III, after the fix

```
chocolate       intensities [1, 6, 7, 17]
  [0] I want chocolate.
  [1] I really want chocolate right now!
  [2] I need CHOCOLATE now!
  [3] I WANT CHOCOLATE NOW!!!

go_home         intensities [1, 6, 7, 20]
  [0] I want to go home.
  [1] I really want to go home right now!
  [2] I need to GO home now!
  [3] I WANT to GO HOME NOW!!!

pinkfong_video  intensities [1, 8, 18, 38, 26]   ← deepest ladder, dips at the last rung
```

| Surface | After A3 (grade) | After Brown's Stages (II-III) |
|---|---|---|
| Sentence Tier-1 | 100% | 100% |
| Escalation Tier-1 | 100%, 1 intermittent | 100%, 1 intermittent |

The one remaining failure is `pinkfong_video`'s final rung — the same
already-documented ceiling effect on the deepest ladder, unchanged by any of this.

## The word-class fix — "I need HUNGRY now"

The A3 section above listed `"I need HUNGRY now"` as a residual wording nit. It was
not cosmetic. The escalation ladder said *"state it as a need — I need …"*, and
`hungry` is a **feeling**, not a thing that can be needed. Forcing a state word
into an object slot is what produced it, and at deeper rungs the model either
doubled down ("Mom, I WANT HUNGRY NOW!!!") or bailed out to a calmer sentence,
which read as a regression.

Two attempts failed before the right one:

1. **Class bullets inside the escalation message.** Fixed `mom_hungry`, but the
   rule only existed while escalating — the same error can occur at rung 0.
2. **Intensifiers only** for feelings ("really hungry" → "SO hungry"). Grammatical,
   and it flatlined: rungs 1 and 2 came back *character-identical*, with only the
   exclamation marks differing. A feeling has almost no intensifier headroom.

**What worked** — Mark's call — was to stop patching escalation and give the base
system prompt a `GRAMMAR BY WORD CLASS` table covering all 22 classes, stating the
grammatical *role* each one must play. It sits beside the existing category-honor
rule: that one governs a word's **meaning**, this one its **grammatical role**.

    (feeling), (health)          a state the child IS in — "I am hungry",
                                 never "I want hungry" / "I need HUNGRY"
    (food), (drinks), (toy)      things that can be given — "I want X"
    (actions)                    verbs — "I want to X", never "I want X"
    (places)                     destinations — "I want to go to X"
    (describe), (colors)         adjectives; never the thing wanted on their own
    (people)                     who the child is speaking TO

For feelings specifically, escalation rides the **request the feeling implies** —
hungry implies eating, tired implies rest. That is not a new want, and the base
prompt already worked this way for `mom, tired → "Mom, I'm tired. Can I lie down?"`.

Rung 2 also stopped saying *"drop the softeners"*: removing "really" and "right
now" lowered the Tier-1 urgency-lexicon count, so a rung that sounded **more**
insistent scored **less**. It now keeps the urgency words and adds the need frame.

### Result

```
mom_hungry      intensities [0, 5, 9, 26]
  [0] Mom, I am hungry.
  [1] Mom, I am really hungry right now!
  [2] Mom, I really NEED to eat right now!
  [3] Mom, I am SO, SO HUNGRY! I need to EAT NOW!!!

mom_snack       intensities [0, 6, 9, 34]      ← added as a control, see below
  [0] Mom, can I have chocolate milk and a graham cracker?
  [1] Mom, I really want chocolate milk and a graham cracker right now!
  [2] Mom, I really NEED chocolate milk and a graham cracker right now!
  [3] MOM! I NEED CHOCOLATE MILK AND A GRAHAM CRACKER NOW!!!
```

All 10 sentence cases pass. `pinkfong_video`'s final rung remains the one
intermittent failure — the deepest ladder, the same ceiling effect documented
above, unchanged by any of this.

**`mom_snack` is a deliberate control.** Both of its items are things a child can
be given, so the need frame must keep working there. If a future fix for a feeling
case regresses `mom_snack`, the ladder has gone back to applying one frame to every
word class.

**Still not re-run:** the Tier-2 judge. The escalate-rate and judge scores in the A3
table were measured against the grade prompt and have not been re-measured against
stages. Worth doing before the pilot.

## One scorer rule was measuring the wrong thing

`dad_help` started failing as *"output is a raw echo of the tiles"*. For the tiles
`dad + help`, the model returned "Dad, help!" — which at Stage II-III is the
**correct** output. `looksLikeRawTileEcho` strips punctuation before comparing, so
it cannot distinguish "dad help" from "Dad, help!".

That check encoded "the model should always expand the selection", an artifact of
the old "2nd-grade student" phrasing. `Tier1.scoreSentence` now takes a `stage` and
applies the echo rule only at **Stage IV+**, where an echo really does mean the
model added nothing. The default stays `.fourPlus`, so every other caller is
exactly as strict as before.

## Harness change — ladders now reach the reader

`print` from a test does not survive into the `.xcresult` bundle, so a CLI run could
see *that* a ladder regressed but never *what it said*. Worse, a **passing** run
produced no output at all — and wording is exactly what a pass hides, since the
Tier-1 proxy cannot tell a well-phrased ramp from a badly-phrased one.

Two additions:

- `liveEscalationSanity` folds every ladder into the expectation message, so a
  failure explains itself.
- `EVAL_TRANSCRIPT_PATH=<file>` appends every generated sentence and ladder,
  pass or fail. Every wording problem in this section was found by reading that
  transcript, not by reading a score.

```
TEST_RUNNER_RUN_LIVE_EVAL=1 \
TEST_RUNNER_OPENAI_API_KEY="$OPENAI_API_KEY" \
TEST_RUNNER_EVAL_TRANSCRIPT_PATH=/tmp/ladders.txt \
xcodebuild -project claudeBlast.xcodeproj -scheme claudeBlast \
  -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.2" \
  -only-testing:claudeBlastTests/LiveTier1EvalTests test
```

---

# The judge, re-run against Brown's Stages — 2026-09-10

The A3 table's escalate-rate and judge scores were measured against the old
grade-level prompt and had been carried forward unmeasured ever since — the
section above says so in as many words ("**Still not re-run:** the Tier-2
judge"). The site was quoting `38% → 85%` off that stale row. Re-run rather than
qualified, at Mark's call.

Subject = `gpt-4o-mini` at Stage II-III (the harness default), Judge = `gpt-4o`.

## Rollup

| Surface | 2026-06-20 baseline | After A3 (grade) | **Brown's Stages, 2026-09-10** |
|---|---|---|---|
| Sentence Tier-1 | 100% | 100% | **100%** |
| Sentence judge | 5.00/5 | 5.00/5 | **4.67/5** |
| Escalation Tier-1 | 0% | 100% | **100%** |
| Escalation escalate-rate | 38% | 85% | **94%** |
| Escalation regressions | 3 | 1 | **0** |

Escalation is better against stages than it ever was against the grade prompt:
every ladder climbs monotonically, and the only non-escalating call in the whole
run is the final rung of `pinkfong_video` — the documented ceiling effect on the
deepest ladder, which has now been present in every capture since June and is
not a regression.

```
chocolate   [1, 6, 9, 17]      I want chocolate. → I really want chocolate right now!
                               → I really NEED chocolate right now! → I NEED CHOCOLATE NOW!!!
mom_hungry  [0, 5, 9, 29]      … → Mom, I am SO, SO HUNGRY! I NEED FOOD NOW!!!
go_home     [1, 6, 9, 20]      … → I WANT to GO HOME NOW!!!
mom_snack   [0, 6, 9, 34]      the need frame still survives the feeling fix — control holds
pinkfong    [1, 6, 15, 23, 23] deepest ladder, flat at the last rung (ceiling)
```

The sentence judge moving 5.00 → 4.67 is not a fault to chase. Stage II-III asks
for shorter, plainer output than "2nd grade" did, and a judge rewarding richness
will score that slightly lower by construction. Tier-1 is 10/10 and the wording
is right for the stage.

## The capture was grading at the wrong stage

`dad_help` failed the first re-run as *"output is a raw echo of the tiles"* — the
exact failure the stage-scoped echo rule was introduced to stop producing, and
which the section above records as fixed.

It was fixed, in `Tier1.scoreSentence`, whose `stage` parameter defaults to
`.fourPlus`. `LiveTier1EvalTests` passes `stage: runner.brownsStage`.
**`LiveTier2EvalTests` did not** — so the Tier-2 capture generated at Stage II-III
and graded at Stage IV+, and had been doing so since stages landed. One
argument, now passed.

Worth stating plainly because it is the second time this file records the same
lesson from the other direction: a green Tier-1 is not evidence escalation works,
and a red one is not evidence it is broken. Read the sentences.

## Residual wording nits — recorded, not chased

- `more_drink` → "I want more drink." Grammatical enough to pass, and not what a
  person says; "more to drink" is the natural form. The tiles are `more` +
  `drink` and the model is honouring both literally.
- `pinkfong_video` → "play Pinkfong and video." Same shape: two nouns conjoined
  where one is really a modifier.

Both are the category-honor rule doing its job at a cost. Neither is worth a
prompt change on its own; if a third case shows up, the pattern is "conjoined
object nouns read awkwardly at Stage II-III" and belongs in the word-class table.

## Re-running this capture

```
TEST_RUNNER_RUN_LIVE_EVAL=1 \
TEST_RUNNER_OPENAI_API_KEY="$OPENAI_API_KEY" \
xcodebuild -project claudeBlast.xcodeproj -scheme claudeBlast \
  -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.2" \
  -only-testing:claudeBlastTests/LiveTier2EvalTests test
```

Costs roughly 10-20 cents (31 `gpt-4o-mini` calls, 15 `gpt-4o` judge calls), and
note that xcodebuild's parallel clones run it twice unless you disable them.
