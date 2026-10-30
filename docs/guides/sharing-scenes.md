# Sharing a scene

Scenes are files. You can send one to a family, a colleague, or your own second
device, and there's no account or server involved.

---

## Sending one

**Settings → Scenes → swipe left on the scene → Share.** Or open the scene and tap
the share icon in the toolbar.

You get a `.blasterscene` file — plain JSON — through the normal iOS share
sheet. Messages, Mail, AirDrop, Files, anything.

**What travels:** the pages, the layout, the navigation, and every word in the
scene — including the ones that ship with the app. Nothing is missing on the
other side.

What doesn't travel is the *artwork* for words we ship, because the receiving
device already has it. Only pictures for words you added yourself ride along,
since those are the ones the other device has never seen.

**Set your name first.** Settings → Scenes → **Author**. It's credited on
everything you share ("by Dr. Yalcin"), and it's how a family knows which
therapist sent which scene. Do it before your first share; there's no going
back and relabelling.

---

## Receiving one

How you open it depends on where it is.

**Already saved in Files?** Just tap it — it opens straight into BlasterAI.

**Arrived as an attachment in Mail or Messages?** Tapping only previews it.
Use the **share** button on the attachment and pick **BlasterAI** from the
share sheet. This trips people up, because the two cases look identical until
the tap does nothing useful.

**Either way**, Settings → Scenes → **Import Scene** always works: save the file
first, then pick it from there.

You get a preview before anything is created. Scene name, page count, tile
count, who made it, and any words it would add to your vocabulary.

### When you already have that scene

Scenes carry an identity, so re-importing an updated version is recognized
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

You don't need to, and you don't need to switch anything on. **iCloud sync is
on by default**, so scenes, profiles and history already follow you across your
own Apple devices — signed into the same Apple Account, with iCloud Drive
enabled.

There is no sync switch in the app to find, which is deliberate: which store is
authoritative is a decision that changes how the app is built at launch, not a
preference to flip on a whim. If you need a device kept local, that is a
conversation to have with us rather than a toggle.

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

`.blasterscene` is JSON with a version header — readable, diffable, and yours.

That matters beyond curiosity: a scene is a file you hold, not a record in
someone's account. You can keep it, back it up, mail it to the next therapist,
or read it in a text editor years from now without our permission or our
servers.

If you want it somewhere other than BlasterAI, scenes also export as
**OBF/OBZ**, the open format CoughDrop and the wider open-AAC world read.

---

## Next

- **[Scenes, pages, and packs](scenes-pages-and-packs.md)**
- **[Tile art and image sets](tile-art-and-image-sets.md)**
