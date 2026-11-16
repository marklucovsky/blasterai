# Adding vocabulary

Six ways to add a word, what word class actually does, and why the app
sometimes flags a word before letting you add it.

---

## The fast one

Open any page in the page editor (**Edit This Page**) → **Add Words…** → type
the word in **Search or add a word**.

If it isn't in your vocabulary, the sheet offers **Add "unicorn"**, asks for a
type, and adds it. Its picture is drawn from the board's **Artwork** page (see
[Where art comes from](#where-art-comes-from)).

That's it. The other five routes are for volume or precision.

**Check the board first.** BlasterAI 60 has more than a thousand words, and the
one you want may already be a folder or two deep. **Search** on the rail in Setup
mode lists every place a word lives on the board, takes you there with a tap,
and says why when a place can't be reached (above the user's level, hidden).

---

## The other five

**A photo or a specific picture** — **Add Words…** → type the word → **More options
(photo, different type)…**. Gives you the full **New Word** sheet: a photo from
your library (square-cropped), or AI art with a refinement field. **Refine**
keeps the picture and applies a change; **Regenerate** makes a new one.

**A list you already have** — **Add Words…** → **Paste a word list**. One per line:

```
word, wordClass
rocket, object
astronaut, people
earth, place, Planet Earth
```

An optional third column is the display name, for when the label should differ
from the key. Unknown classes still work but render in a neutral color and get
flagged. Tap a class chip to insert it correctly.

**From a pack** — in the board editor, **Add Page** → **Start from a vocabulary pack** installs all
of that pack's words and builds a page from them.

**Ask the AI** — **Add Words…** → the suggest bar → "emotions for a 6-year-old" → **Go**.
Suggested words are created as real vocabulary; if you dismiss without placing
any on a page, they're rolled back.

**By word class** — in the board editor, **Add Page** → **Add a page of one word class** doesn't add
anything new. It pulls every word of that class you already have.

---

## Word class is not decoration

Every word has a class — actions, people, food, describe, feeling, place, and
so on. It does two visible things and one invisible one:

- Filters the tile picker
- **Tells the AI what the word means in this context**
- Feeds the grammar guess when nothing better is known

It does **not** set the tile's color. Color comes from the word's *part of
speech* — the Fitzgerald key — which is a separate, grammatical answer: `apple`
is orange because it is a noun, not because it is filed under food. Class only
reaches color as a last-resort fallback, for a word the app has never seen and
has no grammatical entry for.

That third one matters. The class goes to the model as authoritative:

`snack bar (food)` means something you can eat; `snack bar (place)` means
somewhere you can go and visit. A word filed under the wrong class produces
confidently wrong sentences.

The same word can exist in two classes deliberately — `color` the action and
`colors` the category page. When you add a word that already exists, the app
offers **Add "x" as a different type**, and disables the classes already taken.

---

## When a word gets flagged

Before a new word becomes a tile — and before any artwork is generated — it
goes through an age-appropriateness check. You'll see **Checking new words…**
and then a per-word verdict.

Three outcomes:

| | What you see | What you can do |
|---|---|---|
| **Allowed** | Nothing — it's added | — |
| **Flagged** 🟡 | "sensitive — review before adding" | **Keep** or **Remove**. Your call. |


| **Blocked** 🔴 | "not appropriate for a young board" | Hidden, not deleted. **Restore** it in Vocabulary if you disagree. |

**When a board or page is generated, Accept is gated on resolving the flags.**
The banner says "N flagged — keep or remove the 🟡 tiles to continue." That's
deliberate: a flagged word shouldn't slip onto a child's board because someone
tapped Accept quickly.

**We are the proof-reader, not the editor.** Even a blocked word is only
hidden: it keeps its place in your vocabulary, and **Vocabulary → Show:
Hidden → Restore** brings it back. Nothing the moderation check decides is
final, because the person who knows the user is you and the person who wrote
the check is not. What it buys you is that no word reaches a child's board
without someone having looked at it.

**Flagged is not blocked, and the distinction is the point.** Anatomical terms
— including `penis` and `vagina` — are flagged rather than blocked, because you
may legitimately need them for body-safety education. The app doesn't
think it knows better than you; it thinks the decision deserves a beat.

The check runs at **authoring** time, where you can see it, rather than
silently at art-generation time. That placement matters: a word rejected while
art is being generated fails far from the decision that caused it, and can take
a whole page down without saying why — a page-link called "gun show" is enough
to trigger it.

---

## Hiding a word without deleting it

**Settings › Boards and Vocabulary › Vocabulary.**

Search, filter by class, and use **Show** to scope to **All**, **Needs review**,
**No class**, **Hidden**, or **Added by you**. Per word: **Hide**, **Restore**, or **Keep**.

**Hiding is not the same as concealing, and you want different ones on
different days.**

**Hide** acts on the *word*, everywhere. It leaves your vocabulary intact but
takes the word out of every board it appears in, and clears its cached
sentences. Use it when a word shouldn't be available at all right now.

**Conceal** acts on *one tile on one page* (page editor → select the tile →
**Visibility** → **Concealed**). The tile keeps its cell — greyed and badged for
you, simply absent for the user — so nothing around it moves. Use it when you
want fewer choices in front of the user without disturbing a board they have
already learned. It is the one to reach for first, because it costs the user
nothing.

Hiding removes the word from the board and clears its cached sentences. **It is
reversible** — that's why it's the default rather than deletion. A word you
hide today can come back next month without losing its picture or its history.

The footer states the important half: clearing the cache means an un-hidden
word can't resurface an old sentence you'd hidden it to avoid.

Structural words — page links, navigation, core — are excluded from this
screen. Hiding a page link would break navigation.

---

## Where art comes from

A word made in the **New Word** sheet gets its picture there, from **Generate
with AI** or a photo. Words added any other way wait for the board's
**Artwork** page (board editor → **Artwork**): its **New Words** section says
how many have no picture and offers one **Draw N new words** run, rather than
making you visit each tile. Every run starts behind a confirmation that gives
the count, a rough cost and time. If you'd rather use a photo, add one in Tile
Settings → **Photo**; a photo always wins over generated art, everywhere that
tile appears, and syncs across your devices.

See [Tile art and tile styles](tile-art-and-tile-styles.md).

---

## Next

- **[Single words and sentences](ai-sentences-and-single-words.md)**
- **[Tile art and tile styles](tile-art-and-tile-styles.md)**
