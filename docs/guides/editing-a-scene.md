# Editing a scene

How to change a board: its pages, the words on them, where its folders lead,
and the navigation bar along its edge. Read
[Scenes, pages, and packs](scenes-pages-and-packs.md) first; this guide uses
its words.

---

## Getting in

There are two ways in, and they meet in the same two editors.

**From the board.** On a caregiver device, the rail's **Edit** menu (**Tools**
on a narrower rail) has **Edit This Page** and **Edit This Scene**. Use this
when you're standing next to the child and see something to fix.

**From Settings.** Touch and hold Home → **Settings** → **Scenes**, then tap a
scene. Use this when you're building something new, or working on a scene the
child isn't using right now.

### You can't edit BlasterAI 60 — you edit a copy

BlasterAI 60, the board that ships with the app, is supplied and updated by
us. Tapping it shows **This is a built-in board** and offers **Make My Copy**.
The copy is yours, it becomes the board the child sees, and it opens in the
editor.

The copy is light. It holds only Home and the pages you change. Every other
page still comes from BlasterAI 60, so when we improve those pages your copy
gets the improvement. A page stops following BlasterAI 60 the moment you edit
it — the app says so first:

> *Feelings is a BlasterAI 60 page. Edit your own copy of it: the copy
> replaces it on your scene, and BlasterAI 60's updates no longer reach it.*

Tap **Make a Copy and Edit** to go ahead. Changed your mind later? In the scene
editor, that page's row says **Replaces BlasterAI › Feelings**; swipe it left
and tap **Use BlasterAI 60's** to go back.

**Duplicate** (swipe a scene left in the Scenes list) is different: it makes a
second scene you can change without touching the first. Use it to try
something out, or to start a variation for a second child.

---

## The scene editor

Top to bottom, the sections you'll use most:

| Section | What it's for |
|---|---|
| **Scene Info** | Name, description, the **Cover** picture shown in My Topics, which page is **Home Page**, and the grid it's **Designed For**. |
| **Levels** | Off, or 2–10 levels for graded reveal: words appear as the child is ready. |
| **Template** | **Built On** — which board this one builds on — and **Use as a Template**. See [Templates](#templates). |
| **Navigation Bar** | Whose bar this board draws, and where it sits. See [The navigation bar](#the-navigation-bar). |
| **Pages** | Every page, with a one-line health check. |
| **Art Coverage** | Which words still need pictures in each style. |

The toolbar has **Preview** (the eye: the scene exactly as the child will see
it), **Refine with AI**, and **Share**.

### The page list

Each row is a page, with **HOME** on the home page and a summary like:

> 60 tiles · 2 flagged · 3 missing art · 1 no class · 1 hidden

- **flagged** — a word the app wants you to look at (spelling, an unusual word).
- **missing art** — no picture yet in the style the child uses.
- **no class** — a new word you haven't given a word class. It shows white with
  a purple **?** and works fine; the class is what colors it and helps the AI
  pick the right sense.
- **hidden** — concealed on this page, or above the child's current level.

Swipe a page right for **Duplicate** and **Link From…** (put a folder to this
page on another page). Swipe left for **Share** and **Delete**. Below the list:
**Add Page**, and **Import or Update from a Spreadsheet**
(see [Building a board in a spreadsheet](spreadsheet-boards.md)).

---

## Editing a page

Tap a page to open it. The page is a grid, cell for cell the board the child
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
| `go > places` | *go* — says "go", then opens this scene's Places page |
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

**Edit Settings** on a word opens its settings: word type, whether it's added
to the sentence, its **Visibility** (always, from level *n*, or concealed),
and its link and folder color. **Remove from Page** is here too.

### On an iPhone

The same editor, narrower. The grid shows a few columns at a time and snaps
as you scroll sideways; the toggle at the top switches between **Show the
whole page** and **Show columns up close**. While the keyboard is up only the
row you're typing in is shown, so the cell stays visible. Everything works,
but a whole new board is more comfortable on an iPad or in a spreadsheet.

---

## The navigation bar

The **navigation bar** is the row of folders the child can reach from every
page — People, Actions, Feelings and the rest on BlasterAI 60. No page stores
it; the board draws it on every page, in the same cells.

Every scene starts with BlasterAI 60's bar. To change it, open the scene
editor's **Navigation Bar** section and tap **Make the Navigation Bar This
Scene's Own**. The bar becomes a one-row page you edit like any other: type
`> people`, `> letters`, `eat > food`. To go back, swipe the row and choose
**Use BlasterAI 60's**.

### Top or bottom

Once the bar is the scene's own, **Placement** puts it across the **Top** or
the **Bottom** of every page. Nothing on the pages moves when you switch: the
bar is drawn above or below them. Printed boards follow, so a bottom bar is
along the bottom of every printed sheet too.

---

## Templates

A **template** is a board other boards are built on, the way every scene is
built on BlasterAI 60. A scene built on a template draws the template's
navigation bar, in the template's placement, and can link to the template's
pages with `template:`.

This is how one person's board becomes the base for many. A therapist makes a
core board for a school — its own navigation bar along the bottom, its own
People and Places — and turns on **Use as a Template**. Each child's scene is
then **Built On** that board: it adds that child's topics, and when the
therapist improves the core, every child's board shows it.

- **Built On** — *BlasterAI 60* (the usual), one of your templates, or *None*
  (the scene draws its own bar and links only where you point it).
- **Use as a Template** — lets other scenes be built on this one. Its bar, and
  where it sits, become theirs.

**Sharing carries the template with it.** Send a scene built on a template and
the template goes in the same file. The other device keeps it out of the way,
under **Templates in Use** in the Scenes list, and it disappears when the last
scene using it is deleted. A template someone else made is read-only; tap it
for **Make My Copy** to build your own from it.

---

## Things that catch people out

- **Duplicate is on the left swipe in Scenes, on the right in Pages.** We know.
- **Placement is only editable on the bar's owner.** A scene using its
  template's bar shows the template's placement, read-only; change it on the
  template, or make the bar this scene's own.
- **Choosing a template when the scene has its own bar asks first.** "Use
  Brandi Board's Navigation Bar?" — **Keep This Scene's** if you've customized
  it.
- **The page editor's title is the scene's name**; the page's name is on the
  card above the grid.
- **There are no menus on a long press.** Long press is drag. Everything a
  cell can do is in the bar above the grid.

---

## Next

- [Building a board in a spreadsheet](spreadsheet-boards.md) — write a whole
  board at once, and keep it in a sheet you can share.
- [Sharing a scene](sharing-scenes.md) — send it to a family or a colleague.
- [Adding vocabulary](adding-vocabulary.md) — more on word classes and new words.
