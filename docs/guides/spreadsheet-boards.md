# Building a board in a spreadsheet

A whole board can be written in Google Sheets, Excel or Numbers and brought
into BlasterAI in one go. It's the fastest way to make a big board, and the
sheet is a copy you can keep, share with a colleague and print from.

Everything here also works the other way: any scene in the app exports as a
spreadsheet, so the easiest way to learn the format is to export one and look.

---

## The short version

- **One tab per page.** The tab's name is the page's name. The first tab, or
  one named `Home`, is the home page.
- **One row per row of the board.** Ten cells across on an iPad board.
- **An empty cell is a gap**, and stays where you put it.
- **Type words the same way you'd type them in the app's page editor.**
  `cat`, `cat, animal`, `go > places`.

That's most of it. The rest is details.

---

## A worked example

Here is the top of the **Home** tab of a board built for a Malawi project:

| | A | B | C | D | E | F | G | H |
|---|---|---|---|---|---|---|---|---|
| 1 | Name: | malawi-base | | | | | | |
| 2 | Description: | prototype board for spreadsheet based development | | | | | | |
| 3 | Is Template: | yes | | | | | | |
| 4 | Bar Placement: | bottom | | | | | | |
| 5 | | | | | | | | |
| 6 | **Cell Content Options** | | | | | | | |
| 7 | cat | A word the app has, or a new word with no class yet | | | | | | |
| … | | | | | | | | |
| 16 | #board | | | | | | | |
| 17 | yes | more | good | i don't know | different | bad | finished, actions | no |
| 18 | hello | bye | here | | | bathroom | hurt | help |
| 19 | me | we | look | get | stop | see | hear | need |
| 20 | you | them | play | make | sleep | love > people | sing | wash |

Reading it from the top:

- **Rows 1–4 are details.** A label ending in a colon, and its value in the
  next cell. They name the scene, describe it, make it a template, and put its
  navigation bar along the bottom.
- **Rows 6–14 are notes for whoever reads the sheet.** The import skips them:
  above the board, only details lines are read.
- **`#board` in row 16 says where the board starts** — the row below it is the
  board's first row. Without it the app guesses, and tells you where it found
  the board so you can move it.
- **Rows 17 onward are the board.** *finished, actions* is a new word with its
  class; *love > people* says "love" and opens the People page. The two empty
  cells in row 18 stay empty on the board.

---

## Details lines

Put these above the board, on any tab — usually Home. A label in one cell and
the value in the next, or both in one cell (`Name: Tide Pools`).

| Line | What it does |
|---|---|
| `Name:` | The scene's name. |
| `Description:` | The scene's description. |
| `Is Template: yes` | Makes the scene a template other scenes can be built on. |
| `Built On:` | The template this scene builds on, by name. Also read as `Uses Template:`. |
| `Bar Placement: bottom` | Puts the navigation bar along the bottom. `top` is the default. |

**Is Template and Built On answer different questions.** A template's own
sheet says `Is Template: yes` and nothing else — it doesn't name itself under
Built On (if it does, that line is ignored). A sheet for a board that *uses*
that template says `Built On: malawi-base`. The template has to be on the
device before you import a board built on it.

---

## What goes in a cell

The same things you type into a cell in the app:

| Cell | Means |
|---|---|
| `cat` | a word the app has, or a new word with no class yet |
| `cat, animal` | a new word with its class |
| `cat, animal, Kitty` | a new word with its class, shown as *Kitty* |
| `go > places` | says *go*, then opens this scene's Places page |
| `> animals` | a folder to Animals, showing that page's cover |
| `[lion] > animals` | the same folder, showing the lion |
| `go > sys:places` | opens **BlasterAI 60's** Places page |
| `go > template:places` | opens the **template's** Places page |

A word with no class still comes in. It shows white with a purple **?** until
you give it one — in the import preview, or later in the app — and the app
can suggest classes for you.

**Which word classes are there?** The app's list is published as
[`word_classes.json`](https://raw.githubusercontent.com/marklucovsky/blasterai/main/claudeBlast/Resources/word_classes.json)
— the same file the app loads. Use the ones marked
`"caregiverSelectable": true`.

**A page name after `>` is one of this scene's pages.** If no tab draws it
yet, the page is made empty, so you can write Home's folders first and fill
the pages later. BlasterAI 60's pages need `sys:` and a template's need
`template:` — they're different pages even when they share a name.

**Three or more words that aren't a word are a note.** `i don't know` is a
word the app has, so it's a tile. `check this one later` isn't, so it's left
out and listed in the preview. Put notes anywhere; they'll never become tiles.

---

## The navigation bar tab

A tab named **Navigation Bar** (or **NavBar**) is the scene's own navigation
bar, not a page: one row of folders and words that every page draws. Without
one, the scene uses its template's bar, or BlasterAI 60's.

```
> letters   > people   > groups   eat > food   > places   > describe   > actions   > question
```

Write your pages the same way whether the bar is on the top or the bottom —
`Bar Placement:` only moves where it's drawn.

---

## Bringing it in

**A new scene:** Settings → Scenes → **Import Scene**.
**Into a scene you have:** open the scene → **Import or Update from a
Spreadsheet**.

Then either:

- **Paste a Google Sheets link.** In Sheets, **Share → General access →
  Anyone with the link**. The app reads the sheet directly; you never download
  anything.
- **Choose a File…** — an `.xlsx` file, or a CSV of one page. **From Numbers,
  export to Excel first** (File → Export To → Excel); the app doesn't open
  `.numbers` files directly.

### The preview

Nothing is added until you've seen it. The import shows:

- **Pages** — each tab, where its board starts (**Starts at A17** — tap to
  move it), and how many cells it fills.
- **New words** — words the app doesn't have yet.
- **Words to settle** — a word with no class, or one that could mean two
  things. Give it a class or pick the right one right there.
- **Notes left out** and **Cells left empty** — what it skipped, by cell, so
  you can find it in the sheet.

Then a preview of every page as the child will see it. **Accept** to bring it
in.

### Updating from the sheet

Keep the sheet as the master copy if you like. Import into the same scene
again and each page the sheet draws is replaced by the sheet's version; a
toggle on each page lets you keep the app's version of that one instead.
Pages the sheet doesn't mention are left alone.

---

## Getting a sheet out

Any scene, or any single page: **Share → Spreadsheet (.xlsx)**. You get one
tab per page, the navigation bar on its own tab, and the details lines on
Home — ready to open in Numbers, Excel or Google Sheets, change, and import
again.

---

## Next

- [Editing a scene](editing-a-scene.md) — the same things, in the app.
- [Board layout](board-layout.md) — why a page is ten across, and what happens
  on an iPhone.
- [Sharing a scene](sharing-scenes.md) — send the finished scene, not just the
  sheet.
