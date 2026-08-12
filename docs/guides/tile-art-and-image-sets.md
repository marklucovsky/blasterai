# Tile art and image sets

Which pictures a child sees, how to change them, and what to do when none of
the built-in styles are right.

---

## Switching style

**Admin → Device → Tile Style.** It changes every tile everywhere,
immediately. It's a per-device setting, not per-child or per-scene.

Two styles ship:

**Playful 3D** — soft clay-sculpture renders, warm and friendly. The default,
and the most complete.

**Classic** — flat pictograms with bold outlines and saturated colour, in the
tradition most AAC symbol sets follow. Familiar to anyone who has used
Proloquo2Go or TouchChat. Drawn clean-room, so there's no licensing baggage.

Both cover the entire vocabulary. Neither is more "correct" — some children
track photographic-ish 3D better, some track flat symbols better, and the only
way to know is to try both with the child.

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

**Admin → Device → Tile Density**, roughly 64pt to 160pt. Fewer, bigger tiles
per screen, or more, smaller ones. Per-device.

The grid recomputes column count automatically and pages any overflow, so you
can move this freely without breaking a scene's layout.

---

## What about high contrast, or CVI?

Honestly: as of now, not yet — and it's the most common request we get.

There's a High Contrast style in development (bold white shapes on true black
with saturated accents), and it isn't finished enough to offer. Shipping an
incomplete accessibility style is worse than shipping none, because the gaps
land on exactly the words a child uses most.

There is **no CVI-specific support** in the app today. No background control,
no colour or complexity settings, no per-child visual profile. If that's what
you need, it isn't here yet, and we'd rather say so.

### What we're doing instead

The more useful answer, we think, is not one more style from us.

The complete pipeline for **commissioning a set** — specifying a style,
generating art for all 493 words, measuring it against that spec, and reviewing
it tile by tile — is in the open-source repo and documented end to end in
**[Commissioning an image set](commissioning-an-image-set.md)**. It costs about
$20 of compute and an afternoon, and it needs someone comfortable with a
terminal, not an artist.

That means a set can be built for **one child's actual vision** — their
acuity, their colour response, how much visual clutter they can filter —
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
