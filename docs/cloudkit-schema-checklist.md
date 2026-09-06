# CloudKit schema checklist

**Run this on an iCloud-enabled device before any promotion**, and confirm the
Development schema is complete before opening
`docs/cloudkit-promotion-runbook.md`.

## Why

CloudKit's Development schema is built from what the app has actually
**written**, not from what it declares. `SchemaVersions.swift` states the cost:

> a field that never appeared in Development does not exist after promotion

Production is read-only after promotion, so **the first device to write an
unmaterialized record type or field fails to sync — permanently, for everyone.**

This is not hypothetical. A real device on iCloud showed **four of eight** record
types on 2026-09-05, because nothing on it had yet logged an utterance, cached a
sentence, recorded a script or received a pack. `retiredReason` is the same trap
one level down: a *field* absent from the dev schema purely because nothing had
been auto-hidden yet.

## The fast path

**Admin → Device → CloudKit Schema → "Populate CloudKit Schema"** (DEBUG builds).

It writes and then modifies one row of every synced model, then deletes the
rows. The schema survives the cleanup — CloudKit keeps a record type and its
fields once they have been written. `SchemaVersionTests.everySyncedModelIsExercised`
fails if a synced model is ever added without being exercised, so the button
cannot silently fall behind the schema.

Give sync a minute, then verify below.

## The manual path

Use this when you want the schema populated by *real* use rather than by a
probe — which is the more honest test, since it also exercises the code paths
that do the writing.

**Preconditions**

- [ ] A real device (or simulator) signed into iCloud
- [ ] **Admin → Device → Storage → iCloud Sync = ON**, then **relaunch**
      (DEBUG registers it OFF, and the container is rebuilt at launch)
- [ ] An OpenAI key set, or the Mock provider selected

**Actions, and the record type each one materializes**

| # | Action | Record type |
|---|---|---|
| 1 | Launch and let bootstrap run | `CD_TileModel`, `CD_BlasterScene`, `CD_ChildProfile` |
| 2 | Tap tiles and generate a sentence | `CD_SentenceCache` |
| 3 | Let that sentence be spoken / finalized | `CD_LoggedUtterance` |
| 4 | Add a word with AI art, **or** Tile Settings → Regenerate | `CD_TileArtVariant` |
| 5 | Admin → TileScript → record a script and save | `CD_RecordedScript` |
| 6 | Page editor → Share → **Blaster Pack**, save the `.blasterpack`, then open it to import | `CD_ReceivedPack` |

Notes on the two that are easy to get wrong:

- **Step 6 must be a *page* share.** A *scene* share produces `.blasterscene`,
  which goes through `SceneImporter` and never touches `ReceivedPack`. The
  bundled `pack_*.json` files don't count either — those load as vocabulary at
  bootstrap.
- **Step 3 is a separate write from step 2.** Generating caches the sentence;
  finalizing logs the utterance. A generation that is never spoken leaves
  `CD_LoggedUtterance` unmaterialized.

## Verify

CloudKit Console → the container → **Development** → Record Types. Expect
**eight** `CD_` types plus `Users`:

- [ ] `CD_BlasterScene`
- [ ] `CD_ChildProfile`
- [ ] `CD_LoggedUtterance`
- [ ] `CD_ReceivedPack`
- [ ] `CD_RecordedScript`
- [ ] `CD_SentenceCache`
- [ ] `CD_TileArtVariant`
- [ ] `CD_TileModel`

Then spot-check fields, which is where the subtler failure hides. Every stored
property of a synced model should appear as `CD_<name>`; the ones worth checking
by name are the ones nothing writes in ordinary use:

- [ ] `CD_TileModel.CD_partOfSpeechRaw` — schema insurance, ships empty
- [ ] `CD_TileModel.CD_retiredReason` — only set on an automatic hide
- [ ] `CD_ChildProfile.CD_brownsStageRaw`, `CD_languageRaw` — S3 3A insurance
- [ ] `CD_BlasterScene.CD_pagesData` — the pages blob (so no page or tile field
      should appear here; sparse boards and conceal live inside it)

`tools/expected_cloudkit_schema.py` prints the full expected list from the Swift
sources, for a line-by-line comparison.

## What this does not prove

That the schema is complete — nothing more. It says nothing about whether sync
converges, whether `CloudKitDedupReconciler` behaves, or whether two devices
merge sensibly. `docs/cloudkit-promotion-runbook.md` still governs the ceremony,
and Appendix A of `docs/plan-2026-08-06.md` still governs Production testing.
