# Boards, pages, and packs

Start here. Four words do most of the work in BlasterAI, and one of them
probably doesn't mean what you'd assume.

---

## The four words

**Board** — what the child communicates with. A named set of pages, one of
which is home. Exactly one board is active at a time. Boards are shareable and
carry an author, so you can send one to a family or a colleague.

This is what your field calls a board. Core board, activity board, fringe
board — same idea.

**Page** — one screen of tiles inside a board. A board for a therapy session
might have a home page plus pages for feelings, food, and people. The child
moves between them by tapping a navigation tile.

**Tile** — one word. A picture and a label. Tapping it either speaks the word
(and adds it to the sentence), or opens another page, or both.

**Pack** — a named set of *words*, with no layout. Installing the Farm pack
adds barn, tractor, cow, and so on to your vocabulary. It does **not** create a
board. Packs are ingredients; boards are meals.

There's a fifth word you'll see on exactly one screen. **Collections** is where
tiles come from while you're building — a pack, a word class, another board's
page. It's a source, not a thing you own.

---

## The one thing worth memorising

> A **board** is the whole thing. A **page** is one screen of it.

Most confusion is someone using "board" for a single page. The child taps a
navigation tile and lands on the feelings *page* — still the same board.

---

## What lives where

```
Board: "Tuesday speech session"
│
├── Page: home            ← the page the child starts on
│   ├── Tile: i           speaks "I"
│   ├── Tile: want        speaks "want"
│   ├── Tile: feelings    opens the feelings page  ← navigation tile
│   └── Tile: food        opens the food page      ← navigation tile
│
├── Page: feelings
│   └── happy, sad, angry, tired, scared …
│
└── Page: food
    └── apple, cracker, juice, more, all_done …
```

A word is **one tile everywhere it appears**. Put `more` on four pages and it's
still the same tile — one picture, one word class. Change its picture once and
it changes everywhere.

---

## Where you'll find things

The caregiver side is behind a gate the child can't stumble into.

**Long-press the Home button** in the sentence tray → the caregiver menu →
**Admin** (Face ID or PIN). Admin has five tabs; boards live under **Boards**.

That tab has your list of boards, plus **New Board**, **Import Board**, and
**Manage Vocabulary**.

| To do this | Go here |
|---|---|
| Make a board | Admin → Boards → **New Board** |
| Edit a board | Admin → Boards → tap the board |
| Switch which board the child sees | Admin → Boards → swipe right on it → **Activate** |
| Add a page | Open the board → **Add Page** |
| Change which page is home | Open the board → **Board Info** → **Home Page** |
| Add or remove tiles on a page | Open the board → tap the page |
| Add a new word to your vocabulary | Open any page → **+** → type the word |
| Hide a word from the child | Admin → Boards → **Manage Vocabulary** |
| Send a board to someone | Admin → Boards → swipe left on it → **Share** |
| Copy a board before changing it | Admin → Boards → swipe left → **Duplicate** |

Duplicate and Share are swipe actions, which makes them easy to miss. If you're
about to make a big change to a board someone relies on, swipe left and
duplicate it first.

---

## A note on the built-in board

BlasterAI ships with **Core-First** — a board built around high-frequency core
words (`i`, `you`, `want`, `go`, `stop`, `more`, `help`, `like`, `not`…) with
category links out to people, food, places, and the rest.

It's the default for a reason: core words are what generalise. Rather than
starting from scratch, most people **duplicate Core-First and trim it**.

You can't delete Core-First, and it updates when the app does. If you've
customised it, the update sheet offers to save a copy first — take that offer.

---

## A note about file names

When you share a board it goes out as a `.blasterscene` file. "Scene" is the
old internal name for a board; the file extension kept it so that boards
shared before the rename still open. Nothing to do — just don't be thrown by
it.

---

## Next

- **[Make your first board](make-your-first-board.md)** — three ways, including
  one that needs no AI key
- **[Pages and navigation](pages-and-navigation.md)** — adding pages, linking
  them, choosing home
- **[Adding vocabulary](adding-vocabulary.md)** — new words, bulk lists, and
  what the moderation flags mean
