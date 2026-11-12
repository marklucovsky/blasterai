# Writing a BlasterAI board in a spreadsheet

A scene can be drawn in Google Sheets, Numbers or Excel, then imported in the
app: **Settings › Scenes › Import Scene**, or **Import or Update from a
Spreadsheet** inside a scene, which replaces the scene's pages the sheet draws. Bring it in as a Google Sheets link shared
"Anyone with the link", an `.xlsx` file, or a CSV of one page.

Any scene exported from the app's Share sheet as **Spreadsheet (.xlsx)** is a
working example. Its Home tab starts with the scene's details lines (`Name:`,
`Description:`, `Is Template:`, `Built On:`) and `#board`, so it imports
back as the same kind of scene.

The caregiver guide to all of this is
[Building a board in a spreadsheet](../guides/spreadsheet-boards.md).

## Layout

- **Each tab is a page**, named by the tab. The first tab, or one named
  `home`, is the home page.
- **Each row is a row of the board**, ten cells wide on the iPad board. Leave
  out the top row every board shares (People, Questions, Actions, …), since the
  app adds it. Rows past the first screen continue onto the next screen.
- **An empty cell is a gap.** Gaps stay where you put them.
- **Anything above the board is fine.** Details rows like `Name: Tide Pools`
  and `Description: …` are read (they name and describe a new scene); a title,
  notes, column letters and row numbers are left out. The import says where it
  found each board ("Starts at A5") and lets you move it. To say exactly, put
  `#board` in the cell above the board's first word.
- **Sentences are notes.** A cell of several words that is not a word is left
  out and listed, not turned into a tile.
- **A tab named `Sheet1`** (or any name the spreadsheet made up) is Home.
- **A `#covers` tab** (optional) names the picture for each page: one row per
  page, with the page name in column A and a word in column B.

## A cell

| Cell | Meaning |
|---|---|
| `cat` | a word the app already has, or a new word with no class yet |
| `cat, animal` | a new word, with its class |
| `cat, animal, Kitty` | a new word with a different name shown |
| `go > places` | says *go*, then opens this scene's Places page |
| `> animals` | a folder that opens Animals, showing that page's cover |
| `[lion] > animals` | the same folder, showing *lion*'s picture instead |
| `go > sys:places` | opens BlasterAI 60's Places page |
| `go > template:places` | opens the template's Places page (see below) |

A bare page name is always one of this scene's pages. A page no tab draws yet
is created empty, so a folder can link to a page you'll write later. BlasterAI
60's pages need `sys:`, and a template's pages need `template:`.

## The navigation bar

A tab named `Navigation Bar` (or `NavBar`) is the scene's own navigation bar,
not a page: one row of folders and words that every page draws. Without it
the scene uses its template's bar, or BlasterAI 60's.

The bar sits across the top of each page, as BlasterAI 60 draws it. To put it
across the bottom, add a details row:

- `Bar Placement: bottom` (or `top`), in one cell or two, on any tab.

The page rows don't change: write a page the same way wherever its bar sits.
A template's placement applies to every scene built on it.

## Templates

A scene can be a **template** that other scenes are built on, as every scene
is built on BlasterAI 60: they draw its navigation bar and link to its pages.

- `Is Template: yes` in the details rows makes the imported scene a template:
  other scenes can be built on it.
- `Built On: Brandi Board` (or `Uses Template: Brandi Board`) builds the
  imported scene on that template, by its name. The template must already be
  on the device.

They answer different questions. Brandi Board's own sheet says only
`Is Template: yes`; the sheet of a board built on it says
`Built On: Brandi Board`. A template's sheet that names itself under
`Built On:` is ignored, never a template built on its own older copy.
(`Template:` is read as `Built On:`, for sheets written before the rename.)

`sys:` and `template:` are different pages, even with the same name. In a
scene built on Brandi Board, `> template:people` opens Brandi's People and
`> sys:people` opens BlasterAI 60's. `template:` never falls back to BlasterAI
60: a page the template doesn't have is an error in the import preview.

## Word classes

Give a new word a class: the class is what colors the tile, and it tells
sentence generation which sense you mean (*bat* the animal or the bat you
swing). A word written without one still comes in, as `unspecified`, and the
app's edit surfaces keep asking for its class until it has one.

The list is published as data, so you can check a class without opening the
app:

[`word_classes.json`](../../claudeBlast/Resources/word_classes.json), also at
https://raw.githubusercontent.com/marklucovsky/blasterai/main/claudeBlast/Resources/word_classes.json

It is the file the app itself loads, so it is always the current list. Use the
classes marked `"caregiverSelectable": true`; the others are the app's own.

If a word is written with a class the app doesn't have, or written bare in one
cell and with an unknown class in another, the import preview lists it. You
can give it a class right there, without going back to the sheet.
