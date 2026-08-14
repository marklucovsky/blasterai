# Localization & Non-English Vocabularies — Impact Assessment

**Written:** 2026-08-13, after Mark's conversation with Brandi (SLP, board member of a
nonprofit that builds AAC systems in countries with no existing language system —
Cambodia most recently, a new country each year).

**Purpose:** predict the blast radius of non-English support *before* the CloudKit
Production promotion in session 4 makes parts of it permanent. **Solving localization is
not a launch gate. Predicting its impact is** — because one decision in here is
irreversible and the rest are not.

**Status:** assessment only. No code changes proposed for the pilot beyond the two-line
insurance in §6.

---

## 1. What Brandi actually described

Her team's field process, in her words:

> We go on site for two weeks and talk with the locals in a school. We get an idea of their
> language. Write that all down. We generate the boards in English and then use Google
> Translate to translate them to the local language, then we bring it into the locals and
> have them help us, modify the icons and the words to be more culturally relevant.
>
> Both the icons/pictures and the words definitely need a native speaker to help refine it,
> but the bulk of the work can be done by AI.

Follow-up on 2026-08-13 established the rest of the process. Asked whether the deliverable is
an app with Khmer TTS or PDFs printed on poster board, she answered **"Both"**:

> We printed from the web app so that they could use it either way. We generally generate
> everything in an app and then print those that way they have access to both high-tech and
> paper-based AAC.
>
> **We then train some of the locals on how to do editing so they can continue to customize
> and increase the vocabulary.**

Three things follow from this, and they reframe the whole problem:

**(a) The process is not translation of our vocabulary. It's elicitation of theirs.** Mark's
read is right: a Cambodian core board is plausibly ~200 words, not our 492, and the words
are not a subset chosen by translation — they're chosen by watching what children in that
school actually need to say. Trying to auto-translate `vocabulary.json` produces a board
that is grammatically Khmer and pragmatically American.

**(b) Her manual process is already our data model.** "Generate in English → translate →
natives fix the words and the icons" is precisely the shape of `TileModel`, where `key` is a
stable identifier and the label a human reads is a separate field. What she does by hand over
two weeks is a pipeline whose parts we mostly already have: `SceneGeneratorService`,
`PageGeneratorService`, `TileSuggestionService`, `TileImageGenerator`, `WordModerationService`.

**(c) The deliverable is a capability, not a board.** They train locals to keep editing and
growing the vocabulary after the team leaves. The two-week visit produces a starting point and
a set of people who can extend it. This is the finding with the longest reach — see §9.

The gap between us and her workflow is narrower than "localize the app" suggests.

---

## 2. The one irreversible decision

`TileModel.key` is load-bearing almost everywhere in the app. It is simultaneously:

| Role | Where |
|---|---|
| Record identity | `TileModel.key`, dedup in `BootstrapLoader` / `CloudKitDedupReconciler` |
| Bundled art reference | `bundleImage == key` → `TileImageSets/{set}_{key}.png` |
| Custom art reference | `TileArtVariant.tileKey` |
| Page membership | `PageSpec` tile lists (inline JSON on `BlasterScene`) |
| Sentence cache identity | `CacheKeyPolicy.key(for:grade:)` and `stableKey(for:childID:)` |
| History | `LoggedUtterance.tileKeys` |
| Scripts | `RecordedScript` |

And today it is spelled as an English word.

### The rule

> **`key` is a language-neutral concept id that happens to be spelled in English. It is never
> translated. The localized label lives in the display/speech field (see §3).**

Adopt this and a Khmer board is *the same concept graph with different labels*. It inherits
our art, our page structures, our scene generation, our cache, our logs. Localization becomes
a labeling and rendering problem rather than a re-architecture.

### Why it's irreversible

Violate it once — ship a build where a "localization" path mints Khmer-keyed tiles — and:

- Those tiles have no bundled art (`bundleImage` resolves to nothing) and no relationship to
  the English concept, so every generated board needs art generated from scratch.
- The records sync to CloudKit. **The Production schema is additive-only forever and the
  dedup reconciler cannot remove them.** Every device that ever syncs inherits the garbage.
- Cross-language work (a bilingual household, a board shared between an English SLP and a
  Khmer classroom) becomes impossible, because nothing relates `eat` to `ញុំា`.

This is the item that genuinely couples to the session-4 promotion. It costs nothing to
adopt now and cannot be undone later.

**Corollary:** `TileModel.normalizeKey` lowercases and underscores but does not restrict the
character set. If keys must stay ASCII concept ids, that should eventually be enforced there
rather than left to convention. Not urgent; noted so it isn't rediscovered.

