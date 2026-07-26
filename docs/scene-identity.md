<!-- SPDX-License-Identifier: Apache-2.0 -->
# Scene identity & provenance

**Status:** implemented (2026-07). Decentralized — **no central registry / naming
clearinghouse**. Identity rides *inside* the exported file, so existing file-based sharing
(AirDrop / Messages / Files) needs no infrastructure. This supersedes the earlier
domain-authority-only proposal.

## Problem it solves

Scenes used to be keyed by a bare `name`, which doubled as the lookup key. That breaks where it
matters most — a shared **TileScript** declares `scene: "Potty Training"`, but the script's
reference and the scene's identity lived in unresolved, colliding name-spaces. Scenario: Greta (an
SLP) builds a popular "Potty Training" scene, texts the `.blasterscene` around; a friend records a
TileScript against it and shares the script. With bare names: renames break the binding, duplicate
names collide, and a miss silently ran against whatever scene was active. Goals: **provenance**
("the Potty Training in my list is Greta's") and **robust script binding** — decentralized, keeping
file-based sharing.

## Identity model — phone-number vs. contact-name

- **`authorID`** (`DeviceProfile.authorID`) — a stable random id **minted lazily** on this device
  (first scene create/export), like a phone number: always present, machine identity, zero
  onboarding friction. Local-only (never synced). Minted via `DeviceProfileStore.ensureAuthorID`.
- **`authorName`** (`DeviceProfile.authorName`) — the owner's optional display name ("Dr. Yalcin"),
  the "contact name." **The one identity the app captures** (there is no separate device name —
  that field was removed). Captured *skippably* in **caregiver** onboarding, or later in
  Admin → Scenes. Travels inside exported files as `authorName`.
- **`receivedLabel`** (`BlasterScene.receivedLabel`) — a **local** tag the receiver adds on import
  when the incoming file has no author ("from Greta"). Never leaves the device.

### Scene fields (`BlasterScene`, all additive / CloudKit-safe)
- `sceneID` — qualified id: `"<authorID>/<slug>"` for user scenes; `"scenes.blasterai.app/<slug>"`
  for first-party (built-ins + bundled starters). Stamped at **creation** (authorID is free, so
  no lightweight-until-publish). Empty on legacy scenes → resolve by name.
- `slug` — short kebab id derived from the name (`SceneIdentity.slug`), for UI + TileScript.
- `sceneVersion` — for import dedupe/upgrade (`"1.0.0"`, bump on edit-and-reshare).
- `authorName` (carried from the file), `receivedLabel` (local), `importedContentHash` (baseline
  for edit detection).

## Resolution ladder (`TileScriptValidator.resolveScene`)

`nil` → the active scene · `"<default>"` → the `isDefault` scene · else **`sceneID` → `slug` →
`displayName`**. Back-compat: old name-only references and hand-authored scripts still resolve.
On a miss, the UI is explicit ("This demo needs the 'Potty Training' scene — import it") rather
than silently running against the active scene.

**TileScript binding.** New recordings write the active scene's **`sceneID`** (`scriptReference`),
so a shared script binds to the intended scene by stable id even after a local rename. `<default>`
stays a semantic sentinel (do **not** rewrite `<default>` demos to a concrete id — that regresses
"follow the default scene").

## Import — dedupe + edit-aware conflict handling (`SceneImporter`)

- The envelope (`ExportableScene`) carries `id` / `slug` / `sceneVersion` / `authorName`; export
  stamps them.
- **Dedupe by `sceneID`**: an incoming scene already present is the *same* published scene —
  refreshed in place (upgraded), never piled up as a duplicate.
- **Never clobber local edits.** `importedContentHash` (SHA-256 of name + home page + pages,
  captured at import/bootstrap) detects whether the receiver edited their copy. If they did, import
  does **not** overwrite — `SceneImporter.conflict(for:)` reports it and the import sheet prompts
  **Keep Mine / Take Update / Keep Both** (keep-both forks a new locally-owned scene). Unmodified
  re-imports refresh silently and say so ("already on your device — refreshed, not duplicated").
