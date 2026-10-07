<!-- SPDX-License-Identifier: Apache-2.0 -->
# Handoff — App Store dry run

Written 2026-10-06 at the close of session 8, replacing the session 7 handoff
(the iPad mini's extra column, now fixed in #105). Read this first.

## Where things stand

Session 8 set out to make the app ready for an App Store **dry run** — submit
with *Manually release this version*, so an approval ships nothing — and grew
into the work the reviewer and the testers would hit first. PRs #105–#118:

- **Trust and keys.** The `OPENAI_API_KEY` override exists only in DEBUG (#106).
  *Enable AI Features* is explicit, versioned consent before anything reaches
  OpenAI; revoking leaves the key dormant (#107). A gifted key file installs
  from every path, including before onboarding finishes (#108).
- **The board.** Back shares Home's cell (#109). Tile Density became three
  fixed Board Layouts per device kind (#110); scenes declare the grid they were
  designed for (#111) and print from it (#112). Placement pass (#114), then 84
  new words, four noun folders on Groups and art in all five sets (#115).
- **Caregiver side.** Manage Vocabulary shows every route to a word; the
  default board is **BlasterAI 60** (#116). Copies are numbered
  `BlasterAI 60 (1)` with a "Copied from" line (#117).
- **Tester notes** are per build now: *What's new* and *What to test* at the top
  of `docs/beta-review-notes.md` §2, earlier builds below (#118).

**CloudKit Production** has both post-promotion fields
(`BlasterScene.designedFor`, `ChildProfile.linkColorModeRaw`), deployed
2026-10-06. The second had shipped in build 4 a week before its deploy — the
runbook §0 now says to compare `tools/expected_cloudkit_schema.py` with
Production before every upload.

## First: check the session can upload

Build **0.9.0 (5)** is uploaded (2026-10-06, `main` @ `23665b0`). It stopped
once at the upload step because Claude's shell did not have `ASC_KEY_ID` /
`ASC_ISSUER_ID`: Claude's Bash loads `~/.zshrc` once, at session start, and the
exports were added to it during the session. Start this one by checking, without
printing the values:

    [ -n "$ASC_KEY_ID" ] && [ -n "$ASC_ISSUER_ID" ] && echo ok

If it is not `ok`, run uploads with `!` in the prompt, or pass both inline.

Build 5's What to Test is `build/what-to-test.txt` (`make_tester_notes.py`).
Testers who had a key will see Enable AI Features once; until they accept, the
board runs one word at a time. The notes say so.

## Then: the site (`~/src/blasterai-site`, direct to main)

Mark is testing build 5 as an internal tester and moving external testers to it
on 2026-10-07. Meanwhile:

- **Vocabulary counts.** The board grew by 84 words to 619 and gained four noun
  folders; every page that quotes a count, a page list or "Core-First" needs the
  new numbers and the name **BlasterAI 60**.
- **Guides: Board Layout and designed-for grids.** Teach that a device picks
  Standard / Large / Largest (iPad 12×5, 10×4, 9×4; iPhone 4×5, 3×4, 2×4), that
  a scene can declare the grid it was designed for so its words keep their
  places, and that a caregiver can opt a device out. Printing starts from the
  scene's grid.
- `docs/guides/make-your-first-scene.md` and `scenes-pages-and-packs.md` were
  updated here for BlasterAI 60 and `(1)` copy names; the site copies were not.
- Then the main pages and the "how we built it" guide, for whatever session 8
  made stale.

## After that: collect the App Store material

1. **Screenshots** with `tools/screenshot_sweep.sh` — 13" iPad and 6.9" iPhone;
   the Mac listing reuses the iPad set.
2. **`docs/app-store-listing.md`** (direct to main): name, subtitle,
   description in the pitch order of `docs/final-countdown-plan.md` §"The order
   of the pitch", keywords, support and privacy URLs, category Education, price
   Free, availability US / Canada / Australia / UK, age-rating answers, and the
   privacy-label answers with their reasoning ("Data Not Collected").
3. **Review Notes**, from `beta-review-notes.md` §1: the gifted key attached as
   a file and how to install it, why Education and not Kids, what keyless does.
4. **Mint the reviewer's key** with `tools/make_gifted_key.py` on its own OpenAI
   project with a low cap; add it to the ledger.
5. **What's New in This Version** — the same list as build 5's *What's new*.
   A release build is `preflight_release.py`, then `release.py --bump build`,
   then `release.py --no-bump --upload --skip-preflight` (runbook §4).
6. **Submit**, Version Release set to manual.

## Also queued

- **Brandi** has the abstract-word cut sheet; we went with the symbol approach
  for because/but so she can judge them in context.