---

## 3. `value` vs `displayName` — a latent fork localization will force

`TileModel` carries **both** `value` and `displayName`, and `init` sets them to the same
string. Readers have quietly diverged:

- `TileGridView:675` speaks `tile.displayName`
- `SentenceEngine:306,560` uses `tile.value` as the single-word sentence
- `SceneEditorView:367,1440` passes `tile.value` *as* a display name
- `WordModerationService:206` and `SceneImageBatchSheet:161` defensively fall back:
  `displayName.isEmpty ? value : displayName`

Today they're identical, so nothing is broken and nothing is visible. The moment a label is
localized they stop being identical, and the app will show one language and speak another.

The defensive fallbacks are the tell: two of them already exist, which means the ambiguity
has been felt.

**To decide (cheap now, ugly later):** one field is the *written label* and one is the
*spoken string*, and they are legitimately different — in many languages the written form and
the natural spoken form diverge, and for AAC specifically a tile may read "bathroom" and
speak "I need to use the bathroom." Pick the assignment, document it on `TileModel`, and
converge the readers. Both fields already exist in V1, so this costs no schema change at all
— it is pure clarification of fields we already promoted.

---

## 4. What the schema actually costs us — better than expected

- **`BlasterScene` stores pages as inline JSON `Data`** (`pagesData`, decoded to `[PageSpec]`).
  Scene *content* is invisible to the CloudKit schema. Per-page and per-tile language tagging
  can be added at **any time, forever, at zero promotion cost.** This is the single biggest
  de-risker in the assessment.
- **Adding `languageRaw: String = ""` to a synced model later is legal** — a defaulted
  additive field with a lightweight migration. Not a gate.
- **`SentenceCache` has no language dimension.** If a language is added later, old entries
  could serve an English sentence for a Khmer board. Self-healing: bump
  `CacheKeyPolicy.promptVersion` and `evictStale` sweeps them at launch. Already-solved
  problem, no action.
- **`MetricEvent` is device-local** and free to reshape.

Net: **the schema is not the constraint.** The constraint is §2's doctrine.

---

## 5. What's genuinely expensive, in order

### 5.1 Text-to-speech — CONFIRMED BLOCKED for Khmer

**Answered 2026-08-13. iOS has no Khmer voice.** Mark checked the iOS voice list, which is
organized by language/region — Cambodia does not appear. `VoicePickerSection:39` hardcodes
`.filter { $0.language.hasPrefix("en") }`, and removing that filter is trivial, but it would
reveal nothing to select. There is no code change on our side that produces Khmer speech.

So for the exact country Brandi named, **the electronic speech-generating path does not work
today.** This was the top risk in this assessment and it resolved against us.

#### The uncomfortable pattern

This is not bad luck, and it will recur. Brandi's nonprofit deliberately selects **"countries
where there currently isn't a language system"** — and that selection criterion correlates
strongly with the languages Apple has not invested in shipping voices for. Both track the same
underrepresentation. The places that most need AAC built from scratch are systematically the
places with no system TTS.

Expect the next country to have the same problem more often than not. The programmatic
enumeration (`AVSpeechSynthesisVoice.speechVoices()`, grouped by language code) is still worth
doing once to produce an actual coverage table rather than case-by-case surprises — but plan
on the assumption that a target language *lacks* a voice, rather than treating it as the
exception.

#### The three options, given that

1. **Paper / PDF.** Needs no voice at all. See §8 — and note Brandi delivers these already.
   This is the only option that works for Cambodia *today*, with no new runtime capability.
2. **Recorded human audio per tile.** A native speaker records the vocabulary during the
   two-week field visit. This fits their process better than anything else here — they
   already sit with locals to fix words and icons, and recording ~200 words is an afternoon.
   It also yields *better* output than TTS would: a real speaker, correct prosody, culturally
   natural phrasing.

   **Correction to an earlier draft of this document: we have no audio infrastructure to
   reuse.** `AudioPlayer.swift` is an empty tombstone ("Replaced by SpeechSynthesizer.swift"),
   and `RecordedScript` stores YAML tile-tap scripts (`yamlContent`), not audio. Per-tile
   recorded audio is a **new capability** — capture, store, sync, play — not a reuse. Scope it
   accordingly.

   Schema-wise it's cheap and safe: a new `TileAudioVariant` record type keyed by `tileKey`
   with `@Attribute(.externalStorage) Data`, exactly mirroring `TileArtVariant`. **Adding a
   record type is additive and legal post-promotion**, so this can be built any time without
   touching V1.

   The harder parts are not schema: recording UX, storage budget (~200 clips per board synced
   via CloudKit), and the fact that a sentence-generating AAC app cannot *speak a generated
   sentence* from per-tile clips. Recorded audio realistically pairs with **single-word mode**
   (which already exists as `InteractionMode.singleWord`), not with the sentence engine. That
   is a significant product consequence and should not be glossed: for a no-voice language,
   BlasterAI is a single-word AAC device plus an authoring pipeline, not a sentence generator.
