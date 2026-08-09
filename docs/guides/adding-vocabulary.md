# Adding vocabulary

Six ways to add a word, what word class actually does, and why the app
sometimes flags a word before letting you add it.

---

## The fast one

Open any page → **+** → type the word in **Search or add a word**.

If it isn't in your vocabulary, the sheet offers **Add "unicorn"**, asks for a
type, and adds it. Artwork is generated in the background.

That's it. The other five routes are for volume or precision.

---

## The other five

**A photo or a specific picture** — **+** → type the word → **More options
(photo, different type)…**. Gives you the full **New Word** sheet: a photo from
your library (square-cropped), or AI art with a refinement field. **Refine**
keeps the picture and applies a change; **Regenerate** makes a new one.

**A list you already have** — **+** → **Paste a word list**. One per line:

```
word, wordClass
rocket, object
astronaut, people
earth, place, Planet Earth
```

An optional third column is the display name, for when the label should differ
from the key. Unknown classes still work but render in a neutral colour and get
flagged. Tap a class chip to insert it correctly.

**From a pack** — **Add Page** → **Start from a vocabulary pack** installs all
of that pack's words and builds a page from them.

**Ask the AI** — **+** → the suggest bar → "emotions for a 6-year-old" → **Go**.
Suggested words are created as real vocabulary; if you dismiss without placing
any on a page, they're rolled back.

**By word class** — **Add Page** → **Add a page of one word class** doesn't add
anything new. It pulls every word of that class you already have.

---

## Word class is not decoration

Every tile has a class — actions, people, food, describe, feeling, place, and
so on. It does two visible things and one invisible one:

- Sets the tile's colour
- Filters the tile picker
- **Tells the AI what the word means in this context**

That third one matters. The class goes to the model as authoritative:
`snack bar (food)` means eating one, `snack bar (place)` means going there. A
word filed under the wrong class produces confidently wrong sentences.

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
| **Blocked** | "not appropriate for a young board" | Left off |

**When a board or page is generated, Accept is gated on resolving the flags.**
The banner says "N flagged — keep or remove the 🟡 tiles to continue." That's
deliberate: a flagged word shouldn't slip onto a child's board because someone
tapped Accept quickly.

**Flagged is not blocked, and the distinction is the point.** Anatomical terms
— including `penis` and `vagina` — are flagged rather than blocked, because a
caregiver may legitimately need them for body-safety education. The app doesn't
think it knows better than you; it thinks the decision deserves a beat.

The check runs at **authoring** time, where you can see it, rather than
silently at art-generation time. An earlier version worked the other way and
was worse: a page-link called "gun show" got blocked at art generation and took
the whole page with it, invisibly.

---

## Hiding a word without deleting it

**Admin → Boards → Manage Vocabulary.**

Search, filter by class, and scope to **All**, **Needs review**, **Hidden**, or
**Added by you**. Per word: **Hide**, **Restore**, or **Keep**.

Hiding removes the word from the board and clears its cached sentences. **It is
reversible** — that's why it's the default rather than deletion. A word you
hide today can come back next month without losing its picture or its history.

The footer states the important half: clearing the cache means an un-hidden
word can't resurface an old sentence you'd hidden it to avoid.

Structural words — page links, navigation, core — are excluded from this
screen. Hiding a page link would break navigation.

---

## Where art comes from

A new word gets AI artwork automatically, in the background, in every style
your device generates for. If you'd rather use a photo, add one in Tile
Settings → **Photo**; a photo always wins over generated art, everywhere that
tile appears, and syncs across your devices.

If a board introduced several new words at once, the board editor shows a
**New-Word Art** section with a count and a single Generate button, rather than
making you visit each tile.

See [Tile art and image sets](tile-art-and-image-sets.md).

---

## Next

- **[AI sentences vs. single words](ai-sentences-and-single-words.md)**
- **[Tile art and image sets](tile-art-and-image-sets.md)**
