<!-- SPDX-License-Identifier: Apache-2.0 -->
# Handoff — sessions 10 to 14

Rewritten 2026-10-14, partway through session 10, when OpenAI's GPT-4.x
retirement notice turned "next session" into a plan for the next several.
Read this first.

## Where things stand

Session 10 so far (PRs #123–#127, plus `dd3102a` on main):

- **gpt-image-2** — art generation moved off `gpt-image-1` (shut down
  2026-10-23), with per-style reference packs; every drawn set redrawn (#123).
- **Release polish** — welcome screen leads with the board; one request per
  Play; `-TileScriptAutorun` runs once (#124).
- **Coverage** — folders count, the drill-down draws the real grid, page
  changes join the activity log via a new synced `LoggedNavigation` (#125).
- **Art errors** show above the Artwork rows, not below the fold (#126).
- **Brandi's round two** — "I" and TV capitalized through a vocabulary
  `label`; `am`, `are`, `was` on Actions screen 2 (#127).
- **PRD** revised as a living document, scored in `docs/prd-scorecard.md`.

**App Store: 0.9.0 (5) still Waiting for Review** (submitted 2026-10-07).
Mark sent App Review a status inquiry and re-accepted the yearly developer
agreement on 2026-10-13.

## Two OpenAI deadlines

| Date | What retires | Our exposure | Status |
|---|---|---|---|
| **2026-10-23** | `gpt-image-1` | All AI tile art | Migrated (#123); needs a shipped build |
| **2027-01-14** | `gpt-4o`, `gpt-4o-mini`, `gpt-4.1`, `gpt-4.1-mini` | **Every text call** | Sessions 12–14 below |

Every text call is `gpt-4o-mini`: sentences (`CacheKeyPolicy.modelID`),
`SceneGeneratorService`, `PageGeneratorService`, `SceneRefinerService`,
`TileSuggestionService`, `WordModerationService`, and `ModelPricing`. The eval
harness's judge is `gpt-4o`, retiring too. Tools that name a model:
`test_scene_gen.py`, `test_sentence_prompt.py`, `check_prompt_order.py`,
`build_tone_variants.py`; `audit_openai_models.py` lists them all.

OpenAI's recommended replacement is **GPT-6 Luna**, starting at reasoning
effort `none`, cheaper per token than gpt-4o-mini. Their guide says: baseline,
evaluate, tune, roll out gradually.

## The plan

### Session 10 (now) — cut 1.0.0

Gated on App Review. The release plan:

- Apple sends 0.9.0 back → fix, and ship the new build as the resubmission.
- Approved → push the new build right after.
- Still waiting as the 23rd gets close → withdraw, push, resubmit.

**Before that build ships:** Deploy Schema to Production in the CloudKit
Console (`CD_LoggedNavigation`, from #125), and confirm every OpenAI project
holding a key allows `gpt-image-2`, the reviewer's included.

### Session 11 — graded reveal: plan, then mechanism

Brandi asked how the system grows with the child: "Eventually, we want a child
to be able to say anything they need to say. Where will these words live?"
Before deciding what goes on a bigger board, decide how a board reveals more
of itself. Ahead of the ecosystem work because it is more fundamental, and
because it fixes a data shape boards will be built on.

Today's conceal is binary (`TileEntry.isConcealed`: the cell keeps its place,
draws empty, doesn't respond). The proposal:

- **`TileEntry.revealAt: Int`**, 0 meaning always shown, set by the board's
  author. It lives in `BlasterScene.pagesData` JSON, so the cell side has no
  CloudKit schema change. The hand-written `TileEntry` decoder must learn it,
  and tests must load the real bundled board.
- **Keep `isConcealed`** as the caregiver's override: the author says when a
  word normally appears, the caregiver says "not on this board yet". Decide
  now whether it becomes tri-state (auto / concealed / revealed early).
- **The child's level on `ChildProfile`** — the one synced field (additive;
  promote to Production). Default from the Brown's Stage, with an override,
  as device mode works.
- **Payoff:** the read-only bundled BlasterAI 60 can grow by levels written
  in its JSON, with no clone.

Open questions: integer levels with gaps (10/20/30) or named stages; per child
or a per-board floor; levels on folder links; exports at the current level or
the full board (OBF has no levels); an editor "preview at level N".

Content comes after, ideally with Brandi: one big board revealed over time
(LAMP) or stepping up through sizes (WordPower, Crescendo); word forms
(long-press `be` → am/is/are/was) or separate tiles; how much grammar the AI
should supply at each stage.

### Session 12 — eval harness, part 1: baseline on gpt-4o-mini

**The baseline must exist before January 14** — the model it is measured
against disappears that day. The harness (`claudeBlastTests/Eval/`) covers
sentences and escalation; generation prompts were the known gap.

- **Sentences:** cases per Brown's Stage, single-word mode, escalation,
  grammar (am / are / was, pronoun case), homographs.
- **Generation:** scene, page, refine and tile suggestions. A structural
  Tier-1 (valid JSON, new words declared and used, minimum counts, no core-board
  leakage) and a Tier-2 judge rubric for topical coverage. "Potty Training"
  must produce potty / pee / poop.
- **Moderation:** cases that must pass and must be held.
- **Record** quality, latency and cost per call type. Move the judge off
  `gpt-4o`, and keep subject and judge separate.

### Session 13 — Luna migration

- Read the GPT-6 developer guide first: parameters may differ (is
  `temperature` accepted? reasoning effort, verbosity).
- One place for model IDs, not seven.
- Run the harness against Luna at `none`, tune prompts and effort, retest.
- Update `ModelPricing`. The sentence cache is keyed by model, so every
  family's cache resets on the switch — intended, and worth a release note.

### Session 14 — ship the Luna build

- TestFlight first: for a BYOK app with no server, that is the gradual
  rollout.
- Allow-listed OpenAI projects must allow the new model (the gpt-image-2
  lesson: it took minutes to propagate). Update the key setup guide, the site,
  and the reviewer key's project.
- Aim to submit before mid-December, so App Review and the holidays don't
  squeeze the January 14 date.

Sessions 11 and 12 are independent: swap them if the Luna guide shows a harder
migration than expected.

## Later, not time-bound

- **URL scene install + `blasterai.app/boards`** — BlasterAI 40 by a
  transform from the 60 (learn from Vocal Flair and WordPower 40/60), and
  BlasterAI On the Go for iPhone.
- **Spanish localization** — the process for app content and display names
  (`docs/localization-impact.md`; `TileModel.key` stays language-neutral).
- **A web player** — what a fork might build: player only, launched from a
  `.blasterscene`.
- **OBZ import, maybe.** A whole board will not come across as it was: art,
  grid and word forms all differ. The version that holds up is importing an
  OBZ's *vocabulary*, laid out here.
- **Small PRs:** drop runtime tone chaining; scene word-sense hints
  ("shears" → scissors); remove promoted-tile leftovers (`promotedHitThreshold`,
  `speakPromoted`); rebuild the header image.
- **Next App Store listing round:** a styles graphic showing one word in all
  five styles.
- **Brandi:** reminded where the word finder is (Admin › Scenes › Manage
  Vocabulary) — a discoverability signal for page-editing work. Her idea of
  reserving each page's top row for subcategories is better answered by
  curating BlasterAI 60 into a proper board set.