3. **Network TTS.** Google and Azure do offer Khmer synthesis. This breaks the offline story
   and the no-external-backend privacy stance that is currently a core product claim
   (`docs/prd.md`, the site, the deck). Not recommended without a deliberate revisit of that
   claim — and if ever taken, it must be an explicit per-language opt-in, not a silent
   fallback.

   **But note who this favors.** Brandi's electronic deliverable is a *web app*, and she
   named CBoard and CoughDrop as the references that "leverage Google Translate." Web AAC
   tools reach cloud TTS as a matter of course. If their Khmer boards actually speak, they
   almost certainly speak via a network service — which means **the incumbents serve these
   markets precisely by doing the thing our architecture forbids.**

   That is a real strategic tension and it should be named rather than buried: our
   no-backend, on-device, privacy-preserving stance is a genuine differentiator in the US
   market and a genuine *disadvantage* in exactly the underserved markets where the mission
   argument is strongest.

   **Resolved by assumption 2026-08-13 (Mark):** treat Brandi's Khmer board as **classic AAC —
   tap a tile, hear a word** — almost certainly backed by a cloud TTS. That is the bar, and
   it is a *much* lower bar than it first appeared, because a closed vocabulary played one
   word at a time does not need synthesis at runtime at all. See §11.

### 5.2 Culturally relevant art — converges with session 2

Our p3d set is Western: the food, clothing, faces, and buildings are wrong for a Cambodian
classroom, and Brandi named icon modification as a step her natives always perform.

**This is the same object as the installable image set.** `docs/design-installable-image-sets.md`
already found that a set is not a folder of PNGs — it must carry its **style prompt and
subject overrides**, or on-device word-adds render in the wrong style. A culturally adapted
Khmer set is exactly that: same concept keys, different art, different subject overrides
("rice and fish, not sandwiches"), same style prompt discipline.

**Therefore:** building the set format properly in session 2's bundle-slim work buys the
localization art story nearly for free. Building it as a bundle-size hack forecloses it. That
is now an argument for doing 2B right, not just small.

#### 5.2.1 Skin tone — Brandi's "can you adjust skin tone?"

Mark's first instinct was to ask the generator for *diversity* — varied skin tone and body
type across the set. **For AAC specifically that is the wrong answer, on functional grounds
rather than political ones**, and it's worth writing down because the instinct is a good one
everywhere else.

In an AAC symbol set the human figure is not decoration — **it is the referent.** For `me`,
`my`, `I`, `you`, `mom`, `boy`, `teacher`, the person drawn in the tile *is what the word
points at*. A child learning that `me` and `my` refer to the same person must not see two
differently-featured people in those two tiles. Established symbol sets hold the figure
constant on purpose; the reference board Brandi sent shows the same boy in the same red shirt
across `here`, `want`, `eat`, `my`, and `me`. Randomizing appearance across a set doesn't read
as inclusive, it reads as *a different person each time*, which is a comprehension bug for the
exact user we're building for.

The right shape is **consistency within a deployment, configurable across deployments** — one
figure, matched to the child and their community. Which is exactly what Brandi asked for, and
it serves representation *better* than a diverse-but-random cast: the child sees themselves,
every time, rather than occasionally.

Mechanically this is a **subject override on a set** — the fourth time this document has
landed on the installable-set format as the answer (see §5.2, §9). Skin tone is not a new
mechanism; it's an instance of the one 2B is already designing. Use an established scale
(Fitzpatrick, which is also what Unicode emoji modifiers encode) rather than inventing one.

**Cost is tractable if it's done per-deployment rather than pre-baked.** Roughly 180–200 of
our 493 tiles depict people (`people` 20, `social` 32, `feeling` 14, `body`/`health` 17,
`sports`/`games`/`play` 13, the pronoun core, and the majority of `actions` 108, whose
pictograms are mostly figures) — call it ~40% of the set. Pre-generating six tones × two base
styles multiplies that into thousands of images and gigabytes. But **a deployment picks one
tone**, so the real job is ~200 images generated once at set-install or field-visit time. That
fits Brandi's model exactly, and it is another reason tone belongs in the *set* definition
rather than in the shipped bundle.

