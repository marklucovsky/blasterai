<!-- SPDX-License-Identifier: Apache-2.0 -->
# Handoff — iPad mini's extra column

Written 2026-09-28 at the close of session 7, replacing the session 6 handoff
(the App Store Connect Distribution tab, now done). Read this first.

## Where things stand

`main` @ `08f5daf`, clean, no worktrees. **TestFlight build 0.9.0 (4) is
uploaded** and running on internal testers; it has been added for external
testers, so Brandi, Scoble and Cognixion should have it shortly.

Session 7 was the board rework and everything that fell out of it — PRs
#97–#104, 916 tests. The board now answers to WordPower Basic 48, folders take
the colour of the page they open (defaulting to uniform blue, because the SLP
advising us preferred it), and Stage IV+ draws the tray as text with a
backspace.

Releases are scripted and the sequence is two commands, in
`docs/release-runbook.md` §4.

## The task: iPad mini gets 13 columns where the others get 12

At default density the mini lays out **13×5 · 65/pg · 79pt** where an 11" and a
13" both give **12×5 · 60/pg**. The extra column shifts every tile one place, so
a child who learns the board on one size does not know it on another — and tile
position is motor planning, which is the whole reason the grid is pinned at all.

### Why it happens

`GridLayoutCalculator` chooses the column count that **maximises capacity**
(`cols × rows`) among those whose tile width falls inside a ±12% band around the
tier's base size (`tickMultiplier`). The mini's base is
`iPadMiniBaseSize = 88`, so the band is **78.6 – 98.6pt**.

Thirteen columns lands at **79pt** — 0.4pt inside the bottom of that band — and
13×5 = 65 beats 12×5 = 60. It wins by a hair, on a rule that was never asked
whether the answer should match the other iPads.

### The one-line version, and why it may not be enough

Raising the mini's base excludes 13 columns from the band:

    iPadMiniBaseSize: 88 -> 92        // band becomes 82.1 - 103

79pt then falls outside it, and 12 columns (~86pt) is the widest that qualifies.

**Check this before trusting it.** Twelve columns means ~86pt tiles rather than
79pt, so each cell is taller — and the mini may no longer fit **five** rows. If
it drops to four, capacity goes 65 → 48 and the 59-tile home page stops fitting
on one screen. Today's overlay reads `59t/1p`; the fix could make it `59t/2p`.

That trade is the actual decision, and it is not obviously worth taking: a
shifted grid is still one reach away, where a second page is not. **Answer
"does 12×5 fit on the mini?" first** — the debug overlay prints everything
needed, so it is one build and one look.

If five rows do not survive, this is a layout question rather than a constant,
and the options worth weighing are a shorter label band on the mini, tighter
vertical spacing, or accepting 13 columns there and saying so.

### Where to look

- `claudeBlast/Services/GridLayoutCalculator.swift` — the tier constants are
  lines 72–100, the column search is the `for cols in 1...30` loop.
- The 13" tier (`iPadLargeBaseSize = 111`) was added the same way in session 7
  and is the precedent for how a tier gets dialled in.
- `tools/show_page_grid.py` renders the 12-column layout the mini should match.

## Also open, smaller

- **`bus` is on no page** — the only vehicle in the vocabulary, so no category
  wants it.
- **Word order inside leaf pages.** Brandi asked; the tool and technique are
  ready (`show_page_grid.py --page`, hand-placed prefix then class selector).
- **`is` is typed as a function word**, so it sits grey rather than green.
- **The Time folder is blue by accident** — its words are typed `adjective`
  because `PartOfSpeech` has no adverb case.
- **At Stage IV+ the interaction mode is invisible from the board.** The
  caregiver menu is the only signal.

See `docs/board-rework-followups.md` for the full list and what was corrected.

## Not this session

**The keyboard.** Its open question is whether `AVSpeechSynthesizer` can voice a
phonetic keyboard at all — long and short vowels, `ph`/`ch`/`sh`. Answer that
before designing any keys. Brandi has offered input and should be asked before
the layout is chosen.
