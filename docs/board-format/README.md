# Writing a BlasterAI board in a spreadsheet

A scene can be drawn in Google Sheets, Numbers or Excel, then imported in the
app: **Settings › Scenes › Import from a Spreadsheet**, or **Import or Update from a
Spreadsheet** inside a scene, which replaces the scene's pages the sheet draws. Bring it in as a Google Sheets link shared
"Anyone with the link", an `.xlsx` file, or a CSV of one page.

Any scene exported from the app's Share sheet as **Spreadsheet (.xlsx)** is a
working example.

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

## Templates

A scene can be a **template** that other scenes are built on, as every scene
is built on BlasterAI 60: they draw its navigation bar and link to its pages.

- `Is Template: yes` in the details rows makes the imported scene a template.
- `Template: Brandi Board` (its name) builds the imported scene on that
  template, which must already be on the device.

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
