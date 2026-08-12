# Sharing a scene

Scenes are files. You can send one to a family, a colleague, or your own second
device, and there's no account or server involved.

---

## Sending one

**Admin → Scenes → swipe left on the scene → Share.** Or open the scene and tap
the share icon in the toolbar.

You get a `.blasterscene` file — plain JSON — through the normal iOS share
sheet. Messages, Mail, AirDrop, Files, anything.

**What travels:** the pages, the layout, the navigation, and any words *you*
added, with their artwork. Words that ship with the app don't travel — the
receiving device already has them, and sending 493 tiles of art to deliver a
twelve-tile scene would be silly.

**Set your name first.** Admin → Scenes → **Author**. It's credited on
everything you share ("by Dr. Yalcin"), and it's how a family knows which
therapist sent which scene. Do it before your first share; there's no going
back and relabelling.

---

## Receiving one

Tap the file, or **Admin → Scenes → Import Scene** and pick it.

You get a preview before anything is created. Scene name, page count, tile
count, who made it, and any words it would add to your vocabulary.

### When you already have that scene

Scenes carry an identity, so re-importing an updated version is recognised
rather than duplicated. Three outcomes:

- **Unchanged** — "already on your device — refreshed, not duplicated."
- **You changed yours, they changed theirs** — you're asked:

| | What happens |
|---|---|
| **Keep Mine** | Your version stays. The import is discarded. |
| **Take Update** | Their version replaces yours. Your edits are gone. |
| **Keep Both** | Two scenes. Rename one immediately or you'll confuse yourself. |

**Keep Both** is the safe answer when you're not sure. You can always delete
the loser.

### Where it came from

Imported scenes show a provenance dot and a "by …" label. First-party scenes
that ship with the app, scenes you made, and scenes someone sent you are
visually distinct — worth knowing when a family has five scenes and can't
remember which came from you.

---

## Sharing across your own devices

You don't need to. Turn on iCloud (Admin → Device) and scenes, profiles, and
history sync across your own Apple devices automatically.

That's the two-device story: an iPad at home and an iPhone in a pocket, same
child, same scenes, same corrections.

---

## Before you share

A short checklist, learned the boring way:

- **Preview it as the child sees it.** The eye icon in the scene editor. Pages
  you meant to link and didn't are invisible until someone taps around.
- **Check every page is reachable.** A page with no navigation tile pointing at
  it exists but can't be got to. Copying a page from another scene drops its
  links — that's the usual cause.
- **Check the new words have pictures.** The **New-Word Art** section in the
  editor tells you if any don't.
- **Resolve anything flagged.** Orange and red chips in the page list mean words
  needing review. Don't ship those to a family to deal with.
- **Duplicate first if it's a scene someone relies on.** Swipe left →
  **Duplicate**.

---

## The file, if you care

`.blasterscene` is JSON with a version header. It's readable, diffable, and
yours. "Scene" is the old internal name for a scene; the extension kept it so
that scenes shared before the rename still open.

Nothing about a scene is locked to us. That's deliberate — an AAC scene a
family can't take with them isn't really theirs.

---

## Next

- **[Scenes, pages, and packs](scenes-pages-and-packs.md)**
- **[Tile art and image sets](tile-art-and-image-sets.md)**
