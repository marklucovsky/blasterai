<!-- SPDX-License-Identifier: Apache-2.0 -->
# Handoff: the end of session 19 and what comes next

Rewritten 2026-11-17 at the close of session 19. It replaces the session 18
handoff, which is in git history. **Next: session 20.** Read this first. The
plan is rough: revisit it at the start of each session.

**Reordered at the close (Mark, 2026-11-17): the keyboard comes first.** Sessions 21 and 22 move ahead of the vocabulary expansion, which becomes session 22+. The section numbers below are the old ones; the order is keyboard research, keyboard build, then vocabulary.

## Where things stand

Session 19 was the build 10 shakeout, the admin cleanup and the naming pass. It
ended with build 12. Worktree `build-10-shakeout-admin-31f5bd`.

| PR | What |
|---|---|
| #187 | Settings as one list of plain rows; Message Box; quick settings |
| #188 | Profile pass: profile-owned AI mode and message settings, About and Help |
| #189 | Boards list (search, filter, +) and board editor pass |
| #190 | Me pages: Always, Pinned, Includes, sharing with topics |
| #191 | Me page Preview: where added tiles land and why |
| #192 | Copy pass: *the user*, Talk/Setup mode, Sentences, message box |
| #193 | Board terms: scene → board, navigation bar, Tile Style, `.blasterboard` |
| #194 | Guides in the agreed words; The Me page guide |
| #195 | My Topics: a fixed, locked first cell on every Me page |
| #196 | Sharing keeps every tile setting; clearer import prompts |
| #197 | One word chooser and one page chooser, browsed by folder |
| #198 | Tester notes for build 11 |
| #199 | Pack words kept through app updates; New Board on the standard grid |

- **Build 12 (1.0.0)** was uploaded 2026-11-17 and tagged `v1.0.0-12` at
  `45ffed30`. Build 11 (`v1.0.0-11`) was never shared and is expired.
- **The naming decision:** the person using the board is **the user**, and the
  device modes are **Talk mode** and **Setup mode**. "Child" is gone from UI
  copy and guides. The sentence prompt and evals still say "child"; they change
  in the tuning round at the next model deprecation.
- **CloudKit:** ChildProfile `aiModeRaw` and `trayPicturesRaw` were deployed to
  Production 2026-11-17.
- **App Store:** 1.0.0 was resubmitted after the 2026-11-08 rejection (2.3.6
  disputed, 1.4.1 disclaimer added). Check its status first.
- **Site:**
  - the guides are in the new words, and Help in the app opens them;
  - a story page, `/guides/make-it-theirs/` (Aubrey, grandpa's iPad, the Me
    page, Room 4), went out with Facebook and X posts on 2026-11-17.
- **The editor-open freeze is closed.** Mark's Profile re-trace on device was
  smooth. The slow first tap under the debugger is a Debug-build artifact.

## Carried forward from session 19

- **First PR: bump the build to 13.**
- **Next session starts with the keyboard** (sessions 21 and 22 below). Mark has thoughts and screenshots.
  - Start from the parts of Avaz's and TouchChat's keyboards that work: their layouts and behaviour, built our own way, not copied screen for screen.
  - Enough to show the intent. Speech for letters and numbers doesn't have to be solved first; note what's said wrong and keep going.
- **SDK 27 by April 2027.** App Store Connect warned on build 11 (ITMS-90725): we build with the iOS 26.2 SDK, and from April 2027 uploads must use the iOS 27 SDK (Xcode 27). Move the build to Xcode 27 when it ships, before that date.
- **App Store listing for the next version.**
  - The draft is `~/Desktop/blasteria/BlasterAI-appstore-build11.txt`.
  - Touch App Store Connect only after 1.0.0 is through review and released.
  - Then fold it into `docs/app-store-listing.md`, which still lacks the 1.4.1
    disclaimer and the 2.3.6 dispute.
- **The Beta App Description** still says "for non-verbal children". It's a
  positioning call for Mark.
- **Received vocabulary packs** have no "never installed here" prompt. #196 did
  this for boards only.
- **Boards made by hand before #199** declare no grid, so they can't be topics.
  Either a "Use the standard layout" switch in the board editor, or leave it.
  Never convert them automatically: an old 12 × 5 board would lose its top row
  to the navigation bar.
- **Small checks:**
  - Classic *awake* and *movie* tile corners;
  - the phone's bottom navigation bar, which waits for tester feedback;
  - `nav-home.jpg` in the site guides, which shows the old board.
- **Ideas from this session, not scheduled:**
  - **Add a folder while editing,** Avaz-style: make a page and the folder
    that opens it in one step. Room 4 needed two boards for two folders.
    Boards stay the unit a Me page includes.
  - **An edited page still taking non-colliding updates.** Never built. Today
    an edited copy of a BlasterAI 60 page is a snapshot. It keeps art updates,
    because art belongs to the word, and misses new words.

## Session 20: vocabulary expansion, and what it opens up (likely two sessions)

About 400 new words is the centrepiece. It's also the vehicle for exploring and developing:

- **Expand the vocabulary and its art.**
  - Choose the words from the VF60 core gaps, Brandi round three and a school-age frequency list.
  - Class every word (the #178 rubric), and add them to the BlasterAI 60 folders.
  - Art in all five styles. It spends Mark's key, so ask first.
  - **The art model collides with the deadline.** If GPT-Image-2.6 is available by then, generate the new art on it and fold the migration (session 23) into this work, rather than shooting 400 words on a model that dies on 2027-02-10.
- **One word search everywhere.**
  - The searches still to unify (#197 made one word chooser and one page chooser):
    - Find Word
    - Manage Vocabulary
    - Add Tiles (its pack chips)
    - the typing suggestions
    - Use Existing Art
  - Inventory them, then make search and filter one shared component. Filters: class, page, has art, level, scene.
  - **Folder-based browsing is done (#197):** the page chooser is a tree, its search finds a page by a word on it, and `>` in the sheet editor offers Browse.
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
- **Sharing Me is done (#190).** A Me page travels with its includes and topic boards, and sending it again updates it in place. What's left is the base-and-tweak question: whether later edits to an SLP's base flow on to each profile, the way templates do.
- **Word pass 2.** Art for the cells held in `word_pass_2.json`, and a Reactions folder.
- **Malawi image set.** A P3D derivative, driven by the guide from session 20.

## Deadlines

| Date | What |
|---|---|
| **2027-02-10** | gpt-image-2 shuts off; a build on the new model must ship before it |
| **April 2027** | Uploads must be built with the iOS 27 SDK (Xcode 27); ITMS-90725 warning on build 11 |
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
