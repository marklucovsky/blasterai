# Pages and navigation

How a child gets from one screen to another, and how you decide where they
land first.

---

## The idea

A page is one screen of tiles. A child moves between pages by tapping a
**navigation tile** — a tile whose job is to open another page rather than to
say a word.

Navigation tiles look like any other tile. The `food` tile on a home page opens
the food page; the `apple` tile on the food page says "apple". A tile can do
both: open a page *and* speak its word.

One page is **home** — where the child starts, and where the Home button
returns them.

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

\* A vetted prompt you haven't edited is served from cache — no key, no tokens.

Always name the page first. Page names are lowercase slugs — `feelings`,
`body_health` — and autocapitalisation is off for that field on purpose.

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
Link**. That drops a silent navigation tile — a tile that opens the page and
says nothing.

**To link a page manually later:**

1. Open the page that should carry the link
2. Tap the tile you want to use as the door
3. **Navigation** → **Link to Page** → choose the page

Or add a purpose-made navigation tile: on any page, tap **+** and use the
**Page Links** filter — it's pinned second in the filter row, right after
**All**.

**Should the door also speak?** In **Tile Settings** → **Behavior** →
**Add to sentence tray**:

- **Off** — a silent door. Tapping goes to the page and says nothing.
- **On** — says its word *and* goes to the page.

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

The app fits as many tiles as the tile size allows and pages the overflow
automatically — there are no "next page" tiles to manage.

That means a page with sixty tiles isn't an error, it just becomes a page the
child has to scroll. Whether that's right depends on the child, and you know
better than the app does. The **Focused layout** toggle in Scene Info is the
blunt instrument for 1:1 sessions.

**Tile size** is Admin → Device → **Tile Density**, roughly 64pt to 160pt.
It's a per-device setting, not per-child or per-scene.

---

## Next

- **[Adding vocabulary](adding-vocabulary.md)**
- **[Sharing a scene](sharing-scenes.md)**
