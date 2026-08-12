<!-- SPDX-License-Identifier: Apache-2.0 -->
# Installable image sets — design notes

Handoff for the session that implements downloading and installing a tile art
set from a URL. Written 2026-08-12, immediately after building High Contrast v2
as the first payload, while the seams were fresh.

Nothing here is implemented. This is a map, a list of decisions someone has to
make, and the traps found while looking.

**Why it belongs with the app-size work.** Making a set downloadable *is* a
bundle-size intervention — it is how gate 3 of `docs/plan-2026-08-06.md` gets
from 276MB to under 150. Splitting them means two sessions solving one problem
from opposite ends, both editing `TileImageResolver`, `ImageSetID`, the Xcode
target's file membership, and `ImageSetCoverageTests`. That session also has the
apparatus this needs: the plan's own exit criterion is *"measure a real archive,
not the source tree."*

---

## What already exists

**High Contrast v2 is complete and reviewed.** 546 tile masters + 6 pack covers
= 552, matching Classic exactly, all human-approved (`review.json` in the set
folder), all masters in LFS under `tools/tile_sets/high_contrast_v2/` and
`tools/tile_sets/packcovers/hc2_*.png`.

It is deliberately **not** in `claudeBlast/TileImageSets/`, and that is the
whole point — it is a real, complete, shippable-quality set with no delivery
mechanism, which makes it the ideal thing to build a delivery mechanism against.

Optimized output is ~75MB at 512² (409MB of masters). Produced by
`tools/optimize_tiles.py --set high_contrast_v2`, which writes to a gitignored
`optimized/` folder.

---

## The thing most likely to be got wrong

**A set is not a folder of PNGs.**

If you ship only images, a caregiver installs High Contrast, adds the word
"trampoline", and gets a Playful-3D clay render on a black board. The app
generates art for newly-added words at runtime, and it needs the *style
descriptor* to do that in the installed set's style.

So a package has to carry, at minimum:

| Part | Why | Where it lives today |
|---|---|---|
| Optimized PNGs, one per key | the art | `tools/tile_sets/optimized/<set>/` |
| Pack covers | every pack picker shows one; a missing one silently falls back | `tools/tile_sets/packcovers/<prefix>_<slug>.png` |
| **The style prompt** | in-app generation for words added after install | `claudeBlast/Resources/image_styles.json`, keyed by `ImageSetID.rawValue` |
| **Per-key subject overrides** | some keys need a set-specific subject; without them a regenerated tile reverts to the failure the override fixed | `HC_SUBJECT_OVERRIDES` in `tools/generate_sets.py` — **tool-side only, no runtime equivalent exists** |
| Manifest | id, display name, version, prefix, key list, checksum | does not exist |

The style-prompt path is the one with real code consequences.
`TileImageGenerator.style(for:)` is:

```swift
loadedStyles[imageSet.rawValue] ?? fallbackStyle(for: imageSet)
```

where `loadedStyles` is decoded once from `Bundle.main.url(forResource:
"image_styles", ...)` and `fallbackStyle(for:)` is an **exhaustive switch over
the enum** with a hardcoded short string per case. Both assume a closed set of
styles known at build time. An installed set has neither a bundle entry nor an
enum case.

The subject overrides are worse, because there is no runtime concept of them at
all — they exist only in the Python generator. Either the package carries them
and the app learns to apply them, or a word added on-device generates from a
bare display name and can hit exactly the failures the overrides were written to
fix (`up` coming back solid blue, `get` drawing a child catching a ball). See
`docs/imageset-highcontrast-log.md` for what those failures look like.

---

## Current state: what the code assumes

### `ImageSetID` is closed

`claudeBlast/Services/TileImageResolver.swift`:

```swift
enum ImageSetID: String, CaseIterable, Identifiable {
    case playful3D = "playful_3d"
    case classic = "classic"
    case arasaac = "arasaac"
    case highContrast = "high_contrast"
}
```

Every member is an exhaustive `switch` with no `default`: `displayName`,
`shortName`, `description`, `isShippable`, plus `selectable` (DEBUG =
`allCases`, RELEASE = filtered by `isShippable`) and `generationTargets`.

Referenced outside the resolver in **13 files**:

