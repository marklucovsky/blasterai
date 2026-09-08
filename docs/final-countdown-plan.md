# The Final Countdown — Sessions 3–6 to TestFlight

**Written:** 2026-08-24, after session 2 (`cb-cost-and-size`) merged and cleaned up.
**Supersedes** `docs/plan-2026-08-06.md` for sessions 3 onward. That document stays as
the record of sessions 1 and 2 and as the home of the appendices, which are still live
references and are not restated here.
**Purpose:** a durable plan a future session can pick up cold. Read this first.

---

## Where we stand

`main` @ `6b11b34`, 413 tests green. Sessions 1 and 2 are done:

- **Session 1 (`cb-release-plumbing`, PRs #50/#51)** — schema audit D1–D9,
  `BlasterSchemaV1` + migration plan, privacy manifest, export compliance, 0.9.0.
  CloudKit **promotion was deliberately deferred**, because running the ceremony as far
  as Phase 3 found four problems that code review had missed, and two of them would have
  been permanent. The lesson generalizes: *the value of the ceremony is the review, and
  the review only works against a schema that is still mutable.*
- **Session 2 (`cb-cost-and-size`, PRs #53/#54/#55)** — cost accounting (gate 4), bundle
  slim (gate 3: 276 MB / 3 sets → **38 MB / 5 sets** via HEIC re-encode), and metric
  compaction + storage visibility. The synced schema was untouched throughout, which is
  what made 2B safe to iterate on hard.

### Why this plan re-cuts the remaining two sessions into four

The old sessions 3 and 4 had absorbed more than they could hold. Session 3 was Mac +
iPhone layout + a polish sweep + four carried deferrals, and then took on PDF/paper
export and the Brown's Stages work. Session 4 carried CloudKit promotion, AdminGate
hardening, PIN recovery, the entire App Store Connect surface, and build 1.

Four sessions, each with one identity:

| | Branch | Identity |
|---|---|---|
| **S3** | `cb-polish-mac` | It looks and feels right on every screen it runs on, and the caregiver is asked for fewer, better things. **Mac is folded in here.** |
| **S4** | `cb-portable` | A board leaves BlasterAI in whatever form the person needs. |
| **S5** | `cb-launch-prep` | Everything a tester needs, except the build. |
| **S6** | `cb-build-one` | Build 1 exists, in testers' hands, and the path that produced it is a script. |

### Decisions taken 2026-08-23/24

- **Mac (Designed for iPad) is a supported pilot platform for caregivers** —
  screenshots, tester instructions, bug triage. Not advertised for the child surface. A
  child using a Mac as an AAC device is not the use case; a therapist building scenes on
  one absolutely is.
- **Print scope:** multi-page board PDF, single core board, tile-image export. PECS-style
  card sheets fold in as a *layout preset* of the same renderer, not a separate feature.
- **Interop: OBF export, one-way out.** `.obf`/`.obz` so a board opens in CoughDrop and
  the rest of the open ecosystem. Import is post-pilot.
- **Authoring-only is a win.** If a therapist uses BlasterAI purely to author and then
  leaves with a PDF, an OBF, and a folder of images, that is a successful outcome — not
  a leak. The export surface is designed *for* that person, not around them.
- **Brown's Stages moves into S3**, having been post-pilot. It replaces the age→grade
  derivation rather than adding to it, and collapses three existing caregiver knobs into
  one. See 3E.
- **A caregiver-facing usage report is an S4 share destination**, not an Activity-tab
  feature — because its real recipient is an SLP who does not hold the device. See 4E.

### The gates

| # | Gate | Session |
|---|------|---------|
| 1 | CloudKit container is Development-only; TestFlight runs against **Production** | **6** |
| 2 | Privacy manifest / export compliance / version numbers | ✅ S1 |
| 3 | Bundle size | ✅ S2 |
| 4 | Token/cost accounting | ✅ S2 |
| 5 | Mac never built or tested; AdminGate assumes Face ID | **3** |
| 6 | BYOK: a beta reviewer has no OpenAI key | **5** |
| 7 | PIN recovery is still "reinstall the app" | **5** |
| 8 | `ChildProfile.languageRaw` / `brownsStageRaw` must **exist** before promotion | **3A, deadline S6** |
| 9 | `ChildProfile.birthday` must be **gone** before promotion — a stored child DOB | **3F, deadline S6** |

**Gates 8 and 9 are the only irreversible deadlines in the countdown, and they point in
opposite directions.** A CloudKit Production schema is additive-only forever (Appendix B
of `docs/plan-2026-08-06.md`): after promotion you can add a field but never remove one.
So everything that should exist must exist by S6 Phase 4, and everything that should
*not* exist must be gone by the same moment.

- **Gate 8** is why 3A stays a standalone one-hour PR even though 3E consumes
  `brownsStageRaw` in the same session: the field must exist **whether or not 3E lands**.
  That is the entire point of calling it insurance.
- **Gate 9** is the mirror image, and the higher-stakes one, because it concerns a child's
  date of birth. See 3F.

Note that Production currently has **no schema at all** — session 1 deferred Phases 4–5 —
so neither gate is expensive today. Both become impossible the moment S6 promotes.

---

## Session 3 — `cb-polish-mac`

**Identity:** it looks and feels right on every screen it runs on, and the caregiver is
asked for fewer, better things.

The pilot's first impression is a caregiver's, and the caregiver surface has never had a
dedicated polish pass.

### 3A. Schema insurance — land this first

Add `languageRaw` and `brownsStageRaw` to `ChildProfile`, both defaulted. Roughly an
hour. `SchemaVersionTests` enforces membership and disjointness.

This was deliberately **not** in session 2, because session 2's defining property was
"touches no schema" — the guarantee that made the bundle work safe to iterate on. It is
first in session 3 because of gate 8.

### 3B. iPhone / iPad layout pass

Known defect: `VocabManagerView` filter-row clipping. Then a systematic sweep of every
caregiver surface at iPhone width — they were all built iPad-first, and `Views/Admin/*`
is where that concentrates.

### 3C. Mac (Designed for iPad)

Add the supported destination and work **Appendix C of `docs/plan-2026-08-06.md`** as the
test plan. It lists the known breakage classes rather than a generic sweep. In priority
order:

- **`AdminGate`** — Face ID does not exist on Mac and Touch ID may not either. The PIN
  path must be complete and discoverable, and biometric failure must degrade gracefully
  rather than lock a caregiver out. Highest-risk item on the list.
- Long-press gestures (caregiver menu, tile note capture) reachable with a trackpad.
- Arbitrary window sizes against `GridLayoutCalculator` and the portrait snap-offset
  `VStack` — not just device aspect ratios.
- Hardware keyboard vs `NumericKeypad`, which exists specifically to bypass the iPad
  software keyboard.
- macOS voice inventory — the picker must not offer voices that don't exist there.
- `.blasterscene` document-type registration, `fileImporter`, AirDrop.
- Three-way iPad + iPhone + Mac sync — but against Production, which means **S6**.

### 3D. UX tuning, defaults, carried deferrals

- Tap acknowledgement (haptic + visual) on `TileView`
- Escalation re-tap on a grid tile matching the last tray tile
- The `TileScriptRunner.startScript` single-word-mode capture bug (playback assumes
  sentence mode; it must capture `interactionMode`, force `.sentence`, restore on stop)
- Hardcoded `.font(.system(size:))` → semantic sizes
- A defaults audit: what a fresh install lands on before a caregiver touches anything

### 3E. Brown's Stages — the developmental axis

Moved in from post-pilot, and the argument is better than "there was room."

**The problem.** The sentence prompt says the child has "the grammar and vocabulary of a
`{grade}` student" (`SentencePromptBuilder.swift:48`), where `{grade}` is derived from the
child's *birthday* (`ChildProfile.ageGrade`, `:111`). That assumes age predicts expressive
language level — false by definition for AAC users — and in practice it overshoots.
Brown's Stages are age-independent, clinically standard, and a far more precise prompt
(MLU target plus a named morpheme inventory).

**Why it belongs in a polish session.** The stage selector does not *add* a knob. It
**collapses three existing ones into a single clinically-meaningful control.** Today a
caregiver separately sets:

- `interactionMode` — `.sentence` / `.singleWord` (`ChildProfile.swift:116`)
- `maxSelectedTiles` — a 2...8 stepper (`:60`)
- `ageGrade` — implicitly, by answering an age question during onboarding (`:111`)

None of those three means anything to an SLP. One Brown's Stage does.

**The mapping**, default **Stage I**:

| Stage | Interaction | Tile cap | Prompt |
|---|---|---|---|
| **I** | `.singleWord` | 1 | none — no AI call |
| **II / III** | `.sentence` | 4 | Brown constructs + morpheme inventory |
| **IV+** | `.sentence` | >4 | Brown IV+ constructs |

Stage is the stored source of truth and sets the other two; **raising the tile cap past 4
promotes the stage to IV+**, so a caregiver can stray without the setting going stale.
That two-way binding is the fiddly bit — settle the direction before writing it (see
Open Questions).

**Consequences to handle in the same PR:**

- **`birthday` is deleted outright — not merely stopped being read.** See the section
  below; this is the single most important thing in S3.
- **The cache key changes.** `CacheKeyPolicy.key(for:grade:)` emits
  `<model>/v<promptVersion>/g<grade>#…` (`CacheKeyPolicy.swift:57`) *precisely so* a grade
  difference stops serving stale sentences. Swapping `g<grade>` for `b<stage>` invalidates
  existing cached sentences — that is intended, but do it deliberately rather than
  discover it. Caregiver overrides key on the stable combo key (`:67`) and survive.
- **Onboarding gets simpler**, which is a polish win on its own: "how old is your child"
  becomes "where is your child now", with plain-language stage descriptions.
- **Gate the wording on evidence.** The selector and plumbing ship regardless; the
  **prompt rewrite** ships only if the eval harness (`claudeBlastTests/Eval`) shows it
  beats the grade baseline. Same discipline that took escalation from 38% to 85% in M1.

### 3F. Delete `birthday` — the last chance to not store a child's date of birth

**Decided 2026-08-24 (Mark).** An earlier draft of this plan said `birthday` "stops being
read but can never be deleted." **That was wrong**, and the error is worth naming because
it nearly cost us the window.

CloudKit permanence applies to a schema **that has been promoted to Production**. Ours
has not — session 1 deliberately deferred Phases 4–5, and Production has no schema at all.
The only schema that exists is in **Development**, which is disposable, and which the S6
runbook resets anyway as Phases 1–3. So:

> **Removing `birthday` is free today and impossible after S6 Phase 4.**

That is a second irreversible deadline, pointing the opposite way from gate 8. Gate 8 says
*add these two fields before promotion.* This says *remove this one before promotion.*
Both land in S3.

**Why it's the right call and not just a possible one.** A child's date of birth is the
highest-sensitivity field in the app by a wide margin — with a name attached it is a large
fraction of an identity kit, and it is the field a school district, clinic, or IRB will ask
about first. We store it today only to derive a grade number for a prompt, and 3E deletes
that reason: Brown's Stage is a clinical observation, carries no PII, and is a *better*
input. Keeping a DOB to power a feature we just removed would be indefensible.

It also strengthens a claim we already make. `PrivacyInfo.xcprivacy` declares
`NSPrivacyCollectedDataTypes` empty, and the answer to "what do you store about the child"
becomes "the name their caregiver chose, a voice setting, and a language stage" — with no
date of birth anywhere in it.

**Honest scope, so nobody over-claims:** this does not make `ChildProfile` PII-free.
`displayName` is a child's name and `notes` is therapist free text that can contain
anything. Removing the DOB is the large win, not the complete one. Worth pairing with a
nudge in onboarding that **a nickname is fine**.

**What the removal costs.** Bounded — roughly 20 call sites, most of them test fixtures:

- `ChildProfile` — drop the stored `birthday`, `age`, `ageGrade`, `age(from:asOf:)` and
  `synthesizeBirthday(age:asOf:)`, and the `birthday:` initializer parameter
- `SentencePromptBuilder.ageGradeLevel` → a stage, and `ChildProfileResolver.ageGrade` /
  `fallbackAgeGrade` with it (`SentenceEngine.swift:725`, `:923`)
- Onboarding: the age question and "Edit exact birthday" disclosure come out
  (`OnboardingView.swift:342–376`), as does `OnboardingCommit`'s `childBirthday`
- Admin: `ChildProfileFormSheet` birthday picker; the age/grade readouts in
  `AdminView+NowTab.swift:76`, `AdminView+ProfilesTab.swift:87`, `TransitionSheets.swift:237`
- `ProfileMigration` seeds Legacy and Sandbox with synthesized birthdays
  (`:71`, `:100`) — they become stage defaults
- Tests: `ChildProfileTests` loses its four `synthesizeBirthday` cases outright (they test
  a formula that no longer exists — delete, don't neuter, per
  `feedback_failing_tests_flag_at_source`); `ChildProfileResolverTests`,
  `OnboardingCommitTests`, `ProfileMigrationTests`, `InteractionModeTests`,
  `CloudKitDedupReconcilerTests` need fixture updates

**What it does not cost.** Two things Mark offered that turn out to be already paid for:

- **"Blow away the CloudKit container"** — only Development has a schema, and resetting it
  is already Phases 1–3 of the S6 runbook. No extra work, no Production data to lose.
- **"Force install all legacy devices"** — the standing rule already covers this: after a
  dev reset, *every device must be on the post-reset build before any of them syncs*, or
  an older build re-creates the removed field and promotion makes it permanent. Right now
  "all devices" means Mark's own; there are no external testers yet. Discipline, not a
  migration project.

**Sequencing within S3:** 3F rides with 3E in the same PR — 3E is what removes the
*reason* for the field, so splitting them would land a release where a DOB is stored and
nothing reads it. 3A stays separate and first regardless.

### Scope valve

S3 is full: 3A + 3B + 3C + 3D + 3E + 3F. If something has to give it is **3D** — the
carried deferrals are the least valuable items on the list, and 3E/3F are now the most.
Protect this order:

**3A** (gate 8) → **3E + 3F** (gate 9, one PR) → **3C** (gate 5) → **3B** → **3D**.

3E/3F moved ahead of Mac in this ordering because they are the ones with a door that
closes. Mac is a gate but not a *deadline* — it can slip to S5 in extremis; a stored date
of birth cannot.

### Exit criteria

Runs and looks right on iPad, iPhone, and Mac. No known layout clipping. The caregiver
authoring loop walked end-to-end on all three. A caregiver sets one Brown's Stage instead
of three unrelated knobs. **`grep -ri birthday claudeBlast/` returns nothing**, and the
app never asks for a child's date of birth. Full suite green.

---

## Session 4 — `cb-portable`

**Identity:** a board leaves BlasterAI in whatever form the person needs — and leaving is
a supported outcome, not an escape hatch.

Both practitioners we have contact with deliver **laminated paper**, and Brandi's team
ships paper alongside electronic on every deployment. Print is a parallel rendering of the
same board, not a fallback for when the tech isn't available. See
`docs/localization-impact.md` §8.

### What exists today, and what doesn't

- **Sharing is two ad-hoc call sites, not a surface.** `SceneEditorView.swift:311` and
  `AdminView+ScenesTab.swift:45` each build a `BlasterSceneFile` and hand a temp-file URL
  to a raw `ActivityView`. No page-level share, no tile-level share, no second renderer.
- The pieces underneath are sound: `SceneExporter`, `SceneImporter`, `BlasterSceneFile`
  (`Models/SceneTransferModels.swift:93`), `ShareLink` already used in `TileScriptView`.
  What's missing is **one surface they hang off**.
- **Exported scenes do not carry bundled art.** `SceneExporter.export` embeds image data
  only for tiles that are custom *or* carry a user photo; everything else travels as a
  key. Fine for BlasterAI→BlasterAI, fatal for OBZ (which is a zip *of* images) and for
  PDF.
- **Print resolution is settled: 512 px is enough.** Device art is 512×512 HEIC
  (`claudeBlast/TileImageSets/`, 38 MB). The 1024×1024 masters live in LFS under
  `tools/tile_sets/`, off-device. 512 px prints cleanly to ~2.5" tiles (≈205 DPI) and
  acceptably to 3" (≈171 DPI). `localization-impact.md` §8 asked that the print
  requirement be established *before* compressing; it wasn't, but the q65 encode was
  verified against a 2.5" print and holds up. **Decision (2026-08-31): accept the ~3" tile
  ceiling and build no print-quality path.** Typical AAC print tiles are 1–2.5", so the
  ceiling sits above the need. An open-source user who wants full-resolution art can take
  it from `tools/tile_sets/` themselves.

### 4A. One share surface

Replace the two ad-hoc `ActivityView` call sites with a single share action offering every
destination. This is Mark's "revisit sharing and make it excellent" item, and it is the
substrate for everything below, so it goes first.

**The unit of sharing is whatever the caregiver navigated to** — a scene or a page. Both
levels offer the same destinations; only the meaning of the native export differs.

| From | `.blasterscene` | PDF | Tile images | `.obz` |
|---|---|---|---|---|
| **Scene** | the scene | every board page, in order | all tiles in the scene | scene → board set |
| **Page** | a **pack** (4A″) | that board page | that page's tiles | page → one board |

Sharing a *page* natively is the wrinkle, and it is the vocabulary-pack concept: the
content used to build a page, portable into someone else's scene. See 4A″.

### 4A″. Page-as-pack — the native page export

A page is not a scene, so `.blasterscene` is the wrong envelope for one. What travels is
the page's *content*: its tiles, their order, their `wordClass`, their art. What cannot
travel is navigation — a page's `link` targets name pages that will not exist in the
destination scene.

Rule: **drop the links, keep the tiles.** A pack imported into an existing scene becomes a
new page whose linking tiles are inert until the importer wires them up. Record this as a
lossy mapping the same way 4D records OBF's, because it is the same class of loss.

This aligns with the existing `Resources/pack_*.json` shape and with OBF, where a page
maps cleanly onto exactly one board.

### 4A′. Art embedding — prerequisite for 4B, 4C, 4D

Extend `SceneExporter` so an export can carry resolved art for *every* tile, not just
custom ones; `TileImageResolver` already resolves per-set. Keep key-reference-only as the
default for BlasterAI→BlasterAI, since it is far smaller. Build this once, not three
times.

### 4B. PDF board renderer

Caregiver controls: **grid density**, **paper size**, **filters** (wordClass,
audible-only, custom-only). Plus cut lines and margins for lamination, board and page
names printed on the artifact, page links rendered as printed page *references* rather
than taps, and `Scene.attribution` on every sheet — a printed artifact circulates
independently of the app, so it needs its attribution more than the screen does.

#### Terminology, because the two senses of "page" collide here

- **board page** — the app's page, a navigation unit (`home`, `actions`, `describe`).
- **paper sheet** — one physical piece of paper.

**Some board pages are large.** `scenes/core_first.json` defines pages by class expansion
rather than by literal tile lists, so `{"class": "describe"}` resolves at bootstrap
against a 493-word vocabulary in which `actions` is 108 tiles and `describe` is 104. A
board page routinely exceeds one sheet.

#### Pagination rule

- A board page **always begins on a fresh sheet**.
- A board page consumes **as many sheets as it needs** at the chosen density.
- **Two board pages never share a sheet**, even when both are small (`people` resolves to
  ~20, `weather` to 16).
- Continuation sheets are numbered **within** the board page — "Describe · 3 of 12", not a
  running count across the scene — so one sheet can be reprinted without renumbering the
  set.

#### Density, and where the floor is

US Letter with 0.5" margins gives a 7.5 × 10.0" printable area; allow ~0.35" per row for
the label strip:

| Grid | Tile size | DPI at 512 px | Sheets for `describe` (104) |
|---|---|---|---|
| 3 × 3 | 2.5" | 205 | 12 |
| 4 × 4 | 1.88" | 273 | 7 |
| 5 × 6 | 1.5" | 341 | 4 |
| 6 × 8 | 1.25" | 410 | 3 |

At 512 px the constraint is a **floor on columns, not a ceiling**: below 3 columns the
tile passes 3" and the art goes soft. The density picker stops at 3 columns; it needs no
warning at the dense end. A full scene at 3×3 runs to roughly 40–50 sheets, which is
simply what a laminated core-board set looks like — density is what makes that the
caregiver's call rather than ours.

**Letter and A4 both**, chosen at export. A4 (210×297 mm) changes every number in that
table, and a meaningful share of early users are outside the US.

#### Layout presets, one renderer

The "single core board" preset is **struck**. It presupposed condensing a whole scene onto
one sheet, which needed either an AI call or a caregiver picker. Under 4A's model the unit
is whatever you navigated to, so a board page already *is* the single board — no selection
step, and no new AI surface this late. What remains:

- **Scene render** — every board page, each starting a fresh sheet. The core ask.
- **Page render** — one board page, however many sheets it takes.
- **Cut lines + low density** — the PECS case, an option on either render rather than a
  third preset.

**Printed links reference the board page by name** ("→ Food"), never a sheet number: the
target spans sheets and its extent shifts with density. Cheap now, annoying to retrofit.

### 4C. Tile-image export

Multi-select tiles with wordClass filtering, exported as image files (folder or zip), for
the caregiver who wants the pictures themselves. Shares 4A′.

### 4D. OBF / OBZ export

One-way out. Map pages → boards, links → board references, and wordClass onto OBF's own
vocabulary hints where they exist. Ship **`.obz`** (zipped, images embedded) as the
default, since a bare `.obf` referencing our art is useless anywhere else.

**Record the lossy mappings in the doc.** OBF's model is not ours; that list is the honest
spec of what "interop" means here, and it is what makes import (post-pilot) tractable
later.

### 4E. Usage report — the child's patterns, shared to a caregiver or SLP

**Status (2026-09-04): BUILT.** Activity now bands by session; `Coverage` and `Patterns`
are new screens; the readable report renders to PDF from Admin → Activity → Share report,
behind `AdminGate`. Design notes in `docs/usage-report-notes.md`; the draft canvas Mark
reviewed is at <https://claude.ai/code/artifact/de571911-1ab6-4284-9efd-0cc1131085b6>.

**The question held for Brandi is answered as a toggle, not a decision.** "Include what
was said" defaults **off** — the report still carries how often, when, which words and how
much of the board, and withholds only the sentences. A caregiver can always send more and
can never unsend, so the default is the direction that can be walked back. If Brandi says
SLPs need the full history, it is one flag. When utterances ARE included, the warning is a
running footer on every page, because page four can be forwarded without page one.

**Still open, and deliberately deferred:**

- **Scheduled sends and the States screens.** The weekly digest is the same job as the PDF
  — deliver the report — so building it separately would build the delivery path twice.
  Note the constraint that shaped it: a digest only works INSIDE the family iCloud, where
  a caregiver device holds `LoggedUtterance` by sync and raises a *local* notification. On
  a patient-only device there is nowhere to send it, and the SLP is never a sync peer, so
  their copy is always an exported file. That is the PDF's real job.
- **Custom date ranges** — post-launch, `docs/architecture-backlog.md` §4.

Mark's framing: a share operation *from the child's device to the caregiver*, over
iMessage. Same share pattern as 4A, different payload. It belongs here rather than in the
Activity tab because **the recipient is usually not holding the device.**

- **Who it's really for.** In a two-device family, CloudKit already syncs
  `LoggedUtterance`, so the caregiver's own device has the data. The share matters for the
  single-device case and — more importantly — for **sending it to the SLP**, who will
  never be on this family's iCloud account. Design the readable renderer for that reader.
- **This deliberately crosses a line `StorageExport` refuses to.**
  `Services/StorageExport.swift` is aggregates-never-content by explicit design, down to
  omitting `MetricEvent.subjectKey` because for cache rows it *is* the child's speech. A
  usage report is only useful if it contains the words: which ones, how often, which
  pages, sentences per day, time-of-day pattern, vocabulary growth. Therefore: an explicit
  caregiver action behind `AdminGate`, plainly labelled as containing the child's words,
  never automatic and never in the background.
- **Two renderers again** — a readable summary someone can open in Messages, and a data
  file for anyone who wants to analyse it. `StorageExport` stays exactly as it is for the
  device-health case; this is a second, separate export.

### Exit criteria

From one share action, a scene leaves as JSON, as a printable PDF, as an image set, and as
an `.obz` that opens in CoughDrop — and a *page* leaves by all four routes too, its native
form being a pack. A large board page prints across multiple sheets without ever sharing a
sheet with another board page. A child's usage report reaches an SLP who has never touched
the device. Every tile key still renders in every destination.

**Nothing falls this round** (Mark, 2026-08-31). Unlike S3, S4 has no scope valve; the
struck single-core-board preset is a simplification, not a cut.

---

## Session 5 — `cb-launch-prep`

**Identity:** everything a tester needs, except the build.

S4's cleanup list was never cleared — S4 closed on its exit criteria with
`docs/s4-cleanup.md` §1–§6 and §9–§12 still open. Mark's call, 2026-09-04: those
roll into S5 as if they had belonged all along, and PR 1 clears the mechanical
half of them. Two new pieces of scope arrived the same day (tile color and
sparse boards); both are recorded below before the PR table, because the PR
ordering only makes sense once the color decision is understood.

### PR ordering

| # | PR | Contains | Note |
|---|---|---|---|
| 0 | docs | this plan section | doc-only, direct to main |
| 1 | **cleanup** | S4 §1 `bassketball` delete · §2 `cls_help` frame regen · §3 print label shrink-to-fit · §4 `isStructuralChrome` ×5 sites · §5 `NOTICE` rewrite (Apache-2.0) · §6 CLAUDE.md test-name check | mechanical; §4 unblocks PR 2 |
| 2 | **color** | `partOfSpeechRaw` on TileModel · 4-layer resolver · `VocabularyClass.color` → `defaultPartOfSpeech` · drop `PartOfSpeechIndex.overrides` · resolver takes a tile, not a string (~12 sites) · Fitzgerald palette · filled cards · card ignores dark mode | **the only S6 schema deadline** |
| 3 | **sparse boards** | `TileEntry.isConcealed` (not `isHidden` — `hide` is the word-level safety hide) · unique `<spacer>#…` keys · one empty-cell render path · coverage counts concealed ≠ spacer · bulk conceal/reveal · OBF gap | blob-local, no schema change · **merged (#66)** |
| 3.4 | **page rename** | `PageSpec.displayName`, key never moves · rename in the page editor · travels in scene share, print, OBF | **merged (#67, #68)** |
| 3.5 | **letters & numbers** | `GlyphTile` draws a–z and 0–10 · two packs · natural sort · glyphs in the per-set review strip | zero bytes; no generated art |
| 3.6 | **color mapping** | therapist-editable part-of-speech → color, per child | ⚠️ **schema deadline** — see below |
| 4 | **gates** | §9 scene validation on activate · §10 iCloud toggle confirmation both directions · modal progress for long ops · audit sibling one-tap actions | two live lockouts + the stray-tap iCloud flip |
| 5 | **compact + names** | §12 Coverage / Patterns / coverage grid at phone width · **§11 profile model** — see below | both are "reviewed on the wrong device or by the wrong reader" |
| 6 | **tester readiness** | AdminGate hardening · PIN recovery · no-key path verified | no-key path is the likeliest rejection cause |
| 6.5 | **positioning** | the order of the pitch · beta-review notes · site + deck + video recut · onboarding copy | see below — split out of 6 on 2026-09-07 |
| 7 | **launch assets** | claims refresh · ASC record · icon audit · privacy labels · screenshots iPad/iPhone/Mac | exit criteria live here |

PR 2 is sequenced early because it is the only irreversible item, and PRs 3 and 5
both render against the palette it establishes.

### The palette is ours, and it should not be (decided 2026-09-04)

`VocabularyClasses.swift` says it plainly — *"Colors mirror the legacy switch"*.
We invented the colorway, and it colors by **semantic category** (food red,
animal brown, places blue). No clinical practice uses that axis.

What every board we are compared against uses is the **Fitzgerald Key**: a
*part-of-speech* axis, taught by SLPs, carried between apps. TouchChat, Snap Core
First, LAMP, PODD and CoughDrop all speak it. A child moving between our board and
their school board currently gets no transfer at all.

Mark's call: we already know the right answer and we already built the axis —
adopt it now rather than waiting on the design session `docs/s4-cleanup.md` §8
proposed.

**We have the data.** `43ce69b` shipped `PartOfSpeech` + `PartOfSpeechIndex`.
496 of 507 vocabulary keys are in `Resources/parts_of_speech.json`; the 11 that
are not are exactly the structural chrome that `isStructuralChrome` names, and
they *should* fall through to chrome styling rather than a word color. There is
no gap to fill.

**Mapping** (Modified Fitzgerald, as Snap Core First and TouchChat teach it):

| PartOfSpeech | color |
|---|---|
| pronoun | yellow |
| verb | green |
| adjective | blue |
| noun | orange |
| question | purple |
| negation | red |
| social, interjection | pink |
| preposition, determiner, conjunction | white / neutral |
| *(no part of speech — chrome)* | gray / indigo, as now |

**Three consequences, accepted deliberately:**

1. **The palette collapses from ~20 colors to 8.** Food stops being red and
   becomes orange like every other noun; mint, teal, cyan and brown leave the
   board entirely. Color no longer distinguishes food from places. That is the
   trade Fitzgerald makes on purpose — fewer colors, but ones a therapist teaches
   and a child carries elsewhere. Every existing board and PDF changes appearance.
2. **"White" does not survive a naive fill.** Function words are white on a
   Fitzgerald board because the card sits against a colored surround. On our
   white ground that is invisible, so it becomes a neutral card with a visible
   outline.
3. **The tile card does not follow dark mode.** Fitzgerald colors are taught as
   constants; a board is a physical object. The card stays light in both
   appearances and only the chrome around it goes dark. This is also the better
   answer to "the color needs to be bolder in dark mode" — a light card on a dark
   ground is the boldest version available, and it costs no new constants.

**Color on the edge is why ours reads flat.** `TileView.swift:139–149` draws a
`lineWidth: 3` border at `opacity(0.6)` over an `opacity(0.12)` fill. Side by side
with cboard on the same tiles, their color *is* the card and ours is a hairline
around a white card — the board reads monochrome from three feet away. Our own
PDFs are closer to cboard than our app is, because the print renderer fills.

#### Resolving a part of speech

```
1. TileModel.partOfSpeechRaw   stored, synced — therapist / classifier truth
2. parts_of_speech.json        bundled table, 496 words
3. derived from wordClass      total for any real word
4. nil                         structural chrome only (home, page_*, nav)
```

**Reporting stops after layer 2; color runs all four.** "Strict" means *no
guessing*, not *table only*: a therapist's stored answer is not a guess, so
coverage must honour it; a derivation is, so coverage must not.

- `partOfSpeech(for:)` → `stored ?? bundled` — nil-able, feeds the coverage report
- `resolvedPartOfSpeech` → `stored ?? bundled ?? derived` — total, feeds `TileColorResolver`

Layer 1 must outrank layer 2, or a therapist correcting a *bundled* word (calling
`more` a verb on their board, not a determiner) is silently ignored on exactly the
words most likely to be argued about.

**Layer 3 was measured, not assumed.** Deriving from `wordClass` — which the
caregiver already picks when creating a word — gives **92.3% color accuracy**
across the caregiver-selectable classes. Every one of the 36 misses is a *bundled*
word, which has an exact table entry and never reaches the derivation; the misses
concentrate in function words (prepositions filed as `describe`, pronouns filed as
`people`) that a family will never add. They add "grandma", "Bluey", "trampoline".
Real-world accuracy on the population the fallback actually serves is well above
92%.

Two structural changes fall out and should land in the same PR:

- **`PartOfSpeechIndex.overrides` goes.** It was the seam for exactly this, and
  the stored field is now that seam. Keeping both leaves two override mechanisms
  with undefined precedence — the same shape as the copy-pasted predicate §4 is
  cleaning up.
- **`VocabularyClass.color` becomes `defaultPartOfSpeech`.** A column swap, not a
  new file: the catalogue that already declares what classes exist also declares
  what each one is grammatically, so there is no parallel switch to drift. Color
  leaves the catalogue entirely.

The resolver must also move to where a tile is in hand. `wordClassColor(_ String)`
and `colorForWordClass(_ String)` become tile-taking; all ~12 call sites already
have the tile (`TileView`, `SentenceTrayView`, `SingleWordTrayView`,
`CompactTrayStrip`, `CoverageGridView`, `AdminView+ActivityTab`).

#### The schema deadline

`partOfSpeechRaw: String = ""` on `TileModel` is a **synced schema change and must
land before S6 promotion.** It is the only deadline-bearing item in S5.

It is taken as insurance, on the S3 3A precedent (`languageRaw`, `brownsStageRaw`).
v1 derives; the field ships empty. It exists so that a therapist can correct a
color and have it stick, and so a classifier run at word-add time (we already call
`WordModerationService` there and it could return a part of speech in the same
response) can persist its answer. Without it, `overrides` is in-memory only: the
answer dies at relaunch and the same word renders orange on the iPad and gray on
the iPhone. Derivation would be correct today and permanent forever.

### Sparse boards: hidden tiles and spacers (decided 2026-09-04)

Published AAC boards leave cells empty on purpose, and the technique is to grow a
child's word-space by unhiding rather than by adding. Two mechanisms, one
rendering.

**The clinical argument is motor planning, not tidiness** — the same argument that
put Home at cell 0. Deleting a word reflows the board and moves every other word;
hiding it in place moves nothing. So hide-in-place becomes the *normal* way to take
a word off a board, and deletion the rare one.

- **Hidden tile** — `TileEntry.isHidden`. A word that is on the board but
  unavailable. It belongs on `TileEntry` rather than in a parallel page-level
  `hiddenKeys` array: `TileEntry` already *is* the per-page instance (it carries
  `link` and `isAudible`, both page-specific), and a parallel array is a second
  thing to keep in sync — delete a tile and the key is orphaned, reorder and
  nothing tells you.
- **Spacer** — a `TileEntry` with the reserved key `"<spacer>"` and no `TileModel`
  behind it, following the existing `link: "<home>"` magic-token convention. Not a
  word at all.

**The spacer key must be explicit, never "a key that does not resolve."**
`docs/s4-cleanup.md` §9 lists "a page whose tiles all resolve to missing
`TileModel`s" as the export bug's signature — a page that looks populated in the
editor and empty on the board. If unresolvable silently meant spacer, we would
destroy the only signal separating corruption from intent.

**What reflow costs us.** Our board derives its column count from geometry
(`tilesPerPage(geo:isLandscape:)`), so a *designed* gap — "leave column 4 of row 2
empty" — has no stable meaning; it lands differently on iPad, iPhone and at large
Dynamic Type. Column-relative alignment does not survive. **Order-relative grouping
does**: the words before and after a spacer stay separated on every device. That is
weaker than a fixed grid gives, and it is most of what the technique is for. A
fixed rows × columns page remains unbuilt and is not in scope here — it would trade
away the reflow that makes one scene work on iPad, iPhone and Mac.

One render path, two entry kinds. Both draw an empty cell, both are untappable,
both consume their real estate. They differ only in metadata:

| | coverage report | OBF |
|---|---|---|
| hidden tile | on the board, unavailable | `hidden: true` |
| spacer | not a word at all | `null` in `grid.order` |

The coverage distinction is the point: a hidden word is not an ignored word, and
conflating them makes the report read "the child ignores 40 words" when the
caregiver hid them. `OBFExporter.swift:84` already emits `[String?]`, so the export
side of spacers exists.

Both live on `TileEntry`, inside the `pagesData` JSON blob (`Models/Scene.swift:179–197`)
— **not a synced schema change, and no S6 deadline.** Note the symmetry with the
color work: part of speech is per-*word* (`TileModel`, syncs, one answer
everywhere), hidden and spacer are per-*placement*. The same word can be hidden on
the school board and visible at home — and orange in both places.

### A therapist can change what the colors mean (raised 2026-09-06)

Mark, on CVI: *"it might make sense for a therapist to be able to manage/update
our grammar-type ↔ color mappings."*

**This is clinical, not customisation.** A child with cortical visual impairment
often has one reliably-perceived color — commonly red or yellow — and reduced
discrimination generally. The Modified Fitzgerald palette PR 2 adopted assumes
eight distinguishable hues, and for a CVI child several of them collapse into
each other. A board whose color system the child cannot see is not merely
unhelpful; it teaches nothing while looking like it does.

Adjacent needs the same lever serves: a therapist whose school district
standardises on a different key, a family color-blind in a specific band, and
the Goossens' variants that differ from Fitzgerald on prepositions.

**It is cheap now precisely because of how PR 2 landed.** `TileColorResolver` is
already the single source of truth, every surface routes through it, and the axis
is `PartOfSpeech` — eleven cases. The whole mapping is eleven color values.

#### Scope: per child — and why that differs from the image set

There is a precedent pulling the other way, and it is worth being explicit about
why we are not following it. **The image set is a device setting.** A child can
run Classic Light while her therapist's iPad runs Classic Dark, and nobody set
that per child. Mark, 2026-09-06: that was a balance tradeoff — the choice is
static for a given child and the control is five rows, so a device-level setting
that someone sets once is not worth a synced per-child field.

A color map breaks both halves of that argument:

- **It is not simple.** Eleven mappings, not one of five rows — a data structure
  rather than a pick.
- **It is a property of the child, not the screen.** CVI is a fact about how
  *this* child sees, and it has to be true on every device that child touches.
  The image set is a rendering preference; the color map is clinical.

So: per child, on `ChildProfile`, beside `brownsStageRaw` and `languageRaw` —
which the profile already carries for exactly this class of fact.

#### A color map is a thing you can send

Mark's framing, and it changes the shape: *"ideally a therapist can create and
manage color maps and then cut/paste or text the map to the right patient."*

That makes the map an **artifact**, not a bag of settings — the same move scenes
and vocabulary packs already made, and for the same reason. An SLP works with
many children; a palette tuned for one CVI presentation is worth reusing, and
the person who can build a good one is rarely the person holding the device it
needs to be on.

It is also the smallest shareable thing in the app by a wide margin: eleven
name→color pairs. Small enough that **text is a plausible transport** — a
compact JSON blob that survives a paste into Messages — which is a lighter path
than a file share, and does not need a share sheet, a UTI, or an import screen
to be useful on day one.

Shape: `ChildProfile` stores one synced `String` holding the map as JSON, empty
meaning "the Fitzgerald default". Sparse — only what the therapist changed — so
the default palette stays in code and can be improved later without rewriting
stored data. A name travels with it, so a caregiver can see which map their
child is on.

#### Exports flatten; they do not carry the map

Mark, settling the question: printed sheets and `.obz` files are **one-way
transforms of this screen, to paper or to another app**. They already flatten the
device's current settings — the active image set most obviously — and the color
map is one more of those.

So a printed board and an exported `.obz` use whatever palette is in force when
the export runs, baked in, with no separate mapping travelling alongside. That is
the honest statement for a format that cannot resolve it later anyway: OBF's
`background_color` is a literal color per button, not a reference to a system.

The corollary is worth stating for whoever reads this next: an export made for a
CVI child carries that child's palette permanently, so it is not a neutral
starting point for a different child. The lossless, re-configurable copy is the
`.blasterscene`, exactly as it is for conceal.

#### The deadline

`ChildProfile` is a synced model, so **the field must land before S6 promotion**
or it can never land at all. Same reasoning as `partOfSpeechRaw` in PR 2 and
`languageRaw` / `brownsStageRaw` in S3 3A — and that pattern is now proven end to
end rather than assumed: `CD_partOfSpeechRaw` was confirmed present in the
CloudKit Development schema on 2026-09-05 having never been written a non-empty
value, which is the defaulted-property rule working exactly as `SchemaVersions`
claims.

The field is not optional to ship. Only the editor is.

#### What ships

1. **The field**, empty, before promotion. Non-negotiable.
2. **Resolution** through it in `TileColorResolver`, so a stored override wins
   over the Fitzgerald default. One place — it is already the single source, and
   every surface routes through it.
3. **The editor, in the profile editor.** That is where the child's other
   clinical settings live, and it keeps "this is about this child" legible. A
   list of the eleven types with their current swatch, a reset per type and for
   the whole palette, because a therapist experimenting needs a way back.
4. **Seeded with a sample or two** — Mark: a nice touch, and more than that. A
   therapist should not have to invent a high-contrast palette from first
   principles, and a named preset is how we say we know what this is for. At
   minimum: the Fitzgerald default, and one CVI-oriented high-contrast map.
5. **Send/receive by text**, once the above is real.

#### Open question

Whether a shared **scene** should be able to carry a color map. It belongs to
the child rather than the board, which argues no — but an SLP sending a fully
configured board to a family may well mean the colors too. Decide with Brandi,
alongside the part-of-speech questions already queued for her.

### One caregiver, N children (settles §11)

§11 asked what the seeded profiles should be called and whether `Legacy` and
`Sandbox` both need to exist. Mark's answer, 2026-09-07, is better than a
rename: **neither name survives, because the model is wrong.**

- **One caregiver profile.** The default, bootstrapped one. Undeletable.
- **Up to N child profiles**, added and deleted freely, and eventually
  shareable.
- **No Legacy. No Sandbox.**

#### Most of this already exists under the wrong name

The Sandbox **is** the caregiver profile. `isSystem == true`, a stable *shared*
id (`system.sandbox`, deliberately identical on every device), auto-seeded at
bootstrap, undeletable, and `ChildProfileResolver`'s fallback for "no specific
child". It needs a name and a place in the UI, not a rewrite.

`Legacy` is migration debris. `ProfileMigration` seeds it only when
`wasInstalled` — from prior `UserDefaults` on an upgrade — and `OnboardingView`
already treats the literal string `"Legacy"` as "no name yet". **All devices are
wiped before first use** (2026-08-24, reaffirmed 2026-09-06), so no upgrade path
survives for it to serve. It can be deleted outright rather than renamed, which
also removes the "Legacy" that turned up as the title of the first usage-report
PDF — the observation that opened §11.

#### The work

1. Rename the system profile to **Caregiver** (`kSandboxProfileDefaultName`),
   and take the seeding of `Legacy` out of `ProfileMigration`.
2. Split the Profiles page in two: the caregiver's own profile, then the
   children. One list mixing them is what made "why are there two of these"
   unanswerable.
3. Audit which surfaces show a profile name at all — still the useful half of
   §11, and the reason the report was headed "Legacy".

The caregiver profile is already carrying weight: `colorMapLibrary` (PR 3.6)
lives there, because a saved palette belongs to the person building palettes
rather than to any one child. Expect more of a therapist's world to accumulate
there — Mark: *"a therapist's world of scenes, color schemes, vocabulary packs
should travel with her wherever her iCloud is available."*

#### Profile sharing — a plan entry, not this PR

Sharing a child profile the way scenes and packs are shared is the natural next
step, and it is deliberately **not** scoped here. A shared profile would carry
the color map, the voice, Brown's stage and the tile cap — which is to say it
clones a person's clinical setup, not a preference. That deserves its own
thinking: what a receiving device does with a name, whether the child's *identity*
travels or only their configuration, and whether an SLP handing a family a
profile is doing something meaningfully different from handing them a board.

Worth raising with Brandi alongside the part-of-speech and color-map questions
already queued.

### Carried from S4

All of `docs/s4-cleanup.md` that did not land in S4. §1–§6 are PR 1; §9–§12 are
PRs 4 and 5. §7 and §8 landed in `43ce69b`. Detail stays in that file rather than
being restated here; the two entries that shape a decision:

- **§11 — profile names are visible now.** The usage report's title is
  `ChildProfile.displayName`, so the first PDF built was headed **"Legacy"** — a
  migration label that was internal until a document meant for a therapist started
  printing it. The audit question is broader than a rename: whether `Legacy` and
  `Sandbox` both need to exist, and which surfaces should show a profile name at all.
- **§12 — the new activity screens have not been seen on a phone.** Coverage,
  Patterns and the coverage grid were built on iPad and Mac. The heatmap in
  particular is a `weekday × hour` grid with data-driven columns, and nothing caps
  or scrolls it at compact width. Related to the S3 finding that SwiftUI silently
  *drops* toolbar items rather than collapsing them — expect quiet truncation
  rather than an obvious break.

### Provisioning, not profile sharing (decided 2026-09-07)

Sharing a `ChildProfile` device-to-device was the obvious next move after "one
caregiver, N children". It is the wrong one, and it is worth writing down why,
because the reasoning generalises.

Mark: *"what is the purpose… It's probably all about provisioning a child onto a
fresh device where they are going to need a profile and scene to get started. The
profile for the child is most likely created at device install time when selecting
patient mode. Injecting a profile into the device doesn't do much other than
establish their level and possible color schemes."*

The profile is **already created** on a fresh device, by onboarding, at the moment
patient mode is chosen. So a shared profile arrives after the only thing it could
have created already exists, and carries just two useful fields: Brown's stage and
a colorway. That is a small payload wearing the costume of a big feature.

**What a fresh device actually needs is a board it can talk with.** That is a
scene, the vocabulary behind it, and — for a child who does not see the default
palette — a colorway. The unit worth sharing is therefore a **provisioning
bundle**: one or more scenes, one or more vocab packs, and a color setting,
received as a set.

That is also the shape that scales past one therapist. Mark: *"this feels like the
real path to focus on if we get traction with entities like school districts."* A
district does not hand out profiles; it hands out a standard starting
configuration, and expects twenty devices to come up the same way.

**Not now.** The bundle is a post-launch feature and should be designed against a
real district conversation rather than guessed at. Until then: *"point to point
sharing of scenes, vocab packs, and allowing the therapist to push a color scheme
is enough."*

Two of those three already ship — `.blasterscene` and `.blasterpack`. Which leaves
**two things that can be shared and are not**:

- **A colorway** — a named `TileColorMap`, the therapist's answer for one child's
  vision. **Done, S5 PR 5.** It could previously be built, named and saved to the
  caregiver's library, and reached no other device except through that
  caregiver's own iCloud — which is no help at all, because the therapist will
  never be on the family's iCloud. Same shape as the usage report: the real
  recipient is on the other side of a text message.
- **An encrypted OpenAI API key** — gate 6, already designed. See
  `project_gifted_eval_keys`: the key travels as ciphertext, the passcode by a
  different channel, and neither the raw key nor the passcode is ever committed.
  Sequenced for S6, before the first external TestFlight invite, because that is
  the moment it becomes load-bearing.

**Arrival semantics: applied on receipt.** Built 2026-09-07.

The first draft of this section had it follow the pack rule — land in the
library, be applied by the receiving caregiver. Mark overruled that, and the
reason is who is holding the device: *"I do think it should be activated on
receipt. We should just make sure to save the current settings if they are
modified/not-saved and then blindly apply the colorway."*

The recipient of a colorway is frequently a parent who cannot easily work the
color editor — which is precisely why a therapist is sending them colors. A
confirmation step there is a way for the fix to not arrive. So it applies, with
no prompt and no preview.

**What makes that safe is that nothing is lost.** `ColorwayImporter.apply` files
the colors currently in force into the caregiver's library before overwriting
them, so "put it back how it was" is one tap in the profile editor. Two details
that are load-bearing rather than incidental:

- **"Unsaved" is decided by content, not by name.** A caregiver who started from
  a preset and tweaked two colors holds a map whose name still matches a library
  entry while its contents no longer do. Matching on name would call that saved
  and destroy it.
- **An incoming name collision suffixes rather than replaces.** `ColorMapLibrary.store`
  replaces by name, so a received set called "Warm" would otherwise silently
  overwrite the caregiver's own "Warm". An identical map under the same name is
  not a collision — it is the same thing arriving twice.

A colorway that overrides nothing is refused outright: applying it would reset
the child to the defaults, which is destructive wearing the costume of an import.

Format: `.blastercolors`, `application/vnd.claudeblast.colorway+json`, registered
in all three of the places `BlasterFileFormat` warns about.

**Whatever ships must be registered in three places.** `BlasterFileFormat` carries
the standing warning: `CFBundleDocumentTypes`, the `onOpenURL` guard, and the
`fileImporter` content types all have to agree. When the pack format was added the
guard was missed, and a file then arrived, launched the app, and vanished — no
sheet, no error, nothing to explain it.

### The order of the pitch (decided 2026-09-07)

Beta-review notes were a line item inside PR 6 until Mark pulled them out, and
the reason is not that they are long. They are the same document as the site and
the deck, and all three currently lead with the wrong thing.

Mark: *"I think a lot of our deck/site over-rotates on sentence generation mode
for the child. While this is one of our more compelling features from a tech
standpoint, from a more conservative SLP perspective I'm sure it's going to be a
much longer sell."*

That is the whole risk in one sentence. Sentence generation is the most
technically interesting thing here and the least safe thing to open with. An SLP
evaluating AAC has professional reasons to distrust software that puts words in a
child's mouth, and a first impression that leads with it invites a decision
before anything else has been seen. **The feature is not the problem; its
position in the argument is.**

**The order a first look should arrive in:**

1. **Modern AAC that does what an SLP expects.** Boards, pages, motor-planned
   positions, Fitzgerald colors, print, OBF/OBZ. Nothing to grant, nothing to
   configure, no account.
2. **Cross-device and in sync.** The therapist's boards on her iPad, the family's
   on theirs, the same child's history in both.
3. **Data an SLP can act on.** Coverage, patterns, the shareable usage report —
   which words are reached, which sit untouched, when the board gets used and
   whether the range is widening.

   High in the order on purpose. This is not a supporting feature, it is a
   *reason to adopt* for the exact audience most likely to be sceptical of items
   4 and 5, and it is the only part of the pitch that hands a therapist something
   for a session note. It also arrives before any mention of AI, which matters:
   it is all computed locally from what the child actually pressed, with no key
   and no model involved.
4. **Substantial AI for the caregiver**, once a key is installed — scene and page
   generation, art for any word they can name, moderation. Note who is holding
   the device: the adult.
5. **Sentence generation as an advanced mode**, one switch on, one switch off.

**Cost transparency is what makes 4 and 5 safe to consider**, and it belongs
beside them rather than in a footnote. Mark: *"we did a great job on usage
trends, usage costs, etc. I think this transparency needs to find its way into
the deck."*

BYOK plus a per-month cost readout plus a usage log is a specific answer to the
specific fear — that this is a meter running against a family or a district with
no way to see it. The honest version is strong on its own: the key is theirs, the
spend is theirs, the app shows what it spent and on what, and turning the feature
off stops it. Very few AI products in this space can say all four.

**Two distinct transparencies, and they answer different objections.** The
clinical one (item 3) answers *"does this give me anything I can use?"* The cost
one answers *"what is this going to run me, and can I see it?"* Collapsing them
into one "transparency" slide loses both.

Mark: *"our deck/site needs to introduce these advanced concepts BUT it can not
cause people to dismiss it outright."*

**This is not only a marketing problem.** The app's own onboarding leads the same
way: the first screen reads *"A voice for non-verbal children. Pick tiles, hear
sentences"*, and the third card on it is *"Bring your own AI key"* — so the first
forty words a new user reads put sentence generation and an API key ahead of the
board. A reviewer, a therapist and a parent all meet that screen before anything
else. Onboarding copy therefore belongs in this PR, not in the claims refresh.

**The site predates most of the product.** Mark: *"these are just capabilities we
build after the site, so we need to address with some updates."* This is not only
a reordering job — audited 2026-09-07 against `~/src/blasterai-site`:

- The site's `h1` is **"Tiles in. A real sentence out."** The deck's solution
  slide is **"For the child: tap tiles → speak in full sentences"**, and its AI
  section runs *1 · Sentences, 2 · Images, 3 · Boards & vocabulary* — sentence
  generation is literally item one of three, on both surfaces.
- Mentioned **nowhere** across `index`, `deck`, `faq`, `about`: coverage,
  patterns, the usage report, OBF/OBZ, vocabulary packs, Fitzgerald colors,
  colorways, Brown's Stages, conceal/reveal. `print` and `Mac` appear once each.

So the two things Mark now wants leading the pitch — data an SLP can act on, and
visible cost — are the two the site never mentions, while the thing to move down
the order is the headline of both surfaces. Everything shipped in S3–S5 is
missing: Brown's Stages, Mac support, the share surface, PDF boards, OBF/OBZ,
tile-image export, the usage report, coverage, patterns, sparse boards, page
rename, letters and numbers, the Fitzgerald palette and therapist colorways.

**Scope.** Review notes, site, deck, onboarding copy, and recutting whatever
video no longer matches the order. The site is a separate repo
(`~/src/blasterai-site`, direct-to-main, no PRs), so this PR carries the app-side
copy and the notes; the site lands alongside it.

**Sequencing.** Before PR 7. The claims refresh checks that what we say is true;
this decides what we say first, and there is no point auditing sentences that are
about to be reordered.

### Tester-readiness code work

- **`AdminGate` hardening** — enroll the PIN at enable-time rather than at the gate,
  auto-unlock on correct PIN (Mark's request), attempt throttling. On Mac, biometrics may
  be absent entirely, so the PIN path must be complete and obvious. (S3 proves it works on
  Mac; S5 makes it good.)
- **PIN recovery** — "reinstall the app" is not acceptable for a family whose child's
  voice lives in the app. Minimum viable: recovery via a known-good path that does not
  destroy data.
- **Keyless is a product mode, not a fallback.** Mark, 2026-09-07: *"we simply run in
  stock AAC single-word mode. I suspect that many/most child devices will run without a
  key, in this mode, until their caregivers and families are comfortable with sentence
  generation."*

  That reframes this gate. The old wording — "verify the app is usable with no key" — was
  defensive, as though keyless were a review workaround to survive. It is the majority
  configuration on a child's device, and the AI is something a family grows into. An App
  Review reviewer succeeds by exactly the road a real keyless family takes, which is the
  right shape for the same reason it is right for them.

  Mark's analogy from Tibls: a recipe app is useless without recipes, and the answer was
  not to explain that to the reviewer — it was to bootstrap the empty store and offer
  three paths to succeed. Ours are already built:

  1. **Bundled starter scenes** — a working board on first launch, before anything is
     configured.
  2. **Vocabulary packs** — Farm, Tide Pools, Dinosaurs, Mealtime, Vehicles, Space,
     Letters, Numbers. Build a themed board without a key.
  3. **The editor** — arrange, conceal, reveal, rename, print, share.

  Plus speech, the activity log, coverage, and PDF / OBZ export. All keyless.

  A key buys four things and nothing else: sentence generation, AI scene and page
  generation, word moderation, and art for newly added words.

  **Verified on device, 2026-09-07.** The add-word path holds keyless. From the page
  editor: ＋Tiles → search finds nothing → pick a type → Add. The new words land on the
  page as placeholders, and from there either fix them one at a time (AI or existing
  media) or leave the page editor, where the scene editor offers to do all the art at
  once — or, without a key, says that it could. Both halves work; the keyless one simply
  stops before the art.

  **Where we differ from other AAC platforms, and it is not a deficit.** They ship a fixed
  symbol library to pick from when adding a word. So do we — ours is generated, which
  means it has no edges. Their library ends; ours does not. The honest trade is that
  theirs is instant and free where ours costs a key, a few seconds and a fraction of a
  cent.

  State it that way in the S5 claims refresh and any store copy. "Unlimited symbols" reads
  as marketing; "their library ends, ours doesn't" is just true, and it is the more useful
  sentence for a therapist who has hit the end of one.

  **Backlog, not a gate:** the tile picker is built for *finding* an existing word, so
  adding a new one is the fallthrough — search, fail, choose a class, Add. Mark: *"it has
  room for improvement but it works."* Recorded in `docs/architecture-backlog.md`.

  Beta-review notes say all of the above plainly. Round 1 stays **internal testers only**,
  with no beta review at all.

### App Store Connect

- App record under **Education** — decided 2026-08-09, never Kids. The Kids Category
  forbids leaving the app without a parental gate, which would break the in-flow "Get a
  key" link to platform.openai.com that BYOK onboarding depends on. The framing is also
  simply accurate: the person who installs, configures, supplies a key, authors scenes,
  and reviews logs is an adult caregiver. The child is the *subject* of the app, not its
  purchaser.
- App icon audited for iOS 26 **and** Mac (Designed for iPad) requirements.
- Privacy nutrition labels — should be "Data Not Collected"; verify against the shipped
  `PrivacyInfo.xcprivacy`.
- Beta test information, internal tester group.

### Launch assets

Screenshots on iPad, iPhone, **and Mac**. Description and keywords. Tester instructions,
including the Mac path and what to do without an OpenAI key.

### Claims refresh

Re-run the `docs/claims-audit-2026-07-20.md` discipline over everything S2–S4 changed: the
cost numbers, the bundle size, and the new print/interop claims. Site and deck copy staged
in `~/src/blasterai-site` (direct-to-main, no PRs) but **not published** until the
screenshots come from the shipped build.

`NOTICE` is part of this and moves earlier, into PR 1: it still says most tile images are
ARASAAC pictograms under CC BY-NC-SA 4.0 and that commercial distribution "requires
replacement with commercially-licensed imagery". None of that is true — all 2,743 shipped
images across the five sets are OpenAI-generated. It is a standing claim that the app
cannot be shipped as-is, in the file a reviewer or contributor reads first. Mark's intent,
confirmed 2026-09-02: **repo and app images are Apache-2.0 with no additional constraints.**

### Exit criteria

The App Store Connect record is complete, and a build could be uploaded into it today.

---

## Session 6 — `cb-build-one`

**Identity:** build 1 exists, in testers' hands, and the path that produced it is a script
someone else could run.

### Gifted evaluator keys — before the first external invite

Mark, 2026-09-07: *"the instant I send an invite to an external tester I will want to have
already built the key sharing and update code."* That is the deadline — not a date, an
event. Internal round 1 does not need it; the first external invite does, and it must
exist before that invite goes out rather than in response to it.

Design is already agreed in full: [[project_gifted_eval_keys]]. A sealed package texted to
the evaluator, a passcode delivered out of band, PBKDF2-HMAC-SHA256 (reuse `PINAuth`, do
not add a second KDF) into AES-GCM — authenticated, so tampering fails decryption and
provenance comes free with no signing keypair. Expiry, evaluator name and key sealed
inside. A `tools/` script that mints uniformly and writes a **ledger row**, because the
question months later is "key `sk-…7f2a` is burning money — whose is it?", and metadata in
git with secrets in the Keychain, never the reverse. Lost passcode means reissue, never
recover.

**No schema deadline.** Keys live in the Keychain and a document format; nothing synced,
nothing that promotion freezes. That is why this sits in S6 rather than S5.

**Why it is worth building for ~25 people.** Not scale — the opposite. These are chosen
deliberately for influence, so a bad first five minutes is at its most expensive.
Eliminating friction matters *more* when the audience is small and hand-picked, not less.
Pasting a 50-character key on an iPhone is the most likely reason such an evaluator stops
before seeing the app.

**Prerequisite, owned by Mark, before this is designed further:** check whether OpenAI
projects support **per-project budget caps**. Do not assert current OpenAI capabilities
from memory — check the dashboard. If they do, most of the security conversation collapses
into configuration: one project per evaluator, key scoped to it, delete the project and the
key dies, raise the cap to refill, spend cannot exceed the cap whatever the key does, and
usage is attributed per project already. A leaked key drains its own cap and stops, which
is the difference between 25 outstanding keys being something to sleep through or
something to monitor.

Either way the app is unaffected: the package carries "a key, an expiry, a label". Whether
that key is project-scoped with a cap or a raw account key is OpenAI-side and changeable
without touching the format or shipping a build.

### CloudKit promotion — first, before anything else

Re-run Phases 1–3 of `docs/cloudkit-promotion-runbook.md` (the dev environment will have
been reset again), then Phases 4 and 5. **This gates build 1**: TestFlight runs against
Production CloudKit, so no build ships before it.

Do it at the *start* of the session, not the end. A Production sync problem found after
testers have data is far more expensive than one found now — and Appendix A of
`docs/plan-2026-08-06.md` describes the Ad Hoc export loop that verifies Production in
minutes rather than an App Store Connect round trip.

Before promoting, confirm gate 8: `languageRaw` and `brownsStageRaw` are on
`ChildProfile` in the shipped models.

### Script the release

Version and build-number bump, archive, export, upload, changelog, tester notes — as a
checked-in script plus a runbook, not a sequence of Xcode clicks. This is the difference
between "we shipped build 1" and "we can ship build 7." Per `feedback_tool_lifetime`: it
lives in git, versions are pinned, and the runbook documents the whole loop *including*
the manual steps that can't be scripted.

### Build 1

Archive, upload, install from TestFlight on iPad, iPhone, and Mac. Confirm three-way
Production CloudKit sync between them.

### Exit criteria

Build 1 in internal testers' hands, syncing across three form factors, with a caregiver
who is not Mark able to complete setup unaided — and a second build producible by running
the script.

---

## After the pilot build

Site and deck work, both in `~/src/blasterai-site`: the "Tips for Caregivers" walkthrough
series and the word-moderation technique writeup. Both want screenshots from the shipped
build, so they follow S6 rather than precede it.

Post-pilot and explicitly **not** in the first pilot (confirm with Mark before pulling any
of these forward): prosody escalation, promoted-tile promotion, session mode, OBF
*import*, localization beyond the inert `languageRaw` field, VoiceOver / Switch Control.

---

## Open questions, to settle at the top of the session that owns each

- **S3 / 3E** — stage ↔ `maxSelectedTiles` binding direction. The proposal is
  stage-is-source-of-truth *and* raising the cap past 4 promotes to IV+. Confirm before
  implementing; it is ugly to unpick later.
- **S3 / 3E** — does the caregiver UI keep showing age at all?
  `AdminView+ProfilesTab.swift:87` currently prints "Age N · grade N". Does age disappear
  from the caregiver's view entirely once the stage selector exists?
- ~~**S4 / 4B** — print resolution policy.~~ **Settled 2026-08-31:** accept the ~3"
  ceiling at 512 px, no print-quality path.
- ~~**S4 / 4B** — does the single-core-board preset auto-select its words?~~ **Struck
  2026-08-31:** the preset is gone; a board page is the single board.
- **S4 / 4E** — how much of the child's speech goes in the readable report: most-used
  words only, or full utterance history? The SLP wants more; the privacy default wants
  less. **Deferred pending Brandi.**
- **S5** — internal-testers-only for round 1 is a recommendation, not yet a decision.

---

## Related

- `docs/plan-2026-08-06.md` — sessions 1 and 2, and **Appendices A–D**, which remain the
  live references for CloudKit Production testing, the permanent schema rules, and the
  Mac test plan.
- `docs/cloudkit-promotion-runbook.md` — the promotion ceremony, with the session-1
  deferral note.
- `docs/localization-impact.md` — §8 (PDF / paper board export) and §10 (Brown's Stages)
  are the source material for 4B and 3E.
- `docs/schema-audit-2026-08-06.md` — the field inventory the synced schema must match.
- `docs/claims-audit-2026-07-20.md` — the discipline S5's claims refresh re-runs.
- `docs/collaborator-workflow.md` — the collaborator-facing version of the git workflow.
