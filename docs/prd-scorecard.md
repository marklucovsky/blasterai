<!-- SPDX-License-Identifier: Apache-2.0 -->
# PRD scorecard

**Written 2026-10-08, against `main` @ `626c407`** (after PR #122; App Store 0.9.0 (5)
Waiting for Review). Scores `docs/prd.md` requirement by requirement.

**Updated 2026-10-11 for #123–#125** (`main` @ `949fec8`), and after Mark's
review: promoted tiles, session mode and SF Symbols are now **Deliberately
dropped**, and UX-11 is **Shipped** (the mechanism works; BlasterAI 60 chooses
not to use it). `docs/prd.md` was revised the same day to record every change
below, struck through in place. Every other citation was read at `626c407`; line
numbers in files those three PRs touched may have moved.

Each row was checked against the code first and the docs second. A `path:line`
citation is relative to the repo root and was read at `626c407`. Where nothing
turned up, the row says **no evidence found** and is not counted as shipped.

**Statuses.**

- **Shipped**: in the app at `626c407`.
- **Partial**: some of the requirement is built and a named piece is missing.
- **Deliberately dropped**: a recorded decision went another way. The row cites
  where and why.
- **Not started**: nothing built. If a doc deferred it on purpose (most often
  "post-pilot"), the row says so. Deferred is not dropped, so these stay Not
  started.

**PRD drift** marks rows where the PRD no longer describes the product. The
**Superseded by** column names what replaced the PRD's version.

---

## Summary

| Status | Count |
|---|---|
| Shipped | 103 |
| Partial | 6 |
| Deliberately dropped | 15 |
| Not started | 6 |
| **Total requirements scored** | **130** |

25 rows are flagged **PRD drift**. The PRD was last substantially edited in
March 2026 and had fallen out of date in nine places. **Each is now recorded in
`docs/prd.md` (revised 2026-10-11)**, struck through with what replaced it:

