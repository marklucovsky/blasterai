# Boards, pages, and packs

Start here. Four words do most of the work in BlasterAI, and one of them
probably doesn't mean what you'd assume.

---

## The four words

**Board** — what Aubrey communicates with. A grid shape, the template it's
built on, and a set of pages, one of which is home. Exactly one board is
current at a time. Boards are shareable and carry an author, so you can send
one to a family or a colleague.

If you've used other AAC apps, a board is what TouchChat and Proloquo2Go call a
**vocabulary**, what Snap Core First calls a **page set**, what Grid 3 calls a
**grid set**, and what CoughDrop and the Open Board Format call a **board set**.
**For most users, there is one board and it rarely changes.** That is the
point of it: the board Aubrey learns is the board Aubrey keeps, and words staying
where they were put is what makes it fast. Rebuilding it weekly would undo the
motor learning that makes AAC work at all.

A *second* board is for something genuinely separate — a class field trip, a
focused therapy session, an unfamiliar topic starting at school. Not "Tuesday",
and not a different mood.

Most of the time, what looks like "we need a new board for the farm" is really
"we need a **farm page** in the board Aubrey already knows." Adding a page keeps
every word Aubrey has already learned exactly where it was. Reach for a new
board when the whole context is different, not when the topic is.

**Page** — one collection of tiles inside a board. Not strictly one
screenful: a page longer than the grid pages across, depending on the Board
Layout you have chosen. A board for a therapy session might have a home
page plus pages for feelings, food, and people. The user moves between them by
tapping a folder — see [Pages and navigation](pages-and-navigation.md).

**This is what lets the same board live on a phone.** A page is a set of words,
not a fixed grid, so BlasterAI lays it out for whatever screen it is on — the
same page that shows sixty tiles on an iPad shows fewer at a time on an iPhone
and pages across for the rest. Nothing is dropped and nothing is rearranged: the
words stay in the order Aubrey learned them.

That matters more than it sounds. It means Aubrey's board is not stuck on
the iPad that stayed home. Their vocabulary is on whichever phone is in the
room, which is the difference between having a voice at the table and having
one everywhere.

**Tile** — one word placed on a page. A picture and a label. Tapping it speaks
the word and adds it to the message box, or opens another page, or both. A
**word** is the item of vocabulary itself: what it says, its picture, its
class. A **cell** is a position on the grid, and may be empty. A **folder** is
a tile that opens another page.

What happens to the message box is the profile's setting, not the tile's. With
**Single Words** it simply stands as the running record of what was said. With
**Sentences** on, the same words are what the AI turns into a full sentence
when Play is tapped — and the words still speak as they land either way.

**Pack** — a named set of *words*, with no layout. Installing the Farm pack
adds barn, tractor, cow, and so on to your vocabulary. It does **not** create a
board. Packs are ingredients; boards are meals.

There's a fifth word you'll see on exactly one screen. **Collections** is where
words come from while you're building — a pack, a word class, another board's
page. It's a source, not a thing you own.

---

## The one thing worth memorising

> A **board** is the whole thing. A **page** is one screen of it.

Almost every mix-up comes from calling a single page a board. Aubrey taps a
folder and lands on the feelings *page* — that is still the same
board, and nothing has been switched.

**A note on the word "board."** In everyday talk, "board" means both — people
say "I made him a board" about the whole thing, and "core board" about a single
screen of high-frequency words. In the tools and standards it's the narrower
one: an Open Board Format board, or a CoughDrop board, is *one screen*. Here it
is always the whole thing; one screen of it is a **page**. The BlasterAI 60
board we ship is built around exactly the kind of core board you're picturing.

---

## What lives where