#### 5.2.2 `ImageSetID` is a closed enum — a 2B blocker for all of the above

`ImageSetID` (`Services/TileImageResolver.swift`) is a Swift `enum … String` with four
hardcoded cases. `TileArtVariant.imageSetRaw` is a `String`, so the **storage** side already
accommodates arbitrary sets — but the **type** does not. Three consequences:

- A third-party or downloadable set cannot be represented at all without a code change and an
  app update. That defeats the point of installable sets.
- Skin tone as *cases* multiplies combinatorially (`classic_tone1…6`, `playful_3d_tone1…6`).
  Tone is a **dimension**, not a case.
- `var imageSet: ImageSetID { ImageSetID(rawValue: imageSetRaw) ?? .playful3D }` **silently
  falls back** on an unknown raw. An older build encountering a newer set's variants doesn't
  error — it quietly renders the wrong art. Given sets will now arrive out-of-band, that
  fallback needs to become explicit and visible.

**The drift has already started:** `Resources/image_styles.json` contains a `high_contrast_v2`
style prompt that has no corresponding enum case. The style catalog has already outgrown the
type. 2B should make set identity a **string id + metadata record** (style prompt, subject
overrides, coverage, provenance, tone) rather than a hardcoded enum — which is, encouragingly,
what `image_styles.json` is already half-way toward being.

### 5.3 Prompts

`SentencePromptBuilder` bakes in US grade levels (`"2nd-grade student"`, `gradeDescription`)
and generates English. A non-English board needs a target-language instruction and a
replacement for the grade framing, which is a US schooling construct that doesn't transfer.
Moderate work; no schema impact. `CacheKeyPolicy.promptVersion` handles the invalidation.

**The grade framing has a bigger problem than portability — see §10.**

### 5.4 Word moderation

The age-appropriateness rubric in `WordModerationService` is English and culturally American.
Needs native review — which is the human step Brandi's process already includes.

### 5.5 Vocabulary size — the least worrying part

A ~200-word Khmer core is not an architecture problem. A scene is already an arbitrary subset
of vocabulary, `TileModel.isSystem` already distinguishes bundled words from added ones, and
vocab packs already exist as a concept (`VocabPack`, `PackCatalog`). A "Khmer core 200" is a
pack. Mark's instinct that the word list should be elicited rather than translated is not
only right pedagogically, it is *cheaper* for us.

---

## 6. What is NOT a gate

**UI string localization** — `Localizable.strings` for the caregiver surface. Ironically this
is what most people mean by "localization," and for the *pilot* it's the least interesting
piece: **Brandi's team authors in English.** The child-facing surface needs the local language;
the caregiver-facing surface does not. That split removes most of the perceived cost.

**Caveat added after the handoff finding (§9):** this holds for the two-week field visit and
breaks at handoff, when non-English-speaking locals take over the editing. UI localization is
not a pilot gate *and* is a hard prerequisite for the handoff story — two different deadlines,
not one. Don't let "not a gate" harden into "not needed."

---

## 7. Recommended actions before TestFlight

Small, and mostly doctrine rather than code:

1. **Adopt §2's concept-key rule** and record it on `BlasterSchemaV1`'s rule list, where the
   other permanent invariants already live and where it will actually be read.
2. **Add `languageRaw: String = ""` to `ChildProfile`** (empty ⇒ unspecified ⇒ `en`) before
   promotion. Strictly optional — it's a legal additive change later — but it's two lines
   now versus a field plus a backfill of build-1 testers' records later. Cheap insurance.
   Scene-level language needs nothing, per §4's inline-JSON finding.
3. **Resolve `value` vs `displayName`** (§3) and converge the readers. No schema cost.
4. **Enumerate available TTS voices** once, programmatically, into a coverage table (§5.1).
   The Khmer answer is already known (absent); the table is for the *next* country, so the
   answer arrives before the trip rather than during it.
5. **Design the installable-set format as the localization vehicle** in session 2 (§5.2),
   not merely as a bundle-size fix.
6. **Check print resolution before re-encoding** in 2B (§8). Compressing for screen is easy
   to undo *now* and expensive to undo after a set ships.
7. **Replace `ImageSetID`'s closed enum with a string id + metadata record** in 2B (§5.2.2).
   It currently blocks installable sets, skin-tone variants, and silently mis-renders unknown
   sets. `image_styles.json` already contains a `high_contrast_v2` with no enum case.
8. **Add `brownsStageRaw: String = ""` to `ChildProfile`** before promotion (§10) — same
   two-lines-now-versus-backfill-later argument as `languageRaw`, and it makes pilot data
   answer a question we can't ask retroactively.

