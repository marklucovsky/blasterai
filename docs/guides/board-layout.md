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

The iPad's grid is set for landscape, the way an iPad is usually held. Turned
to portrait it keeps its grid, with smaller tiles.

### The iPhone: two layouts, one board

**Turn the iPhone sideways and it is the iPad board, small.** Same ten columns,
same six rows, the same system row across the top and every word in the same
cell as on the iPad the child probably has at home. The tiles are tiny, but a
child who knows where *more* is on the iPad finds it in the same place here.

**Hold it upright and you get the layout built for a phone in a hand:**
full-size tiles, four across, with the full ten-folder system row along the
top. Four show at a time; the row slides sideways for the rest, in the same
order as on the iPad, with a chevron that says there is more.

The page under it is not re-wrapped to fit. A phone that took BlasterAI 60's
pages four words at a time would cut every row in the wrong place, so it cuts
the page into **bands of columns** instead. BlasterAI 60 lays a page out as
two blocks of four either side of an empty column; on the phone, each block
is a screen of its own, rows still rows and clusters still clusters. *I, me,
my, come* are a row on the iPad and a row on the phone. Scroll down and the next
band arrives whole, settling into place with a firm haptic tap, so a child
feels each screen land instead of watching words slide past.

**The phone can be felt as well as seen.** Each folder that slides past in the
system row gives a light tick and the row stops on a whole folder, so a child
can count their way to *places*. Opening a folder or a doorway gives a bump,
Back a light tap, and Home the same tap held longer — out, and all the way
out. Words give nothing: their feedback is the voice. A child who finds it
too much: **Settings → Device → Haptics**. (iPads have no haptic engine, so
this is the phone's alone.)

So the two complement each other: sideways for the iPad's places, upright for
big tiles and the same clusters a screen at a time.

### A layout is a grid and a system row

A grid alone doesn't make a board. The other half is the **system row**: the
folders a child can reach from every page, in the same cells every time. The
grid and where that row sits are chosen together, as a **template**.

**BlasterAI 60's template puts its system row across the top.** People,
Question, Actions, Feelings, Social, Time, Describe, Places, Small words and
Things sit along row 1 of every page. No page stores them: the board draws
them, so a 10 × 6 page holds 50 words and folders under the row. On a grid
narrower than ten (Large, Largest, an iPhone) the row scrolls sideways.

Across the top is a choice, not a law. A board for a different setting might
want its system row down the two left-hand columns, or along the bottom, and
the template is where that will be said. Today every board uses BlasterAI 60's
template; the guides say "the top row" because that is what you will see, not
because it is the only shape a board can take.

**The controls are on a rail, outside the grid.** Home is always the first
slot and the keyboard the last. Beside the grid in iPad landscape, under it in
portrait and on an iPhone. Speak and Clear stay with the sentence, in the tray.

| Child's rail | Caregiver's rail, iPad landscape | Caregiver's rail, elsewhere |
|---|---|---|
| Home | Home | Home |
| Back | Back | Back |
| Topics | Level − N + / Topics | Topics / Search |
| | Search / Edit | Tools (Level and Edit) |
| | Child mode | Child mode |
| Keyboard | Keyboard | Keyboard |

A patient device always shows the child's rail. A caregiver device shows the
caregiver's until **Child mode** locks it to the child's; getting it back goes
through the Settings lock (touch and hold Home → **Caregiver Controls**). Topics
is greyed out for now; it arrives with topic boards.

![The BlasterAI 60 home page on an iPad, with the system row and rail marked](/img/guides/nav-home.jpg)

*3* is BlasterAI 60's system row and *5* the child's rail; the rest are
explained in [Pages and navigation](pages-and-navigation.md).

There is nothing denser than Standard. Smaller, more numerous pictures were
possible and were left out on purpose: they over-stimulate, and they didn't
look good on a phone either.

### Choosing one

**Settings → Device → Board Layout.** It's a per-device setting, not per-child or
per-scene: the same child can use Standard on an iPad at school and Large on a
smaller iPad at home.

A board that overflows its grid simply pages — there are no "next page" tiles
to manage — so moving between layouts never breaks a scene. Words on a long
page keep their order; they just wrap at a different point.

---

## A scene can say which grid it was designed for

A scene laid out for 10 × 6 — with *I*, *want* and *more* in a deliberate
place — only keeps those places on 10 × 6. So a scene can **declare its grid**:

**Settings → Scenes → (your scene) → Designed For** → pick one, such as
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
  Layout. Settings says so rather than pretending otherwise.

A scene declares **one** grid, not one per device. "Standard everywhere" would
promise positions it can't keep.

**BlasterAI 60** is designed for **iPad 10 × 6** — that's the 60 in its name.
A copy you make keeps the declaration; change it in the copy if you're
re-laying it out for something else.

### Opting a device out

Sometimes the device should win. A child with low vision may need Large
whatever the author chose.

**Settings → Device → Use Each Scene's Designed Layout** — turn it off, and this
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
