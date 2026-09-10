<!-- SPDX-License-Identifier: Apache-2.0 -->
# Architecture backlog

Cross-cutting design work to schedule. Each is a stub to expand into its own note
+ worktree when picked up. See also [scene-identity.md](scene-identity.md).

---

## 1. CloudKit: dev sandbox → production schema  ⚠️ highest risk

> **Update 2026-07-15:** the two-device sniff test surfaced the multi-device
> **duplication** bug (local seed-once flag → double bootstrap → duplicates of every
> logical key → crash + silent wrong-active-record corruption). Root cause + a
> deterministic dedup reconciler are now **implemented** (builds clean, pending the
> on-device two-device test) — see [cloudkit-dedup.md](cloudkit-dedup.md). That fix is a
> **prerequisite** for the Production promotion and for enabling iCloud by default.

**Why it's scary:** CloudKit has separate **Development** and **Production**
environments. We build against Development, where the schema is auto-created from
the SwiftData model. Shipping requires **promoting the schema to Production** in
the CloudKit Dashboard — and once in Production, schema changes are
**additive-only, effectively forever**:

- ❌ cannot delete or rename record types or fields
- ❌ cannot change a field's type
- ❌ cannot add uniqueness (we already avoid `@Attribute(.unique)` — CloudKit-incompat)
- ✅ can add new record types, new fields, new indexes

**Implications / to-do before first Production deploy:**
- **Freeze the model as much as possible first.** Every current model
  (`ChildProfile`, `BlasterScene`, `SentenceCache`, `LoggedUtterance`,
  `MetricEvent`, `RecordedScript`, …) should be reviewed as if its field names and
  types are permanent. Land the [scene-identity](scene-identity.md) `id`/`version`
  fields *before* Production, not after.
- **All properties optional or defaulted; relationships have inverses.** Verify the
  whole model still satisfies SwiftData+CloudKit constraints.
- **Indexes/queryable fields** must be enabled per-field in the Dashboard for any
  field we query in Production — they don't come for free from Development.
- **Test against Production with a real iCloud account** before launch; the sandbox
  masks issues (esp. around first-sync, account state, and quota).
- **Migration story is code-side + additive.** New app versions must keep reading
  old records. No destructive migrations.
- **Reset semantics stay as designed:** reset = local wipe, **preserve** cloud
  (never per-object delete in reset); per-word delete is the explicit cloud-delete
  path; DEBUG defaults iCloud OFF. (Already the intended behavior — re-verify.)
- **Schema-split container** (DeviceProfile in a `cloudKitDatabase: .none`
  "DeviceLocal" config; everything else flips local↔CloudKit per `icloud_enabled`)
  must be exercised in both states against Production.

**Deliverable when picked up:** a pre-flight checklist + a Production dry-run on a
throwaway iCloud account, gating the App Store submission.

---

## 2. Sentence-cache lifetime & invalidation

Today `SentenceCache` is keyed by the order-independent sorted tile combo, with a
`hitCount`, and no expiry. Open questions:

- **TTL / staleness:** should entries expire? A cached sentence can go stale when
  the prompt, model, child age, or a tile's `displayName` changes.
- **Invalidation triggers:** bump/clear the cache on prompt-template change, model
  change, or per-child profile edits (age → grammar level).
- **Bounds:** size cap + eviction policy (LRU by `hitCount`/recency) so it can't
  grow unbounded, especially once it syncs via CloudKit.
