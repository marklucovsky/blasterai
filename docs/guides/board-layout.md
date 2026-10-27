# Board layout

How big the tiles are, how many fit on a screen, and why a word stays in the
same place from one device to the next.

---

## Three grids, not a size slider

A board is a grid of rows and columns, and the grid is fixed. Each device picks
one of three **Board Layouts**:

| Layout | iPad | iPhone |
|---|---|---|
| **Standard** | 10 × 6 | 4 × 6 |
| **Large** | 8 × 5 | 3 × 5 |
| **Largest** | 6 × 4 | 2 × 5 |

Columns × rows. Every iPad shows the same grid for the same layout — an iPad
mini, an 11-inch and a 13-inch all give 10 × 6 at Standard. Only the tile size
changes to fill the screen.

That matters because of **motor planning**. A child who learns that *more* is
third from the left on the top row reaches for it without looking. If the grid
changed with the screen, the word would move every time the child picked up a
different iPad, and that learning would start over.

The grids are set for the way each device is usually held — iPad in landscape,
iPhone in portrait. An iPad turned to portrait keeps its grid, with smaller
tiles; an iPhone turned sideways sizes its tiles to fit and makes no promise
about where words sit.

**Row 1 is the system row.** People, Questions, Actions, Places, Social, Time,
Describe, Things, Feelings and Small words sit along the top of every page, the
same ten in the same cells. No page stores them: the board draws them, so a
10 × 6 page holds 50 words and folders under the row. On a grid narrower than
ten (Large, Largest, an iPhone) the row scrolls sideways.

**The controls are on a rail, outside the grid.** Home is always the first
slot and the keyboard the last. Beside the grid in iPad landscape, under it in
portrait and on an iPhone. Speak and Clear stay with the sentence, in the tray.

| Child's rail | Caregiver's rail |
|---|---|
| Home | Home |
| Back | Back |
| Topics | Level − N + / Topics |
| | Search / Edit |
| | Child mode |
| Keyboard | Keyboard |

A patient device always shows the child's rail. A caregiver device shows the
caregiver's until **Child mode** locks it to the child's; getting it back goes
through the Admin gate (long-press Home → Caregiver Controls). Topics arrives
with the scene editor work.

There is nothing denser than Standard. Smaller, more numerous pictures were
possible and were left out on purpose: they over-stimulate, and they didn't
look good on a phone either.

### Choosing one

**Admin → Device → Board Layout.** It's a per-device setting, not per-child or
per-scene: the same child can use Standard on an iPad at school and Large on a
smaller iPad at home.

A board that overflows its grid simply pages — there are no "next page" tiles
to manage — so moving between layouts never breaks a scene. Words on a long
page keep their order; they just wrap at a different point.

---

## A scene can say which grid it was designed for

A scene laid out for 10 × 6 — with *I*, *want* and *more* in a deliberate
place — only keeps those places on 10 × 6. So a scene can **declare its grid**:

**Admin → Scenes → (your scene) → Designed For** → pick one, such as
*iPad 10 × 6* or *iPhone 2 × 5*.

A scene that declares a grid gets the system row on every page. One that
doesn't — a scene from before the 10 × 6 board, an undeclared pack — draws its
pages as they are, every cell a word.

Once it's set:

- **Devices of that kind show that grid**, whatever their own Board Layout
  says. An iPad set to Large shows a 10 × 6 scene at 10 × 6, so the words are
  where the scene's author put them.
- **The scene preview and the page editor show that grid**, on any device. You
  can lay out a phone board while sitting at an iPad and see exactly what the
  phone will show.
- **The other kind of device uses its own layout.** A 10 × 6 iPad board cannot
  keep its positions on a 4 × 6 phone, so the phone falls back to its Board
  Layout. Admin says so rather than pretending otherwise.

A scene declares **one** grid, not one per device. "Standard everywhere" would
promise positions it can't keep.

**BlasterAI 60** is designed for **iPad 10 × 6** — that's the 60 in its name.
A copy you make keeps the declaration; change it in the copy if you're
re-laying it out for something else.

### Opting a device out

Sometimes the device should win. A child with low vision may need Large
whatever the author chose.

**Admin → Device → Use Each Scene's Designed Layout** — turn it off, and this
device uses its own Board Layout for every scene. The note under the switch
tells you what the active scene declares and which grid is actually in use.

---

## Printing starts from the scene's grid

A printed board is most useful when it matches the screen: the child finds
*more* in the same place on paper as on the iPad.

When you print a scene — **Share → Printable PDF** — the options start from the grid it
was designed for. **Match Screen Page Breaks** puts one screen's worth of tiles
on each sheet, so long pages split exactly where the board does. Turn it off to
fit more words per sheet instead. Paper, orientation and cut lines are yours to
change.

---

## Next

- **[Pages and navigation](pages-and-navigation.md)**
- **[Tile art and image sets](tile-art-and-image-sets.md)**