### The insurance PR — scheduled for session 3 (decided 2026-08-13)

Actions 2 and 8 (`languageRaw` + `brownsStageRaw` on `ChildProfile`) travel together as one
small worktree + PR. **Session 3**, not session 2.

The deciding reason is a property worth protecting rather than a preference: `plan-2026-08-06.md`
defines session 2 as **"Touches no schema."** That's what makes 2B safe to iterate on
aggressively — nothing in the cost ledger or the bundle work can possibly compromise the
Production promotion. Putting two synced-model fields into it would forfeit that guarantee to
save a few days.

**Hard constraint:** this PR must merge before session 4 Phase 4. It is the only piece of
session 3 with an irreversible deadline, so it should land *early* in the session rather than
riding along with the polish sweep. Both fields are inert on arrival — nothing reads them yet —
which is exactly why they're safe to land early and cheap to land at all.

Explicitly deferred past the pilot: prompt localization, moderation-rubric localization,
translation tooling, UI strings, per-tile recorded audio, PDF export, any actual non-English
board.

**Reordered by §5.1's outcome:** with no Khmer voice, PDF export (§8) is a more likely first
real deliverable than anything in §5, and it is useful to English-speaking therapists on day
one regardless of localization.

---

## 8. PDF / paper board export — promoted from "open thread" to the lead candidate

Raised by Mark 2026-08-13 from a second angle: his granddaughter's SLP started her on
**laminated paper boards** before any electronic system. Brandi confirmed the same day: asked
electronic *or* PDF, she said **"Both"** — "we printed from the web app so that they could use
it either way… so that they have access to both high-tech and paper-based AAC."

**This corrects a question posed in the previous draft.** It asked what makes a school get the
electronic version versus the PDF. The answer is *nothing* — it isn't a fork in the road.
Every deployment gets both, deliberately, and they come out of the same authoring session.
Print is a **parallel rendering of the same board**, not a fallback for when the tech isn't
available. Design accordingly: not "export to PDF" as an escape hatch, but *every board has a
printed form* as a first-class output.

Combined with §5.1, that changes this item's status. Paper is not a consolation prize:

- **It is the path that works for Cambodia today regardless of §5.1.** No iOS voice exists, so
  our speech-generating runtime cannot serve Khmer — but a printed board needs no voice, no
  battery, and no device. The authoring pipeline we're strongest at (elicit → generate →
  translate → native review → print) is fully intact and ships value with the TTS question
  still unresolved.
- **It's already how the field works.** Both practitioners we have contact with — Brandi's
  team and a US-based SLP treating a specific child — deliver laminated paper. That's two
  independent confirmations that paper AAC is standard practice rather than a fallback, and
  frequently where a child *starts* before a speech-generating device.
- **Printing from the app is exactly what Brandi already does.** "We printed from the web app"
  — the artifact she wants is a rendering of the authored board, which is the cheap version of
  this feature, not the expensive one.
- **It reframes what BlasterAI is for a no-voice language:** an AAC *authoring* tool whose
  output happens to be printable, rather than a speech device that also prints.

### Session assignment — DECIDED 2026-08-13

**Session 3 (`cb-polish-mac`).** Mark's call, and the fit is better than "somewhere to put it":
session 3 is when Mac support first exists, and **the Mac is the device a therapist actually
prints from.** The feature and the platform arrive together.