- **Receiver tag** is offered only when a genuinely **new, non-first-party** scene is created with
  no author (`needsReceiverLabel`) — never on a refresh, and never for first-party content.

## Provenance in the UI (`BlasterScene.provenance` + `attribution`)

Each scene row shows a colored **dot** (origin) + a `by …` label (authorship):

| Dot | `provenance` | Meaning | Label |
|---|---|---|---|
| 🟣 purple | `.firstParty` | BlasterAI-shipped (built-in or bundled starter) | **by BlasterAI** |
| 🟢 green | `.local` | authored on this device (`!isImported`), in the user's iCloud | **by Mark** / **by Me** |
| 🟠 orange | `.imported` | arrived as a `.blasterscene` file (`isImported`), whoever authored it | **by Greta** / **by Unknown** |

`isImported` (persisted) is the origin axis; the author label is the authorship axis — an imported
scene *you* authored reads "🟠 by Mark." Any of them gains ", modified locally" once edited past the
baseline (`isLocallyModified`). First-party wins over imported, so starters read purple, not orange.

## First-party content

- Built-ins (`Core-First`, `All Tiles`, `Empty`) are stamped `scenes.blasterai.app/<systemSceneKey>`
  at bootstrap, with a pristine `importedContentHash` baseline.
- **Bundled starters** (`starter_farm/tidepools/mealtime.json`) now carry
  `id: "scenes.blasterai.app/<slug>"` so imports of them are first-party (purple "by BlasterAI"),
  get real identity/dedupe, and support "modified locally."
- `SceneIdentityBackfill` (launch, idempotent) stamps pre-identity scenes on existing installs —
  including recognizing an already-imported starter by title against the bundled catalog.

## Domain standardization (done)

Pack ids migrated `vocab.blaster.app/*` → **`packs.blasterai.app/<slug>`** (`Resources/packs.json`
+ 6 `pack_*.json` + code refs; pack version → 1.1.0). Scenes use `scenes.blasterai.app`. Safe:
installed tiles key on the word key, not the pack id.

## The "Vocab" scene (unchanged)

`demo_wordmode.yaml`'s `scene: "Vocab"` is a **demo precondition, not app functionality** — a sample
the presenter builds by hand (combining single-word packs) before the wordmode script. Not bundled;
resolves by slug/displayName (no canonical id to point at). The `<default>` two-device scripts are
unaffected and stay `<default>`.

## Deferred

- **Universal-link sharing** (`https://blasterai.app/s/<id>` + AASA + Associated-Domains entitlement
  + URL handler). Cross-repo, entitlement-adjacent. **Not needed** for the provenance/brittleness
  goal — identity rides inside the file and file sharing is unchanged. Do when link-sharing is a
  priority.
- **Vocab as a shareable starter** — waits on the multi-pack "New Scene from Collections" builder.

## Key files

`Services/SceneIdentity.swift` (slug/authority) · `Models/Scene.swift` (fields + provenance +
attribution + hashes) · `Models/DeviceProfile.swift` + `Services/DeviceProfileStore.swift` (author
identity) · `Engine/TileScript/TileScriptValidator.swift` (resolver ladder) · `Services/SceneImporter.swift`
(dedupe + conflict) · `Services/SceneExporter.swift` (stamp) · `Views/SceneImportSheet.swift`
(conflict + receiver-tag UI) · `Views/Admin/SceneAdminSheets.swift` (`AuthorNameField` + provenance
dots) · `Services/SceneIdentityBackfill.swift` (launch backfill) · `Services/BootstrapLoader.swift`
(first-party stamps + baselines) · `Resources/starter_*.json`, `Resources/packs.json` (ids/domain).
Tests: `claudeBlastTests/SceneIdentityTests.swift`.
