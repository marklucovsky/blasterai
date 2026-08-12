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

## Domain vocabulary: Scene, Page, Pack

| Concept | Name | Code / format | What it is |
|---|---|---|---|
| The thing a child communicates with | **Scene** | `BlasterScene`, `.blasterscene`, `sceneID`, `slug` | A named set of pages with one designated home page. Shareable, has provenance, one active at a time. |
| One screen within it | **Page** | `PageSpec` / `PageModel` | A grid of tiles. Reached by a navigation tile that links to it. |
| A named vocabulary set | **Pack** | `VocabPack`, `packs.json` | Words only, no layout — installing one adds vocabulary, it does not create a scene. |
| Where tiles come from when building | **Collection** | `CollectionSource` | A *source* used while authoring (a pack, a word class, another page), not a thing that persists. Only ever surfaces on the "Build from Collections" screen. |

Unlike the `Blaster` / `BlasterAI` split, these are the same word in code and in
the UI. There is no translation to teach.

### Why not "Board" — decided 2026-08-11

This was renamed to **Board** and reverted within the same branch. Recording
why, so it doesn't get re-litigated.

**The case for Board** was that clinicians say it. "Core board", "activity
board", "fringe board" are ordinary speech in the field, and "scene" is our
word and nobody else's. The marketing site had already drifted to it
("Describe → a board").

**The case against, which is stronger: in the standards, a board is one
screen — not the whole thing.**

| product | one screen | the whole thing |
|---|---|---|
| Open Board Format | board (`.obf`) | board set (`.obz`) |
| CoughDrop | board | board set |
| TouchChat | page | vocabulary |
| Proloquo2Go | page | vocabulary |
| Snap Core First | page | page set |
| Grid 3 | grid | grid set |

Naming our multi-page container "Board" therefore **inverts** the OpenAAC
interchange standard that `docs/gtm.md` cites as the portability story we are
attacking, and inverts CoughDrop, the reference open-source AAC app. Our
**Page** would be their *board*; our **Board** would be their *board set*.

Note what the table also shows: **Page is safe.** It is standard vocabulary
across Proloquo2Go, TouchChat and Snap Core First. The unsettled term was only
ever the container, and every product names that with a "set" word or calls it
the vocabulary — and "vocabulary" is unavailable to us, since it already means
the word list.

The remaining candidates were "Board set" (standards-exact, clunky in UI and
marketing) and keeping **Scene**. Scene wins on a second argument beyond
avoiding the clash: it is *accurate*. This container is an activity context —
bedtime, farm visit, therapy session, grandma's house — which is `docs/prd.md`'s
own framing and arguably the distinctive product idea. It is jargon, but it is
jargon that means something, and it needs teaching exactly once.

**Cost of the revert:** near zero. It also preserved the recorded demo videos
and the deck, which show the Scenes tab on screen and would have needed
re-recording.

**If this is revisited**, the only fully standards-aligned option is the big
one: rename Page → Board *and* find a container word. Do not adopt Board for
the container alone.

### Do / don't

- ✅ "Make a scene", "add a page to this scene", "install a vocabulary pack"
- ❌ "Board" for the container; "board" for a single page in our own copy
- ❌ "Pack" for anything carrying layout or art

### Where "board" is still correct

The word is not banned. **"Core board"** is a term of art for a page of
high-frequency core vocabulary, and our built-in scene is named **Core-First**
for that reason. Using "board" loosely in prose about the field is fine; using
it as the name of one of our objects is not.

Two places in the app used "Board" to mean something else entirely, and both
were fixed while the rename was in flight and kept after the revert:

- `AboutStatsView` — `Section("Boards")` over scene and page counts is now
  `Section("Content")`.
- `SceneEditorView` — `Section("Board")` around the Focused toggle is now
  **"Focused layout"**, which describes the toggle rather than the container.

### Site alignment

`blasterai.app` still mixes both, including on one page: `index.html` says
"Describe → a board" in a card and "whole scenes on demand" a few lines later,
and `faq/index.html` says "builds boards and scenes". The site follows this
canon and needs a sweep.

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
