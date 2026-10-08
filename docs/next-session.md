<!-- SPDX-License-Identifier: Apache-2.0 -->
# Handoff — session 10

Written 2026-10-08 at the close of session 9, replacing the App Store dry-run
handoff. Read this first.

## Where things stand

Session 9 (PRs #119–#121) took the app to its first App Store submission:

- **Site** — Board Layout guide, 619-word counts, the guides synced, and a
  false claim removed (the phone does not keep the iPad's word positions).
- **Release tags** — `release.py --upload` refuses an untraceable archive,
  then commits the bump and tags it `v<version>-<build>` (#119). Builds 3–5
  backfilled: `v0.9.0-3/4/5`.
- **Screenshots** — `tools/frame_screenshots.py`, ten real captures, dark mode,
  "Modern. Familiar. Free." (#120). How: `docs/release-runbook.md`
  §"App Store screenshots". Pack and starter words lowercased in the same PR.
- **Listing** — `docs/app-store-listing.md`, every field as submitted, with
  `tools/check_listing.py` (limits, and `--export` plain text to paste) (#121).

**App Store: 0.9.0 (5) is Waiting for Review**, manual release. Nothing ships
on approval.

## This session, in order

1. **gpt-image-2 migration — deadline October 23.** OpenAI shuts down
   `gpt-image-1` that day; `gpt-image-2` is the documented replacement (not
   `gpt-image-1-mini` / `-1.5`, which go December 1). The app's art generation
   (`TileImageGenerator`), `ModelPricing`, tests, `generate_sets.py` and
   `build_tone_variants.py` all name it.
   - **Style first.** Render ~20 words × 5 styles with gpt-image-2 and compare
     against the shipped tiles before switching. New art has to match the sets
     it lands in.
   - Check `/images/edits` and refine still behave (multi-image input,
     `quality`).
   - Mark upgrades the constrained OpenAI project allowlists, including the
     reviewer's key. `tools/audit_openai_models.py` lists what the code calls.
   - Builds 4 and 5 will lose art on the 23rd regardless — confirm it fails as
     a message, not a crash.
2. **Coverage drill-down: draw the real grid.** It reflows the page's words
   instead of drawing the board's geometry (12×5, Home in cell 0), so a dimmed
   region doesn't read as a place. Boards are fixed grids now; use the scene's
   designed layout.
3. **Coverage: count link taps.** Home reads "27 of 47" on a 59-cell page —
   the 11 folders and keyboard are skipped, including eat/drink/play, which
   speak *and* navigate. An unopened folder is as much a signal as an unpressed
   word. A link press needs logging as one.
4. **Score ourselves against the PRD.** `docs/prd.md`, requirement by
   requirement: shipped, partial, deliberately dropped, not started.
5. **Version switch — wait on App Review.** If review sends us back, iterate on
   **0.9.x**. Move to **1.0.0 (6)** once 0.9.0 is approved and we're cutting
   the build that will actually release. Open question: whether an
   approved-unreleased 0.9.0 blocks creating 1.0.0 until withdrawn.

**Carried, smaller:**

- **Onboarding copy** — the welcome screen still leads with "Pick tiles, hear
  sentences" and "Bring your own AI key". Fix before the release build.
- **Play double-request** — Play can launch two generation requests ~4ms apart;
  the first is cancelled and the second counts as a repeat (stray ↻ badge).
- **`-TileScriptAutorun` re-fires** every time TileScript opens during that
  launch.

## Next session after that

Ideas to get in front of, not market needs.

- **URL scene install + `blasterai.app/boards`.** Install a scene from a link,
  and publish a few boards on the site to seed a tiny ecosystem:
  - **BlasterAI 40** — learn from Vocal Flair 40 vs 60 and WordPower 40/60.
    The real goal is a *mechanism*: derive a 40 from the 60 by a transform,
    if possible, rather than positioning by hand.
  - **BlasterAI On the Go** — a purpose-built, reduced-vocabulary board for
    iPhone. (Related: a phone scene generated from the companion iPad's
    coverage — see memory `project_phone_board_ideas`.)
- **Spanish localization** — understand the process for app content and
  display names. `docs/localization-impact.md` is the assessment;
  `TileModel.key` stays language-neutral.
- **A web player** — what someone might build if they forked the repo.
  Player only: scenes are authored in the app, and the web launches an
  instance from a supplied `.blasterscene`. In this repo or a web-only repo
  that makes its own claims about accounts and privacy.
