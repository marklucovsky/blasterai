# Writing a BlasterAI board in a spreadsheet

A scene can be drawn in Google Sheets, Numbers or Excel, then imported in the
app: **Settings › Scenes › Import from a Spreadsheet**, or **Import Pages from a
Spreadsheet** inside a scene. Bring it in as a Google Sheets link shared
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
- **A `#covers` tab** (optional) names the picture for each page: one row per
  page, with the page name in column A and a word in column B.

## A cell

| Cell | Meaning |
|---|---|
| `cat` | a word the app already has |
| `cat, animal` | a new word, with its class |
| `cat, animal, Kitty` | a new word with a different name shown |
| `go > places` | says *go*, then opens this scene's Places page |
| `> animals` | a folder that opens Animals, showing that page's cover |
| `[lion] > animals` | the same folder, showing *lion*'s picture instead |
| `go > sys:places` | opens BlasterAI 60's Places page |

A bare page name is always one of this scene's pages. A page no tab draws yet
is created empty, so a folder can link to a page you'll write later. BlasterAI
60's pages need `sys:`.

## Word classes

A new word needs a class. The list is published as data, so you can check a
class without opening the app:

[`word_classes.json`](../../claudeBlast/Resources/word_classes.json), also at
https://raw.githubusercontent.com/marklucovsky/blasterai/main/claudeBlast/Resources/word_classes.json

It is the file the app itself loads, so it is always the current list. Use the
classes marked `"caregiverSelectable": true`; the others are the app's own.

If a word is missing or has no class, the import preview lists it. You can
give it a class right there, without going back to the sheet.
