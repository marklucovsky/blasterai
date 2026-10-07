# Tile art and image sets

Which pictures a child sees, how to change them, and what to do when none of
the built-in styles are right.

---

## Switching style

**Admin → Device → Image Set.** It changes every tile everywhere,
immediately. It's a per-device setting, not per-child or per-scene.

Five sets ship:

**Classic — Light, Medium and Dark** — flat pictograms with bold outlines and
saturated color, in the tradition most AAC symbol sets follow. Familiar to
anyone who has used Proloquo2Go or TouchChat. The three are the same drawings in
three skin tones; a child recognizing themselves on their own board is not a
cosmetic detail. Classic — Light is the default.

**Playful 3D** — soft clay-sculpture renders, warm and friendly.

**High Contrast** — white line art on true black, for low vision and CVI. See
below.

All five cover the entire vocabulary — every word that ships with the app. At
launch that is **619 core vocabulary words plus the words in the bundled packs,
five sets over: 3,252 pieces of tile art.** Three were drawn in full; Classic
Medium and Dark are Classic retoned, where a tile shows skin. All five sets were generated
by us, so none of them carries licensing baggage. None is more
"correct" than another: some children track photographic-ish 3D better, some
track flat symbols better, and the only way to know is to try them with the
child.

---

## When a single tile is wrong

You don't have to accept the set's picture for any given word.

**A photo.** Tile Settings → **Photo** → pick from your library, crop square.
A photo of the child's actual cup beats any generic cup. Photos win over
generated art, apply everywhere that tile appears, and sync across your
devices.

**Different AI art.** Tile Settings → the style strip → regenerate. Or use
**Refine this image** to keep the picture and change one thing ("make the
apple red", "show it from the side"). Refine keeps the composition;
regenerate starts over.

For a child whose vocabulary is full of specific real things — their dog, their
school, their cup — photos are usually the right answer, and faster than
prompting.

---

## Tile size

**Admin → Device → Board Layout** — Standard, Large or Largest. Fewer, bigger
tiles per screen, or more, smaller ones. Per-device.

The grid is fixed for each layout, so a word stays in the same place on every
iPad, and overflow pages rather than reflowing. See
[Board layout](board-layout.md).

---

## What about high contrast, or CVI?

**High Contrast** is white line art on true black, with saturated accents kept
only where color carries meaning. It covers the whole vocabulary rather than a
subset — gaps in an accessibility style land on exactly the words a child uses
most.

Switch to it like any other style: **Admin → Device → Image Set**.

**Color is adjustable per child.** The Fitzgerald part-of-speech palette can be
changed — any part of speech, or a single word whose grammar you disagree with —
and a palette is a file you can export and send to every device in a caseload,
so a child sees the same board at school and at home.

**What is still missing, and it matters:** there is no background control, no
complexity or density-of-detail setting, and no per-child visual profile that
bundles those together. A real CVI provision would let you dial down visual
clutter, not just invert contrast. High Contrast plus a palette is a useful
start and it is not that, and we would rather say so than let the checkbox
imply more than it does.

### If you need a style we don't ship

The more useful answer, we think, is not one more style from us.

The complete pipeline for **commissioning a set** — specifying a style,

generating art for every word that ships with the app, measuring it against
that spec, and reviewing
it tile by tile — is in the open-source repo and documented end to end in
**[Commissioning an image set](commissioning-an-image-set.md)**. It costs about
$25 of compute and an afternoon, and it needs someone comfortable with a
terminal, not an artist.

That means a set can be built for **one child's actual vision** — their
acuity, their color response, how much visual clutter they can filter —
rather than us guessing at a compromise from the literature and shipping it to
everybody.

If you know what a set should look like for a child you work with, that spec is
the valuable part. Tell us and we'll help build it.

---

## Where art comes from

Tiles that ship with the app have reviewed artwork in both styles. Words you
add get AI-generated art automatically, in the background.

**Generate all styles** (in the scene editor's New-Word Art section, and in the
New Word sheet) makes art for every style rather than just the one you're
using. Slower and slightly more expensive, but the scene then still looks right
if you or a family switch styles later. Worth it for a scene you intend to
share.

---

## Next

- **[Commissioning an image set](commissioning-an-image-set.md)** — build your own
- **[Adding vocabulary](adding-vocabulary.md)**
