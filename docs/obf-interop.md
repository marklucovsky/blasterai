# OBF / OBZ interop — what "interoperable" actually means here

Blaster exports [Open Board Format](https://www.openboardformat.org) so a board
can leave for CoughDrop, or any other AAC app that reads it. This document is the
honest specification of that boundary: what maps cleanly, what is approximated,
and what does not survive.

Written for two readers. Someone debugging an export that looks wrong in another
app should find the answer here. And whoever builds **import** after the pilot
needs this list, because every lossy mapping below is a decision they will have
to make in reverse.

**Export only.** There is no OBF import. It is post-pilot work
(`docs/final-countdown-plan.md`).

---

## Why `.obz`, never a bare `.obf`

A `.obf` is one board as JSON. It *references* images rather than containing
them — by `path`, `url`, or an inline base64 `data` URI.

Our art lives in the app bundle, so a bare `.obf` from Blaster would reference
pictures the recipient does not have: a board of broken images. Inlining base64
would work but bloats the file several-fold over the same images as files.

So Blaster ships `.obz` — a zip holding `manifest.json`, one `.obf` per page
under `boards/`, and a PNG per tile under `images/`. `UTType.openBoard` is
declared for completeness but is not offered as a destination.

---

## What maps cleanly

| Blaster | OBF |
|---|---|
| Scene | the `.obz` package |
| Page | a board, `boards/<pageKey>.obf` |
| Home page | `manifest.root` — the board a reader opens first |
| Tile placement | a button |
| `TileModel.displayName` | `button.label` |
| `TileModel.value` | `button.vocalization` (speaking buttons only) |
| `TileEntry.link` | `button.load_board` → the target board |
| `"<home>"` magic link | resolved to the scene's home page **before export** |
| wordClass colour | `background_color` / `border_color` as `rgb(r, g, b)` |
| Tile art | `images/<key>.png`, referenced by `path` |

### Navigation is kept here, unlike in a pack

A vocabulary pack **drops** page-link and navigation tiles, because a link means
nothing outside the scene whose pages it points at (`Services/PackTransfer.swift`).

An `.obz` is the opposite case: it carries the whole scene, so the target board
travels with the link and the reference stays meaningful. Page links export as
real navigation buttons.

---

## What is approximated

### Home is re-materialised at export

In the app, Home is **not a tile**. Session 3 made it chrome: the grid injects it
at cell 0 of every page, so it never appears in `page.tiles` — an invariant
position is what makes it motor-planned rather than hunted for.

OBF has no equivalent of injected chrome. Exporting `page.tiles` faithfully
therefore produced boards with no way back: every sub-board a one-way trip, which
is worse than useless to a child.

So export writes a Home button into every board that is not the home board and
does not already carry its own way home, at cell 0, matching the app's position
for the same reason. It navigates and does not speak.

This is the one place export *adds* something rather than dropping it. An
importer reading it back would see an explicit Home tile where Blaster has none —
noted here because it is the kind of asymmetry a round trip would otherwise
accumulate.

### The grid is a rendering choice, not a fact

OBF pins buttons to a fixed `rows` × `columns` grid and addresses cells by button
id, with `null` for an empty cell. Blaster boards **reflow** — the same page is a
different grid on an iPhone, an iPad, and a printed sheet, computed at layout
time by `GridLayoutCalculator`.

There is therefore no "true" grid to carry across. Export picks one — slightly
wider than tall, matching how a page lays out on a landscape tablet, which is
what most AAC readers assume — and pads the last row with empty cells. A board
that round-trips back into Blaster would keep its tile *order*, not its shape.

### Colour is flattened

Blaster tints a tile by wordClass and derives its border from the same colour,
with opacity carrying meaning (a navigation tile reads blue). OBF has two flat
colour fields and no opacity semantics, so the exported colours are the resolved
values. A reader that applies its own colour scheme — several do — will override
them entirely.

### One image set, not five

A tile has art in up to five styles. An `.obz` carries **one**: whichever set is
active at export. There is no OBF concept of alternate art for the same button.

### Licence differs per image, on purpose

`image.license` is not uniform, because the art is not uniformly ours:

- **Bundled art** reports `Apache-2.0`, author `BlasterAI`, pointing at the
  canonical Apache licence URL. This reports the repository's licence; it grants
  nothing additional and cannot narrow it.
- **Caregiver-generated art** — a word generated on the caregiver's own OpenAI
  key — reports type `private`, attributed to the scene's author. Under OpenAI's
  terms that image is *theirs*. Naming them is honest; licensing their work on
  their behalf, in a file they may be sending to a stranger, is not ours to do.

Decided with Mark, 2026-09-02.

---

## What does not survive

Everything here is dropped, and every one is a decision import will have to make
in reverse.

| Not carried | Why |
|---|---|
| **Sentence generation** | The whole point of Blaster — tiles compose into an AI-written sentence. OBF buttons are literal: a button says its vocalization. An exported board is a *vocabulary board*, not a Blaster board. |
| **`isAudible == false`** | OBF has no "present but silent" button. Such a tile exports with **no** `vocalization`, which is the closest true statement. |
| **Brown's Stage, interaction mode** | Properties of the child and the device, not of the board. `ChildProfile` is never exported. |
| **Scene identity beyond an id** | `slug`, `sceneVersion`, `authorName`, `receivedLabel`, `importedContentHash` have no OBF equivalent. `sceneID` is preserved in `ext_blasterai_scene_id`; the rest is lost. |
| **wordClass, semantically** | Carried as colour, and preserved raw in `ext_blasterai_word_class` — but OBF has no vocabulary-class vocabulary of its own, so a non-Blaster reader sees only the colour. |
| **Photo overrides vs set art** | Both export as a PNG. The distinction — that one is a caregiver photo sitting on top of every style — is not representable. |
| **Sounds** | `sounds` is always empty. Blaster speaks through TTS at play time and stores no audio. |
| **Cached sentences, logged utterances, metrics** | Not board content, and `LoggedUtterance` is the child's speech. Nothing of the kind belongs in an interchange file. |

### Vendor extensions

OBF permits vendor fields under an `ext_<vendor>_` prefix. Ours use
`ext_blasterai_`:

- `ext_blasterai_scene_id` — board level
- `ext_blasterai_page_key` — board level
- `ext_blasterai_word_class` — button level
- `ext_blasterai_tile_key` — button level, the language-neutral concept id

`tile_key` is the important one for a future import: it is the stable identity a
returning board could match against existing vocabulary, rather than guessing
from labels. See `project_localization_and_paper_aac` — the key is a concept id
and is never translated.

---

## What real readers actually do

The spec is not the whole story. Two things learned from importing into **Cboard**
(`src/components/Settings/Import/Import.helpers.js`, read 2026-09-02), both of
which shape what we write:

**`manifest.json` is ignored.** Cboard's `obzImportAdapter` filters zip entries
ending `.obf` and never opens the manifest, so `manifest.root` has no effect
there. We still write it, correctly and root-first, for readers that honour it —
but the manifest cannot be relied on to decide which board opens.

**`load_board` is matched by `path`, against the zip entry key.** Not by id. So
board file paths must be exactly what `load_board.path` says, and the archive must
be **flat** — an `.obz` whose entries are nested under a staging folder resolves
nothing. This is why the package is assembled entry-by-entry rather than by
zipping a directory.

**A board whose id already exists is silently skipped:**

```js
tempBoard.id !== 'root' && !allBoardsIds.includes(tempBoard.id)
```

Bare page keys are generic and repeat across scenes — `body_health`, `vehicles`,
`home` — so importing a second scene dropped every page whose name had been seen
before, with no error. Board ids are therefore qualified by the scene's identity
(`OBFExporter.boardID`), while paths stay page-key based and readable.

Note that this check also makes Cboard refuse to re-import a board you have
deleted, if its own board list still holds the id. That is a Cboard behaviour and
nothing an exporter can work around: test a changed export under a fresh id or a
fresh account.

**Which board opens is Cboard's race, not our choice.** After import it calls
`switchBoard(boardsResponse[0].id)`, and that array is built by iterating an
object whose keys are inserted as each entry finishes decompressing inside a
`Promise.all` — so the winner is whichever board file happens to resolve first,
not the archive order, the manifest, or anything an exporter writes. A home page
is usually the largest board (it is the hub), so it usually loses.

Verified 2026-09-02, twice. A two-board export whose archive listed `tidepools`
first and whose manifest named it root still opened on `vehicles`. And importing
the full 13-board bundled scene produced a board picker ordered almost exactly by
**tile count ascending** — Vehicles 12, Drinks 12, Weather 17, Body Health 18,
People 21 … Home 65, Describe 107, Actions 109 — which is decompression time
tracking file size. A home page is the hub and therefore usually among the
largest, so it reliably loses.

There is no hook to influence this — `CBOARD_EXT_PROPERTIES` is only
`['labelKey', 'nameKey', 'hidden']`, and the communicator stores an unordered set
of board ids. **Do not try to game it** by tuning file sizes; that encodes a guess
about someone else's scheduler. In Cboard, set the home board by hand after
import.

`root` is a reserved board id in Cboard. We never emit it.

---

## Verifying an export

`OBFExportTests` covers the mapping and the package. Beyond that, the real test
is a receiving app: import the `.obz` into CoughDrop and confirm the home board
opens, navigation buttons move between boards, and pictures resolve.

**Done 2026-09-02, in Cboard.** The full bundled scene — 493 words, 13 boards,
42 MB — imported and works: colours, navigation, art and Home buttons all
correct. The only manual step is choosing the start board, for the reason above.

Not yet tried in CoughDrop, which authored the format and honours `manifest.root`.
That remains worth doing, but the export is no longer unverified against every
real reader.

**Size is not a problem.** 42 MB imported without complaint, so tile art stays at
512 px rather than being downsampled for this destination.
