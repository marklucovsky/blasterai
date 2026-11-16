# Editing a board

How to change a board: its pages, the words on them, where its folders lead,
and the navigation bar along its edge. Read
[Boards, pages, and packs](boards-pages-and-packs.md) first; this guide uses
its words.

---

## Getting in

There are two ways in, and they meet in the same two editors.

**From the board.** In Setup mode, the rail's **Edit** menu (**Tools** on a
narrower rail) has **Edit This Page** and **Edit This Board**. Use this when
you're standing next to Aubrey and see something to fix.

**From Settings.** Touch and hold Home → **Settings** → **Boards and
Vocabulary**, then tap a board. (**Settings › Current Board › Edit This
Board** goes straight to the current one.) Use this when you're building
something new, or working on a board Aubrey isn't using right now.

### You can't edit BlasterAI 60 — you edit a copy

BlasterAI 60, the board that ships with the app, is supplied and updated by
us. Tapping it shows **This is a built-in board** and offers **Make My Copy**.
The copy is yours, it becomes the current board, and it opens in the editor.
(From the board, **Edit This Board** offers the same thing as **Make a Copy
and Edit**.)

The copy is light. It holds only Home and the pages you change. Every other
page still comes from BlasterAI 60, so when we improve those pages your copy
gets the improvement. A page stops following BlasterAI 60 the moment you edit
it — the app says so first:

> *Feelings is a BlasterAI 60 page. Edit your own copy of it: the copy
> replaces it on your board, and BlasterAI 60's updates no longer reach it.*

Tap **Make a Copy and Edit** to go ahead. Changed your mind later? In the board
editor, that page's row says **Replaces BlasterAI › Feelings**; swipe it left
and tap **Use BlasterAI 60's** to go back.

**Duplicate** (swipe a board left in the boards list) is different: it makes a
second board you can change without touching the first. Use it to try
something out, or to start a variation for a second user.

---

## The board editor

Top to bottom:

