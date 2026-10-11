# Blaster - Next Gen AAC Communication Device
## Informal PRD (Living Document)

**Revised 2026-10-11** against what shipped (scored in `docs/prd-scorecard.md`). ~~Struck~~ text is a requirement we changed or dropped on purpose; **Now:** says what replaced it and why. Unstruck text still stands, built or not.

### Mission
Redefine communication for non-verbal children. Open source (Apache license) to give back to the community.

Personal motivation: Built after seening how non-verbal granddaughter benefits from AAC technology. These devices are life-changing.

---

### What Blaster Is
An AI-powered AAC (Augmentative and Alternative Communication) app for non-verbal children. iPad-first. The child selects word tiles, and AI constructs ~~age-appropriate~~ sentences at the child's language stage from those selections, delivered as both text and speech. **Now:** language level follows Brown's Stages, not age (#56). The board works fully without AI; sentences are an optional, caregiver-enabled layer.

### What Makes This "Next Gen"
The original Blaster was hand-coded with a fixed 500-word vocabulary and proved the concept. This version rethinks the architecture with AI throughout - not just sentence expansion, but AI-assisted vocabulary creation, therapeutic tools, and adaptive growth.

---

### Core Principles

**1. Stability for the child**
- Fixed tile positions. The child builds muscle memory and spatial patterns.
- No dynamic rearrangement of tiles. Predictability is paramount.
- The grid is the child's voice. It must be reliable.

**2. Intelligence for the ecosystem**
- AI serves the therapists, parents, and teachers who shape the child's communication environment.
- AI generates tile sets ~~, expands sentences, synthesizes speech~~ and tile art, and expands sentences. **Now:** speech is on-device (`AVSpeechSynthesizer`, #11), so it works with no network.
- The child experiences the *output* of AI, not the complexity.

**3. Privacy is non-negotiable**
- User data lives in SwiftData + iCloud (private to the user's Apple ecosystem).
- No backend servers. No analytics platforms. No data harvesting.
- API calls to AI services (OpenAI) are stateless - send words, get sentences/speech back. No user identity or history stored externally.
- This population is vulnerable. Trust is everything.

**4. Open source (Apache)**
- Give this back to the community.
- Enable others to build on it, adapt it, translate it.

---

### Architecture Overview

#### Data Layer (Private - SwiftData + iCloud)
- Tile sets, tiles, layouts, scenes
- Usage history and analytics ~~(on-device only)~~ — on the family's own devices (iCloud), leaving only by an explicit, caregiver-initiated share (the SLP usage report, #62/#63)
- User preferences, voice settings
- Therapist-created content
- Syncs across user's own devices via iCloud. Nothing else.

#### Intelligence Layer (Stateless API Calls)
- **Sentence expansion**: Child selects tiles ("eat" + "chocolate") -> API constructs natural sentence ("I want to eat some chocolate")
- **Text-to-speech**: High quality, multiple voices ~~(OpenAI TTS or similar)~~. Voice selection matters - child may want a kid-sounding voice that feels like "theirs". **Now:** on-device system voices, picked per child (#11, #32).
- **AI-assisted tile set generation**: Therapist describes a goal ("emotions for a 5-year-old working on frustration vs anger") -> AI generates vocabulary, categories, suggested layout
- API provider: OpenAI (current target). Architecture should allow swapping providers.

---

### Two-Layer UX

#### Layer 1: Child Surface
- Full-screen tile grid. Big, clear, high-contrast.
- Sentence bar at top showing selected words.
- "Speak" button to trigger sentence expansion + TTS.
- Category pages (food, feelings, people, actions, places, etc.)
- ~~Promoted tiles: Frequently used combinations ("eat chocolate") can be promoted to their own single tile. Emerges from the child's own usage patterns.~~ **Dropped (2026-10-11).** A tile that appears because of usage moves the board under the child. Motor planning — finding a word where it always is — is how AAC is learned, and self-arranging tiles work against it.

#### Layer 2: Therapist/Parent Surface
- Behind Face ID / passcode authentication.
- **Create/edit tile sets**: Build custom vocabularies, assign images, set positions.
- **Scenes/Worlds**: Curated communication contexts:
  - Home morning routine
  - Classroom
  - Playground
  - Therapy session (targeted vocabulary)
  - Grandma's house
  - etc.
- **Import/export tile sets**: File-based, AirDrop between devices. No cloud service needed. Therapist builds on their device, AirDrops to child's iPad.
- **Usage analytics**: "This week Jamie used 'frustrated' 12 times but never 'disappointed'. Sentence complexity increased." Data stays on device. Child should never feel surveilled.
- ~~**Session mode**: Therapist takes over the tile set for a focused session (e.g., all about emotions). Reverts to normal home setting afterward.~~ **Dropped (2026-10-11), superseded by admin mode.** Behind the PIN / Face ID gate a caregiver switches scenes and the device's mode directly (long-press Home for the caregiver menu); there is no separate session to start and revert.

---

### UX Patterns (from original Blaster)

**Sentence Tray** (top of screen):
- Horizontal strip showing tile images the child has selected (e.g., [mom] [eat] [peanut butter])
- Below the tray: the AI-generated sentence text ("Mom, I want to eat peanut butter.")
- Clear button (X) to reset the tray

**Tile Grid** (main area):
- Dense grid of tiles filling the iPad screen. Each tile = image + label text below.
- Tiles are either **audible** (tap adds to sentence tray) or **navigation** (tap jumps to another page)
- Some tiles are BOTH (e.g., "eat" is audible AND links to the eat page full of food items)
- Navigation tiles include: home, ~~next_page, previous_page,~~ and category headers
- Grid is paginated when a category has too many items ~~(actions spans 2 pages with next/prev navigation)~~. **Now:** pages swipe, Home is pinned to cell 0 of every page and shares it with Back (#57, #109), and each device kind has three fixed grids, so a word keeps its cell (#110/#111).

**Page Navigation Structure:**
- Home page: category navigation tiles (people, actions, social, places, etc.) + frequently used people (mom, dad, grandma, etc.)
- Category pages: "eat" page has all food (meals, fruit, veggies, snacks in one big page), "drink" page, "actions" page (paginated), "social" page, "people" page
- Cross-links between related pages (eat page has link to drink page and vice versa). **Now:** supported, but BlasterAI 60 does not use them. Next to audible links they read wrong: Home → *eat* (audible) → Drinks → lemonade says "eat drink lemonade".

**Sentence Cache:**
- AI-generated sentences are cached by tile combination key (e.g., "mom, eat" or "eat, mom, pizza")
- Cache hits avoid redundant API calls - both cost savings and instant response for frequent phrases
- Cache tracks hit count per entry ~~- feeds into promoted tile logic~~
- Cache view shows: tile combination, cache hits, generated sentence, date, play/delete buttons

**Usage Analytics:**
- Per-tile metrics: selected count, used count, cache hits
- Overview shows "Frequently Used Tiles" ranked by usage
- "Top Cache Entries" shows most common phrases
- ~~This data drives the promoted tile feature - high-frequency combinations become single tiles~~ (promoted tiles dropped; see Layer 1). **Now:** it drives the caregiver's Activity, Coverage and Patterns views.

---

### Data Model (Sketch)

Informed by the original Blaster models but evolved for the next-gen architecture.

**Now:** the shipped shape differs from this sketch. Pages are inline `PageSpec` JSON on `BlasterScene`, not `PageModel`/`PageTileModel` (no relationships in the synced schema, #31). Per-tile metrics live in device-local `MetricEvent`; `type`/`TileType` was removed with promoted tiles. `Scene` shipped as `BlasterScene`. The concepts below — a global vocabulary, per-placement behaviour, wordClass as semantics only — all hold.

**Core concept**: Tiles exist in a global vocabulary. Pages reference tiles and give them position, navigation behavior, and audibility. This separation means the same tile ("eat") can appear on multiple pages with different behaviors.

```
TileModel (the vocabulary unit)
  - key: String (unique ID, doubles as image asset name)
  - displayName: String (shown on tile)
  - value: String (the word/phrase value)
  - wordClass: String (category: food, actions, people, etc.)
  - bundleImage: String (asset name for bundled image)
  - userImageData: Data? (optional user-provided photo)
  - metrics: [MetricType: Metric] (selected, used, cache hits, etc.)
  - type: TileType (word vs phrase - for promoted combo tiles)

PageModel (an ordered page of tiles)
  - displayName: String
  - tiles: [PageTileModel] (relationship)
  - tileOrder: [String] (explicit ordering array)
  - orderedTiles: computed from tileOrder

PageTileModel (junction: tile + page-specific behavior)
  - tile: TileModel (relationship)
  - link: String (if non-empty, tapping navigates to this page key)
  - isAudible: Bool (if true, tapping adds to sentence tray)

SentenceCache (cached AI responses)
  - tileKeys: [String] (the combination, e.g., ["mom", "eat", "pizza"])
  - sentence: String ("Mom, I want to eat pizza.")
  - hitCount: Int
  - created/lastUsed: Date

Scene (future: context switching)
  - name, description
  - activePages: [PageModel]
  - isActive: Bool
```

**Key relationships:**
- A Tile can appear on many Pages (via PageTileModel junction)
- A Page owns an ordered list of PageTileModels
- The same tile can be audible on one page and navigation-only on another
- Scenes compose Pages into a communication context
- **wordClass is purely semantic metadata** - it describes what a tile IS (noun, verb, feeling, etc.), NOT where it appears. Page membership is entirely a layout/composition decision. A therapist can compose pages from any mix of wordClasses based on therapeutic intent (e.g., an "emotions" page pulling from describe, actions, and social tiles).

---

### Tile Images / Symbols

The original Blaster uses custom illustrated images per vocabulary word (the key doubles as the asset name). For next gen:
- **Default**: ~~Ship with the original illustrated image set (or similar open-source AAC symbols)~~ **Now:** five sets generated for the app and shipped under Apache-2.0 — Classic in three skin tones, Playful 3D, High Contrast. ARASAAC was removed because its non-commercial licence blocked the App Store.
- **Customization**: Support user photos (camera/photo library) per tile - the child's actual dog, their real kitchen, their friend's face
- **AI-generated**: For therapist-created tile sets, AI could generate appropriate images. **Now:** shipped; new words are drawn in the board's own style from a per-style reference pack (`gpt-image-2`, #123).
- ~~**SF Symbols**: Could supplement for abstract/action concepts~~ **Obsolete.** Concepts no picture fits — letters, numbers, days, function words — are drawn in code (#69). An SF Symbol can still be used where one is the right picture.

---

### Sentence Engine

**Interaction flow:**
1. Child taps tiles → added to sentence tray ~~(tap again to remove)~~. **Now:** a grid tap only adds; tapping the last tile again escalates, and a word is removed from the tray chip (#26).
2. ~~1-second debounce: after no taps for ~1 second, trigger sentence generation~~ **Now:** the child presses Play; generation is automatic only at the tile cap (#26).
3. Cache check first → instant response + audio playback on cache hit
4. Cache miss → API call to OpenAI
5. Staleness guard: when API response arrives, verify selection hasn't changed while waiting. If child kept tapping, cache the result but don't display it (it's stale)
6. Display generated sentence text below tray + play audio

~~**No "speak" button.** The system auto-generates once the child pauses. This keeps the interaction dead simple - just tap tiles.~~ **Now:** there is a Play button (#26).

**Single tile:** If only one tile is selected, just display the word (no API call). Configurable option for auto-voicing single words.

**Max selected tiles:** Currently 4 in original. Should be configurable per child/profile. **Now:** set by the child's Brown's Stage (I = 1, II–III = 4, IV+ = 5–8).

**System prompt design (from original, to evolve):**
- Persona: "You are their voice and soul"
- Explains the word-selection communication model
- Safety rails: no sexual/violent content generation
- Uses wordClass as disambiguation context - tiles are sent as `"mom (people), eat (actions), pizza (meals)"` so AI can interpret ambiguous words correctly (e.g., "snack bar (food)" vs "snack bar (place)")
- ~~Age/voice setting: "grammar and vocabulary of a 1st grade student" → should be configurable per child profile in next gen~~ **Now:** per child, by Brown's Stage (#56).
- The prompt encourages relatable first-person sentences: "mom, tired" → "Mom, I am tired. Can I go lie down?"

**API integration:**
- Provider: OpenAI ~~(target: gpt-4o-audio-preview for integrated text+audio response)~~
- ~~Single API call returns both text transcript and base64 audio~~ **Now:** text only (`gpt-4o-mini`); speech is on-device.
- Voice: configurable (original hardcoded "nova"). Child should be able to pick "their" voice
- Architecture should abstract the provider so it can be swapped

**Sentence cache (SwiftData):**
- Key: sorted tile combination (e.g., "eat, mom, pizza")
- Value: generated sentence text ~~+ base64 audio data~~
- Hit count tracking ~~(feeds promoted tile logic)~~
- Cache lookup avoids API cost + gives instant response for repeated phrases
- The cache IS the child's developing language - their most common expressions crystallize into instant, cached phrases

**Conversational context:**
- Sentence generation should NOT be stateless. The session should track recent generated sentences and feed them back to the AI as conversation history.
- E.g., child says "Mom, I'm hungry" then taps "eat" + "pizza" → AI generates "Can I have pizza?" instead of the standalone "I want to eat pizza" (because the hunger context was just established)
- This makes the generated language feel like a real conversation, not a series of isolated announcements.

**Repetition as intensity / emotional escalation:**
- When the child taps the same tile combination repeatedly, each repetition should escalate the emotional intensity of the generated sentence.
- Real example: "pinkfong video" tapped once → "Grandpa, can we watch some Pinkfong videos?"
- Tapped 3 times → "Grandpa, I really want to watch Pinkfong right now!"
- Tapped 10 times → "GRANDPA, ALL I WANT TO DO IS WATCH PINKFONG NOW!"
- This is critical: repetition IS the child's volume knob. Neurotypical kids whine, raise their voice, tug on sleeves. A non-verbal child has tile taps. The device must understand that repetition = urgency/insistence and reflect it in both the language AND the speech (tone, emphasis, volume).
- Implementation: track repetition count in the session context. Feed it to the prompt as an intensity signal. Don't cache escalated sentences the same way - the cache should serve the baseline version, and escalation is applied dynamically.
- The TTS voice/prosody should also reflect the escalation - louder, more emphatic delivery as repetitions increase.

**Implementation notes for next gen:**
- Replace custom ApiTimer with Swift concurrency (`Task` + cancellation for debounce)
- Cache should persist in SwiftData (syncs via iCloud across devices)
- Cache serves the baseline sentence; conversational context and repetition escalation are layered on top dynamically (cache miss path)

---

### v1 Build Priorities (Revised)

Sentence generation is proven from the original Blaster. The high-value unknown is the content management / therapist layer. Build order reflects this — data architecture and content tools first, sentence engine is clean re-implementation of solved problem.

1. **SwiftData models** — Tile, ~~Page, PageTile,~~ TileSet/Scene. Get the data architecture right first. This is the foundation everything else builds on. (Pages became inline `PageSpec`.)
2. **Bootstrap loader** — Load the default ~500 word vocabulary + pages from JSON into SwiftData. Proves the data model works end-to-end.
3. **Skeletal grid view** — Minimal tile grid + sentence tray. Just enough to see and tap tiles. Scrolling grid with snap/haptics.
4. **Therapist mode** — The high-value new territory:
   - Face ID / passcode gate
   - Create / edit / save / name tile sets
   - Swap active tile sets (load/unload/swap operations)
   - ~~Session mode (temporary takeover, revert)~~ — dropped, superseded by admin mode
   - Import tile sets from JSON (URL, text message, AirDrop)
5. **Sentence engine** — OpenAI integration, debounce, cache-first lookup, staleness guard, conversational context. Clean re-implementation of proven concept.
6. **TTS + audio** — Voice selection, ~~integrated audio response,~~ repetition escalation in prosody.
7. ~~**Promoted tiles** — Usage tracking, surfacing frequent combinations as single tiles.~~ — dropped: works against motor planning
8. **AI tile set generator** — Therapist describes a goal, AI generates vocabulary + layout.
9. **Import/export polish** — JSON schema finalized, sharing via multiple channels.
10. **UX polish** — Tray redesign, grid haptics, ~~age-adaptive~~ stage-adaptive voice/complexity.

---

### Platform
- **iPad + iPhone from the start.** Not "iPhone later" — develop both layouts together.
- iPhone rationale: old/surplus iPhones are abundant and can be repurposed as dedicated communication devices. Lowers the barrier to access. Aligned with open source mission.
- Grid adapts to form factor: iPad shows more tiles per screen, iPhone shows fewer but snapping scroll handles it naturally. **Now:** three fixed grids per device kind (iPad 12×5 / 10×4 / 9×4, phone 4×5 / 3×4 / 2×4), and a scene declares the grid it was designed for (#110/#111).
- SwiftUI adaptive layouts handle most of this. Same data, same logic, different grid density.
- iOS/iPadOS, SwiftUI, SwiftData
- Target: iOS 26+

---

### Default Vocabulary Structure (from original Blaster)

~500 words across these wordClass categories:
- **navigation**: home, next_page, previous_page
- **actions**: ~90 verbs (eat, drink, play, want, help, go, stop, feel, etc.)
- **social**: greetings, responses, common phrases (hello, goodbye, yes, no, please, thank you, i_love_you, etc.)
- **people**: family, pronouns (mom, dad, grandma, friend, teacher, she, they, etc.)
- **food/drinks/snacks/meals/fruit/veggie**: comprehensive food vocabulary
- **places**: home rooms, community locations, school areas
- **describe**: ~90 adjectives/adverbs (big, little, happy, sad, fast, slow, etc.)
- **colors**: 14 colors
- **body/health**: body parts, ailments
- **toy/sports/games/art**: play and activity items
- **weather/shape**: environmental and educational concepts

Page structure: Home -> category pages -> sub-pages (with pagination for large categories)

---

### Decisions Made

**Tile/Page sharing format:**
- Define a JSON grammar for tiles, pages, and tile sets. Portable, human-readable.
- Sharing works via multiple channels: host JSON on a website (URL import), text/message the JSON (iOS share sheet / universal links), AirDrop the file.
- App registers as a handler for the JSON format - opening/receiving it triggers import flow.
- This supports both ad-hoc sharing (therapist texts a tile set to a parent) AND structured publishing (curated tile sets hosted on a website).
- Privacy preserved: the JSON contains vocabulary/layout only, never usage data or personal info.

**~~Age~~ Language stage / profile influences the AI layer:** **Now:** Brown's Stages replaced age, and the child's date of birth was deleted from the schema (#56) — a stage names a language target; a birthday was a privacy liability.
- ~~Age is a per-child profile setting.~~
- It determines: sentence complexity, vocabulary level in generated sentences, TTS voice selection/characteristics.
- A 4-year-old gets simpler sentences and a younger-sounding voice. A 12-year-old gets more complex language.
- This feeds directly into the system prompt ("communicate at the level of a [age]-year-old").

**API key management:**
- User supplies their own API keys during setup/configuration.
- Best practices TBD - need to research secure key storage on iOS (Keychain), onboarding UX for non-technical parents.
- OpenAI is the target provider. Relationship exists to influence what we need from them if gaps emerge.

---

### Demo Record & Playback (TileScript)

**Problem:** Demoing the app live is hard — the presenter can't simultaneously talk and drive the UI without mistakes. Preparing for a specific demo scenario requires writing YAML by hand.

**Solution:** TileScript provides scriptable playback with two content sources:
- **Built-in demos** — Hand-authored YAML scripts bundled with the app for common scenarios
- **User-recorded demos** — Record mode captures real interactions as replayable scripts

**Record mode flow:** Tap Record on the Home tab, interact with the app naturally (navigate pages, tap tiles, let sentences generate), tap Stop, name and save. The system captures every navigation and tile tap, grouping actions into utterance rows. The generated sentence becomes a comment in the YAML for readability.

**Playback features:** Scripts play back hands-free with configurable timing. Debugger-style controls (step over, step into, continue, pause, rewind) allow fine-grained control during presentations. A floating HUD shows current position and upcoming actions.

**Storage:** Recordings are SwiftData models (`RecordedScript`) — they sync across devices via iCloud alongside other app data. Export to `.yaml` files is available for sharing.

**Test harness:** TileScript also supports bulk cache generation for scale testing (e.g., 10K random tile combinations exercising the sentence cache). This shares the same script format and runner infrastructure.

See `docs/tilescript.md` for the full technical specification.

---

### Open Questions
- **TabView / minimum deployment target** (still open; Admin uses legacy `.tabItem`): iOS 18 introduced a new `Tab` API with significantly improved iPad behavior (sidebar-style tab bar, better adaptive layout). We're currently using the legacy `tabItem` modifier to support older targets, but should revisit raising the minimum to iOS 18 to get the modern tab experience — especially important for the iPad form factor where the tab bar presentation changed substantially.
- ~~Voice selection: What voices feel right for a child? Can we let the child pick "their" voice?~~ Answered: per-child voice picker.
- Accessibility: Beyond AAC - VoiceOver, Switch Control, other iOS accessibility features?
- Localization: Multi-language support from the start or later?
- ~~Image assets: Source/license for the default tile images?~~ Answered: generated for the app, Apache-2.0.
- ~~Sentence cache: Should cache be per-scene or global? What's the eviction strategy?~~ Answered: global, TTL + LRU (`docs/cache-policy.md`).
- ~~JSON sharing format: What's the schema?~~ Answered: `.blasterscene` / `.blasterpack`, plus OBF/OBZ export.
- Onboarding: How does a non-technical parent/guardian set up API keys without friction? Partly answered: setup guide, gifted keys, and a board that needs no key at all.

---

### Appendix: Discussion Log

*(Newest first)*

**2026-03-15 — Apple Foundation Models evaluation: blocked by safety guardrails**
- Built an `AppleSentenceProvider` using iOS 26 `FoundationModels` framework (`@Generable` structured output, on-device ~3B LLM). Goal: eliminate the OpenAI API key requirement — the #1 adoption barrier from the GTM plan.
- Also built a provider comparison mode (A/B): fire OpenAI and Apple in parallel, show both results in the sentence tray for side-by-side quality evaluation.
- **Result: Apple Intelligence is currently unusable for AAC sentence generation.** The on-device safety guardrails trigger on completely innocuous tile combinations — "grandpa" + "banana", "dad" + "cheese", "grandpa" + "peanut butter". These are core AAC vocabulary items.
- Tried multiple prompt strategies: (1) reusing the full OpenAI system prompt — triggered guardrails due to content-filtering language ("sex acts", "pornographic") in the prompt itself; (2) simplified child-focused prompt — "child" + food words triggered guardrails; (3) fully neutral prompt with no mention of children, age, or disabilities — still triggered on family member + food combinations.
- The ~3B on-device model also struggled with output quality when it did work — echoing prompt format back instead of generating sentences, likely due to the model's limited instruction-following capability.
- **Decision:** Apple provider code retained but hidden from the UI. The comparison infrastructure (parallel provider execution, comparison display in tray) is kept as general-purpose plumbing for future provider A/B testing (e.g., OpenAI vs Anthropic Claude API). The `AppleSentenceProvider`, `compareProviders` setting key, and `comparisonSentence` flow through `SentenceEngine` are all in place and can be re-enabled when Apple improves their guardrails or offers a way to configure safety thresholds for assistive technology use cases.
- **Filed as a known limitation.** Apple's Foundation Models framework is iOS 26 beta — safety guardrails may be relaxed or made configurable before GA. Worth re-evaluating each beta cycle.

**2026-02-17 — iPhone from day one + sharing is solved**
- iPhone layout developed alongside iPad, not deferred. Old/surplus iPhones become repurposed communication devices. Lowers access barrier.
- Grid adapts to form factor (fewer tiles visible on iPhone, snapping scroll handles it).
- Sharing (JSON import via text, file, URL) is solved engineering — Mark shipped this pattern in his production app Tibls (recipe sharing). Not a risk item.
- *PRD impact: Platform section updated. Sharing de-risked.*

**2026-02-17 — Build order revised: content management first**
- Sentence generation is proven — just needs clean re-implementation. The real unknown and high-value work is the therapist/content management layer.
- New priority: data models → bootstrap loader → skeletal grid → therapist mode (create/edit/save/swap tile sets, import JSON, session mode) → then sentence engine and TTS.
- Rationale: if content management is solid, the child grid is just "render the active set" and the sentence engine just processes whatever tiles are selected. The interesting problems are all in content creation and management.
- *PRD impact: v1 Build Priorities reordered.*

**2026-02-17 — PRD first pass review / clarifications**
- API provider: No lock-in to OpenAI. Use whatever suite of APIs delivers what we need. Mark has direct working relationship with OpenAI team (filed/resolved audio bugs during beta). Provider choice is pragmatic, not ideological.
- Sentence tray UX: The original tray layout was a rough guess. Needs real design thought. Open questions: should tiles shrink in the tray? Should text be more prominent? Better controls? The tray is prime real estate and deserves more attention.
- Tile grid scrolling: Traditional AAC devices don't scroll (inherited from paper-based systems). Links/manual page transitions shouldn't be the solution for grid scalability. A snapping scroll view (page-at-a-time with haptics) is more natural - kids already know how to scroll. Links should be reserved for context switches (e.g., "eat" → food context), not pagination.
- Tile key model: The `_`, `_1`, `_2` suffix convention for disambiguating duplicate words across categories is a hack but maybe a useful one if applied uniformly. Keys are designed to be simple, readable, sortable, and extensible.
- Cache/phrase key model: Cache keys are formed by collecting member tile keys into a Set (order-independent: "mom cookie" == "cookie mom"), then concatenating the sorted set into a stable string key. Set membership makes lookup clean; concatenation makes the composite key stable and immune to selection order.
- *PRD impact: Updated API provider stance, flagged tray UX as needing design work, added scrolling grid concept, clarified key/cache key patterns.*

**2026-02-17 — Open question resolutions**
- Tile sharing: JSON grammar for tiles/pages. Importable via URL, text message, AirDrop. App registers as handler. No usage data in exports.
- Age profiles: Age setting drives sentence complexity, vocab level, and voice in generated output. Feeds system prompt.
- API keys: User-supplied at setup. Stored securely (Keychain TBD). OpenAI contacts available if platform gaps arise.

**2026-02-17 — Repetition as emotional intensity**
- Repeated tile combinations should escalate sentence urgency. Tap 1: polite request. Tap 10: emphatic demand.
- Mirrors how non-verbal children use repetition as their "volume knob."
- Cache serves baseline sentence; escalation applied dynamically via session context + repetition count.
- TTS prosody should also escalate (louder, more emphatic).
- *PRD impact: New section in Sentence Engine covering repetition escalation.*

**2026-02-17 — Conversational context**
- Sentence generation should be stateful within a session. Recent sentences feed back to AI as conversation history.
- Enables natural follow-ups ("Can I have pizza?" instead of standalone "I want to eat pizza" when hunger was just expressed).
- *PRD impact: Added to Sentence Engine section.*

**2026-02-17 — BlasterState review**
- Reviewed original sentence engine: 1-second debounce timer, cache-first lookup, staleness guard, OpenAI integration with integrated audio (gpt-4o-audio-preview), wordClass used as disambiguation context in prompts.
- System prompt sets persona, safety rails, age-appropriate voice.
- *PRD impact: New Sentence Engine section capturing full flow, prompt design, cache mechanics.*

**2026-02-17 — Reference material review (models, screenshots, vocabulary, loader)**
- Original architecture: TileModel (vocabulary unit, key=image asset name, metrics tracking), PageModel (ordered tile collection), PageTileModel (junction with link/isAudible behavior).
- ~500 word vocabulary across 20+ wordClass categories. Pages defined separately in JSON.
- Key clarification: wordClass is purely semantic metadata. Page membership is a layout decision, not driven by wordClass.
- Screenshots confirmed: sentence tray at top, dense tile grid, cache view with hit counts, usage analytics.
- *PRD impact: UX Patterns section, Data Model refined, Default Vocabulary Structure section added.*

**2026-02-17 — Privacy and sharing architecture**
- Data stays in SwiftData + iCloud. No external backend.
- Therapist has local device access only (Face ID gated). No remote access.
- AI API calls are stateless (words in, sentence out). OpenAI is target provider.
- Open source under Apache license.
- *PRD impact: Core Principles section, Architecture Overview updated.*

**2026-02-17 — Initial brainstorm: two-layer architecture**
- Child surface: stable, predictable tile grid. Fixed positions for muscle memory. No dynamic rearrangement.
- Therapist/parent surface: create/edit tile sets, scenes/contexts, usage analytics, session mode.
- AI is for the ecosystem (therapists, parents), not the child directly. Child experiences AI output, not complexity.
- Promoted tiles: frequent combinations (from usage data) become single tiles. Emerges from child's own patterns.
- Scenes/worlds: curated communication contexts (home, school, therapy, grandma's house). Therapist can take over for a session, then revert.
- *PRD impact: Established Two-Layer UX, Core Principles, v1 Build Priorities.*