```
Board: "Tuesday speech session"
│
├── Page: home            ← the page the user starts on
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

A word is **one word everywhere it appears**. Put `more` on four pages and it's
four tiles of the same word — one picture, one word class. Change its picture
once and it changes everywhere.

---

## Where you'll find things

Setup is behind a lock Aubrey can't stumble into.

**Touch and hold Home** on the rail → **Settings** (Face ID or PIN).
Settings is a list of ten rows — Profile, Current Board, Message Box, Look
Sound Feel, Boards and Vocabulary, Activity, AI, Help, About and Advanced — and
boards live under **Boards and Vocabulary**: your list of boards, the **+**
menu with **New Board** and **Import Board or Spreadsheet**, and
**Vocabulary**.

**In Setup mode the rail does most of this without the trip.** Its
**Edit** button (**Tools** on a narrower rail) opens one menu with the board
switcher, Tile Style, Message (Single Words or Sentences), **Edit This Page**,
**Edit This Board**, and Settings. **Search** finds any word on the board and
shows the path to it. **Talk mode** hands the device over: it swaps in Aubrey's
shorter rail until someone gets back through the Settings lock.

| To do this | Go here |
|---|---|
| Change the page Aubrey is looking at | Rail → **Edit** → **Edit This Page** |
| Switch which board Aubrey sees, quickly | Rail → **Edit** → **Board** → pick the board |
| Make a board | Settings › Boards and Vocabulary → **+** → **New Board** |
| Edit a board | Settings › Boards and Vocabulary → tap the board |
| Switch which board Aubrey sees | Settings › Boards and Vocabulary → swipe right on it → **Make Current Board** |
| Add a page | Open the board → **Add Page** |
| Change which page is home | Open the board → **Details** → **Home Page** |
| Add or remove tiles on a page | Open the board → tap the page |
| Add a new word to your vocabulary | Open any page → **+** → type the word |
| Hide a word from Aubrey | Settings › Boards and Vocabulary → **Vocabulary** |
| Send a board to someone | Settings › Boards and Vocabulary → swipe left on it → **Share** |
| Write a whole board at once | A spreadsheet → Settings › Boards and Vocabulary → **+** → **Import Board or Spreadsheet** ([guide](spreadsheet-boards.md)) |
| Copy a board before changing it | Settings › Boards and Vocabulary → swipe left → **Duplicate** |

Duplicate and Share are swipe actions, which makes them easy to miss; touching
and holding a board in the list shows the same actions. If you're about to make
a big change to a board someone relies on, duplicate it first.

---

## A note on the built-in board

BlasterAI ships with **BlasterAI 60** — a board built around high-frequency core
words (`i`, `you`, `want`, `go`, `stop`, `more`, `help`, `like`, `not`…) with
folders out to people, food, places, and the rest.

It's the default for a reason: core words are what generalise. Rather than
starting from scratch, most people start from BlasterAI 60 and trim it.

**You can't edit it, and you don't have to think about that.** BlasterAI 60 is
supplied by us and is read-only. The first time you try to change something,
the app offers to make you an editable copy — "BlasterAI 60 (1)" — and
makes it the current board. From then on it is yours, and app updates never
touch it.

That is not a restriction so much as the thing that makes updates safe. Because
none of your work can be inside the board we ship, we are free to improve the
shipped one, and you are free to change your copy, without either overwriting
the other.

**During the TestFlight pilot, the shipped board is a question, not a fixture.**
We are not planning to change it every release — a board that moves under a
child is worse than an imperfect one. But this is exactly what we want pilot
feedback on: which core words are missing, which are dead weight, what the home
page should hold. The goal is that the board shipping after the pilot is one
the clinicians in it have endorsed, rather than one we guessed at.

---

## A note about file names

When you share a board it goes out as a **board file** ending in
`.blasterboard`. Older board files end in `.blasterscene` — "scene" was the
old name for a board — and they still open. Nothing to do — just don't be
thrown by it.

---

## Next

- **[Pages and navigation](pages-and-navigation.md)** — adding pages, linking
  them, choosing home
- **[Adding vocabulary](adding-vocabulary.md)** — new words, bulk lists, and
  what the moderation flags mean