**Shape it as the tibls share pattern, not as an export button.** Mark's precedent from tibls:
one share action offers the *native format* (JSON, for direct import into another user's app)
**and** a *PDF* (for a human who just needs the thing), from the same surface. Applied here:
share a board → the recipient either imports it into BlasterAI or prints it.

That framing makes this **one feature with two renderers, on infrastructure that already
exists** — not a new subsystem:

- `SceneExporter.export` / `.exportJSON` already produce the native payload
- `SceneTransferModels.swift:91` already wraps a scene as `Transferable` for `ShareLink`, and
  `:125` already wraps `UIActivityViewController`
- `ShareLink` is already used in `TileScriptView` (`:140`, `:217`)

The new work is the PDF renderer and print layout, plugged into a share surface that ships
today. It also subsumes the deferred "universal-link sharing / vocab as a shareable starter"
follow-on from the A3 work — same surface, third destination.

### Technical shape

Modest, and well matched to what exists. A scene is already an ordered page structure with
resolvable art (`TileImageResolver`) and labels; a print layout is a rendering of the same
object we already render to a grid. New concerns are print-specific rather than architectural:

- Physical tile size (an SLP picks by the child's motor precision, not by screen density) and
  therefore tiles-per-page independent of `GridLayoutCalculator`
- Cut lines / margins for lamination; optionally per-tile cards for PECS-style use
- Page and board naming printed on the artifact, and navigation links rendered as page
  references rather than taps
- Art attribution — `Scene.attribution` already computes this, and a printed artifact
  arguably needs it *more* than a screen does, since it circulates independently
- Resolution: our sets are sized for screens. Print at physical size may expose the
  re-encoding decisions made in session 2's bundle slim — **worth checking before we
  compress, not after.** (Flagged into 2B.)

It also composes with §5.2: a culturally adapted image set prints as well as it displays.

### Still worth asking Brandi

What the artifact physically is (single core board, page set, communication book, PECS-style
cards), who prints and laminates it, and at what physical tile size.

No estimate offered yet, but this is now the most likely first piece of real localization work
— and notably, it is valuable to English-speaking US therapists on day one, independent of any
localization at all.

---

## 9. Handoff — the locals keep editing after the team leaves

> We then train some of the locals on how to do editing so they can continue to customize and
> increase the vocabulary.

This is the finding with the longest reach, and it is not a localization requirement — it's a
statement about **who the caregiver persona actually is** at the far end of the distribution.

The deliverable is not a board. It's a board plus people who can grow it. The two-week visit
seeds a vocabulary; the locals extend it for years afterward. Which means the authoring
surface has to survive being used by someone who:

- **does not read English**, while our entire caregiver UI is English (§6 said UI strings
  aren't a gate because *Brandi's team* authors in English — that reasoning holds for the
  two-week visit and **fails at handoff**. This is a genuine correction to §6's scope: UI
  localization isn't a pilot gate, but it *is* a prerequisite for the handoff story, and those
  are different deadlines rather than the same one.)
- had a few days of training, not a product tour
- has no one to escalate to when something breaks
- is adding words in a language the app's AI prompts, moderation rubric, and art generator
  were never tuned for

Three concrete consequences:

1. **The installable-set finding stops being theoretical.**
   `docs/design-installable-image-sets.md` found that a set must carry its own style prompt
   and subject overrides or on-device word-adds render in the wrong style. Handoff is *the
   scenario that finding describes*: locals adding vocabulary for years, each new word
   generating art on-device. Get the set format wrong and their board degrades into visual
   incoherence one word at a time, with nobody present who knows why. **This raises the
   stakes on session 2's 2B from "bundle size" to "does the handoff story work at all."**
2. **BYOK is hostile at the far end of this.** Our onboarding assumes a caregiver who can
   create an OpenAI account, hold a credit card, and paste a key. A trained local at a
   Cambodian school plausibly has none of those. Whatever the answer is (a key provisioned by
   the visiting team, a shared organizational key, a no-AI editing mode that still lets words
   be added with existing art), it is not the flow we have. Not a pilot problem — the pilot is
   US caregivers — but it's the wall this direction hits, and it's worth knowing that before
   investing in the mission story.
3. **AI-assisted authoring is the actual product here.** Brandi already said "the bulk of the
   work can be done by AI" and her ask was for "a process that is streamlined to minimize the
   load for creating a whole new system." That is a fair description of `SceneGeneratorService`
   + `PageGeneratorService` + `TileSuggestionService` + `TileImageGenerator`, which we already
   have and CBoard/CoughDrop do not. **Our differentiator in this market is the authoring
   pipeline, not the runtime** — the runtime is where we're *behind* (no Khmer voice, §5.1),
   and the authoring pipeline is where we're substantially ahead.

None of this is pilot work. It's recorded because it changes what a collaboration with Brandi
would actually be building toward, and because #1 changes a decision we are making in session 2
in the next few weeks.

---

## 10. Brown's Stages — the grade-level axis is probably wrong

Raised by Mark 2026-08-13. **Roger Brown's Stages** (Brown, 1973) describe the path of normal
expressive language development in English in terms of morphology and syntax, indexed by
**MLU** (mean length of utterance, in morphemes) rather than by age. Stages I–V+ each carry a
target MLU band and a specific inventory of grammatical morphemes acquired in a reliable order
(present progressive `-ing`, plurals, possessive `'s`, articles, regular past `-ed`, third
person `-s`, copula and auxiliary *be*, …).
Reference: https://www.speech-language-therapy.com/clinical-topics/browns-stages-of-syntactic-and-morphological-development

**This is standard clinical vocabulary.** SLPs use Brown's stages routinely when analyzing a
language sample. It is not a novel framework we'd be importing — it's the one our users
already think in.

### Why our current axis is wrong for this population

`SentencePromptBuilder` instructs the model with `"Use the grammar and vocabulary of a {grade}
student."` `{grade}` comes from `ChildProfile.ageGrade`, which is computed **from the child's
birthday**. That encodes an assumption — *age predicts expressive language level* — which is
true for typically developing children and **definitionally false for the population this app
exists to serve.** A nine-year-old AAC user may be at Brown's Stage II.

And the error runs in the harmful direction: age-derived grade will usually *overshoot*,
generating utterances more complex than the child can own. In AAC, output the child couldn't
have produced isn't a helpful stretch — it's the app putting words in their mouth, which is the
central ethical failure mode of the whole category.

### Why Brown's is also just a better prompt

"2nd-grade" is a vague instruction. A Brown's stage is a *specification* — an MLU target plus a
named, closed morpheme inventory — and that is precisely the kind of constraint an LLM follows
well:

> Produce an utterance of 2–3 morphemes. You may use present progressive `-ing`, plural `-s`,
> and `in`/`on`. Do not use articles, past tense, or copulas.

That should measurably outperform the grade framing, and it's testable with the existing eval
harness — escalation quality was moved 38% → 85% by exactly this sort of prompt work.

### Fit with what already exists

- **Stage I ↔ `InteractionMode.singleWord`.** The single-word mode we already ship *is* Brown's
  Stage I. Right now the two are unrelated settings a caregiver sets independently.
- **MLU band ↔ `ChildProfile.maxSelectedTiles`.** Also currently independent and hand-set.
- A stage field would replace or augment `grade` in `CacheKeyPolicy.key(for:grade:)`, which
  embeds `g\(grade)`. That rotates cache keys — handled by a `promptVersion` bump, a path that
  already exists and is already exercised.
- **Schema:** a `brownsStageRaw: String = ""` on `ChildProfile` is a defaulted additive field,
  legal before or after promotion. Same cheap-insurance argument as `languageRaw` (§7.2): two
  lines now versus a field plus a backfill of build-1 testers later.

### The caveat that ties back to this document

**Brown's Stages are English-specific.** The 14 grammatical morphemes Brown identified *are
English inflectional morphemes*. Khmer is an analytic language with essentially no inflectional
morphology — no plural `-s`, no past `-ed`, no copula to contract. The framework does not
transfer. MLU counted in *words* may port with care; MLU counted in *morphemes* does not, and
the morpheme inventory is meaningless outside English.

So: adopting Brown's makes the **English** product substantially better and explicitly does
**not** solve the localization axis. It must not be allowed to look like it does — a
stage-based prompt is still an English-shaped prompt. A non-English board needs its own
developmental framing, which is a question for a native-speaking SLP, not for us.

### Recommendation

Worth doing, and **not because of localization** — it's a generation-quality and clinical-
credibility improvement that stands alone. It's also the kind of thing that changes how SLPs
read the product: speaking their framework is worth more than any amount of marketing copy,
and it's directly relevant to Kurt's clinical-trial and survey work and to
`docs/objection-register.md`.

Not a pilot gate. But **add the field before promotion** and let pilot SLPs record their
child's stage — then we learn from pilot data whether generation quality tracks stage, which
is a question we can't ask retroactively. This should probably graduate to its own design note
before implementation; it's larger than a localization concern and only landed here because
that's where the conversation was.

### Session assignment — DECIDED 2026-08-13

**English only, targeted at session 3** (Mark's call). Explicitly *not* framed as localization
work — per the caveat above, a stage-based prompt is still an English-shaped prompt.

**Split it in two, because the halves have different deadlines and different risk:**

| Piece | When | Why |
|---|---|---|
| `brownsStageRaw: String = ""` on `ChildProfile` | **session 3** (see below) | Two lines, but must precede session 4's promotion. Pairs with `languageRaw` (§7.2) in one small insurance PR. |
| Stage-driven prompt + eval validation | session 3, or post-launch | Reversible any time. Real work: prompt rewrite, `promptVersion` bump, eval-harness validation against the current grade baseline. |

The field is cheap and time-boxed by the promotion. The prompt change is a **generation-behavior
change landing immediately before a pilot**, and it needs eval evidence that it beats the grade
baseline before it ships — the same discipline that took escalation 38% → 85%. Don't let the
second half get squeezed into a polish session by the first half's deadline; if it can't be done
with eval backing, ship the pilot on grade and change the axis on pilot feedback.

---

## 11. The English-side AI boundary — the architecture a non-English board actually wants

Established 2026-08-13, from two of Mark's observations: that Brandi's board is classic AAC
(tap tile → hear word, cloud TTS), and that **our existing OpenAI calls are likely to behave
badly in a small-market language.**

The second suspicion is well founded. For a low-resource language like Khmer we should expect:
weaker generation quality from `gpt-4o-mini` than its English output would suggest; degraded
`/v1/moderations` coverage, meaning our three-tier word-safety gate silently gets less reliable
exactly where we can't tell; and materially worse tokenization (non-Latin scripts cost several
times more tokens per character, and Khmer is written without spaces between words), which
distorts the cost model session 2 is building.

Worse than any of those: **we cannot evaluate the output.** Nobody on this project reads Khmer,
and the eval harness is English. Shipping a generator whose sentences we are structurally
unable to check — to a non-verbal child, as their voice — is not a quality problem, it's an
ethical one.

### The resolution: the AI never sees the target language

Brandi's own process already draws this line, and we should adopt it as architecture:

> generate in English → translate → native speaker refines → deploy

Every AI service we run — `SceneGeneratorService`, `PageGeneratorService`,
`TileSuggestionService`, `WordModerationService`, `TileImageGenerator` — sits **upstream of the
translation boundary** and operates in English, driven by an English-speaking team. The
deployed board downstream is a static artifact: concept keys (already language-neutral, §2),
translated labels, art, and audio.

**Consequence: every risk above disappears.** The models only ever see English. Moderation runs
on English words. Token costs are English-shaped. And we can evaluate everything the AI
produces, because it's produced in a language we read.

The rule, stated so it can be checked:

> **AI runs English-side, upstream of translation. The deployed non-English board contains no
> live model call.**

### Runtime: no backend, and better output than a proxy

Mark's read is that a cloud TTS "doesn't necessarily mean we need a backend yet, and if we did
it would probably just be a simple proxy." Correct — and under this design we likely need
neither, because **a single-word board with a closed vocabulary has no novel utterances to
synthesize.** ~200 words is ~200 audio clips. Synthesize (or record) them **once at authoring
time** and ship them with the board.

That is strictly better than a runtime proxy on every axis that matters here:

- **Works offline** — decisive for schools in developing countries, where connectivity is the
  binding constraint and a per-tap network round trip is a broken product
- **No per-utterance cost**, no backend to run, no keys in-country
- **No change to the no-external-backend privacy claim**
- **Better audio**: for a low-resource language, a **native speaker recording 200 words** beats
  cloud TTS outright — and Brandi's team is already sitting with native speakers for two weeks

Cloud TTS then becomes an authoring-time convenience with a human-recording alternative, not a
runtime dependency. A proxy stays available as a fallback if pre-synthesis proves impractical,
but it should not be the design's assumption.

### This unifies two problems into one capability

Per-tile recorded/baked audio (`TileAudioVariant`, mirroring `TileArtVariant`, an additive and
therefore always-legal record type — §5.1) solves **both**:

- **§5.1** — languages iOS has no voice for
- **§9** — the handoff, where locals add vocabulary for years. A local adding a word **records
  it themselves on the device**: no cloud, no proxy, no API key, no BYOK problem, and higher
  quality than synthesis. Graceful degradation is natural — a new word shows its tile and stays
  silent until someone records it.

That last point is the strongest argument in this document for the whole direction: the
handoff-friendly answer and the no-voice answer are **the same feature**, and it is a feature
that needs no network at all.

### Caveats

- **Sentence generation is out of scope for such a board**, by construction. `InteractionMode`
  `.singleWord` already exists and is the right runtime mode. Be honest about it: for a
  language with no voice, BlasterAI is a single-word AAC device plus an English-side authoring
  pipeline — not a sentence generator. That's a narrower product than the US pitch, and it is
  still the thing Brandi asked for.
- **Machine translation is a first draft only.** Brandi's process already assumes a native
  speaker refines it; ours must too. Whether that step uses Google Translate, OpenAI, or a
  human is an implementation detail, not an architecture question.
- **The boundary must be enforced, not just intended.** The failure mode is someone later
  wiring "add a word" in-country straight into `WordModerationService` or `TileImageGenerator`
  with a Khmer string. That's the moment all the risks above come back, quietly.

---

## Related

- `docs/plan-2026-08-06.md` — the 4-session path to TestFlight; §5.2 modifies session 2's 2B.
- `docs/design-installable-image-sets.md` — the set format that §5.2 depends on.
- `docs/schema-audit-2026-08-06.md`, `claudeBlast/Models/SchemaVersions.swift` — the
  additive-only rules that make §2 permanent.
- `docs/cloudkit-promotion-runbook.md` — the session-4 ceremony this assessment precedes.
