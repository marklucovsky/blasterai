<!-- SPDX-License-Identifier: Apache-2.0 -->
# Handoff — sessions 12 to 16

Rewritten 2026-10-19 at the end of session 11, building on the sessions 10–14
plan (`47484ec`). Read this first.

## Where things stand

Session 11 (PRs #128–#132):

- **Editor lag fixed**, with permanent perf signposts (#128).
- **Graded reveal** — boards that grow with the child (#129). A scene declares
  a level count and carries a current level, which syncs; each placement has a
  `revealLevel` in `pagesData`. BlasterAI 60 ships a demo map: L1 13 first
  words, L2 the rest of Home, L3 the folders, L4 everything.
- **Caregiver Menu quick actions** — mode, level, scene, tile style; a
  long-press on Home no longer also goes Home (#130).
- **Find Word** — search from the Home menu; the board goes to the page and
  highlights the word (#131).
- **Vocal Flair 60 comparison** — `tools/compare_levels.py` and
  `docs/vocabulary-gaps-2026-10-19.md` (#132). Vocal Flair levels only its
  home board; we share 83% of our words with it; ~90 core words are worth
  adding.

**TestFlight 0.9.0 (8)** uploaded 2026-10-19 (`v0.9.0-8`), What to Test written.
The two `CD_BlasterScene` level fields were deployed to Production first.
Build 7 is in App Review.

**Levels go to testers as a prototype**, to provoke comment rather than to
recommend a clinical map. Find Word should tell us which missing words matter.

## Deadlines

| Date | What | Status |
|---|---|---|
| 2026-10-23 | `gpt-image-1` retires | Done: builds 6+ draw with `gpt-image-2` |
| **2027-01-14** | `gpt-4o`, `gpt-4o-mini`, `gpt-4.1*` retire — **every text call** | Sessions 12–14 |

Every text call is `gpt-4o-mini`: sentences (`CacheKeyPolicy.modelID`),
`SceneGeneratorService`, `PageGeneratorService`, `SceneRefinerService`,
`TileSuggestionService`, `WordModerationService`, and `ModelPricing`. The eval
judge is `gpt-4o`, retiring too. `tools/audit_openai_models.py` lists every
tool that names a model. OpenAI's replacement is **GPT-6 Luna**, starting at
reasoning effort `none`.

## The plan

The Luna work stays first: it has a hard date, and its baseline can only be
measured while gpt-4o-mini exists. Tester feedback on build 8 arrives in the
meantime and feeds session 14.

### Session 12 — eval harness: baseline on gpt-4o-mini

Unchanged from the last plan.

- **Sentences:** cases per Brown's Stage, single-word mode, escalation,
  grammar (am / are / was, pronoun case — "she + pool" must not become "She, I
  want…"), homographs.
- **Generation:** scene, page, refine, tile suggestions. Structural Tier-1
  (valid JSON, new words declared and used, minimum counts, no core-board
  leakage) and a Tier-2 judge rubric. "Potty Training" must produce potty /
  pee / poop.
- **Moderation:** cases that must pass and must be held.
- **Record** quality, latency and cost per call type. Move the judge off
  `gpt-4o`; keep subject and judge separate.

### Session 13 — Luna migration, TestFlight build

- Read the GPT-6 developer guide first (temperature, reasoning effort,
  verbosity).
- One place for model IDs, not seven.
- Run the harness against Luna at `none`; tune prompts and effort; retest.
- Update `ModelPricing`. The sentence cache is keyed by model, so it resets
  on the switch — worth a release note.
- Allow-listed OpenAI projects must allow the new model, the reviewer key's
  included (the gpt-image-2 lesson). Update the key guide and the site.
- **Ship to TestFlight** at the end of the session: for a BYOK app with no
  server, that is the gradual rollout.

### Session 14 — testers' round, vocabulary gaps, level map

- **Read build 8 feedback** — levels, quick actions, Find Word, and what
  testers found missing.
- **Vocabulary PR** from `docs/vocabulary-gaps-2026-10-19.md`, merged with
  what testers report. Days of the week (drawn in code, like the other day
  strips), the small words (of, from, if, did, could…), feelings, "I need a
  break". Small words may want the code-rendered treatment too.
- **Level map with Brandi** — finer early steps? some folders before the rest
  of Home? If BlasterAI 60 follows Vocal Flair's map, credit OpenAAC/CoughDrop
  (CC BY) in NOTICE and the scene description.
- **Submit the Luna build** to App Review once TestFlight has soaked — aim for
  mid-November, mid-December at the latest, so App Review and the holidays
  can't squeeze January 14.

### Session 15 — sharing boards: URL install, plus the import bugfixes

- **URL scene install** and a first `blasterai.app/boards` page. The vocab-pack
  route for domain boards (church, school, a hospital stay): we don't ship
  them canned; AI builds them, and URL install lets caregivers and domain
  experts share them.
- **One bugfix PR** in the same session:
  - Scene share drops `linkColor` / `linkColorIsAuto`
    (`SceneExporter.swift`).
  - Prompt for scenes that were never imported.
  - Tell the importer the file's level when "Replace Mine" takes it.

### Session 16 — editing revisit

- **Grid-first page editor** on landscape iPad and Mac: grid in the right
  two-thirds, a word well on the left; drag a word to a cell; insert N words
  into N selected cells. Portrait and phone keep the overlay.
- **Phone page editor**: a 12×5 page draws as tiny pills; draw cells the way
  Coverage does.
- Pilot testers want specialised scenes (a child with a brain injury; a
  14-year-old who struggles with his device): hand-authoring has to get easier.

Whether 12 and 13 stay separate sessions is decided at session 12's close.
Sessions 15 and 16 can swap; 14's vocabulary work can slide later if
testers' feedback points somewhere more urgent.

## Later, not time-bound

- **BlasterAI 40** by a transform from the 60, and **BlasterAI On the Go**
  for iPhone (20 cells).
- **Spanish localization** — `docs/localization-impact.md`;
  `TileModel.key` stays language-neutral.
- **Keyboard and grammar** — prefixes (some-/any-/every-), word endings
  (-s/-ed/-ing), word forms. With clinical guidance.
- **Voice selection guide** on the site: steer families to enhanced and
  premium voices.
- **A web player** — player only, launched from a `.blasterscene`.
- **OBZ import, maybe** — import an OBZ's vocabulary, laid out here.
- **Small PRs:** drop runtime tone chaining; scene word-sense hints
  ("shears" → scissors); remove promoted-tile leftovers; rebuild the header
  image.
- **Next App Store listing round:** one word in all five styles.
