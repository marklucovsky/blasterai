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
**For most children, there is one scene and it rarely changes.** That is the
point of it: the board a child learns is the board they keep, and words staying
where they were put is what makes it fast. Rebuilding it weekly would undo the
motor learning that makes AAC work at all.

A *second* scene is for something genuinely separate — a class field trip, a
focused therapy session, an unfamiliar topic starting at school. Not "Tuesday",
and not a different mood.

Most of the time, what looks like "we need a new scene for the farm" is really
"we need a **farm page** in the scene they already know." Adding a page keeps
every word the child has already learned exactly where it was. Reach for a new
scene when the whole context is different, not when the topic is.

**Page** — one collection of tappable tiles inside a scene. Not strictly one
screenful: a page longer than the grid pages across, depending on the Board
Layout you have chosen. A scene for a therapy session might have a home
page plus pages for feelings, food, and people. The child moves between them by
tapping a link — see [Pages and navigation](pages-and-navigation.md).

**This is what lets the same board live on a phone.** A page is a set of words,
not a fixed grid, so BlasterAI lays it out for whatever screen it is on — the
same page that shows sixty tiles on an iPad shows fewer at a time on an iPhone
and pages across for the rest. Nothing is dropped and nothing is rearranged: the
words stay in the order the child learned them.

That matters more than it sounds. It means the child's board is not stuck on
the iPad that stayed home. Their vocabulary is on whichever phone is in the
room, which is the difference between having a voice at the table and having
one everywhere.

**Tile** — one word. A picture and a label. Tapping it speaks the word and adds
it to the set the child has collected so far, or opens another page, or both.

What happens to that set is the child's mode, not the tile's. In single-word
mode it simply stands as the running record of what was said. With sentence
mode on, the same set is what the AI turns into a full sentence when Play is
tapped — and the words still speak as they land either way.

**Pack** — a named set of *words*, with no layout. Installing the Farm pack
adds barn, tractor, cow, and so on to your vocabulary. It does **not** create a
scene. Packs are ingredients; scenes are meals.

There's a fifth word you'll see on exactly one screen. **Collections** is where
tiles come from while you're building — a pack, a word class, another scene's
page. It's a source, not a thing you own.

---

## The one thing worth memorising

> A **scene** is the whole thing. A **page** is one screen of it.

Almost every mix-up comes from calling a single page a scene. The child taps a
folder and lands on the feelings *page* — that is still the same
scene, and nothing has been switched.

**A note on the word "board."** In everyday talk, "board" means both — people
say "I made him a board" about the whole thing, and "core board" about a single
screen of high-frequency words. In the tools and standards it's the narrower
one: an Open Board Format board, or a CoughDrop board, is *one screen*. So when
you say board, we'll usually mean **page** — and the BlasterAI 60 scene we ship is
built around exactly the kind of core board you're picturing.

---

## What lives where

```
Scene: "Tuesday speech session"
│
├── Page: home            ← the page the child starts on
│   ├── Tile: i           speaks "I"
│   ├── Tile: want        speaks "want"
│   ├── Tile: feelings    opens the feelings page  ← folder
│   └── Tile: eat         says "eat", opens food    ← doorway
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

**Touch and hold Home** on the rail → **Settings** (Face ID or PIN).
Settings has five tabs — Now, Scenes, Profiles, Activity and Device — and
scenes live under **Scenes**: your list of scenes, plus **New Scene**,
**Import Scene**, and **Manage Vocabulary**.

**On a caregiver device the rail does most of this without the trip.** Its
**Edit** button (**Tools** on a narrower rail) opens one menu with the scene
switcher, tile style, Single Words or Sentences, **Edit This Page**, **Edit
This Scene**, and Settings. **Search** finds any word on the board and shows
the path to it. **Child mode** hands the device over: it swaps in the child's
shorter rail until someone gets back through the Settings lock.

| To do this | Go here |
|---|---|
| Change the page the child is looking at | Rail → **Edit** → **Edit This Page** |
| Switch which scene the child sees, quickly | Rail → **Edit** → pick the scene |
| Make a scene | Settings → Scenes → **New Scene** |
| Edit a scene | Settings → Scenes → tap the scene |
| Switch which scene the child sees | Settings → Scenes → swipe right on it → **Activate** |
| Add a page | Open the scene → **Add Page** |
| Change which page is home | Open the scene → **Scene Info** → **Home Page** |
| Add or remove tiles on a page | Open the scene → tap the page |
| Add a new word to your vocabulary | Open any page → **+** → type the word |
| Hide a word from the child | Settings → Scenes → **Manage Vocabulary** |
| Send a scene to someone | Settings → Scenes → swipe left on it → **Share** |
| Copy a scene before changing it | Settings → Scenes → swipe left → **Duplicate** |

Duplicate and Share are swipe actions, which makes them easy to miss. If you're
about to make a big change to a scene someone relies on, swipe left and
duplicate it first.

---

## A note on the built-in scene

BlasterAI ships with **BlasterAI 60** — a scene built around high-frequency core
words (`i`, `you`, `want`, `go`, `stop`, `more`, `help`, `like`, `not`…) with
category links out to people, food, places, and the rest.

It's the default for a reason: core words are what generalise. Rather than
starting from scratch, most people start from BlasterAI 60 and trim it.

**You can't edit it, and you don't have to think about that.** BlasterAI 60 is
supplied by us and is read-only. The first time you try to change something,
the app offers to make you an editable copy — "BlasterAI 60 (1)" — and
switches the child to it. From then on it is yours, and app updates never touch
it.

That is not a restriction so much as the thing that makes updates safe. Because
none of your work can be inside the scene we ship, we are free to improve the
shipped one, and you are free to change your copy, without either overwriting
the other.

**During the TestFlight pilot, the shipped scene is a question, not a fixture.**
We are not planning to change it every release — a board that moves under a
child is worse than an imperfect one. But this is exactly what we want pilot
feedback on: which core words are missing, which are dead weight, what the home
page should hold. The goal is that the scene shipping after the pilot is one
the clinicians in it have endorsed, rather than one we guessed at.

---

## A note about file names

When you share a scene it goes out as a `.blasterscene` file. "Scene" is the
old internal name for a scene; the file extension kept it so that scenes
shared before the rename still open. Nothing to do — just don't be thrown by
it.

---

## Next

- **[Pages and navigation](pages-and-navigation.md)** — adding pages, linking
  them, choosing home
- **[Adding vocabulary](adding-vocabulary.md)** — new words, bulk lists, and
  what the moderation flags mean
