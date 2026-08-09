<!-- SPDX-License-Identifier: Apache-2.0 -->
# BlasterAI — branding & naming guide

The single source of truth for how the product is named across every surface. When a
name appears in code, data, a domain, a store listing, or a slide, use the canonical
form from the table below.

## The name

**BlasterAI** — one word, no space, camelCase: capital **B**, lowercase middle, capital
**AI**. This is the human-readable product name everywhere it's *read*: App Store, the
marketing site, slides, docs, in-app UI, and first-party attribution ("by BlasterAI").

- ✅ BlasterAI
- ❌ Blaster AI · Blaster ai · BlasterAi · blasterAI · Blaster.ai · ClaudeBlast
- **"Blaster"** alone is acceptable shorthand in running prose *after* the first mention,
  but the product name is BlasterAI.
- Marketing may visually emphasize the "AI" (e.g. a color accent, as on the deck/site),
  but the underlying **text string is always `BlasterAI`**.

## Canonical forms by context

| Context | Canonical form | Notes |
|---|---|---|
| Product / display name | **BlasterAI** | App Store, in-app UI, docs, slides |
| First-party attribution | **by BlasterAI** | in-app + shared files (`BlasterScene.firstPartyAuthorDisplay`) |
| Primary domain | **blasterai.app** | site on Cloudflare Pages |
| Content-authority subdomains | **scenes.blasterai.app**, **packs.blasterai.app** | qualify first-party scene/pack ids |
| GitHub repo | **marklucovsky/blasterai** | lowercase |
| Local checkout | **~/src/blasterai** | |
| Support email | **support@blasterai.app** | |
| Bundle identifier | **app.blasterai.ios** | reverse-DNS; do not change |
| CloudKit container | **iCloud.app.blasterai** | do not change (rename orphans data) |
| Source module / Xcode target / scheme | **Blaster** | *target state* — currently `claudeBlast`; see below |
| Source directories | **Blaster/**, **BlasterTests/** | follow the module name |
| App entry point | **BlasterApp** | |
| Test import | **`@testable import Blaster`** | |
| Type-name prefix (code) | **Blaster** | e.g. `BlasterScene`; never `BlasterAI` in code |
| License / SPDX headers | unchanged | keep `Copyright … Mark Lucovsky` |

## Code identifier vs. brand: use `Blaster` in code, `BlasterAI` for the brand

The display name is **BlasterAI**, but the **code identifier is `Blaster`** — the module,
Xcode target, scheme, source directories, and type-name prefix. Two reasons:

1. **Suffix ergonomics.** Swift doesn't prefix types with the module name (unlike ObjC's
   `NS`/`CB`), so the module name only surfaces as a *suffix* in a couple of spots. With
   `BlasterAI` those read `BlasterAIApp` / `BlasterAITests` — an all-caps `AI` colliding
   with the next capital, ambiguous to parse. `Blaster` gives clean `BlasterApp` /
   `BlasterTests`.
2. **Consistency with what's already there.** The codebase already prefixes its types with
   `Blaster` — `BlasterScene`, `BlasterSceneFormat`, `BlasterSceneFile` — never `BlasterAI`.

A marketing name that differs from the code name is normal. (Mild nit: `Blaster.BlasterScene`
in fully-qualified form is slightly redundant, but that almost never appears in practice.)

**This is the target, not yet the state.** The source still uses `claudeBlast`. Renaming an
Xcode target is invasive and wide:

- `claudeBlast.xcodeproj` (target, scheme, build settings, product name)
- the module name → **every** `@testable import claudeBlast` in tests
- `claudeBlastApp` → `BlasterApp`, directories `claudeBlast/` + `claudeBlastTests/` →
  `Blaster/` + `BlasterTests/`
- file-header comments (`// claudeBlast`), asset-catalog references, entitlements/plist refs

Do it as its **own dedicated PR/worktree** (mechanical but broad), never folded into feature
work — per `CLAUDE.md`'s standing note. Until then, `claudeBlast` in source is tolerated
*only* as the current module name; no new code should introduce it, and new type names use
the `Blaster` prefix.

## Domain vocabulary: Board, Page, Pack

The same split as `Blaster` vs `BlasterAI` applies to the domain nouns. **The
user-facing word is Board; the code identifier stays `BlasterScene`.**

| Concept | User-facing | Code / format | What it is |
|---|---|---|---|
| The thing a child communicates with | **Board** | `BlasterScene`, `.blasterscene`, `sceneID`, `slug` | A named set of pages with one designated home page. Shareable, has provenance, one active at a time. |
| One screen within it | **Page** | `PageSpec` / `PageModel` | A grid of tiles. Reached by a navigation tile that links to it. |
| A named vocabulary set | **Pack** | `VocabPack`, `packs.json` | Words only, no layout — installing one adds vocabulary, it does not create a board. |
| Where tiles come from when building | **Collection** | `CollectionSource` | A *source* used while authoring (a pack, a word class, another page), not a thing that persists. Only ever surfaces on the "Build from Collections" screen. |

**Why Board.** It is what the audience already says. "Core board", "activity
board", and "fringe board" are terms of art for speech-language pathologists;
"scene" is ours and nobody else's. We already use "core board" correctly in the
scene-refine hints, and the built-in board is named **Core-First** — the
vocabulary was half-adopted already. A pilot clinician who reads the site's
"Describe → a board" and then opens the app should not have to translate.

**Why the code keeps `Scene`.** Identical reasoning to `Blaster` in code: the
type names, the exported UTI (`com.claudeblast.scene`), the file extension, and
every `sceneID`/`slug` in shared content are already in the wild. Renaming them
buys nothing a reader ever sees and breaks content people have already shared.
`docs/scene-identity.md` stays as written — it is a format spec.

The one visible seam is the **`.blasterscene` file extension**, which a
caregiver does see when AirDropping a board. It stays: compatibility with
already-shared files outweighs a rarely-read suffix.

### "Board" had three other meanings — all retired

The word was already in the UI meaning three different things. Each needs a
different fix, and none of them may keep the bare word:

| Where | Meant | Becomes |
|---|---|---|
| `SceneEditorView.swift` — `Section("Board")` around the Focused toggle | the board's tile complement | **"Focused layout"** — describe the toggle, not the container |
| `Admin/AboutStatsView.swift` — `Section("Boards")` over scene + page counts | boards *and* pages together | **`Section("Content")`** with rows "Boards" and "Pages" |
| `VocabManagerView.swift`, `WordModerationService.swift` reason strings | "what the child sees" | keep "board" — now correct, and it already reads naturally |

### Do / don't

- ✅ "Make a board", "add a page to this board", "install a vocabulary pack"
- ❌ "Make a scene" in any user-facing copy; "board" for a single page; "pack"
  for anything that carries layout or art
- ✅ `BlasterScene`, `sceneID`, `.blasterscene` in code and wire formats
- ❌ Renaming code types to `Board*`

### State

Canon as of 2026-08-09. The site and all new collateral use it immediately;
the in-app string rename lands as its own commit (UI strings only — no type,
format, or identifier changes).

## What stays as-is (never rename)

- **Bundle id `app.blasterai.ios`** and **CloudKit container `iCloud.app.blasterai`** —
  already brand-aligned; renaming the container orphans every user's synced data.
- **Historical references** in changelogs, plan docs, and merged-PR titles that mention
  `claudeBlast` — leave as history; don't rewrite the past.

## Quick do / don't

- ✅ "BlasterAI", "blasterai.app", "by BlasterAI", `marklucovsky/blasterai`
- ❌ "Blaster AI", "ClaudeBlast", "Blaster.ai", inventing new `claudeBlast`-prefixed symbols

## Related

- First-party content attribution: `BlasterScene.isFirstParty` / `attribution` (Models/Scene.swift).
- Content authorities: `SceneIdentity.firstPartyAuthority` (`scenes.blasterai.app`), pack ids
  `packs.blasterai.app/<slug>` (`Resources/packs.json`). See `docs/scene-identity.md`.