| Section | What it's for |
|---|---|
| **Pages** | Every page, with a one-line health check. |
| **Artwork** | How complete the pictures are. Tap it for the Artwork page. See [Artwork](#artwork). |
| **Details** | Folded away. Name, description, the **Cover** picture shown in My Topics, and which page is **Home Page**. |
| **Board Setup** | Folded away. The grid it's **Designed For**; **Levels** (off, or 2–10 for graded reveal: words appear as Aubrey is ready); **Built On** and **Use as a Template** (see [Templates](#templates)); the **Navigation Bar** and its placement (see [The navigation bar](#the-navigation-bar)); **Add Pages and Core Words…**; and **Refine with AI…**. |

While pictures are being made, a progress row sits at the top; tap it to
pause or cancel.

The toolbar has **Preview** (the eye: the board exactly as Aubrey will see
it), **Make Current** (the check mark), a heart that adds the board to (or
removes it from) **My Topics**, and **Share**. On a narrow screen they are in
the **…** menu.

### The page list

Each row is a page, with **HOME** on the home page and a summary like:

> 60 tiles, 2 flagged, 3 missing art, 1 no class, 1 hidden

- **flagged** — a word the app wants you to look at (spelling, an unusual word).
- **missing art** — no picture yet.
- **no class** — a new word you haven't given a word class. It shows white with
  a purple **?** and works fine; the class is what colors it and helps the AI
  pick the right sense.
- **hidden** — concealed on this page, or above Aubrey's current level.

Swipe a page right for **Duplicate** and **Link From…** (put a folder to this
page on another page). Swipe left for **Share** and **Delete**. Touch and hold
a page for all of them in a menu. Below the list: **Add Page**, and **Import or
Update from a Spreadsheet** (see
[Building a board in a spreadsheet](spreadsheet-boards.md)).

### Artwork

The **Artwork** row shows how complete the pictures are, say *3 without a
picture · 2 of 3 styles*, or *Complete*. Tap it for the Artwork page: how many
words have no picture yet, and each tile style in turn with what it still
needs. **Draw** the new words, **Finish** one style, or **Finish All** of
them. Every run asks first, with how many pictures, roughly what it will cost
on your OpenAI key, and about how long it will take. A run keeps going while
you use the app; leaving the app pauses it.

---

## Editing a page

Tap a page to open it. The page is a grid, cell for cell the board Aubrey
sees, with a card on top for the page's name, cover and **Set as Home**.

**Select first, then act.** Nothing is selected when the page opens. Tap a
cell to select it; the bar above the grid shows what you can do with it:

- an empty cell — **Type**, **Add Words…**, **Paste**
- a word — **Edit Settings**, **Visibility**, **Cut**, **Copy**, **Paste**, **Clear**
- several words (tap each one's check circle) — **Visibility**, **Cut**, **Copy**, **Clear**

**Press and drag** a tile to move it. Drop it on the middle of a cell to move
or swap; drop it on a cell's left edge to slide it in front.

### Typing into a cell

Tap a selected cell again, or tap the input row, and type. What you type says
what the cell is:

| Type | You get |
|---|---|
| `cat` | the word *cat* |
| `cat, animal` | a new word, *cat*, with the word class *animal* |
| `cat, animal, Kitty` | the same, shown on the tile as *Kitty* |
| `go > places` | *go* — says "go", then opens this board's Places page |
| `> animals` | a folder: opens Animals, says nothing |
| `[lion] > animals` | the same folder, with the lion as its picture |
| `go > sys:places` | opens **BlasterAI 60's** Places page |
| `go > template:places` | opens your **template's** Places page |

As you type, suggestions appear underneath: words the app knows, pages you can
link to, and — for a new word — the classes to choose from. **Return** puts
the word in and moves to the next cell, so a row of ten words is ten words and
ten Returns.

A page name after `>` that doesn't exist yet makes an empty page. That's on
purpose: you can put all the folders on Home first, then fill each page.

If the app can't tell what you meant it says so under the input row — "A new
word needs a class", or "*bat* could be …" when two words share a name — and
leaves your typing there to fix.

**On an iPad with a keyboard** it behaves like a spreadsheet: arrow keys move,
**Shift**-arrows select a block, **Tab** moves across, **Return** edits,
**Delete** clears, **⌘C / ⌘V** copy and paste, **⌘Z** undoes.

### Tile settings

**Edit Settings** on a tile opens its settings: word type, whether it's added
to the message box, its **Visibility** (always, from level *n*, or concealed),
and its link and folder color. **Remove from Page** is here too.

### On an iPhone

The same editor, narrower. The grid shows a few columns at a time and snaps
as you scroll sideways; the toggle at the top switches between **Show the
whole page** and **Show columns up close**. While the keyboard is up only the
row you're typing in is shown, so the cell stays visible. Everything works,
but a whole new board is more comfortable on an iPad or in a spreadsheet.

---

## The navigation bar

The **navigation bar** is the row of folders Aubrey can reach from every
page — People, Actions, Feelings and the rest on BlasterAI 60. No page stores
it; the board draws it on every page, in the same cells.

Every board starts with BlasterAI 60's bar. To change it, open the board
editor's **Board Setup** section and tap **Make the Navigation Bar This
Board's Own**. The bar becomes a one-row page you edit like any other: type
`> people`, `> letters`, `eat > food`. To go back, swipe the **Navigation
Bar** row and choose **Use BlasterAI 60's**.

### Top or bottom

Once the bar is the board's own, **Placement** puts it across the **Top** or
the **Bottom** of every page. Nothing on the pages moves when you switch: the
bar is drawn above or below them. Printed boards follow, so a bottom bar is
along the bottom of every printed sheet too.

---

## Templates

A **template** is a board other boards are built on, the way every board is
built on BlasterAI 60. A board built on a template draws the template's
navigation bar, in the template's placement, and can link to the template's
pages with `template:`.

This is how one person's board becomes the base for many. A therapist makes a
core board for a school — its own navigation bar along the bottom, its own
People and Places — and turns on **Use as a Template**. Each student's board
is then **Built On** that board: it adds that student's topics, and when the
therapist improves the core, every student's board shows it.

- **Built On** — *BlasterAI 60* (the usual), one of your templates, or *None*
  (the board draws its own bar and links only where you point it).
- **Use as a Template** — lets other boards be built on this one. Its bar, and
  where it sits, become theirs.

**Sharing carries the template with it.** Send a board built on a template and
the template goes in the same file. The other device keeps it out of the way,
under **Templates in Use** in **Settings › Advanced › Authoring**, and it
disappears when the last board using it is deleted. A template someone else
made is read-only; **Add to My Boards** puts it in the boards list, where
tapping it offers **Make My Copy** to build your own from it.

---

## Things that catch people out

- **Duplicate is on the left swipe in the boards list, on the right in Pages.**
  We know.
- **Placement is only editable on the bar's owner.** A board using its
  template's bar shows the template's placement, read-only; change it on the
  template, or make the bar this board's own.
- **Choosing a template when the board has its own bar asks first.** "Use
  Brandi Board's Navigation Bar?" — **Keep This Board's** if you've customized
  it.
- **The page editor's title is the board's name**; the page's name is on the
  card above the grid.
- **There are no menus on a long press in the page editor.** Long press is
  drag. Everything a cell can do is in the bar above the grid.

---

## Next

- [Building a board in a spreadsheet](spreadsheet-boards.md) — write a whole
  board at once, and keep it in a sheet you can share.
- [Sharing a board](sharing-boards.md) — send it to a family or a colleague.
- [Adding vocabulary](adding-vocabulary.md) — more on word classes and new words.
