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

---

*Add new cross-cutting items here as stubs; promote to a dedicated note + worktree
when scheduled.*
