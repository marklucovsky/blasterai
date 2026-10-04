<!-- SPDX-License-Identifier: Apache-2.0 -->
# After the board rework — what is left

Written 2026-09-26 at the merge of PR #97, rewritten 2026-09-28 at the close of
session 7 (`main` @ `5a68db6`, PRs #97–#104).

**Almost all of the original list is done.** It is rewritten rather than deleted
because two of its entries were *wrong*, and a follow-up list that quietly
deletes its own mistakes teaches nothing.

## Done

- **Usage testing** — Mark drove the board, and it produced most of what
  follows.
- **TileScripts** — updated to navigate through the folders rather than tapping
  words directly. Nothing was broken: **a tap resolves against the whole
  vocabulary, not the current page**, so moving `mom` off the home page broke no
  script. That is worth keeping in mind, because the opposite was assumed first
  and a check written on the assumption reported 38 problems where there were
  none.
- **Questions and Feelings out from under Social** (#98) — with a `groups`
  folder to pay for the cells.
- **Website screenshots** — regenerated twice, and every page on the site given
  a social card it did not have.

## Corrected

- **`don't` is not missing.** The original list said it was the one word both
  reference boards carry that we do not have at all. It is in `vocabulary.json`
  with art in all five sets, and it is now on the home page. What was missing
  was a *placement*, not a word — an audit that checks vocabulary and an audit
  that checks placement answer different questions.
- **The keyboard is not a board feature.** It was listed here as a placeholder
  page to fill in. It is a new input mode whose real open question is whether
  `AVSpeechSynthesizer` can voice a phonetic keyboard at all — long and short
  vowels, `ph`/`ch`/`sh` digraphs. Its own session, deliberately outside the
  TestFlight iteration.

## Still open

- ~~**`bus` is on no page.**~~ Placed on Places in session 8, with the other
  second homes from `tools/audit_page_placement.py` (sick/hurt/tired/feel/…
  on Body & Health, feelings typed `describe` on Feelings, the mealtime words on
  Food and Drinks). The audit reports anything left on no page.
- **Word order inside leaf pages.** Brandi: *"touch chat orders them by alpha
  order. Do we want them organized in a certain way?"* Ours are in
  vocabulary-file order, which is alphabetical only by accident — so `actions`
  opens on `answer, ask, bathe, blow, blush` while `want` is on page 2. The tool
  is built (`show_page_grid.py --page <name>`) and the technique is pinned by a
  test: name the important words first, then let the class selector fill in
  behind them. No exclude list, because every command skips a key already on the
  page.
- **`is` is typed as a function word**, so it sits grey with `to` and `for`
  rather than green with the verbs. Defensible; worth a decision.
- **The Time folder is blue by accident.** `today`, `soon`, `later`, `first`,
  `next` and `last` are all typed `adjective` because `PartOfSpeech` has no
  adverb case, and the folder takes its colour from them.
- **WordPower colours `GROUPS` orange** where we resolve a folder of folders to
  wayfinding — recorded in `tools/reference_boards/wordpower_colors.txt` as an
  open question rather than a defect.
- **At Stage IV+ the interaction mode is no longer visible from the board.**
  Both modes draw the tray as a line of words with the same three controls, so
  the caregiver long-press menu is the only signal. If that is too quiet, the
  cheapest fix is the speech bubble: sentence mode has one and word mode does
  not, which is already a difference and simply is not labelled as one.
