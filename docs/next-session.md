<!-- SPDX-License-Identifier: Apache-2.0 -->
# Handoff: the end of session 20 and what comes next

Rewritten 2026-11-20 at the close of session 20. It replaces the session 19
handoff, which is in git history. **Next: session 21.** Read this first. The
plan is rough: revisit it at the start of each session.

Session 20 did the old sessions 21 and 22 (keyboard research and build) on top
of its own carry-forwards, so the numbering below starts again from 21.

## Where things stand

Session 20 was the keyboard. It ended with build 13. Worktree
`keyboard-plus-plus-28c084`. The design record is `docs/keyboard-design.md`;
the caregiver guide is `docs/guides/the-keyboard.md`.

| PR | What |
|---|---|
| #200 | Build 13; received packs offer to install; Use the Standard Layout; Classic awake/movie; Find Word searches the whole board; Search full size on the Talk rail |
| #201 | `SpeechNormalizer` (how sums, symbols and letters are said), the voice probe, `docs/keyboard-design.md` |
| #202 | Typed text in the message box (C) and the QWERTY and ABC keyboards (D) |
| #203 | The numbers page, the `?` math helper, sums said once, Keyboard settings (E) |
| #204 | Phone portrait keyboards, the calculator, brackets/powers/roots, wrong answers put right (E.5) |
| #205 | Word prediction, alphabetical by default (F) |
| #206 | The rail's Keyboard skips a keyboard the navigation bar has; the keyboard guide; build 13 tester notes (G) |

- **Build 13 (1.0.0)** was uploaded 2026-11-20 and tagged `v1.0.0-13` at
  `f79f7405`. The tester text and PDF are on the Desktop
  (`what-to-test-build13.txt`, `BlasterAI-TestFlight-build13.pdf`).
- **App Store:** 1.0.0 (build 9) was approved 2026-11-19 with the 4+ rating
  held, and is waiting for manual release. **The plan (Mark, 2026-11-20):**
  don't release it. Reject the pending release, attach build 13, resubmit, and
  keep the top of main approved so we're always ready to go live. Stay on
  version 1.0.0 and move only the build number until an intentional public
  launch; if a version bump is ever forced before then, it's 1.0.1. A first
  version has no What's New field, so the keyboard goes in the description or
  Promotional Text (draft: `~/Desktop/blasteria/BlasterAI-whats-new-1.1.txt`).
- **Phonetic keys are off the table** until a better voice: the IPA probe
  clipped every sound. They come back with recorded audio per key.
