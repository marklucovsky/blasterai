<!-- SPDX-License-Identifier: Apache-2.0 -->
# Handoff: the end of session 18 and what comes next

Rewritten 2026-11-13 at the close of session 18. It replaces the sessions 14–18
handoff, which is in git history. **Next: session 19.** Read this first. The
plan is rough: revisit it at the start of each session.

## Where things stand

Session 18 was the editor pass, and it ended with build 10. Worktree
`scene-editor-round-2-e76aa7`, now removed.

| PR | What |
|---|---|
| #172 | Select-first page editor, option bar, page card, Make a Copy of BlasterAI 60 |
| #173 | Typing panel: class picker, full link-target list after `>` |
| #174 | Use Existing Art |
| #175 | Phone editor: column bands, whole page, landscape |
| #176 | Editor-open freeze, partial: lazy bands, deferred link colours |
| #177 | Class-less words (`unspecified`, white tile, purple ?) |
| #178 | AI word classification |
| #179 | Copy-on-write: sparse copies, a page decouples only when edited |
| #180 | A scene's own navigation bar; Me and topics by page name |
| #181 | Scene templates: `sys:` / `template:`, Built On |
| #182 | Template sharing; carried templates |
| #183 | Navigation bar at the bottom; Built On in sheets |
| #184 | Tile art decoded off the main thread; PDF link strips name the page |
| #185 | Guides: editing a scene, spreadsheet boards; export writes scene details |
| #186 | Build 10 tester notes; Classic white tile fix |

- **Build 10 (1.0.0)** was uploaded 2026-11-11 and tagged `v1.0.0-10` at `4434faca`.
- **CloudKit:** `isTemplate`, `templateID` and `isCarriedTemplate` were deployed to Production 2026-11-12.
- **Site:** both new guides are live on blasterai.app.

## Session 19: build 10 shakeout, admin cleanup, nomenclature

- **First PR: bump the build to 11.**
- **Build 10 feedback.**
  - Fix what testers report.
  - Mark re-traces the editor-open freeze on a device to confirm #184 fixed it.
  - The phone's bottom navigation bar sits above the rail and feels awkward. Decide once there's feedback.
  - Eyeball the Classic *awake* and *movie* tiles. Their corners are opaque, and they're probably deliberate full scenes.
- **Sharing bugfixes, one small PR.**
  - A shared scene drops its folder colours (`linkColor` / `linkColorIsAuto`, `SceneExporter.swift`).
  - Ask about scenes that were never imported.
  - Tell the importer which level they're replacing with Replace Mine.
- **Admin cleanup.**
  - Inventory every section and control in Settings and the scene editor.
  - Propose a grouping: everyday, occasional, advanced.
  - Evaluate where quick actions overlap the Settings tabs (Now and the rest): which surface owns what, and what a caregiver reaches for first.
  - **Show Mark before moving anything.**
- **Nomenclature: "the child" vs "the talker".** Decide the term first, then change it in the same copy pass.
  - "Talker" is used both ways: for the device ("her talker"), and in setup scripts for the person ("who is the talker?"). Read it as the person driving the hardware-and-software combination to communicate. That fits us, since the app is the device.
  - "Child" already leaves out real users, such as the Sunday School pastor, who is an adult.
  - Candidates: *talker* (leading), *AAC user*, *communicator*.
  - Scope: UI copy, guides, the site, the App Store listing, the tester notes.
  - **Not in this pass:** the sentence prompt and the evals. They change in the tuning round at the next model deprecation.
  - Code identifiers stay.

## Session 20: vocabulary expansion, and what it opens up (likely two sessions)

About 400 new words is the centrepiece. It's also the vehicle for exploring and developing:

