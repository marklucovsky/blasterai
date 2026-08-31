# S4 PR 1 — the share surface, art resolution, packs, and tile-image export

## Context

Session 4 (`cb-portable`) makes a board leave BlasterAI in whatever form the person
needs. Sharing today is not a surface: `SceneEditorView.swift:311` and
`AdminView+ScenesTab.swift:45` each independently build a `BlasterSceneFile` and hand a
temp-file URL to a raw `ActivityView`. There is no page-level share and no second
renderer.

This PR builds the substrate — one share surface, one art-resolution service, the
page-as-pack concept, and tile-image export. The PDF renderer (4B) and OBF/OBZ (4D) are
later PRs that plug destinations into the surface this one establishes.

Decisions taken with Mark, 2026-08-31:

- **Print resolution is settled** at 512 px q65; no print-quality path. (Affects 4B, not
  this PR.)
- **The unit of sharing is whatever the caregiver navigated to** — a scene or a page —
  and both offer the same destinations.
- **A shared page arrives as a pack**: words + art into the recipient's vocabulary, *no*
  page and no scene created. They build a page from it later via the existing pack
  pickers. This is exactly `CollectionSource.pack` semantics, already used by bundled
  packs.
- **A received pack persists as a new synced SwiftData model.** V1 has not been promoted
  yet, so now is the cheap moment; after S6 the schema is additive-only forever.
- **Blaster-to-Blaster preserves our HEIC bytes.** PNG is produced only where the artifact
  *is* images — the 4C tile-image export.
- **A shared custom word carries every set's art the sender has, not just the active
  set's** — so a received word behaves like a bundled pack word and follows the
  *recipient's* style choice. For sharing this is the norm, not an option.
- **PDF and tile-image export get an explicit choice**: render the active set only, or all
  installed sets.

## The correction this plan makes to 4A′

The plan doc frames 4A′ as "extend `SceneExporter` so an export can carry resolved art for
*every* tile." Taken literally that is wrong in two ways, and the second is a bug.

1. **Embedding bundled art into a Blaster-to-Blaster file is pure waste.** The recipient
   already ships that art, in all five sets. A full scene would grow ~9 MB to deliver
   nothing.
2. **It would silently pin every imported tile to the sender's image set.**
   `SceneImporter` writes embedded art to `tile.userImageData`, and
   `TileImageResolver.image(for:)` consults the photo override *before* the active set
   (`TileImageResolver.swift:84-104`). Correct today, because only custom words and real
   photos are ever embedded. Fatal the moment everything is.

So 4A′ becomes **one art-resolution service, with a per-destination policy** rather than
"embed everything":

| Destination | Art |
|---|---|
| `.blasterscene` / `.blasterpack` | **references only, but complete for what it does carry** — nothing for system words; for each custom word, *every* `TileArtVariant` the sender holds, plus any photo override. Stored bytes verbatim, no re-encode. |
| PDF (4B) | resolved `UIImage`, drawn straight into the PDF context. Never serialized. Active set, or one render per installed set. |
| Tile images (4C) | resolved image, re-encoded to **PNG**. The one PNG path. Active set, or all installed sets. |
| OBZ (4D) | resolved image as PNG files in the zip — a non-Apple reader is the entire point. Confirm with Mark when 4D lands. |

Same resolution logic, four consumers, built once.

**Why "every variant" and not "the active set's".** A custom word the caregiver authored
may have art in several sets (`TileArtVariant` is keyed `tileKey` × `imageSetRaw`). If a
sender on Playful-3D shipped only that one variant, the recipient viewing in Classic would
fall through `anyVariantImage` to a Playful-3D picture sitting in a Classic board — art
that visibly doesn't match its neighbours. Shipping every variant makes a received word
behave exactly like a bundled pack word: it follows the *recipient's* set.

The cost is bounded: ~14 KB per variant, so a custom word with all five sets is ~70 KB and
a twenty-custom-word pack about 1.4 MB. System words still contribute nothing.

## Work

### 1. `ExportArtResolver` (new, `Services/`)

Given tile keys plus an `ImageSetID`, yield resolved art and its provenance
(bundled / variant / photo). Wraps the existing `TileImageResolver.image(for:in:)` and
`hasImage(for:)` — `hasImage` already exists precisely so export can tell bundled from
custom, and its doc comment says so.

Returns stored bytes **verbatim**; no `UIGraphicsImageRenderer` round-trip. The existing
`SceneExporter.encodeImage` re-encode to 512 px PNG is what makes exports enormous, and
the art is already 512 px.

### 2. `SceneExporter` / `SceneImporter` — art policy and the override fix