- **Age** gave way to Brown's Stages, and the child's birthday was deleted (#56).
- **Pages:** `PageModel`/`PageTileModel` became inline `PageSpec` (#31).
- **Images:** ARASAAC was removed and five OpenAI-generated sets ship instead.
- **Speech:** OpenAI audio gave way to on-device `AVSpeechSynthesizer` (#11).
- **Generation trigger:** the auto-debounce gave way to an explicit Go/Play
  button (#26).
- **Grid:** the size-derived grid became three fixed board layouts (#110/#111).
- **Navigation:** `next_page`/`previous_page` tiles were replaced by swipe paging,
  with Home in cell 0 (#57).
- **Scenes:** the PRD's "Scene (future)" now ships as `BlasterScene`.
- **Naming:** the UI says "board" for a scene in places, but "Board" was rejected
  as the container name (`docs/branding.md:89-134`).

### Notable gaps for a 1.0 release

Ordered by how much each one matters to a 1.0.

1. ~~**AI tile art stops working on 2026-10-23.**~~ **Resolved by #123.** Art
   generation moved to `gpt-image-2` with a per-style reference pack, and every
   drawn set was redrawn on it ahead of the `gpt-image-1` shutdown.
2. **Accessibility beyond AAC is Partial.** PR #58 did an accessibility pass:
   `accessibilityLabel` appears in 40 files and `@ScaledMetric` 29 times.
   **VoiceOver and Switch Control are explicitly post-pilot**
   (`docs/final-countdown-plan.md:1320-1322`). For an AAC app, Switch Control is
   the access method for children with motor impairments, so this is the gap a
   reviewer or clinician is most likely to raise.
3. **TTS prosody escalation: Not started.** Escalation lives only in the words;
   `SpeechSynthesizer.speak` takes no repeat count (`Engine/SpeechSynthesizer.swift:34-37`).
   It was deferred on purpose (`docs/plan-2026-06-16.md:67-69,173-175`). Recorded
   eval lesson: `AVSpeechSynthesizer` barely inflects on "!" and ignores capitals,
   so the volume knob is weaker through the speaker than on screen.
4. **URL import and website-hosted boards: Not started.** File sharing works
   through AirDrop, Messages and Files. There is no URL import, universal link,
   or `blasterai.app/boards` (`docs/scene-identity.md:106-109`,
   `docs/next-session.md:69-76`). Priority 4 and "Decisions Made → sharing" are
   therefore Partial.
5. **Localization: Not started.** There is no `.xcstrings`, and
   `ChildProfile.languageRaw` is inert. The decision is recorded as "not a launch
   gate" (`docs/localization-impact.md`; `docs/final-countdown-plan.md:1322`).
   This only matters if 1.0 targets non-English markets.
   
6. ~~**Promoted tiles.**~~ **Dropped (2026-10-11).** Tiles that appear from
   usage move the board under the child, and motor planning is how AAC is
   learned. Leftovers from PR #12 remain and can be removed:
   `promotedHitThreshold` (`Views/TileGridView.swift:13`, unused) and
   `SentenceEngine.speakPromoted` (no caller).
   
7. ~~**Session mode.**~~ **Dropped (2026-10-11), superseded by admin mode** —
   the PIN / Face ID gate, the caregiver menu and the device mode override.
8. **Small Partials:**
   - The cache viewer has no Play button (UX-14).
   - ~~Coverage skips link taps.~~ Resolved by #125: folders count, and the
     drill-down draws the board's real grid.
   - ~~The onboarding welcome copy leads with "Bring your own AI key".~~
     Resolved by #124: it leads with the board.
   - The Admin tabs still use the legacy `.tabItem` API.

---

## Core Principles

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| CP-1a | Fixed tile positions; muscle memory | Shipped | Fixed grids per device kind, `claudeBlast/Services/GridLayoutCalculator.swift:65` (`BoardLayout` 12×5 / 10×4 / 9×4 iPad, 4×5 / 3×4 / 2×4 phone), #110; scenes declare `designedFor` (`Resources/scenes/core_first.json` `ipad-12x5`), #111; Home pinned to cell 0 of every page, #57 | PRD drift: size-derived density was replaced by pinned rows×cols (#110) |
| CP-1b | No dynamic rearrangement | Shipped | Concealing a word holds its cell (`Models/PageSpec.swift` `TileEntry` conceal docs), #66; iPad mini forced to the same 12 columns, #105 | Caveat: a word *hidden from child* (moderation) still reflows, by design (`PageSpec.swift` "Conceal is not hide") |
| CP-2 | AI serves the ecosystem: generates tile sets, expands sentences, synthesizes speech | Shipped | `Engine/SceneGeneratorService.swift:7-20`, `Engine/SentenceEngine.swift`; the child sees output only | PRD drift: speech is on-device `AVSpeechSynthesizer`, not AI-synthesized (`Engine/SpeechSynthesizer.swift:22`), #11 |
| CP-3a | Data in SwiftData + iCloud, private to the user's Apple ecosystem | Shipped | Persistent store + `cloudKitDatabase: .private(...)` `Services/AppSettings.swift:175-199`; synced/local split `Models/SchemaVersions.swift:69-105`; #10, #41; CloudKit Production promoted in session 6 | |
| CP-3b | No backend servers, no analytics platforms | Shipped | `claudeBlast/PrivacyInfo.xcprivacy:8-26` (no tracking, no collected types); the only SPM dependency is Yams (`claudeBlast.xcodeproj/project.pbxproj:496-498`); #50 | |
| CP-3c | AI calls stateless; no identity or history stored externally | Shipped | Sentence calls send words + the last 5 sentences only (`Engine/SentenceEngine.swift:344-354`); explicit, versioned consent before anything reaches OpenAI, #107; `docs/openai-tos-memo-2026-07-21.md` | |
| CP-4 | Open source (Apache) | Shipped | `LICENSE`, `NOTICE`, SPDX headers, #9; porting guide for forkers, #96 (`docs/porting.md`) | |

## Architecture Overview

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| AR-1 | Data layer: tile sets, tiles, layouts, scenes | Shipped | `TileModel`, `TileArtVariant`, `BlasterScene` (pages inline) synced, `Models/SchemaVersions.swift:69-80` | PRD drift: layouts are inline `PageSpec` JSON, not models (#31) |
| AR-2 | Usage history + analytics on-device only | Shipped | `MetricEvent`, `APIUsageEvent`, `CompactionRun` device-local (`SchemaVersions.swift:98-105`); `LoggedUtterance` and `LoggedNavigation` (#125) sync only within the family's private iCloud; the SLP usage report leaves only by an explicit, gated share, #62/#63 (`docs/final-countdown-plan.md:436-477`) | PRD drift: "on-device only" became "the user's own devices + explicit export" |
| AR-3 | User preferences, voice settings | Shipped | `ChildProfile.voiceIdentifier`, `ttsRate`, `ttsVolume` (`Models/ChildProfile.swift:244-257`), #32 | |
| AR-4 | Therapist-created content | Shipped | Caregiver words + photos #33; scenes, packs, colorways (`Info.plist:5-156`) | |
| AR-5 | Syncs across the user's own devices via iCloud, nothing else | Shipped | `Services/AppSettings.swift:186`; dedup reconciler #41 (`docs/cloudkit-dedup.md`) | |
| AR-6 | Sentence expansion via API | Shipped | `Engine/Providers/OpenAISentenceProvider.swift:30`, model `gpt-4o-mini` (`Services/OpenAI/ModelPricing.swift:19`), #5 | |
| AR-7a | TTS: high quality, multiple voices, child picks "their" voice | Shipped | Per-child voice picker `Views/VoicePickerSection.swift`; `ChildProfile.voiceIdentifier`; on-device voices, #11 | PRD drift: "OpenAI TTS or similar" became on-device `AVSpeechSynthesizer` |
| AR-7b | OpenAI-hosted TTS | Deliberately dropped | No OpenAI audio endpoint anywhere in `claudeBlast/` (no `audio/speech`, `tts-1`, `gpt-4o-audio`); the dead `SentenceCache.audioData` was removed (`docs/schema-audit-2026-08-06.md:48-57`, F1). Reason, from F1 and #11: speech is on-device, and no audio comes back from the API. No standalone decision doc found | PRD drift: superseded by `AVSpeechSynthesizer` (#11) |
| AR-8 | AI-assisted tile set generation from a therapist's goal | Shipped | `Engine/SceneGeneratorService.swift:7-20`, `PageGeneratorService`, `TileSuggestionService`, `SceneRefinerService`; marquis world-inference #35; structure step #77 | |
| AR-9 | Provider is swappable | Shipped | `Engine/Providers/SentenceProvider.swift:10`; OpenAI, Mock and Apple implementations; #14 | |

## Two-Layer UX

### Layer 1: Child Surface

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| L1-1 | Full-screen tile grid, big, clear, high-contrast | Shipped | `Views/TileGridView.swift`; High Contrast image set #24/#52; Largest layout (9×4 / 2×4), #110 | |
| L1-2 | Sentence bar at top showing selected words | Shipped | `Views/SentenceTrayView.swift`, phone `Views/CompactTrayStrip.swift`, #27/#30 | At Stage IV+ the tray shows text, not tile pictures, #104 |
| L1-3 | "Speak" button triggers expansion + TTS | Shipped | Go/Play: `Engine/SentenceEngine.swift:579-594` (`triggerGo`), #26 | PRD drift: contradicts the PRD's own Sentence Engine section ("No speak button"). The product sided with this row; see SE-7 |
| L1-4 | Category pages (food, feelings, people, actions, places…) | Shipped | 21 pages in `Resources/scenes/core_first.json` (home, people, social, actions, describe, food, drinks, places, …, feelings, groups, animals) | |

| L1-5 | Promoted tiles: frequent combinations become single tiles | Deliberately dropped | Decided 2026-10-11 (Mark): tiles that appear from usage move the board under the child, counter to motor planning. Was deferred post-pilot (`docs/plan-2026-06-16.md:64-66`); `TileType` removed (`docs/schema-audit-2026-08-06.md:59-77`); #12 leftovers unused (`Views/TileGridView.swift:13`; `speakPromoted` has no caller) | Struck in `docs/prd.md` |

### Layer 2: Therapist/Parent Surface

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| L2-1 | Behind Face ID / passcode | Shipped | `Views/AdminGate.swift:10-31` (LocalAuthentication, then PIN fallback); `Services/PINAuth.swift:13-26` (PBKDF2); throttling + device-passcode recovery #74; #32 | Also works on Mac with no biometry (#57) |
| L2-2 | Create / edit tile sets, assign images, set positions | Shipped | `Views/SceneEditorView.swift:12`, `Views/PageEditorView.swift:12-18` (drag reorder, add, remove, undo), `Views/TileGridEditor.swift`; photos `Views/TilePhotoSection.swift`; #8, #37, #45, #67 | |
| L2-3 | Scenes/Worlds: curated contexts | Shipped | `BlasterScene` (`Models/Scene.swift`); bundled starters farm / tidepools / mealtime (`Resources/starter_scenes.json`); AI scene generator; #31, #35 | Morning routine, classroom and the like are authored by caregivers, not bundled |
| L2-4 | Import/export tile sets, file-based, AirDrop | Shipped | `.blasterscene` / `.blasterpack` UTTypes (`Info.plist:5-156`); `onOpenURL` `claudeBlast/claudeBlastApp.swift:274-282`; single share surface `Views/ShareBoardSheet.swift:7`; #16, #34, #59 | |
| L2-5 | Usage analytics on device; child never surveilled | Shipped | Admin → Activity (`Views/Admin/AdminView+ActivityTab.swift:14-286`): Activity Log, Coverage, Patterns, Usage report (`Services/UsageReport.swift:12-33`); #29, #62, #63; nothing analytic on the child surface | Coverage counts folders and draws the real grid; page changes in the activity log (#125) |

| L2-6 | Session mode: therapist takeover, then revert | Deliberately dropped | Decided 2026-10-11 (Mark): superseded by the PIN / Face ID admin mode — the long-press-Home caregiver menu (`Engine/CaregiverMenuCoordinator.swift:7-31`) and a two-way device mode override (`Models/DeviceProfile.swift:59-96`). Earlier "likely obsolete framing" (`docs/plan-2026-06-16.md:70-74`). Unused hook: `ChildProfile.defaultSceneKey` | Struck in `docs/prd.md` |

## UX Patterns (from original Blaster)

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| UX-1 | Tray: strip of selected tile images | Shipped | `Views/SentenceTrayView.swift`; Stage IV+ shows words (`BrownsStage.showsPicturesInTray`), #104 | |
| UX-2 | AI sentence text below the tray | Shipped | `SentenceTrayView.swift` speech bubble | |
| UX-3 | Clear (X) button | Shipped | "Done" renamed "Clear", same height as Play, #57 | |
| UX-4 | Dense grid, image + label per tile | Shipped | `Views/TileView.swift`; label band sized from the font's real line height, #75 | |
| UX-5 | Audible vs navigation tiles | Shipped | `TileEntry.link` / `isAudible`, `Models/PageSpec.swift:109-113` | |
| UX-6 | Tiles that are both (eat speaks and links) | Shipped | Home `eat` / `drink` / `play` links in `core_first.json`; link colours #99-#101 | |
| UX-7 | Navigation tiles: home, next_page, previous_page, category headers | Shipped | Home as chrome in cell 0 (#57); Back shares Home's cell (#109); folders coloured by target page (#100) | PRD drift: `next_page`/`previous_page` are still in `Resources/vocabulary.json:1481,1691` but on no page of `core_first.json`; paging is a swipe |
| UX-8 | Paginated grid for large categories | Shipped | `.scrollTargetBehavior(.paging)` at `Views/TileGridView.swift:555`, plus a haptic; #6, #30 | PRD drift: paging replaced next/prev tiles (the PRD log of 2026-02-17 anticipated this) |
| UX-9 | Home: category navigation + frequent people | Shipped | `core_first.json` home links (people, question, eat, drink, play, actions, places, social, time, describe, groups, keyboard); sentence-first home #97, Questions #98 | |
| UX-10 | Category pages: eat (all food), drink, actions, social, people | Shipped | `core_first.json` pages food, drinks, actions, social, people; food classes collapsed #46 | |


| UX-11 | Cross-links between related pages (eat ↔ drink) | Shipped | Any page can link to any other (`TileEntry.link`); Actions links to eat / drink / play (`core_first.json`). BlasterAI 60 deliberately has no food ↔ drinks link: beside audible links it reads wrong (Home → *eat* → Drinks → lemonade says "eat drink lemonade") | Noted in `docs/prd.md` |
| UX-12 | Sentence cache keyed by tile combination | Shipped | `Engine/Cache/CacheKeyPolicy.swift:50-92`, #43 | The key now also carries model, prompt version, Brown's Stage and word class |
| UX-13 | Cache hits avoid API calls; hit count tracked | Shipped | `Engine/SentenceEngine.swift:999-1060`; `SentenceCache.hitCount` | |
| UX-14 | Cache view: combination, hits, sentence, date, play / delete | Partial | `CacheDetailView` with delete, Flush All, Clear Stale (`Views/Admin/AdminView+ActivityTab.swift:366-401,521-550`); **no play button found** | |
| UX-15 | Per-tile metrics: selected, used, cache hits | Shipped | `MetricEvent` (`.selected` logged at `Engine/SentenceEngine.swift:445`), compacted #55 | PRD drift: lives in device-local `MetricEvent`, not `TileModel.metrics` |
| UX-16 | "Frequently Used Tiles" overview | Shipped | Activity tab "Most Used" (`AdminView+ActivityTab.swift:14-27`) | |
| UX-17 | "Top Cache Entries" | Shipped | Activity tab Cache Performance + Sentence Cache sections (`AdminView+ActivityTab.swift:419-550`) | |
| UX-18 | Usage data drives promoted tiles | Deliberately dropped | See L1-5. Usage data drives the caregiver's Activity, Coverage and Patterns views instead | Struck in `docs/prd.md` |

## Data Model (Sketch)

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| DM-1 | Global vocabulary; pages reference tiles with position + behaviour | Shipped | `TileModel` + `PageSpec`/`TileEntry` (`Models/PageSpec.swift:21,109`) | |
| DM-2 | `TileModel` fields as sketched | Shipped | `Models/TileModel.swift:18-30` (key, displayName, value, wordClass, bundleImage, userImageData) | PRD drift: no `metrics` (now `MetricEvent`); `type`/`TileType` deleted (`docs/schema-audit-2026-08-06.md:59-77`); added `partOfSpeechRaw` (Fitzgerald colour, #65) and moderation flags (#47/#49) |
| DM-3 | `PageModel` / `PageTileModel` with relationship + `tileOrder` | Deliberately dropped | Replaced by inline `[PageSpec]` on `BlasterScene` (`Models/Scene.swift:189-207`), #31. Reason: zero relationships in the synced schema avoids CloudKit relationship problems (`docs/schema-audit-2026-08-06.md:34-37`; `docs/plan-2026-06-02.md:26`) | PRD drift; CLAUDE.md §Current Architecture still describes the old models |
| DM-4 | `SentenceCache`: keys, sentence, hitCount, created / lastUsed | Shipped | `Models/SentenceCache.swift:17-67` | Adds keyVersion, isPinned, childID and refine overrides (#48) |
| DM-5 | `Scene` (future): name, pages, isActive | Shipped | `BlasterScene` with identity / provenance (`docs/scene-identity.md`), #44 | PRD drift: no longer "future" |
| DM-6 | A tile can be audible on one page and navigation-only on another | Shipped | Per-placement `TileEntry` (`PageSpec.swift:109-113`) | |
| DM-7 | wordClass is purely semantic, never layout | Shipped | Page membership comes from scene JSON (`core_first.json` uses class *queries* only as authoring shorthand); taxonomy work #46 | |

## Tile Images / Symbols

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| TI-1 | Default: original illustrated set or open-source AAC symbols | Shipped | Five OpenAI-generated sets in `claudeBlast/TileImageSets/` (`cls`, `clsm`, `clsmd`, `p3d`, `hc`), Apache-2.0; #36, #52, #54 | PRD drift: ARASAAC was removed in July 2026 (`NOTICE:13-32`) because CC BY-NC-SA blocked the App Store (`docs/plan-2026-06-16.md:77-87`) |
| TI-2 | User photos per tile (camera / photo library) | Shipped | `PhotosPicker` in `Views/TilePhotoSection.swift` and `Views/AddWordSheet.swift`; `Services/TilePhotoProcessor.swift:7-27`; #33 | |
| TI-3 | AI-generated images for therapist tile sets | Shipped | `Services/TileImageGenerator.swift` (`gpt-image-2`, per-style reference packs in `Resources/ReferencePacks/`); #34, #39, #123 | Was at risk from the `gpt-image-1` shutdown (2026-10-23); migrated in #123 |

| TI-4 | SF Symbols for abstract / action concepts | Deliberately dropped | Obsolete (Mark, 2026-10-11): concepts no picture fits are drawn in code (#69); an SF Symbol can still be used where it is the right picture, with a little code | Struck in `docs/prd.md` |

## Sentence Engine

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| SE-1 | Tap adds to tray; tap again removes | Deliberately dropped | A grid tap only adds; re-tapping the last tile escalates ("mash"), and removal is by tray chip (`Engine/SentenceEngine.swift:403-431`). The reason is recorded in code ("the universal rule — adds, never deletes"; mashing is the volume knob), #26/#36. **No docs/*.md record found** | PRD drift: superseded by mash-to-escalate |
| SE-2 | ~1 s debounce, then auto-generate | Deliberately dropped | Generation is an explicit Go, or automatic at the tile cap (`SentenceEngine.swift:579-581` "auto-generation on idle is disabled except at cap", `:900-909`); `idleDebounceDuration` (2.5 s default) now only pulses Play (`:289-294`); #26. **No docs/*.md record of the reason found** | PRD drift: superseded by the Go/Play button |
| SE-3 | Cache check first, instant on hit | Shipped | `SentenceEngine.swift:999-1060` (override lookup, then cache) | |
| SE-4 | Cache miss → OpenAI | Shipped | `OpenAISentenceProvider.swift:30` | |
| SE-5 | Staleness guard; cache the stale result but do not display it | Shipped | Store at `SentenceEngine.swift:1143-1153` runs before the guard at `:1155-1158` | |
| SE-6 | Display text + play audio | Shipped | `SentenceEngine.swift:1160-1185` (`speak(result.text)`) | |
| SE-7 | No "speak" button; auto-generate on pause | Deliberately dropped | Same decision as SE-2, #26 | PRD drift: superseded by Go/Play |
| SE-8 | Single tile: show the word, no API call | Shipped | `SentenceEngine.swift:890-898`; Stage I single-word mode makes no AI call at all, #36/#56 | |
| SE-9 | Single-tile auto-voicing is configurable | Shipped | `tileSpeechEnabled` (`Views/TileGridView.swift:786-788`) | |
| SE-10 | Max selected tiles configurable per child | Shipped | `ChildProfile.maxSelectedTiles` bound to Brown's Stage (I=1, II-III=4, IV+=5-8) (`Models/ChildProfile.swift:126-132,246-253,449-470`), #56 | |
| SE-11 | Prompt persona "voice and soul" | Shipped | `Resources/sentence_prompt.json:2`; fallback `Engine/SentencePromptBuilder.swift:87` | |
| SE-12 | Safety rails: no sexual / violent content | Shipped | `sentence_prompt.json:4`; at-authoring word moderation #49; content purge #47 | |
| SE-13 | wordClass sent as disambiguation context | Shipped | `SentencePromptBuilder.swift:67-70` (`"value (wordClass)"`); grammar-by-class rules `sentence_prompt.json:9-10` | |
| SE-14 | Age / grade level configurable per child | Deliberately dropped | Replaced by Brown's Stages (`SentencePromptBuilder.swift:31-40`; `ChildProfile.brownsStageRaw` at `:290`); birthday deleted in `9701a0d`, #56. Reasons: grade phrasing overshot, a stage names an MLU target, and a child's DOB was a privacy liability (`docs/final-countdown-plan.md:55-57,73,200-264`; `ChildProfile.swift:221-237`) | PRD drift: superseded by Brown's Stages |
| SE-15 | First-person, relatable sentences | Shipped | `sentence_prompt.json:2` ("Speak AS the child") | |
| SE-16 | gpt-4o-audio-preview: one call returns text + audio | Deliberately dropped | Text-only `gpt-4o-mini` + on-device TTS; `audioData` removed (`docs/schema-audit-2026-08-06.md:48-57`); #11 | PRD drift: see AR-7b |
| SE-17 | Voice configurable; child picks theirs | Shipped | Per-child `voiceIdentifier`, resolution order at `SentenceEngine.swift:1272-1288`; `Views/VoicePickerSection.swift` | |
| SE-18 | Provider abstraction | Shipped | `Engine/Providers/SentenceProvider.swift:10` | |
| SE-19 | Cache key = sorted tile combination | Shipped | `CacheKeyPolicy.swift:72-79` (de-duplicated, sorted) | Key extended (`docs/cache-policy.md:21-36`) |
| SE-20 | Cache value = sentence text + base64 audio | Partial | Text only; audio deliberately removed (F1, `docs/schema-audit-2026-08-06.md:48-57`) | PRD drift |
| SE-21 | Conversational context: recent sentences as history | Shipped | Last 5 (`SentenceEngine.swift:344-354`, `:1067`), #5 | |
| SE-22 | Repetition escalates the language | Shipped | Repeat count goes into the prompt (`SentencePromptBuilder.swift:57-59,135-177`); eval harness 38%→85%, #36; re-graded against stages, #76 | |
| SE-23 | Escalated sentences not cached; cache serves the baseline | Shipped | Lookup and store are both guarded by `repetition == 0` (`SentenceEngine.swift:1039,1143`; `docs/cache-policy.md:48-50`) | |
| SE-24 | TTS prosody escalates (louder, more emphatic) | Not started | `SpeechSynthesizer.speak` has no repeat parameter (`Engine/SpeechSynthesizer.swift:34-37`); "when prosody escalation lands" (`SentencePromptBuilder.swift:132-134`). Deferred: `docs/plan-2026-06-02.md:92-94`, `docs/plan-2026-06-16.md:67-69,173-175`, `docs/final-countdown-plan.md:1320-1322` | |
| SE-25 | Swift concurrency (`Task` + cancellation) for debounce | Shipped | `generationTask` / `idleTask` (`SentenceEngine.swift:327-336,881-883`) | |
| SE-26 | Cache persists in SwiftData, syncs via iCloud | Shipped | `SentenceCache` synced (`SchemaVersions.swift:69-80`); TTL / LRU eviction (`docs/cache-policy.md:52-67`), #43 | |

## v1 Build Priorities (Revised)

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| P-1 | SwiftData models | Shipped | #3; reshaped in #31 (scenes-as-data); versioned schema `BlasterSchemaV1`, #50 | Page models dropped (DM-3) |
| P-2 | Bootstrap loader, ~500 words + pages from JSON | Shipped | `Services/BootstrapLoader.swift`; `Resources/vocabulary.json` = **619** tiles; #3, #10 | |
| P-3 | Skeletal grid + tray; snap scrolling with haptics | Shipped | `Views/TileGridView.swift:38,555`; #4, #30 | |
| P-4a | Therapist mode: Face ID / passcode gate | Shipped | See L2-1 | |
| P-4b | Create / edit / save / name tile sets | Shipped | See L2-2; page rename #67 | |
| P-4c | Swap active tile sets | Shipped | Activate from the Now and Scenes tabs (`Views/AdminView.swift:211-214`); #18 (image sets) | |
| P-4d | Session mode | Deliberately dropped | See L2-6 | Struck in `docs/prd.md` |
| P-4e | Import tile sets via URL, text message, AirDrop | Partial | Text, AirDrop and Files shipped (L2-4). **URL import: no evidence found**; universal links deferred (`docs/scene-identity.md:106-109`); `claudeBlast.entitlements` has no associated domains | |
| P-5 | Sentence engine: integration, debounce, cache, staleness, context | Shipped | #5, #26; see SE-* | Debounce superseded (SE-2) |
| P-6 | TTS + audio: voice selection, integrated audio, prosody escalation | Partial | Voice selection shipped (SE-17); integrated audio dropped (SE-16); prosody not started (SE-24) | |

| P-7 | Promoted tiles | Deliberately dropped | See L1-5 | Struck in `docs/prd.md` |
| P-8 | AI tile set generator | Shipped | See AR-8; #35, #37 (AI page creation), #77 | |
| P-9 | Import / export polish: schema finalized, many channels | Partial | `Models/SceneTransferModels.swift:34-195` (`ExportableScene`, `BlasterFileFormat`); one share surface #59; PDF board `Services/BoardPDFRenderer.swift`, #60/#112; OBF/OBZ export `Services/OBFExporter.swift`, #61 (import is post-pilot, `docs/obf-interop.md:13`). The URL / web channel is missing (P-4e) | |
| P-10 | UX polish: tray redesign, grid haptics, age-adaptive voice / complexity | Shipped | Tray: #27, #57, #104; haptics `TileGridView.swift:38`; complexity adapts by Brown's Stage (#56) | PRD drift: stage replaces age, and voice is chosen per child rather than derived from age |

## Platform

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| PL-1 | iPad + iPhone from the start | Shipped | `TARGETED_DEVICE_FAMILY = "1,2"` (`claudeBlast.xcodeproj/project.pbxproj:373,417`); #30 | Mac (Designed for iPad) is also supported for caregivers (`project.pbxproj:365`; `docs/final-countdown-plan.md:44-47`), #57 |
| PL-2 | Grid adapts to form factor | Shipped | Separate iPad and phone grids (`GridLayoutCalculator.swift:42-88`) | PRD drift: a fixed grid per device kind, not density-by-size (#110). The phone does **not** keep the iPad's positions (`docs/next-session.md:11-12`) |
| PL-3 | SwiftUI + SwiftData, iOS 26+ | Shipped | `IPHONEOS_DEPLOYMENT_TARGET = 26.0` (`project.pbxproj:265`) | |

## Default Vocabulary Structure

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| DV-1 | ~500 words across the listed wordClasses | Shipped | 619 tiles in `Resources/vocabulary.json`; classes collapsed and retagged #46; 84-word batch #115 | PRD drift: counts (README and CLAUDE.md still say 473 / 480) |
| DV-2 | Navigation class: home, next_page, previous_page | Shipped | Keys exist (`vocabulary.json:1481,1691`) | Unused on boards (UX-7) |
| DV-3 | Home → category pages → sub-pages, with pagination | Shipped | `core_first.json` (home + a Groups folder of sub-pages, #98); swipe paging | Default board is named "BlasterAI 60 - System Supplied" (`core_first.json:3`), #116 |

## Decisions Made

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| DC-1 | JSON grammar for tiles, pages, tile sets | Shipped | `.blasterscene` + `.blasterpack` (`SceneTransferModels.swift:34-87`); packs `Resources/packs.json`; identity travels inside the file (`docs/scene-identity.md`) | |
| DC-2 | Share via website URL import | Not started | No evidence found; `blasterai.app/boards` is a future idea (`docs/next-session.md:69-76`) | |
| DC-3 | Share via text / share sheet | Shipped | `ShareBoardSheet` + `UIActivityViewController` (`SceneTransferModels.swift:275`) | |
| DC-4 | Universal links | Not started | Deferred: "do when link-sharing is a priority" (`docs/scene-identity.md:106-109`) | |
| DC-5 | AirDrop the file | Shipped | Share sheet; `Info.plist` document types | |
| DC-6 | App registers as handler; opening a file triggers import | Shipped | `Info.plist:5-156`; `claudeBlastApp.swift:274-282` → `ImportRouteSheet` (`ContentView.swift:154`); import conflict handling #44 | |
| DC-7 | Curated sets published on a website | Not started | See DC-2 | |
| DC-8 | Exports carry vocabulary / layout only, never usage or personal data | Shipped | `ExportableScene` has no usage fields (`SceneTransferModels.swift:162-195`); `docs/obf-interop.md:130-135`; the usage report is a separate, explicit export (#62) | |
| DC-9 | Age is a per-child setting driving complexity, vocabulary, voice | Deliberately dropped | Birthday / age / ageGrade deleted (`9701a0d`, #56; gate 9, `docs/final-countdown-plan.md:73,200-264`). Brown's Stage drives complexity (SE-14) | PRD drift: superseded by Brown's Stages |
| DC-10 | User supplies API key at setup | Shipped | Onboarding key step `Views/OnboardingView.swift`; key onboarding polish #36 | |
| DC-11 | Key stored securely (Keychain) | Shipped | `Services/OpenAIKeyVault.swift:10-29` (Keychain); env override DEBUG-only #106; a fresh install does not inherit a key #86 | |
| DC-12 | Low-friction key onboarding for non-technical parents | Shipped | Gifted keys (`docs/gifted-keys.md`) #83/#84/#108; keyless is a product mode (`Services/ProviderSelection.swift:21-50`; #71) | Welcome copy fix still pending (`docs/next-session.md:58-59`) |

## Demo Record & Playback (TileScript)

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| TS-1 | Built-in YAML demos bundled | Shipped | `claudeBlast/Resources/Scripts/`; #13, #38, #42 | |
| TS-2 | Record mode captures real interactions | Shipped | `docs/tilescript.md:106-116`; #13, #27 | |
| TS-3 | Hands-free playback, step / continue / pause / rewind | Shipped | `docs/tilescript.md:130-135`; rewind in `Engine/TileScript/TileScriptRunner.swift` + `Views/TileScriptPlaybackOverlay.swift` | |
| TS-4 | Floating HUD | Shipped | `Views/TileScriptPlaybackOverlay.swift` | |
| TS-5 | `RecordedScript` synced via iCloud; `.yaml` export | Shipped | `SchemaVersions.swift:69-80`; `docs/tilescript.md:109` | |
| TS-6 | Bulk cache generation for scale testing | Shipped | `BulkCacheGenerator` (`docs/tilescript.md:26,57,127`) | The single-word-mode playback TODO is still open in `TileScriptRunner.startScript` |

## Open Questions (as resolved)

| # | Question | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| OQ-1 | Move to the iOS 18 `Tab` API | Not started | The target is iOS 26, but the Admin tabs still use `.tabItem` (`Views/Admin/AdminView+NowTab.swift:23`, `+ScenesTab.swift:56`, `+ProfilesTab.swift:20`, `+DeviceTab.swift:101`, `+ActivityTab.swift:37`); the root is no longer a TabView (`ContentView.swift:76-83`) | PRD drift: the child surface left the TabView |
| OQ-2 | Voice selection for a child | Shipped | Per-child voice, rate and volume (SE-17) | |
| OQ-3 | Accessibility: VoiceOver, Switch Control | Partial | Accessibility pass #58; `accessibilityLabel` in 40 files, 29 `@ScaledMetric`; VoiceOver / Switch Control post-pilot (`docs/final-countdown-plan.md:1320-1322`) | |
| OQ-4 | Localization | Not started | No `.xcstrings`; `ChildProfile.languageRaw` is inert (`Models/ChildProfile.swift:258-271`); recorded as "not a launch gate" (`docs/localization-impact.md`); the rule that `TileModel.key` stays language-neutral is fixed | |
| OQ-5 | Image source / licence | Shipped | Resolved: the project's own OpenAI-generated art, Apache-2.0 (`NOTICE:13-32`) | |
| OQ-6 | Cache per-scene or global; eviction | Shipped | Resolved: global, with a versioned key; 180-day TTL + 2000-entry LRU, pinned entries exempt (`docs/cache-policy.md:52-67`), #43 | |
| OQ-7 | JSON sharing schema | Shipped | Resolved: DC-1 | |
| OQ-8 | Key onboarding without friction | Shipped | Resolved: DC-12 | |

## Appendix: discussion-log items that set requirements

| # | Requirement | Status | Evidence | PRD drift / superseded by |
|---|---|---|---|---|
| AX-1 | Apple Foundation Models provider (2026-03-15): retained, hidden from UI | Deliberately dropped | Hidden in the UI (`Views/Admin/AdminView+DeviceTab.swift:328`, "Apple Intelligence hidden — on-device safety guardrails"); kept for comparison (`SentenceEngine.swift:1292-1297`); #14. Reason: the guardrails trip on core AAC words (`docs/prd.md:344-351`) | |