```
6  Views/TileStyleStripView.swift        2  Views/AddWordSheet.swift
5  Services/TileImageGenerator.swift     2  Engine/TileScript/TileScriptParser.swift
3  Models/TileArtVariant.swift           1  Views/AdminView.swift
2  Views/TilePhotoSection.swift          1  Services/AppSettings.swift
2  Views/SceneImageBatchSheet.swift      1  Engine/TileScript/TileScriptRunner.swift
2  Views/Admin/AdminView+DeviceTab.swift 1  Engine/TileScript/TileScriptCommand.swift
                                         1  claudeBlastApp.swift
```

### Images load from the bundle only

`TileImageResolver` resolves in this order:

1. `userPhoto(for:)` — SwiftData `TileModel.userImageData`
2. `rawImage(for:in: activeSet)`
3. **Playful-3D backfill** if the active set lacks the key
4. `anyVariantImage(for:)` — any-style `TileArtVariant`
5. `placeholderImage(for:)`

`rawImage` is `bundledImage(...) ?? variantImage(...)`, and `bundledImage` is a
hard switch mapping each case to a prefix, ending at:

```swift
Bundle.main.url(forResource: resourceName, withExtension: "png")
```

**There is no search path and no on-disk branch.** `prefixedBundleImage(for:prefix:)`
is the single choke point where one would go.

> **Trap: step 3 hides failure.** The Playful-3D backfill means a half-installed
> or corrupt set renders as a *mostly working board* rather than an obvious
> error. Any install path needs its own explicit coverage check; do not rely on
> "it looks fine."

### Everything in `TileImageSets/` ships

`claudeBlast.xcodeproj` uses a `PBXFileSystemSynchronizedRootGroup` with
`fileSystemSynchronizedGroups` on the target, and **both** `PBXResourcesBuildPhase`
and `PBXSourcesBuildPhase` have empty `files = ()`. Every file under
`claudeBlast/` is auto-included, and PNGs land flat at the bundle root (which is
why `forResource: "p3d_eat"` works with no subdirectory).

Consequence: `isShippable` controls *selectability*, not *shipping*. The old
High Contrast set is 62MB in every build today despite being unselectable in
Release. Excluding anything requires a `PBXFileSystemSynchronizedBuildFileExceptionSet`.

### Nothing else exists

No zip or archive support (the only SPM dependency is Yams, for TileScript
YAML). No download code, no progress reporting, no background `URLSession`, no
resume, no checksum or signature verification. No URL scheme
(`CFBundleURLTypes` absent), no associated domains (`claudeBlast.entitlements`
has only APS + iCloud). The app writes nothing outside
`Documents/TileScriptLogs/` and a temp file for share-sheet export.

Every `URLSession` call site is an OpenAI request. The one arbitrary-URL fetch
in the app is `TileImageGenerator.decodeImage` following an OpenAI-returned
image URL.

---

## Seams worth reusing

Not starting from zero:

- **`.blasterscene` import** is a complete versioned-envelope install flow:
  `Models/SceneTransferModels.swift` (UTType, `BlasterSceneFormat` with
  `currentVersion`, `Transferable`, `ImportCoordinator`),
  `Services/SceneImporter.swift` (validation, analysis, conflict resolution,
  content hashing), `Views/SceneImportSheet.swift` (security-scoped resource
  read, preview-then-commit). The **preview-then-commit** shape is the right
  one for a 75MB install too.
- **`packs.json` → `pack_<slug>.json`** (`Services/VocabPack.swift`,
  `PackCatalog`) is the manifest-plus-payload catalog pattern to copy.
- **`image_styles.json`** is already a per-set-raw-value data registry — the
  nearest precedent for shipping a style descriptor as data.
- **`TileArtVariant.imageSetRaw` is already a free-form `String`**, with
  `imageSet` computed as `ImageSetID(rawValue:) ?? .playful3D`. Installed-set
  variants are nearly representable already.
- **`onOpenURL`** exists in `claudeBlastApp.swift`, currently gated to
  `.blasterscene`.

---

## Decisions to make

**1. Set identity.** Recommend a ref that is `.bundled(ImageSetID)` or
`.installed(InstalledImageSet)` rather than opening the enum. Opening it means
losing exhaustiveness checking in 13 files at once; a wrapper lets those sites
be widened deliberately. Whatever is chosen, `AppSettingsKey.imageSet` currently
stores a raw string and `claudeBlastApp.swift` does
`ImageSetID(rawValue: stored)` at launch — an unknown value silently falls back
to Playful-3D, which is a reasonable behaviour to keep for an uninstalled set.

