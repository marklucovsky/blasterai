# Sharing a board

Boards are files. You can send one to a family, a colleague, or your own second
device, and there's no account or server involved.

---

## Sending one

**Settings › Boards and Vocabulary → swipe left on the board → Share.** Or open
the board and tap the share icon in the toolbar. Then pick **Blaster Board**.

You get a `.blasterboard` file — plain JSON — through the normal iOS share
sheet. Messages, Mail, AirDrop, Files, anything. Older `.blasterscene` files
still open.

**What travels:** the pages, the layout, the navigation, and every word in the
board — including the ones that ship with the app. Nothing is missing on the
other side.

What doesn't travel is the *artwork* for words we ship, because the receiving
device already has it. Only pictures for words you added yourself ride along,
since those are the ones the other device has never seen.

**Set your name first.** **Settings › Advanced › Authoring** → **Author**.
It's credited on everything you share ("by Dr. Yalcin"), and it's how a family
knows which therapist sent which board. Do it before your first share; there's no going
back and relabelling.

---

## Receiving one

How you open it depends on where it is.

**Already saved in Files?** Just tap it — it opens straight into BlasterAI.

**Arrived as an attachment in Mail or Messages?** Tapping only previews it.
Use the **share** button on the attachment and pick **BlasterAI** from the
share sheet. This trips people up, because the two cases look identical until
the tap does nothing useful.

**Either way**, **Settings › Boards and Vocabulary**, then **+** → **Import
Board or Spreadsheet** always works: save the file first, then pick it from
there.

You get a preview before anything is created. Board name, page count, tile
count, and any words it would add to your vocabulary.

### When you already have that board

Boards carry an identity, so re-importing an updated version is recognized
rather than duplicated. Three outcomes:

- **Unchanged** — "already on your device (matched by id) — refreshed in
  place, not duplicated."
- **You changed yours, they changed theirs** — you're asked:

| | What happens |
|---|---|
| **Keep Mine (skip the update)** | Your version stays. The import is discarded. |
| **Replace Mine with the Update** | Their version replaces yours. Your edits are gone. |
| **Keep Both** | Two boards. Rename one immediately or you'll confuse yourself. |

**Keep Both** is the safe answer when you're not sure. You can always delete
the loser.

### Where it came from

Imported boards show a provenance dot and a "Shared by …" label. Built-in
boards that ship with the app, boards you made, and boards someone sent you are
visually distinct — worth knowing when a family has five boards and can't
remember which came from you.

### A board built on a template

A board built on someone's template — a school's core board, say — needs that
template to look right. So the template goes in the same file. On the other
device it isn't added to the boards list; it sits under **Templates in Use** in
**Settings › Advanced › Authoring**, read-only, and goes away when the last
board using it is deleted. Send an updated board later and its template is
refreshed with it. **Add to My Boards** there puts it in the boards list, where
tapping it offers **Make My Copy** to build your own on it.

**Sending a spreadsheet instead?** **Share → Spreadsheet (.xlsx)** gives a sheet
that says what the board is — its name, whether it's a template, what it's
built on — so it comes back in as the same kind of board. See
[Building a board in a spreadsheet](spreadsheet-boards.md).

**A Me page travels the same way.** In **Settings › Profile › Me Page**, tap
**Share Aubrey's Me Page**; whoever opens it can add its words and folders to the Me page of a
profile on their device. See [The Me page](the-me-page.md).

---

## Sharing across your own devices

You don't need to, and you don't need to switch anything on. **iCloud sync is
on by default**, so boards, profiles and history already follow you across your
own Apple devices — signed into the same Apple Account, with iCloud Drive
enabled.

There is no sync switch in the app to find, which is deliberate: which store is
authoritative is a decision that changes how the app is built at launch, not a
preference to flip on a whim. If you need a device kept local, that is a
conversation to have with us rather than a toggle.

That's the two-device story: an iPad at home and an iPhone in a pocket, same
user, same boards, same corrections.

---

## Before you share

A short checklist, learned the boring way:

- **Preview it as the user sees it.** The eye icon in the board editor. Pages
  you meant to link and didn't are invisible until someone taps around.
- **Check every page is reachable.** A page with no navigation tile pointing at
  it exists but can't be got to. Copying a page from another board drops its
  links — that's the usual cause.
- **Check the new words have pictures.** The **Artwork** row in the editor
  tells you if any don't.
- **Resolve anything flagged.** Orange and red counts in the page list mean
  words needing review. Don't ship those to a family to deal with.
- **Duplicate first if it's a board someone relies on.** Swipe left →
  **Duplicate**.

---

## The file, if you care

`.blasterboard` is JSON with a version header — readable, diffable, and yours.

That matters beyond curiosity: a board is a file you hold, not a record in
someone's account. You can keep it, back it up, mail it to the next therapist,
or read it in a text editor years from now without our permission or our
servers.

If you want it somewhere other than BlasterAI, boards also export as
**Open Board (.obz)**, the open format CoughDrop and the wider open-AAC world read.

---

## Next

- **[Boards, pages, and packs](boards-pages-and-packs.md)**
- **[Tile art and tile styles](tile-art-and-tile-styles.md)**