- `SceneExporter.export` takes an art policy; the reference-only path stays the default
  and keeps today's "custom or has photo" rule for *which tiles* qualify, sourced from
  `ExportArtResolver`.
- **`ExportableTile` gains `art: [ExportableTileArt]?`** — one entry per set, each
  `{ imageSet, imageData }`. The existing scalar `imageData` stays, meaning what it always
  meant: a set-independent photo override. Both defaulted, so old files still decode and
  old builds still read new files (they see the photo override and ignore `art`).
- **`SceneImporter` routes by shape**: each `art` entry upserts a `TileArtVariant` for its
  declared set (`Models/TileArtVariant.swift:60` already has the upsert); scalar
  `imageData` continues to `userImageData`. Never write set art to `userImageData` — that
  is the pinning bug above.
- Regression test: import a scene carrying variants for two sets, switch the active set,
  assert the tile renders the recipient's set both times.

### 3. `ReceivedPack` (new synced model) + portable pack format

```
@Model final class ReceivedPack       // BlasterSchemaV1.syncedModels
  id, packID, slug, displayName, packVersion, authorName, received
  @Attribute(.externalStorage) wordsData: Data     // [VocabPackWord] + art, inline JSON
```

Non-optional defaulted properties only, no `@Attribute(.unique)` — the rules in
`SchemaVersions.swift`. Update `SchemaVersionTests` (it asserts `models` is exactly the
union of the partitions).

`PackCatalog.all` is currently a `static let` over bundle JSON. It becomes bundled +
received, which needs a `ModelContext`; check the three read sites
(`TilePickerView.swift:71`, `SceneEditorView.swift:662`, `SceneFromCollectionsView.swift:30`).

New `.blasterpack` / `com.claudeblast.pack` UTType, exported type + document type in
`Info.plist`, alongside the existing `.blasterScene` declaration in
`SceneTransferModels.swift:19`.

Export a page → pack: words in the page's tile order, each custom word carrying all its
set variants. Import → `PackInstaller.install` (already idempotent) + a `ReceivedPack`
row + a `TileArtVariant` per shipped variant, so a received pack word is a first-class
multi-set tile — the property `VocabPack.swift:8` describes for bundled packs. Links are
dropped; record that as a lossy mapping the way 4D will record OBF's.

### 4. One share surface

A `ShareSubject` (`.scene` / `.page`) and a destination sheet that builds the payload and
hands it to `ShareLink`. Replaces both ad-hoc `ActivityView` call sites. Destinations
present in this PR: native file, tile images. PDF and OBZ slot in later.

Keep the identity/provenance stamping that `AdminView+ScenesTab.swift:258-266` does today
(`ensureIdentity`, author fill) — it must not get lost in the refactor.

Entry points: `SceneEditorView` toolbar (existing button), `AdminView+ScenesTab` row, and
`PageEditorView` toolbar. **The page one goes in the overflow menu at compact width** —
`PageEditorView.swift:203` documents the S3 finding that SwiftUI silently *drops* toolbar
items rather than collapsing them, and that view is already at four controls.

### 5. Tile-image export (4C)

Multi-select is already there (`PageEditorView` `isSelecting`). Export selected tiles, or
a whole page/scene, as PNGs.

A **set scope** control: active set only → `<key>.png` at the root; all installed sets →
`<setSlug>/<key>.png`. Same control 4B will reuse for the PDF.

For the zip: `NSFileCoordinator` with `.forUploading` zips a directory with no third-party
dependency — and it is the same machinery 4D needs for `.obz`, so build it as a small
reusable writer.

## Verification

- New tests: `ExportArtResolverTests`, `PackTransferTests`, plus additions to
  `SceneExportImportTests`. Extend `SchemaVersionTests` for `ReceivedPack`.
- The regression test that matters: import a scene whose custom word carries variants for
  two sets, switch the active image set, and assert the tile renders the recipient's set
  both times — never the sender's.
- Suites are nested in `SerialTests`, so the filter path is
  `claudeBlastTests/SerialTests/<Suite>` — and a wrong path prints `TEST SUCCEEDED`
  while running nothing. Confirm counts from the result bundle.
- Manual, in the simulator from this worktree: author a custom word, generate art for it
  in two sets, share the page → `.blasterpack`; re-import and confirm the word appears in
  the Tile Picker as a named pack with no page created, and that switching the active set
  switches its art. Export tile images at both set scopes and confirm the PNGs.

## Out of scope for this PR

4B (PDF), 4D (OBF/OBZ), 4E (usage report — deferred pending Brandi), and the escalation
re-tap carried from 3D.
