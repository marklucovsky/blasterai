<!-- SPDX-License-Identifier: Apache-2.0 -->
# Handoff: the end of session 14 and what comes next

Rewritten 2026-10-28, partway through session 14, replacing the sessions 12–16
plan of 2026-10-19; updated 2026-10-29 at the session's close. Read this first.

## Where things stand

Session 14, worktree `cb-vocab-tree` (PRs #150–#158):

| PR | What |
|---|---|
| #150 | BlasterAI 60 gets a visible hierarchy: a system row, doorway words (go → Places), static folders |
| #151 | Word pass 1: 405 words into the folders |
| #152 | Art for pass 1 in all five styles; a word-class audit; hidden words hold their cell |
| #153 | Classic art cut off its white ground, for the tinted look |
| #154 | Main-actor isolation warnings fixed (vt0r) |
| #155 | The square tile look, behind a Classic/Square setting |
| #156 | The 10×6 board with a control rail; row 1 is inherited by every page, never stored |
| #157 | Square tiles on every board surface; the tray lines up with the grid; underline way markers; Social, Feelings, I and Describe clustered |
| #158 | Questions, Places, Actions and Describe's folder pages clustered |
| #159 | The screen check and the phone: column bands, phone landscape, Tools, fixes (below) |

**Mark, 2026-10-29: this is the 1.0 build**, before word pass 2. Session 15
ships it.

**Clustering** follows Avaz: two blocks of four either side of an empty column
5, each row a cluster, folders in columns 9–10. Actions is the exception: Home's
column 5 (go, want, like, watch, make) keeps its Home cells there. Pages are
hand-tuned through `at` rows in `tools/board_spec/blasterai60.json`.
`tools/board_spec/word_pass_2.json` lists the words that need art, with the
cells held for them: good morning and good afternoon on Social, and eight
question phrases.

**Field feedback, 2026-10-28.** Aubrey's SLP saw the new layout, and Brandi
was online.
- What resonated most: **extending the system board** with cheap topic
  scenes, for sharing or for one child.
- **Gestalt language processing.** The SLP starts every child on about 30
  phrases. For these children the phrase's melody is the meaning, so she wants a
  **recorded voice override per tile**.
- **Free** matters: one child waits until January for a trial device, then up
  to six months more. She suggested Android for the Fire tablet.
- Brandi's projects:
  - **Malawi AAC.** P3D's people drawn with a Malawian look, recorded
    voices, no sentence generation.
  - **A Sunday School board**, by a pastor who uses AAC.

**App Review rejected 0.9.0 (7)** on 2026-10-28 for three things:
- 2.3.7: "free" in the subtitle.
- 2.1(b): questions about the business model; the answer is bring your own
  OpenAI key, and nothing is sold.
- 2.3.6: the age rating claims In-App Controls; it should say None.

## Session 14, the rest: done (#159)

Every surface #155–#158 touched was checked: iPad landscape and portrait, the
iPad mini, the iPhone in both orientations, the tray in both modes, the page
editor, scene preview, coverage and the board PDF.

**Bugs fixed**
- Edit → Settings crashed (`AttributeGraph precondition failure: setting
  value during update`): `TileImageResolver`'s caches were observed and
  filled from view bodies. They are `@ObservationIgnored` now.
- The phone tray still drew the boxed chips; it is the white tray now.
- Coverage never lit the system row; a press on it from the page counts now.
- Coverage drew a page at full width and scrolled; each screen fits now.

**The phone**
- **Portrait:** row 1 scrolls sideways (a chevron and a one-time slide hint
  at launch). The page scrolls in 4-wide column bands of the iPad page
  (`ColumnBands`). Only blank columns *before* a band are skipped; a blank
  inside a band is kept, so a 3-wide cluster keeps its trailing break
  (Seasons) and the next cluster starts its own band.
- **Landscape:** the iPad's 10×6 page, scaled, with the side rail. Square
  tiles go wide to fill the width (as Avaz does), the link marker moves to
  the tile's corner, the path line is hidden, and the single-word strip is
  64pt. Tiles are about 70×54pt on a Pro Max.
- Family, Cooking, Senses, Taking care, Talking and Sounds were laid out for
  the phone's bands.

**The rail.** Tools replaces Levels and Edit everywhere but iPad landscape:
Topics over Search, then Tools, whose menu carries the level stepper and the
Edit menu. Long-press Home now offers only Caregiver Controls (in Child mode)
and Settings. The "Caregiver Menu Quick Actions" setting is gone.

**Do better, with the editor work or on feedback**
- Page editor sizing.
- Sentence-mode controls in phone landscape: Play over Done needs the 94pt
  tray. Defer until testers say.
- The empty band between the grid and the bottom rail in iPad portrait.
- Home's third phone band holds only columns 9–10.
- A band can cut a run on a page that doesn't use the split (Actions).
- The iPhone 16e is unchecked; its landscape tiles will be smaller again.
- **Per-tile audio**, starting with Social › Sounds (GLP feedback).

**The printed book.** The PDF prints in board order, with path titles (#159).
Next, on feedback:
- **Print a shared folder in both places.** Toys is opened from Play and from
  I. A book could print it after each, so it's a few pages from wherever you
  are. It makes the book longer, so make it a toggle.
- **Edge tabs by section.** Put a coloured tab on the page edge, stepped down
  for each row-1 folder, like a dictionary's thumb index. People, Actions,
  Time and the others can then be found with the book closed.
- **Page numbers and a contents page.** Number the sheets and add a contents
  page. Each folder tile prints "→ p. 14", so a caregiver turns straight to
  the page the folder opens.
- **A cover,** with the board's name and the child's name.
- **A binding gutter** for a ring binder or laminating, and an option for cut
  lines.

## Session 15: new UI to testers on TestFlight

- Bump the build number.
- Check that no CloudKit schema change is pending. #156 changed only
  `designedFor` strings.
- Write What to Test and the tester PDF (`BlasterAI-TestFlight-build<N>.pdf`).
- **Use the same build for the resubmission.**

### Parallel track: the resubmission (its own session if needed)

- **New screenshots**, all of them, from the new UI. They must show real
  captures. No price words in any screenshot.
- **Copy:**
  - Take "free" out of the subtitle. It may go in the description.
  - Answer the four 2.1(b) questions in Reply to App Review, and put the
    bring-your-own-key model at the top of the review notes.
- **Age rating:** set Parental Controls and Age Assurance to None.
- Then resubmit the build from session 15.

## Session 16: prototype mountable scenes

Extending the system board is the high-value move, and we need a scene story
around it.

**Already in place:**
- `<system>:` links.
- Scenes built on the template inherit row 1 and the rail.
- The rail has a Topics/My slot, disabled until now.

**Two levels to prototype:**
1. **Topics hub.** Topics/My opens a page of mounted topics. A topic is a small
   scene whose pages inherit row 1 and the rail, so the child never leaves the
   system board.
2. **Extensions.** A topic adds a folder to a free folder slot (columns 9–10) on
   a system page, for example People › My family or Places › Grandma's. That is
   the folder rule as it stands: the folder extends the path, and the system
   page itself is unchanged.

**Decide:**
- Where the mount list lives. A local setting is enough for the prototype;
  sync needs a schema change.
- How a topic is made: AI, by hand, or from a URL.
- What happens when two topics want the same slot.
- How create / mount / share reads to a caregiver.

**Test cases:** the SLP's 30 starter phrases; the Sunday School board.

## After that

- **Per-tile recorded voice.** It serves GLP phrases, Malawi and any
  language without TTS. Audio sits on the tile like `userImageData`, as a
  CloudKit asset, which is a schema change.
- **Word pass 2.** Art for the cells held in `word_pass_2.json`, where
  generation spends Mark's key, so ask first. A Reactions folder beside Sounds
  would make room on Social. Phase 2 depth (actions, feelings, describe,
  places, people) comes from a school-age frequency list; ask Brandi for one.
- **Sharing boards.** URL scene install and a first `blasterai.app/boards`.
  Bugfixes in the same pass:
  - Scene share drops `linkColor` / `linkColorIsAuto` (`SceneExporter.swift`).
  - Prompt for scenes that were never imported.
  - Tell the importer the file's level when "Replace Mine" takes it.
- **Editor revisit.** A grid-first page editor on landscape iPad and Mac, plus
  the "do better" list from the screen check.
- **Malawi image set.** A P3D derivative with its own style prompt and
  reference pack. Show Brandi a small sample first.

## Deadlines

| Date | What | Status |
|---|---|---|
| **2027-01-14** | `gpt-4o`, `gpt-4o-mini`, `gpt-4.1*` retire | Done: build 9 moved to GPT-6 |

## Later, not time-bound

- **Android or a web player** for Fire tablets: a port versus a player. The
  player is far cheaper and covers a child waiting for a device.
- **BlasterAI 40** by a transform from the 60, and **BlasterAI On the Go**
  for iPhone (20 cells).
- **Spanish localization**: `docs/localization-impact.md`; `TileModel.key`
  stays language-neutral.
- **Keyboard and grammar**:
  - prefixes (some- / any- / every-)
  - word endings (-s / -ed / -ing)
  - word forms, including the inflection bubble
  - all with clinical guidance
- **Level map with Brandi**, over the new board.
- **Voice selection guide** on the site.
- **OBZ import, maybe.**
- **Small PRs:**
  - drop runtime tone chaining
  - scene word-sense hints ("shears" → scissors)
  - remove promoted-tile leftovers
  - rebuild the header image
