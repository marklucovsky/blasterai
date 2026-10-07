# Board layout

How big the tiles are, how many fit on a screen, and why a word stays in the
same place from one device to the next.

---

## Three grids, not a size slider

A board is a grid of rows and columns, and the grid is fixed. Each device picks
one of three **Board Layouts**:

| Layout | iPad | iPhone |
|---|---|---|
| **Standard** | 12 × 5 | 4 × 5 |
| **Large** | 10 × 4 | 3 × 4 |
| **Largest** | 9 × 4 | 2 × 4 |

Columns × rows. Every iPad shows the same grid for the same layout — an iPad
mini, an 11-inch and a 13-inch all give 12 × 5 at Standard. Only the tile size
changes to fill the screen.

That matters because of **motor planning**. A child who learns that *more* is
third from the left on the top row reaches for it without looking. If the grid
changed with the screen, the word would move every time the child picked up a
different iPad, and that learning would start over.

The grids are set for the way each device is usually held — iPad in landscape,
iPhone in portrait. Turn the device the other way and the board still works,
but it sizes the tiles to fit and makes no promise about where words sit.

**Home takes one cell.** It sits in the grid as cell zero on every page, so a
12 × 5 page holds 59 words, not 60.

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

A scene laid out for 12 × 5 — with *I*, *want* and *more* in a deliberate
place — only keeps those places on 12 × 5. So a scene can **declare its grid**:

**Admin → Scenes → (your scene) → Designed For** → pick one, such as
*iPad 12 × 5* or *iPhone 2 × 4*.

Once it's set:

- **Devices of that kind show that grid**, whatever their own Board Layout
  says. An iPad set to Large shows a 12 × 5 scene at 12 × 5, so the words are
  where the scene's author put them.
- **The scene preview and the page editor show that grid**, on any device. You
  can lay out a phone board while sitting at an iPad and see exactly what the
  phone will show.
- **The other kind of device uses its own layout.** A 12 × 5 iPad board cannot
  keep its positions on a 4 × 5 phone, so the phone falls back to its Board
  Layout. Admin says so rather than pretending otherwise.

A scene declares **one** grid, not one per device. "Standard everywhere" would
promise positions it can't keep.

**BlasterAI 60** is designed for **iPad 12 × 5** — that's the 60 in its name.
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