- **Scope:** already `+childID`-keyed; confirm that's the right granularity.
- **Interaction with escalation:** repetition escalation must not be short-circuited
  by a cache hit (verify the cache key / escalation path don't collide).

---

## 3. Sentence generation — refinement & flagging

Give caregivers a feedback loop on generated sentences (they're the audience for the
text):

- **Flag** a sentence as wrong / awkward / inappropriate, inline from the tray.
- **Refine:** regenerate with a nudge, or hand-edit and pin an override for that
  tile combo (writes to cache as a caregiver-authored result).
- **Close the loop with the eval harness:** flagged cases become fixtures /
  regression cases; recurring flags inform prompt tuning. (Ties into the existing
  Tier-1/Tier-2 eval harness.)
- **Safety:** flagging is also the report path for anything that trips the content
  rails in practice.

---

## 4. Custom date ranges in the activity reports — **post-launch**

**Raised:** 2026-09-04, building Coverage and Patterns. Deferred deliberately;
launch ships the three fixed windows.

Activity, Coverage and Patterns all read one `ActivityLogView.Window` — **Today /
Past Week / All Time** — persisted in `activity_range` and shared across the three
screens so they never disagree about the period being described.

That is enough to launch and not enough for the reader these screens are
ultimately for. CoughDrop offers an arbitrary range plus a *compare to…* control,
and the reason is the SLP's actual working unit: a **term**, a **six-week block**,
the stretch **since the last review**. "Past week" cannot express any of them, and
"All Time" dilutes the recent past into a year of history.

**What exists already, and what does not.** The reporting layer is range-native —
`PatternsReport.make(inWindow:allTime:from:to:)` takes explicit bounds, and its
comparison already computes the *preceding window of equal length* from them. So
the arithmetic is done. What is missing is only the way to say which dates, and
the plumbing to carry a pair instead of an enum case.

**Sketch when picked up:**

- `Window` grows a `.custom(from:to:)` case, or is replaced by a `DateInterval`
  with the three presets as constructors. The latter is cleaner and touches every
  call site once.
- The persisted `activity_range` becomes two dates rather than a raw string.
  Non-trivial in one respect: an absolute range **ages**. A caregiver who picks
  "1 Sep – 15 Sep" and returns in November sees a report about September, which is
  correct and will read as a bug. Presets are relative and never stale, so the
  UI has to distinguish "the last six weeks" from "these six weeks".
- The comparison window is already implied by the range's length, so *compare to
  the period before* comes free — it is the same code path Patterns uses today.
- Coverage's all-time halves (`usageByKind`, `usageByPage`, never-used) stay
  all-time regardless. They answer "has this word ever been reached", which a
  date range must not narrow, or an untouched page starts looking used because
  the window excluded the day it was used.

**Why not now:** it is a control and a persistence change across three screens,
for a reader we have not yet put the screens in front of. Brandi's feedback on
the reports should shape whether the range picker is a term selector, a
free-form pair of dates, or a "since last review" marker — and those are
different designs, not different defaults.

## Adding a word is the tile picker's fallthrough path

Raised 2026-09-07, while verifying that the keyless path holds (it does — see
`docs/final-countdown-plan.md` gate 6).

`TilePickerView` is built for **finding an existing word**: search, filter by
class or pack, multi-select, add. Creating a word that does not exist yet is
reached by failing at that — type a word, get no results, choose a word class,
tap Add. It works, and Mark's read is that it "has room for improvement but it
works", so this is not a gate.

What makes it worth revisiting: creating a word is not a rarer act than finding
one, it is the act a caregiver performs when the board does not yet fit their
child — which is exactly when they are most invested and least tolerant of
friction. The flow currently treats it as the error branch of search.

Related, and the reason this is not urgent: **our symbol library is generated,
so it has no edges.** Other AAC platforms ship a fixed set to pick from at this
moment; a caregiver there eventually hits its end. A caregiver here does not.
The trade is that theirs is instant and free where ours costs a key, a few
seconds and a fraction of a cent — and keyless, the word still arrives, just as
a placeholder until art is generated later. Worth saying plainly in store and
site copy, where "unlimited symbols" reads as marketing but "their library ends,
ours doesn't" is simply true.

---

## A new word can only ever get the style you were standing on

**Found 2026-09-08 on device** (iPad, `Core-First - My Copy`). Added `unicorn` and
`princess` from the page editor. Both came out with Classic Light, Medium and Dark
and nothing else — no Playful 3D, no High Contrast — and the scene editor then
offered no way to finish them. The per-tile Tile Settings sheet was the only
surface that could, one word at a time.

**Two defects that compound.**

1. **`generateAllStyles` defaults to `false`**, and the scene banner that carries
   the toggle (`SceneEditorView.swift`) is also the only place it is offered
   during a batch. `ArtPlan.plan(activeSet:allStyles: false)` then covers the
   active set's style and its variants up to the active one — Classic Light,
   Medium, Dark — which is correct for what it was asked, and not what the
   caregiver expected.

2. **The catch-up path is scoped to the active style, so it can never recover.**
   The scene editor has exactly two batch offers and a word like this falls
   through both:

   - `tilesNeedingArt` (`SceneImageBatch.swift`) is *nothing resolves*. The word
     has Classic art, so it resolves, so the section — and the toggle inside it —
     disappears the moment the first run finishes.
   - `tilesMissingVariants` reads `activeStyle` only (`SceneEditorView.swift`,
     *"a style they don't use isn't a gap they can see"*). Classic is complete, so
     it is empty. Playful 3D and High Contrast are separate `TileStyle`s, not
     variants of Classic, and **no scene-level surface asks about a style other
     than the active one.**

   The comment defending (2) is right about the common case and wrong about this
   one: the caregiver *does* see the gap — Tile Settings renders a dashed empty
   slot per missing style — they just cannot act on it in bulk.

**Shape of the fix.** A third offer beside the other two: words with art in the
active style but missing from other generatable styles → "Complete Playful 3D for
N words", or one row naming the count across styles. Reuse
`SceneImageBatch.tilesMissingVariants` with the style passed in rather than read
from the resolver. Separately, decide whether that scene toggle should default on
— cost is the argument against, and the cost readout is now good enough to make
the honest version affordable.

Not a launch gate: keyless boards never hit it, and a single-style family never
notices. It bites exactly the person evaluating us — someone trying all five sets.

---

## Tile-image export shares the naked picture, not the tile

**Raised 2026-09-09, while reviewing the Fitzgerald card treatment.**
`TileImageExporter` writes the artwork alone. That is right for re-importing into
another AAC app, which wants a symbol and applies its own card, and it is what the
"pick a page or a scene and ask for the images" pitch currently delivers.

It is the wrong thing for the other half of who asks. A therapist building a
worksheet, a teacher assembling training materials, a parent making a fridge
strip: they want the tile as the child sees it — the Fitzgerald card, the white
plate, the word on its colored band — because the *color* is the part that
teaches, and a bare picture has thrown it away.

So the export needs a choice, not a change: **picture only** (today's behaviour,
still the default for OBF-adjacent uses) or **finished tile**, rendered at export
size. `BoardPDFRenderer` already draws a finished tile for print, so the shape of
the renderer exists; what does not exist is a single tile-card renderer both it
and the exporter share, which is the actual work — the print card and the screen
card are separately implemented today and have already drifted (print puts the
label on top, the screen puts it underneath).

Mark's call on that drift, same day: **leave it.** The two looks differing is not
worth a refactor until someone asks. This note exists so that when someone does,
the fix is known to be "one shared tile-card renderer" rather than a third
implementation.

Related: [[project_installable_image_sets]] — a set that travels needs its style
prompt and subject overrides, and a finished-tile export is the same question
asked about pixels instead of prompts.

---

*Add new cross-cutting items here as stubs; promote to a dedicated note + worktree
when scheduled.*
