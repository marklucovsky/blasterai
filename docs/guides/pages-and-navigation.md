# Pages and navigation

How a child gets from one screen to another, and how you decide where they
land first.

---

## The idea

A page is one screen of tiles. A child moves between pages by tapping a
**link** — a tile that opens another page. Every link carries a small **arrow
badge** in the corner of its picture; that badge, not the colour, is what says
"this one goes somewhere".

There are two kinds, and the difference matters:

- **Folders** say nothing. Their whole job is to open a page — *Places*, *Things*,
  *Moving*. They are **blue**, a colour no part of speech uses, so a child learns
  that blue means "go look in here", not "say this".
- **Doorways** are words first. *go* says "go" **and** opens Places, so the
  child who wants to go somewhere is already looking at where. A doorway keeps
  its own Fitzgerald colour — *go* is a green verb like the verbs beside it —
  and the badge says it also opens a page.

One page is **home** — where the child starts, and where the Home button
returns them.

---

## Seeing it on the board: Home

![The BlasterAI 60 home page on an iPad, with five numbered callouts](/img/guides/nav-home.jpg)

1. **The tray.** What the child has said so far. Tapping a folder adds nothing
   here; tapping a doorway adds its word.
2. **The path line.** Where the child is. On Home it just says *Home*.
3. **The system row** — ten blue folders across the top. In BlasterAI 60 they
   are the same ten, in the same cells, on every page, so *Places* is always
   top row, eighth from the left, wherever the child is. No page stores them:
   the board draws them. (This is BlasterAI 60's layout; a board built on
   another template could put its system row somewhere else — down the left
   side, or along the bottom.)
4. **Doorways.** *I*, *me*, *my* open the I page; *come* and *go* open Places;
   *eat* and *drink* open Food and Drinks; *play* and *feel* open Play and
   Feelings. Each says its word as it opens the page.
5. **The rail** — Home, Back and the keyboard, outside the grid so they never
   take a word's place. On a child's rail, Topics is greyed out for now; it
   arrives with topic boards.

## Going in: Actions › Moving

Some pages hold more than fits. **Actions** keeps the everyday verbs on the page
itself and puts the rest in eight folders down its two right-hand columns.

![The Actions page, with four numbered callouts](/img/guides/nav-actions.jpg)

1. **The path line**: *Home › Actions*.
2. ***Actions* in the system row**, veiled, with a dark bar along its foot.
   That bar is the **way marker**: you are on this page.
3. **Folders in the page** — *Cooking & eating*, *Moving*, *Senses*, *Taking
   care*, *Doing*, *Talking*, *Thinking*, *Playing*. Folders like the system
   row's, blue and silent, just placed in the page instead of across the top.
4. **Words to remember the place of** — *walk*, *run*, *jump*, *come*, *go*, and
   *sit* and *stand* in the bottom corner. Watch where they are on the next page.

Tap *Moving*:

![The Actions › Moving folder page, with six numbered callouts](/img/guides/nav-actions-moving.jpg)

1. **The path line** grows: *Home › Actions › Moving*.
2. ***Actions* keeps its way marker** — this is the folder the path started from.
3. ***Moving* is still where the child pressed it**, in its own cell: veiled,
   no badge — it is a label now, not a button — and marked. You are here.
4. **The words they know stay put.** *walk*, *run*, *jump*, *come*, *go*, *sit*
   and *stand* are in the same cells as on Actions. A child who reached for
   *run* there finds it under the same finger here.
5. **Doorways of its own**: *ride* and *drive* say their word and open Vehicles.
6. **Back** goes up one level, to Actions. **Home**, above it, goes all the way.

The same thing one level down, on Places › House:

![The Places › House folder page, with five numbered callouts](/img/guides/nav-places-house.jpg)

1. The path line: *Home › Places › House*.
2. *Places*, in the system row, with the way marker under it — the folder the
   path started from.
3. *House*, in the cell Places shows it in: veiled, no badge, way marker. You
   are here.
4. **Back** — up to Places.
5. **Home** — all the way out.

### Folder colour is a choice

Blue folders are the default. If you would rather a folder take the colour of
the page it opens — *Places* in noun orange, *Actions* in verb green — that is
**Settings → Profiles → (the child) → Folder Color → As Each Link Is Set**.
Doorways keep their word colour either way.

