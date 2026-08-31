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

**Status (2026-08-31): design deferred pending Mark's conversation with Brandi.** Not
blocking — 4A and 4A′ are the substrate and do not depend on this payload's shape. The
question held open for her is how much of the child's speech the readable report carries.

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

### Tester-readiness code work

- **`AdminGate` hardening** — enroll the PIN at enable-time rather than at the gate,
  auto-unlock on correct PIN (Mark's request), attempt throttling. On Mac, biometrics may
  be absent entirely, so the PIN path must be complete and obvious. (S3 proves it works on
  Mac; S5 makes it good.)
- **PIN recovery** — "reinstall the app" is not acceptable for a family whose child's
  voice lives in the app. Minimum viable: recovery via a known-good path that does not
  destroy data.
- **Reviewer / no-key path** — verify the app is genuinely usable with **no** OpenAI key
  (single-word mode + mock provider), and write beta-review notes that say so. This is the
  single most likely rejection cause: if the app looks broken without a key, that is a
  rejection regardless of how good it is with one. Recommendation stands that round 1 is
  **internal testers only**, with no beta review at all.

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

### Exit criteria

The App Store Connect record is complete, and a build could be uploaded into it today.

---

## Session 6 — `cb-build-one`

**Identity:** build 1 exists, in testers' hands, and the path that produced it is a script
someone else could run.

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
