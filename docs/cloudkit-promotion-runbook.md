# CloudKit Production Promotion — Runbook

**Container:** `iCloud.app.blasterai` · **Session:** 1C/1D of `docs/plan-2026-08-06.md`
**Schema audit:** `docs/schema-audit-2026-08-06.md` · **Written:** 2026-08-09

Run this once, from a `main` build, with a clean install. It is the irreversible step of the
whole TestFlight plan: **once a schema is deployed to Production you can add fields and
record types forever, but you can never delete one, change its type, or change its on-disk
name.**

Work top to bottom. Phase 3 is the point of no return — everything before it is repeatable
at no cost.

---

## Phase 0 — Preconditions and the one check that can abort this

**0.1 — Code.** Local `main` at `914faa2` (PR #50) or later. Confirm:

```
git -C ~/src/blasterai log --oneline -1
ls ~/src/blasterai/claudeBlast/Models/SchemaVersions.swift
```

**0.2 — Confirm Production is empty. ⚠️ THIS IS THE ABORT CHECK.**

CloudKit Console → `iCloud.app.blasterai` → switch the environment selector to
**Production** → browse record types.

- **Expected: a single `Users` record type, and no `CD_*` types.** `Users` is
  CloudKit's own system record type — every container has one in both
  environments, it is created for you, and it cannot be deleted. Confirm its
  **Record Fields** list is empty (the seven entries under **Metadata** are
  CloudKit's bookkeeping). Only `CD_*` types are ours; if there are none, nothing
  has ever been deployed.
- **If Production already has a schema:** STOP. Do not continue. A deployed Production
  schema cannot be removed or reset, so the whole "clean slate" premise is gone and the
  plan needs rethinking — we'd be deciding what to live with rather than what to ship.
  Bring this back before doing anything else.

**0.3 — Record the "before" state.** With the environment selector on **Development**,
list the current record types and note anything you expect to disappear — `CD_MetricEvent`
should be there now, and `CD_SentenceCache` should still show an `audioData` field. These
are what prove the reset worked in Phase 2.

**0.4 — Devices.** Know which devices have the app. Every one of them must be on the
post-reset build before it syncs (see the sequencing rule at the bottom). Simplest path:
delete the app from all devices now, reinstall only after Phase 1.

---

## Phase 1 — Reset the Development environment

CloudKit Console → `iCloud.app.blasterai` → **Development** environment → the environment
settings area → **Reset Development Environment**. It will ask you to confirm by typing the
container identifier.

What this does:

- Wipes the Development **schema** — including every field that ever existed during
  development, which is the entire point.
- Wipes Development **data**.
- Copies the Production schema down. Production is empty (verified in 0.2), so you land on
  a genuine clean slate.

This is *not* the same operation as the app's own reset, which is a local wipe that
preserves cloud data (`project_cloudkit_wipe_semantics`). This one is deliberate,
destructive, and acceptable only because we are pre-pilot and dev data is disposable.
**Do not run it again once testers have data.**

---

## Phase 2 — Regenerate a clean schema, then verify it is complete

**2.1 — Clean install.** Delete the app from the device first (this also clears the local
SwiftData store, so there is no old-schema residue). Build and run `main` from
`~/src/blasterai`.

**2.2 — Turn iCloud on.** DEBUG builds default iCloud **off** (`claudeBlastApp.swift:51`;
RELEASE defaults on). So: Admin → Device → **iCloud Sync** on → **relaunch the app**. The
toggle's own hint says it takes effect on next launch, and it means it — the container is
built once at startup.

**2.3 — Exercise every synced record type. ⚠️ Do not skip this.**

A record type only exists in the schema once a record of that type has actually been
saved. Anything you don't exercise here won't be in the schema you promote — and in
**Production the schema is read-only**, so the app cannot create the missing type later.
The failure mode is saves silently failing for real users on a type nobody exercised.

> **Fields used to have this problem too, and no longer do.** CloudKit stores no
> nulls, so a nil optional was never written and its field never materialized —
> `TileModel.retiredReason` was missing from the schema purely because nothing had
> been auto-hidden yet. Since no synced model has optional stored properties any
> more (the rule lives on `BlasterSchemaV1`), every field is written on every save
> and materializes with its record type. **You need one record per type; you no
> longer need to hit every field.** If a future change reintroduces an optional,
> this hazard comes back with it.

Seven synced types. Bootstrap gives you three for free; the other four need deliberate
action:

| Record type | How to materialize it |
|---|---|
| `CD_TileModel` | ✅ automatic — bootstrap seeds 492 tiles |
| `CD_BlasterScene` | ✅ automatic — bootstrap creates the default scenes |
| `CD_ChildProfile` | ✅ automatic — `ProfileMigration` seeds the Sandbox profile |
| `CD_SentenceCache` | Tap tiles and let a sentence generate (needs an API key) |
| `CD_LoggedUtterance` | Same action — a finalized utterance is logged alongside the cache entry |
| `CD_TileArtVariant` | Add a custom word and generate art for it, **or** import a pack that carries art |
| `CD_RecordedScript` | Record a short TileScript (Admin → Now → Record, tap a couple of tiles, Stop, save) |

Give sync a minute, then confirm all seven appear in the Console under Development.

**Two types must NOT appear**, because they are device-local by design (D3):
`CD_MetricEvent` and `CD_DeviceProfile`. If either shows up, the build is not the merged
one — stop and investigate.

---

## Phase 3 — Review the schema. Last look before permanence.

Development environment → walk the record types. This is the whole payoff of the audit;
take the extra ten minutes.

**Absences to confirm** (these are the removals — if any is still present, the reset did
not take, and you should return to Phase 1 rather than promote):

- `CD_SentenceCache` — **no `audioData`**
- `CD_TileModel` — **no `type`**
- `CD_TileArtVariant` — **no `created`**
- `CD_RecordedScript` — **no `sceneName`**
- **No `CD_MetricEvent` record type at all**
- **No `CD_DeviceProfile` record type at all**

**Presences to confirm** (these are the additions and renames):

- `CD_TileArtVariant` — has **`modified`** (and `tileKey`, `imageSetRaw`, `imageData` as a
  CKAsset via `.externalStorage`)
- `CD_RecordedScript` — has **`sceneRef`** (it holds a scene *identifier*, not a name)
- `CD_LoggedUtterance` — has **both `sceneID` and `sceneName`**
- `CD_TileModel` — has `isSystem`, `isRetired`, **`retiredReason`**, `needsReview`
- `CD_SentenceCache` — has `stableKey`, `keyVersion`, `isCaregiverEdited`, `isSuppressed`,
  `caregiverAccepted`, `isPinned`, `created`, `lastUsed`, `childID`

**General sanity:** exactly seven `CD_*` record types, plus `Users`. Every field nullable.
No unique constraints.

**Field-count cross-check.** Every `CD_*` type carries **one more record field than its
model has stored properties** — the extra is `CD_entityName`, which the Core Data ↔ CloudKit
mirroring layer stamps on every record so it can map a `CKRecord` back to the right entity.
Computed properties never appear (`isOverride`, `isHiddenFromChild`, `pages`, `age`,
`interactionMode`, …), and `*Raw` fields are the real storage behind the typed accessors.
Adding six metadata fields, the totals should be:

| Record type | Total fields | = 6 metadata + model props + entityName |
|---|---|---|
| `CD_TileModel` | 19 | 12 props |
| `CD_SentenceCache` | 21 | 14 props |
| `CD_BlasterScene` | 27 | 20 props (`pagesData`, not `pages`) |
| `CD_ChildProfile` | 21 | 14 props |
| `CD_LoggedUtterance` | 15 | 8 props |
| `CD_RecordedScript` | 13 | 6 props |
| `CD_TileArtVariant` | 11 | 4 props |

A count that is one short is the signature of a field that never materialized.

---

## Phase 4 — Deploy to Production

> **⏸️ DEFERRED as of 2026-08-11 (Mark's call).** Phases 0–3 have been run and pass;
> promotion is held until immediately before the first TestFlight build (session 4 of
> `docs/plan-2026-08-06.md`).
>
> This is a decision, not a delay. TestFlight runs against Production CloudKit, so
> promotion is a hard prerequisite for build 1 — but it is required *no earlier* than
> that, and every day it stays deferred is another day the schema is freely mutable.
> Running Phases 0–3 already earned that: it surfaced `retiredReason` missing from the
> schema (which forced the no-optionals rule), `RecordedScript.sceneName` holding an
> identifier, and — through two-device testing — a sync bug that was destroying caregiver
> scene edits. Promoting on the first pass would have frozen the first two permanently.
>
> Re-run Phases 1–3 before Phase 4, since the dev environment will have been reset
> again by then.

CloudKit Console → Development → **Deploy Schema to Production**. Review the diff summary
it shows you, then confirm.

**This is irreversible.** From here the synced schema is additive-only forever.

---

## Phase 5 — Verify against Production

A build must be signed for distribution to reach the Production environment — running from
Xcode always uses Development, with no in-app switch.

**Fast loop (preferred):** Archive with the Release configuration → Distribute → **Ad Hoc**
→ install via Xcode's Devices & Simulators window or Apple Configurator. Minutes, no App
Store Connect round trip.

**Or:** upload to TestFlight and install from there. Slower, but it's the loop you'll live
in later anyway.

Then:

1. Install on device A, complete onboarding, confirm iCloud is on.
2. Create something distinctive — a scene with an obvious name.
3. Install on device B. Confirm the scene arrives.
4. Edit on B, confirm the change reaches A.
5. CloudKit Console → **Production** → confirm the records are actually there.

If sync works both directions and Production shows the records, session 1 is done.

---

## The sequencing rule

In the Development environment, SwiftData auto-creates record types and fields on demand
but **never removes them**. So after Phase 1:

> **Every device must be on the post-reset build before any of them syncs.**

An older build touching CloudKit would re-create the fields we just removed, and if that
happens before Phase 4, the cruft becomes permanent. Deleting the app from every device
during Phase 0 is the cheapest way to guarantee this.

---

## If something goes wrong

**Before Phase 4** — nothing is at stake. Reset Development again and redo Phase 2. This
costs a clean install and a few minutes.

**After Phase 4** — the schema is frozen. You cannot remove a field, retype one, or rename
one. Your only options are to live with it or to add a corrected field alongside and
migrate in code, leaving the mistake as permanent dead weight. This asymmetry is the entire
reason Phases 0–3 exist.