- **Simulators.** When a simulator refuses to launch apps ("Launchd job spawn
  failed"), `xcrun simctl shutdown all` and restarting
  `com.apple.CoreSimulator.CoreSimulatorService` fixes it without an erase. A
  test run can also silently reuse a stale test bundle: always check new tests
  by name (CLAUDE.md), and touch the file when one is missing.

## Carried forward from session 20

- **First PR: bump the build to 14.**
- **App Review:** check whether build 13 went in, and its status.
- **Site:** render the keyboard guide into `blasterai-site` (direct to main
  there, with Mark's OK) if session 20 didn't.
- **Keyboard follow-ups, from use:**
  - Aubrey and Brandi on the keyboards, the `?` helper and the calculator.
  - The helper's pacing on a device (it waits for the voice, then 0.35 s).
  - Prediction learns new words only when a letter keyboard reopens.
  - Brandi's board import: confirm her Keyboard cell links `sys:keyboard`, so
    the rail shows Calculator.
- **Tiles for `calculator`, `numbers` (123) and `abc`** — none exist, so a
  folder to those pages has no picture. Session 21 makes them.
- **The phone's iOS-keyboard path** (the system keyboard with our prediction
  bar) was planned as its own PR. The portrait layouts in #204 may have made it
  unnecessary; decide after phone feedback.
- **Still open from session 19:**
  - SDK 27 by April 2027 (below).
  - The App Store listing: fold the draft into `docs/app-store-listing.md`,
    with the 1.4.1 disclaimer and the 2.3.6 dispute.
  - The Beta App Description still says "for non-verbal children": Mark's call.
  - `nav-home.jpg` in the site guides shows the old board.
  - The phone's bottom navigation bar waits for tester feedback.
  - Ideas: add a folder while editing (Avaz-style); an edited page that still
    takes non-colliding updates.

## Session 21: the art model, and the art we're missing

gpt-image-2 shuts off 2027-02-10, so everything drawn from here on should be
drawn on its replacement (Mark, 2026-11-20: art first, words later).

- **Evaluate the model.** GPT-Image-2.6 Sunburst against Flare, per style
  (Classic, P3D, HC): style match to the reference packs, cutout, price.
  Measure, don't eyeball.
- **Switch.** Allow it on the key projects, update `ModelPricing`, move
  `TileImageGenerator` and the tools. A build carrying it on TestFlight by
  mid-January.
- **Get the missing art** on the new model, all five styles (spends Mark's
  key, so ask first):
  - `calculator`, `numbers` (123) and `abc`, for keyboard folders in a
    navigation bar (123 and ABC could be drawn as text tiles instead);
  - the cells held in `word_pass_2.json`;
  - whatever `tools/audit_art_coverage.py` reports.

## Session 22: localization, image styles, and voice — before the Malawi kickoff

**Malawi kickoff: 2026-12-11.** This session should land before it.

- **Localization impact.** App, vocabulary and shared boards across languages.
  `TileModel.key` stays language-neutral; settle word naming (#167) first.
  Outcome: an updated `docs/localization-impact.md` and a decision.
- **How to build and ship an image style.** A guide for a collaborator who
  isn't us — the style prompt, the reference pack, generation, audit,
  optimize, sync, ship — with Malawi (a P3D derivative with a Malawian look)
  as the worked case.
- **Recorded audio per tile.** For GLP phrases, Malawi, languages with no TTS,
  and the phonics keys IPA couldn't voice. Audio sits on the tile as a
  CloudKit asset: a schema change, deployed to Production first.
- **Explore TTS options** beyond the system voices, for languages and sounds
  they do badly.

## Session 23: vocabulary expansion, and how many taps a phrase takes

- **About 400 new words.** Choose from the VF60 core gaps, Brandi round three
  and a school-age frequency list. Class every word (the #178 rubric), place
  them in the BlasterAI 60 folders, art in all five styles on the session 21
  model.
- **Path analysis.** How many taps it takes to say a set of simple phrases on
  BlasterAI 60 against Avaz, measured, so the word placement is chosen by
  reach rather than by feel.

## Session 24 and later (unordered)

- **Revisit board and topic generation** now that templates, Me, My Topics and
  the spreadsheet exist.
- **One word search everywhere:** Find Word, Manage Vocabulary, Add Tiles, the
  typing suggestions and Use Existing Art onto one shared search-and-filter
  component (#197 did the choosers).
- **Sharing topics:** install a board from a URL, and a first
  `blasterai.app/boards`. Whether later edits to an SLP's base Me page flow on
  to each profile.
- **The Malawi image set** itself, driven by the session 22 guide (it may
  start earlier, with the kickoff).
- **Keyboard tier 2:** phonics pages (with recorded audio), enlarge keys on
  selection, next-word prediction, Brandi's review of the layouts.
- **PDF print styling** (Brandi's mock: title, framed grid, binder tab,
  footer).
- **A Reactions folder** (word pass 2's other half).

## Deadlines

| Date | What |
|---|---|
| **2027-02-10** | gpt-image-2 shuts off; a build on the new model must ship before it |
| **April 2027** | Uploads must be built with the iOS 27 SDK (Xcode 27); ITMS-90725 warning on build 11 |
| next model deprecation | Tuning round: the sentence prompt and evals move from "child" to the new term |

## Later, not time-bound

- **Android or a web player** for Fire tablets. The player is far cheaper.
- **BlasterAI 40** by a transform from the 60, and **BlasterAI On the Go** for
  iPhone (20 cells).
- **A template picks the grid and the bar placement**, including left and right
  columns.
- **Grammar** (with clinical guidance): prefixes, word endings, the inflection
  bubble.
- **Level map with Brandi**, over the new board.
- **Voice selection guide** on the site.
- **OBZ import, maybe.**
- **Small PRs:** drop runtime tone chaining; scene word-sense hints ("shears" →
  scissors); remove promoted-tile leftovers; rebuild the header image.