**2. Storage.** `Application Support/ImageSets/<setID>/`, flagged
`isExcludedFromBackupKey` — it is re-downloadable and should not bloat iCloud
backup. Not `Documents` (user-visible, backed up).

**3. Package format.** ZIPFoundation is the boring choice: standard tooling both
sides, inspectable by hand, one new SPM dependency. Validate entry names
strictly (`<prefix>_<key>.png` only, no path separators) — zip-slip is the
obvious hazard. `AppleArchive` avoids the dependency at the cost of unfamiliar
producer-side tooling.

**4. Size.** ~75MB at 512² PNG. WebP decodes natively on iOS and would cut that
by roughly 60-70%. Worth deciding deliberately, since a downloadable set's size
budget is a user's patience rather than an App Store limit — and it interacts
directly with the re-encoding work already scoped in that session.

**5. Where the style descriptor lands.** Options: a `style.json` in the package
read at generation time; or merge into a runtime-mutable registry at install.
Either way `TileImageGenerator.loadedStyles` stops being a `let` decoded once
from `Bundle.main`, and `fallbackStyle(for:)`'s exhaustive switch needs a
non-enum path.

**6. Uninstall and update.** What happens when the active set is deleted, or
when a newer version exists? `BlasterScene.sourceURL` records provenance and
**nothing ever fetches it** — there is no update-check precedent anywhere in the
app.

---

## Traps

- **TileScript.** `TileScriptCommand.setTileSet(imageSet: ImageSetID)`,
  `TileScriptParser.parseImageSet` (aliases then `ImageSetID(rawValue:)`),
  `TileScriptSerializer`, and `TileScriptRunner`'s `originalImageSet`
  save/restore. A script can switch sets mid-run and restore on stop — that
  restore must tolerate a set uninstalled while the script was running.
- **`ImageSetCoverageTests`.** `shippableSetsCoverEntireVocabulary()` iterates
  `ImageSetID.allCases where set.isShippable`; `authoredSetsCoverExtensionSceneWords()`
  iterates `generationTargets`; both use `Bundle.main`, and
  `extensionSceneKeys()` calls `Bundle.main.urls(forResourcesWithExtension:)`
  with a flat-bundle assumption. These need re-scoping to bundled sets plus a
  **new install-time coverage gate**. Per the standing rule, if they break they
  get flagged at the source, not allowlisted.
- **`CloudKitDedupReconciler`** references `ImageSetID` — check what it assumes
  before widening.
- **`generationTargets` is `[.playful3D, .classic]`.** Mark's rule is that
  adding a word backfills all three sets, so High Contrast joins this list —
  but only once its art is reachable, or `authoredSetsCoverExtensionSceneWords`
  fails immediately.
- **Pack covers are not per-set-foldered.** They live in one shared folder
  keyed by prefix, which is why they were invisible to every check until
  2026-08-12. Any packaging code that walks `tools/tile_sets/<set>/` will miss
  them.

---

## Suggested order

1. Re-scope the coverage tests to bundled sets and add an install-time gate.
   Do this first — it is the safety net for everything after.
2. Introduce the set-identity ref and widen the 13 call sites, with no
   behaviour change. Should be a pure refactor with green tests.
3. On-disk resolution in `prefixedBundleImage`, still with no download —
   side-load a set by hand and prove it renders.
4. Package format + producer script in `tools/`.
5. Download, verify, unpack, register, coverage-check.
6. Exclude High Contrast from the release target; measure a real archive.
7. Host on blasterai.app with a `sets.json` manifest; the site's image-set
   gallery page is still unbuilt.

Steps 1-3 are the ones that touch the most code and carry the least risk. Step 6
is the one that pays for gate 3.

---

## Related

- `docs/imageset-highcontrast-log.md` — how the payload set was built, including
  the failures the subject overrides fix
- `docs/guides/commissioning-an-image-set.md` — the end-to-end authoring flow a
  third-party set would follow
- `docs/plan-2026-08-06.md` §2B — bundle slim, and the "measure a real archive"
  exit criterion
- `docs/gtm.md:66` — scenes as portable JSON "hosted on a web page for any
  Blaster device to download" is the stated product intent this extends to art