---

## Adding a page

Open the scene → **Add Page**. The sheet gives you six routes; pick by whether
you have a key and how much you want the AI to decide.

| Route | Needs a key | What you get |
|---|---|---|
| **AI Goal** — describe the page | yes | New words, new artwork, a whole page |
| **Build with AI** — a vetted prompt | no* | Same, from a known-good prompt |
| **Start from a vocabulary pack** | no | Every word in that pack |
| **Add a page of one word class** | no | Every word of that class you already have |
| **Copy from another scene** | no | An existing page's word tiles |
| **Skip AI — Create Empty Page** | no | Nothing. You add the tiles. |

\* A vetted prompt you haven't edited is served from cache — no AI call, nothing spent.

Always name the page first. Page names are lowercase slugs — `feelings`,
`body_health` — and you don't have to type them that way: the app lowercases
what you type and turns spaces into underscores, so "Body Health" becomes
`body_health`. Autocapitalisation is off for that field so the keyboard doesn't
fight you.

**One thing to know about Copy from another scene:** it copies the word tiles
but **drops the navigation links**. A copied page won't take the child anywhere
until you re-add the links. The sheet says so; it's easy to skip past.

---

## Linking a page in

A page nobody can reach is invisible. After AI creates a page, or after you
duplicate one, BlasterAI offers to link it for you:

> **Link this page in?**
> Add a "feelings" link to…

Tick the pages that should carry the link (home is pre-selected) and tap **Add
Link**. That drops a folder — a tile that opens the page and
says nothing.

**To link a page manually later:**

1. Open the page that should carry the link
2. Tap the tile you want to use as the door
3. **Navigation** → **Link to Page** → choose the page

Or add a purpose-made folder: on any page, tap **+** and use the
**Page Links** filter — it's pinned second in the filter row, right after
**All**.

**Should the door also speak?** In **Tile Settings** → **Behavior** →
**Add to sentence tray**:

- **Off** — a silent door. Tapping goes to the page and says nothing.
- **On** — a doorway: says its word *and* goes to the page.

A plain word tile always adds to the tray; the toggle is disabled for those.

---

## Choosing home

Two controls, and they do the same thing:

- **Scene Info → Home Page** — a picker listing every page
- Open a page → **Set as Home** in the header

The page marked home shows a **HOME** badge in the page list. Turn home off on
a page and it passes to the conventional `home` page, or to the first other
page. A scene with only one page keeps it as home.

---

## Editing what's on a page

Tap the page.

- **Press and hold a tile, then drag** to reorder. A quick swipe still scrolls,
  so you have to hold.
- **Tap a tile** for Tile Settings — name, word class, art, photo, navigation,
  and **Remove from Page** at the bottom. Removal lives inside that sheet,
  which is not obvious.
- **✓ Select** for multi-select, to move or remove several at once.
- **Undo / redo** arrows in the toolbar, 25 steps deep, for this session.
- **+** to add tiles — see [Adding vocabulary](adding-vocabulary.md).

The editor grid is what the child sees, in the same order.

---

## How much should go on a page?

The board is a fixed grid, and anything past the end of it pages
automatically — there are no "next page" tiles to manage.

How many fit depends on the device's **Board Layout**: **60 cells on any iPad**
at Standard (10 × 6), 40 at Large, 24 at Largest; on an iPhone, 24, 15 or 10.
**The system row takes the first row** on a scene that declares its grid, so a
60-cell page holds 50 words and folders. Home, Back and the keyboard are on the
rail beside the grid, not in it.

**Folder pages keep the same frame.** A folder page is still a full page under
the system row, and its own folder tile takes the cell it was opened from —
that is how *Moving* stays where the child pressed it.

That means a page with eighty tiles isn't an error, it just becomes a page the
child has to scroll. Whether that's right depends on the child, and you know
better than the app does. A new scene starts with only the words it is about,
and you decide how much more it gets.

**Tile size** is Settings → Device → **Board Layout** — Standard, Large or
Largest. It's a per-device setting, and a scene can declare the grid it was
designed for so its words keep their places. See
[Board layout](board-layout.md).

---

## Next

- **[Board layout](board-layout.md)**
- **[Adding vocabulary](adding-vocabulary.md)**
- **[Sharing a scene](sharing-scenes.md)**
