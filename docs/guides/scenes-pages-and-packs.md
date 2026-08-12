# Scenes, pages, and packs

Start here. Four words do most of the work in BlasterAI, and one of them
probably doesn't mean what you'd assume.

---

## The four words

**Scene** — what the child communicates with. A named set of pages, one of
which is home. Exactly one scene is active at a time. Scenes are shareable and
carry an author, so you can send one to a family or a colleague.

If you've used other AAC apps, a scene is what TouchChat and Proloquo2Go call a
**vocabulary**, what Snap Core First calls a **page set**, what Grid 3 calls a
**grid set**, and what CoughDrop and the Open Board Format call a **board set**.
We call it a scene because it usually corresponds to a situation — bedtime, a
farm visit, a therapy session, a trip to Grandma's — and naming it that way
tends to make people build better ones.

**Page** — one screen of tiles inside a scene. A scene for a therapy session
might have a home page plus pages for feelings, food, and people. The child
moves between them by tapping a navigation tile.

**Tile** — one word. A picture and a label. Tapping it either speaks the word
(and adds it to the sentence), or opens another page, or both.

**Pack** — a named set of *words*, with no layout. Installing the Farm pack
adds barn, tractor, cow, and so on to your vocabulary. It does **not** create a
scene. Packs are ingredients; scenes are meals.

There's a fifth word you'll see on exactly one screen. **Collections** is where
tiles come from while you're building — a pack, a word class, another scene's
page. It's a source, not a thing you own.

---

## The one thing worth memorising

> A **scene** is the whole thing. A **page** is one screen of it.

Most confusion is someone using "scene" for a single page. The child taps a
navigation tile and lands on the feelings *page* — still the same scene.

**A note on the word "board."** In everyday talk, "board" means both — people
say "I made him a board" about the whole thing, and "core board" about a single
screen of high-frequency words. In the tools and standards it's the narrower
one: an Open Board Format board, or a CoughDrop board, is *one screen*. So when
you say board, we'll usually mean **page** — and the Core-First scene we ship is
built around exactly the kind of core board you're picturing.

---

## What lives where

```
Scene: "Tuesday speech session"
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
**Admin** (Face ID or PIN). Admin has five tabs; scenes live under **Scenes**.

That tab has your list of scenes, plus **New Scene**, **Import Scene**, and
**Manage Vocabulary**.

| To do this | Go here |
|---|---|
| Make a scene | Admin → Scenes → **New Scene** |
| Edit a scene | Admin → Scenes → tap the scene |
| Switch which scene the child sees | Admin → Scenes → swipe right on it → **Activate** |
| Add a page | Open the scene → **Add Page** |
| Change which page is home | Open the scene → **Scene Info** → **Home Page** |
| Add or remove tiles on a page | Open the scene → tap the page |
| Add a new word to your vocabulary | Open any page → **+** → type the word |
| Hide a word from the child | Admin → Scenes → **Manage Vocabulary** |
| Send a scene to someone | Admin → Scenes → swipe left on it → **Share** |
| Copy a scene before changing it | Admin → Scenes → swipe left → **Duplicate** |

Duplicate and Share are swipe actions, which makes them easy to miss. If you're
about to make a big change to a scene someone relies on, swipe left and
duplicate it first.

---

## A note on the built-in scene

BlasterAI ships with **Core-First** — a scene built around high-frequency core
words (`i`, `you`, `want`, `go`, `stop`, `more`, `help`, `like`, `not`…) with
category links out to people, food, places, and the rest.

It's the default for a reason: core words are what generalise. Rather than
starting from scratch, most people **duplicate Core-First and trim it**.

You can't delete Core-First, and it updates when the app does. If you've
customised it, the update sheet offers to save a copy first — take that offer.

---

## A note about file names

When you share a scene it goes out as a `.blasterscene` file. "Scene" is the
old internal name for a scene; the file extension kept it so that scenes
shared before the rename still open. Nothing to do — just don't be thrown by
it.

---

## Next

- **[Make your first scene](make-your-first-scene.md)** — three ways, including
  one that needs no AI key
- **[Pages and navigation](pages-and-navigation.md)** — adding pages, linking
  them, choosing home
- **[Adding vocabulary](adding-vocabulary.md)** — new words, bulk lists, and
  what the moderation flags mean