- **Expand the vocabulary and its art.**
  - Choose the words from the VF60 core gaps, Brandi round three and a school-age frequency list.
  - Class every word (the #178 rubric), and add them to the BlasterAI 60 folders.
  - Art in all five styles. It spends Mark's key, so ask first.
  - **The art model collides with the deadline.** If GPT-Image-2.6 is available by then, generate the new art on it and fold the migration (session 23) into this work, rather than shooting 400 words on a model that dies on 2027-02-10.
- **One word search everywhere.**
  - The searches to unify:
    - Find Word
    - Manage Vocabulary
    - Add Words…
    - the typing suggestions
    - Use Existing Art
    - the link-target picker
  - Inventory them, then make search and filter one shared component. Filters: class, page, has art, level, scene.
  - **Folder-based search and navigation.**
    - Picking or finding a page should browse the folder tree, for a caregiver who remembers a page but not its path.
    - Typing `>` today shows a flat list of page keys. It should show a tree (`actions > feelings`), with search across it.
    - The link-target picker and Edit This Page get the same tree.
- **Recorded-audio TTS override per tile.**
  - For GLP phrases, Malawi, and languages with no TTS.
  - Audio sits on the tile as a CloudKit asset. That's a schema change, and it needs a Production deploy.
- **Localization.**
  - Covers app localization, vocabulary localization, and what happens to shared scenes across languages.
  - `TileModel.key` stays language-neutral.
  - Settle word naming (#167) first.
  - Outcome: an impact doc that updates `docs/localization-impact.md`, and a decision.
- **A beginner's guide to driving a new image set,** with Malawi as the worked case.
  - Steps: the style prompt, the reference pack, generation, audit, optimize, sync.
  - It's written for a collaborator who isn't us.
- **Revisit scene and topic generation and the workflows around it,** now that templates, Me, My Topics and the spreadsheet exist.

## Session 21: keyboard research (findings, no UI)

The keyboard is the next large item. How TTS handles letters, numbers and symbols decides how much of it we build.

Aubrey's TouchChat shows the target: she types a whole expression, `2 + 2 = 4`. She isn't asking the device to compute the answer, only to say what she typed.

- **TTS, measured on the voices we steer people to:**
  - single letters: `a`, `A`, `i` (the existing `loneSpeech` fix)
  - digits and numbers: `7`, `12`, `100`
  - symbols: `+ − × ÷ = < >`, `5/3`
  - whole lines: `2 + 2 = 4`, `I am 7`
  - partial words while typing
  - What is said wrong, and whether text normalisation before speech fixes it ("two plus two equals four").
- **Phonetic mode.**
  - Does `AVSpeechSynthesisIPANotationAttribute` voice long and short vowels and digraphs (`sh`, `ch`, `ph`) on the enhanced voices?
  - If not, recorded audio is the fallback.
- **Field study.**
  - **Aubrey's TouchChat** (Mark):
    - its layout
    - word prediction
    - number and symbol entry
    - what it speaks and when (each key, on space, or the whole line)
    - how typed text and symbol tiles mix in one line
  - **Avaz's keyboard:** it auto-completes to words. What does its prediction draw on, and how is a prediction picked?
  - **Brandi:** ask her before a layout is chosen.
- **Design questions to answer.**
  - **The tray contract:** typed text vs tiles in the sentence bar. Never two trays.
  - **AI on typed text:** does it go to sentence generation, or is it spoken as typed? An expression must be spoken as typed.
  - **Layout:** QWERTY, ABC, or a setting for both.
  - **Where the keyboard lives:** the rail's keyboard button opens it; the system row and the rail stay put.
  - **Graded reveal:** does a keyboard have levels?
- **Output:** `docs/keyboard-design.md`, with findings, scope tiers and a recommendation. Mark decides the scope.

## Session 22: keyboard build, tier 1 (scope set by session 21)

Likely shape:
- Letters, digits and a math row.
- Word prediction from the vocabulary plus what the talker has said.
- Space speaks the word just typed. Speak says the whole line, with numbers and symbols normalised.
- Typed text lands in the tray as text.
- Tests for the speech normalisation table.
- Phonetic keys only if session 21 shows IPA works. Otherwise they come later, with recorded voice.

## Session 23: art model migration (hard deadline; may fold into session 20)

- **gpt-image-2 shuts off on 2027-02-10.** Move generation to GPT-Image-2.6.
  - A build carrying it should be on TestFlight by mid-January.
  - Re-check the style prompts and reference packs.
  - Re-shoot a sample per style and compare before switching.
- **PDF print styling** (Brandi's mock: title, framed grid, binder tab, footer) rides along if there's room.

## Session 24 and later (unordered)

- **Sharing topics.** Install a scene from a URL, and a first `blasterai.app/boards`.
- **Sharing Me.**
  - Probably part of profiles. An SLP keeps a base Me configuration and injects it into a talker's profile, which is then tweaked on its own.
  - To define:
    - what a Me configuration is
    - how it travels
    - whether later edits to the base flow on to profiles, as templates do
- **Word pass 2.** Art for the cells held in `word_pass_2.json`, and a Reactions folder.
- **Malawi image set.** A P3D derivative, driven by the guide from session 20.

## Deadlines

| Date | What |
|---|---|
| **2027-02-10** | gpt-image-2 shuts off; a build on the new model must ship before it |
| next model deprecation | Tuning round: the sentence prompt and evals move from "child" to the new term |

## Later, not time-bound

- **Android or a web player** for Fire tablets. The player is far cheaper.
- **BlasterAI 40** by a transform from the 60, and **BlasterAI On the Go** for iPhone (20 cells).
- **A template picks the grid and the bar placement**, including left and right columns.
- **Grammar** (with clinical guidance):
  - prefixes
  - word endings
  - the inflection bubble
- **Level map with Brandi**, over the new board.
- **Voice selection guide** on the site.
- **OBZ import, maybe.**
- **Small PRs:**
  - drop runtime tone chaining
  - scene word-sense hints ("shears" → scissors)
  - remove promoted-tile leftovers
  - rebuild the header image
