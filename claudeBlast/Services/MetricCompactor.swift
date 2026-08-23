// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MetricCompactor.swift
//  claudeBlast
//
//  Keeps the device-local store inside a space budget by folding old usage
//  history into monthly aggregates. Does nothing until the budget is threatened.
//

import Foundation
import SwiftData
import SQLite3
import os

/// Folds `MetricEvent` and `APIUsageEvent` history into monthly aggregates when
/// the device-local store approaches its space budget.
///
/// ## Space management, not housekeeping
///
/// An earlier design folded everything older than 30 days on a schedule. The
/// arithmetic says that is wrong. Measured on 2026-08-22 by the `load_sizing`
/// script — 10,000 utterances, 2–4 tiles each, backdated over 180 days, written
/// into a fresh device-local store — an utterance costs **4 metric rows** (one
/// per tile plus one for the sentence) and the store came to 5.93 MB for 39,996
/// rows: **~148 B/row**, or ~594 B per utterance. That 148 B is the whole file
/// over the row count, so it carries SQLite's own fixed overhead and is an upper
/// bound on the per-row cost.
///
/// Six months of *heavy* use (200 utterances/day) is therefore about **22 MB**,
/// and extreme use (500/day) about **54 MB**. Folding on a calendar would destroy
/// detail to reclaim space nobody needs.
///
/// The planning estimate was 5 rows at 275 B — 48 MB heavy, 120 MB extreme — so
/// the shipping thresholds were set against a footprint 1.9× larger than the real
/// one. They are left where they are: the error is entirely in the conservative
/// direction, and every threshold below is a ceiling rather than a target.
///
/// So compaction is triggered by measured bytes and by nothing else. On every
/// real device this class measures one file, finds it far under the mark, and
/// returns having touched nothing.
///
/// ## Why the budget is 256 MB
///
/// Six months of retained history — the target — costs 3–54 MB, so 256 MB is
/// roughly 5× the worst realistic case. Going higher would buy capacity the
/// retention floor guarantees is unreachable, at the cost of allowing an app that
/// shows over a gigabyte in iOS Settings. A large app is what a user deletes when
/// their phone runs out of space; at this budget the ceiling sits around 330 MB
/// including the ~71 MB bundle, and the realistic worst case around 125 MB.
///
/// ## This is a safety valve, not a tuning knob
///
/// Follow the measured numbers through and the high-water mark is out of reach:
/// 205 MB is ~1.45M rows, or ~362,000 utterances — about 2,000 a day, every day,
/// for six months. The smallest offered budget, 128 MB, puts its high-water at
/// 102 MB, still ~2× extreme use. No budget in `offeredMegabytes` will fire
/// compaction under any plausible real use.
///
/// That is the intended outcome and not a defect — the class exists so that an
/// unbounded log cannot fill a device — but it has a consequence worth stating:
/// the fold/delete/vacuum path never runs in production, so it is only ever
/// exercised deliberately, by `load_compaction` against a lowered budget or by
/// `MetricCompactorTests`. Treat those two as the only proof it works.
///
/// ## Everything happens in whole calendar months
///
/// The unit of work is a month, not a day and not a row. Day-granular folding was
/// dropped because it reclaims almost nothing from the highest-volume subject
/// type (see `foldKey`), and because a month-aligned aggregate describes a period
/// a reader can actually name.
enum MetricCompactor {
    private static let log = Logger(subsystem: "app.blasterai", category: "compaction")

    struct Policy: Sendable {
        /// Hard ceiling for the device-local store.
        var budgetBytes: Int64 = 256 * 1024 * 1024
        /// Start folding at this size.
        var highWaterBytes: Int64 = 205 * 1024 * 1024
        /// Stop folding once the projection drops below this.
        var lowWaterBytes: Int64 = 154 * 1024 * 1024
        /// **Coverage floor** — this much history is never deleted, whatever the
        /// budget says. Breaching it is reported, never done silently.
        var retainMonths: Int = 6
        /// **Detail floor** — the most recent N calendar months keep per-call
        /// detail and are never folded. Two, so the current and previous month
        /// survive: the OpenAI cost export covers roughly a month, and folding
        /// inside that window would leave the app's own figures unable to be
        /// reconciled against the bill.
        var keepDetailMonths: Int = 2

        static let `default` = Policy()

        /// Budget sizes offered as a setting, in megabytes.
        ///
        /// 256 MB is the shipping default: ~5x the worst realistic six-month
        /// footprint (see the measured figures above) while keeping the whole
        /// install inside the ~400 MB band most phones are already full of, where
        /// nobody goes hunting for space to delete.
        ///
        /// The others exist because that reasoning is not universal. A 64 GB
        /// device, or a household where storage pressure is a weekly event, is
        /// better served by 128 — and somewhere with heavy multi-child use, by
        /// 512. The floors do not move with the budget, so choosing a smaller one
        /// never silently costs the child history: it makes `floorHeld` more
        /// likely, which the compaction report shows plainly.
        static let offeredMegabytes = [128, 256, 512]

        /// The policy a launch actually runs under, honouring the storage-budget
        /// setting. Zero — the default — means the shipping policy untouched.
        ///
        /// Only `budgetBytes` and the two watermarks scale. `retainMonths` and
        /// `keepDetailMonths` are promises about the child's data rather than
        /// functions of disk, so a smaller budget makes the app hold the floor
        /// and report it, never quietly keep less.
        static func resolved(defaults: UserDefaults = .standard) -> Policy {
            let mb = defaults.integer(forKey: AppSettingsKey.compactionBudgetMB)
            guard mb > 0 else { return .default }
            var policy = Policy()
            // Floor at 8 MB: below that the store's own fixed overhead dominates
            // and the run would be measuring SQLite rather than the app's data.
            policy.budgetBytes = Int64(max(8, mb)) * 1024 * 1024
            // Same 80% / 60% shape as the shipping thresholds.
            policy.highWaterBytes = policy.budgetBytes * 4 / 5
            policy.lowWaterBytes = policy.budgetBytes * 3 / 5
            return policy
        }
    }

    struct Outcome: Sendable, Equatable {
        var monthsFolded = 0
        var monthsDeleted = 0
        var rowsRemoved = 0
        var startBytes: Int64 = 0
        /// True when everything permitted was done and the store is still over
        /// budget — the coverage floor held rather than being breached.
        var floorHeld = false
        /// True when the store was under the high-water mark and nothing ran.
        var skipped = false

        static let noop = Outcome(skipped: true)
    }

    // MARK: - Entry point

    /// Bring the device-local store back under budget, if it is over.
    ///
    /// Runs at launch beside the sentence-cache sweep. Returns `.noop` — having
    /// issued no fetch at all — whenever the store is under the high-water mark,
    /// which is the expected path on every real device.
    @MainActor
    @discardableResult
    static func run(container: ModelContainer,
                    policy: Policy? = nil,
                    now: Date = .now) -> Outcome {
        let policy = policy ?? .resolved()
        let bytes = StorageReporter.deviceLocalBytes(container: container)
        // The cheap guard, deliberately before any fetch: measuring one file is
        // the whole cost of compaction on a device that does not need it.
        guard bytes >= policy.highWaterBytes else { return .noop }

        log.notice("compaction: store=\(bytes, privacy: .public) over high-water — starting")
        let context = container.mainContext
        let started = ContinuousClock.now
        let rowsBefore = rowCount(in: context)
        let outcome = compact(context: context, measuredBytes: bytes,
                              policy: policy, now: now)
        record(outcome: outcome, policy: policy, context: context,
               rowsBefore: rowsBefore,
               endBytes: StorageReporter.deviceLocalBytes(container: container),
               elapsed: started.duration(to: .now), at: now)

        // Folding frees pages inside the file but cannot hand them back now — see
        // `reclaimPendingSpace`. Leave a note for the next launch instead.
        //
        // Requested whenever compaction RAN, not only when it removed rows.
        // Gating on `rowsRemoved > 0` looks tighter and strands the store
        // permanently: a reclaim that fails clears its own flag, the next launch
        // is still over the mark so compaction runs again, but everything
        // foldable is already folded — zero rows removed, no new flag, and the
        // free pages are never offered to the filesystem again. Being over the
        // high-water mark is itself the reason to try, and it is self-limiting,
        // because a store back under the mark never gets here.
        if let local = container.configurations
            .first(where: { $0.name == StorageReporter.deviceLocalConfigurationName }) {
            let defaults = UserDefaults.standard
            defaults.set(local.url.path, forKey: AppSettingsKey.compactionStorePath)
            defaults.set(true, forKey: AppSettingsKey.compactionReclaimPending)
            log.notice("compaction: free pages queued for reclaim on next launch")
        }
        return outcome
    }

    // MARK: - Recording what happened

    /// How many compaction records to keep. Enough to see a pattern across a
    /// pilot without the audit trail becoming its own storage problem.
    static let retainedRuns = 50

    /// Live rows in the two managed models, so a run can report what it started
    /// with and what it left. `fetchCount` rather than fetching: the whole point
    /// of this pass is that the store is large.
    @MainActor
    private static func rowCount(in context: ModelContext) -> Int {
        let metrics = (try? context.fetchCount(FetchDescriptor<MetricEvent>())) ?? 0
        let usage = (try? context.fetchCount(FetchDescriptor<APIUsageEvent>())) ?? 0
        return metrics + usage
    }

    /// Persist the pass so it can be judged later. Best-effort: a compaction that
    /// worked must not be reported as failed because its audit row would not save.
    @MainActor
    private static func record(outcome: Outcome, policy: Policy, context: ModelContext,
                               rowsBefore: Int, endBytes: Int64,
                               elapsed: Duration, at now: Date) {
        let run = CompactionRun()
        run.startedAt = now
        run.budgetBytes = Int(policy.budgetBytes)
        run.highWaterBytes = Int(policy.highWaterBytes)
        run.lowWaterBytes = Int(policy.lowWaterBytes)
        run.retainMonths = policy.retainMonths
        run.keepDetailMonths = policy.keepDetailMonths
        run.startBytes = Int(outcome.startBytes)
        run.endBytes = Int(endBytes)
        run.monthsFolded = outcome.monthsFolded
        run.monthsDeleted = outcome.monthsDeleted
        run.rowsRemoved = outcome.rowsRemoved
        run.rowsBefore = rowsBefore
        run.rowsAfter = rowCount(in: context)
        run.floorHeld = outcome.floorHeld
        run.durationMs = Int(elapsed.components.seconds * 1000
                             + elapsed.components.attoseconds / 1_000_000_000_000_000)
        context.insert(run)

        // The next launch reclaims and needs to know which row to complete.
        UserDefaults.standard.set(run.id, forKey: AppSettingsKey.compactionLastRunID)

        pruneRuns(in: context)
        try? context.save()
        log.notice("""
            compaction: folded=\(outcome.monthsFolded, privacy: .public) \
            deleted=\(outcome.monthsDeleted, privacy: .public) \
            rows=\(outcome.rowsRemoved, privacy: .public) \
            floorHeld=\(outcome.floorHeld, privacy: .public)
            """)
    }

    @MainActor
    private static func pruneRuns(in context: ModelContext) {
        var descriptor = FetchDescriptor<CompactionRun>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = retainedRuns * 2
        guard let runs = try? context.fetch(descriptor), runs.count > retainedRuns else { return }
        for run in runs.dropFirst(retainedRuns) { context.delete(run) }
    }

    /// Attach the previous launch's reclaim result to the run that caused it.
    ///
    /// Called at launch once the container exists. Reclamation itself happens
    /// *before* there is a store to write to — that is the whole constraint —
    /// so the byte figure is parked in `UserDefaults` and collected here. Without
    /// this the report could say what compaction destroyed but never what it
    /// bought, which is exactly the comparison that decides whether the policy is
    /// worth having.
    @MainActor
    static func attachPendingReclaim(container: ModelContainer,
                                     defaults: UserDefaults = .standard) {
        guard let runID = defaults.string(forKey: AppSettingsKey.compactionLastRunID),
              defaults.object(forKey: AppSettingsKey.compactionReclaimedBytes) != nil
        else { return }
        let reclaimed = defaults.integer(forKey: AppSettingsKey.compactionReclaimedBytes)
        defaults.removeObject(forKey: AppSettingsKey.compactionReclaimedBytes)
        defaults.removeObject(forKey: AppSettingsKey.compactionLastRunID)

        let context = container.mainContext
        var descriptor = FetchDescriptor<CompactionRun>(
            predicate: #Predicate { $0.id == runID })
        descriptor.fetchLimit = 1
        guard let run = try? context.fetch(descriptor).first else { return }
        run.reclaimedBytes = reclaimed
        run.reclaimAttempted = true
        try? context.save()
    }

    // MARK: - Returning the space to the device

    /// Hand pages freed by a previous compaction back to the filesystem.
    ///
    /// **Must run before the `ModelContainer` is created, and that is not a
    /// preference.** Measured, because the obvious implementation does not work:
    /// with a second connection open on the store, `PRAGMA incremental_vacuum`
    /// reclaims exactly one page out of a 22,016-page freelist. The freelist is
    /// fully visible; SQLite simply will not truncate a database file that
    /// another connection has open, whatever order the pragmas are issued in.
    /// With no other connection, the same call took a 91 MB store to 1 MB in
    /// ~110 ms.
    ///
    /// So compaction and reclamation are split across launches: launch N folds
    /// rows and leaves a note here, launch N+1 opens the file before SwiftData
    /// does and returns the space. That is the only window in the app's life when
    /// nothing holds the store.
    ///
    /// Without this the app's footprint would never fall. Folding alone still
    /// bounds *growth* — freed pages get reused, so the store pins at the
    /// high-water mark — but a caregiver looking at iOS Settings would never see
    /// the number go down, and the disk would never come back to their device.
    ///
    /// The store path comes from a `UserDefault` written by the previous launch
    /// rather than being reconstructed here: SwiftData owns where its store
    /// lives, and a guessed path that stopped matching would silently reclaim
    /// nothing. Entirely best-effort — any failure is logged and the flag cleared,
    /// since the alternative is failing a launch over disk space.
    static func reclaimPendingSpace(defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: AppSettingsKey.compactionReclaimPending),
              let path = defaults.string(forKey: AppSettingsKey.compactionStorePath),
              FileManager.default.fileExists(atPath: path)
        else { return }
        // Cleared BEFORE the work, deliberately. This runs before the app has a
        // store, a UI, or a way to report anything, so a store that somehow made
        // these pragmas fatal would otherwise crash on every launch forever, with
        // the app unusable and the cause invisible. One attempt per request; if it
        // fails, the store is simply not trimmed, which costs disk and nothing
        // else — and the next compaction requests it again.
        defaults.set(false, forKey: AppSettingsKey.compactionReclaimPending)

        let before = StorageReporter.storeBytes(at: URL(fileURLWithPath: path))
        reclaimFreeSpace(at: URL(fileURLWithPath: path))
        let after = StorageReporter.storeBytes(at: URL(fileURLWithPath: path))
        log.notice("reclaim: \(before, privacy: .public) -> \(after, privacy: .public) bytes")

        // Park the result for `attachPendingReclaim`. Written even when nothing
        // was freed: "tried and got nothing back" is the finding that would
        // condemn the whole policy, and it must not look identical to "the second
        // launch has not happened yet".
        defaults.set(max(0, Int(before - after)), forKey: AppSettingsKey.compactionReclaimedBytes)
    }

    /// The pragmas themselves. Separate from `reclaimPendingSpace` so tests can
    /// drive it against a store they control.
    ///
    /// Only ever call this with no `ModelContainer` open on the file.
    static func reclaimFreeSpace(at url: URL) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            log.warning("reclaim: could not open store")
            sqlite3_close(db)
            return
        }
        defer { sqlite3_close(db) }

        // Checkpoint FIRST: in WAL mode the deletes live in the log, and the
        // freelist is not materialised in the main file until they are copied
        // back. Vacuuming before this reclaims nothing.
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
        // Bounded so an enormous freelist cannot stall a launch; whatever is left
        // over is reclaimed by the next pass.
        if sqlite3_exec(db, "PRAGMA incremental_vacuum(50000);", nil, nil, nil) != SQLITE_OK {
            log.warning("reclaim: incremental_vacuum failed — space stays reserved")
        }
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
    }

    /// The compaction itself, against an already-measured size.
    ///
    /// Split out so tests can drive it with a synthetic byte count instead of
    /// having to write hundreds of megabytes to disk.
    @MainActor
    @discardableResult
    static func compact(context: ModelContext,
                        measuredBytes: Int64,
                        policy: Policy = .default,
                        now: Date = .now) -> Outcome {
        var outcome = Outcome(startBytes: measuredBytes)

        let metrics = (try? context.fetch(FetchDescriptor<MetricEvent>())) ?? []
        let usage = (try? context.fetch(FetchDescriptor<APIUsageEvent>())) ?? []
        var liveRows = metrics.count + usage.count
        guard liveRows > 0 else { return outcome }

        // ## Why the target is a row count, not a re-measured file size
        //
        // Deleting rows does not shrink the file: SQLite moves the pages to a
        // freelist inside it. Measured on a real store — 200k rows at 91 MB, drop
        // 90% of them, still 91 MB with 19,755 free pages. So re-measuring
        // between folds would report no progress and drive this loop to fold
        // everything it is allowed to touch, every single run.
        //
        // The space IS reclaimable — see `reclaimFreeSpace`, which runs once at
        // the end — but not incrementally enough to steer the loop by. So the
        // stopping condition is expressed in rows, converted with a bytes-per-row
        // figure derived from this store's own measurement. The trigger stays
        // real measured bytes; only the projection is arithmetic, and it is
        // calibrated against the device it runs on rather than an assumed size.
        let rate = exchangeRate(context: context, measuredBytes: measuredBytes,
                                liveRows: liveRows)

        // ## Shed the surplus, do not re-derive the whole file from rows
        //
        // The target is `liveRows` minus the rows the surplus is worth, never
        // `lowWater / bytesPerRow`. The two agree only if every byte in the file
        // belongs to a metric row, and measurement says they do not: the store
        // also holds the device profile, the compaction log, every index, and —
        // after a fold — pages that are allocated but half empty, because SQLite
        // frees a page only when it empties completely.
        //
        // Ignoring that put a real soak into a ratchet. Across four launches the
        // naive ratio read 145, then 316, then 593, then 603 B/row as the row
        // count fell and the fixed overhead stopped amortising. Each inflated
        // reading demanded another fold, and the second launch destroyed 15,214
        // rows to chase a target it had already met. Subtracting the surplus
        // instead makes the fixed overhead cancel: it is in `measuredBytes` and
        // in `lowWaterBytes` alike, so only the *marginal* cost of a row matters.
        let surplusBytes = Double(measuredBytes - policy.lowWaterBytes)
        let rowsToShed = Int((surplusBytes / rate.bytesPerRow).rounded(.up))
        let targetRows = liveRows - rowsToShed
        log.notice("""
            compaction: rows=\(liveRows, privacy: .public) \
            bytesPerRow=\(Int(rate.bytesPerRow), privacy: .public) \
            source=\(rate.source, privacy: .public) \
            shed=\(rowsToShed, privacy: .public) \
            targetRows=\(targetRows, privacy: .public)
            """)

        // ## Unreachable is a stopping condition, not a reason to try harder
        //
        // A non-positive target means the surplus is larger than every row in
        // the store is worth: deleting the entire history would still leave the
        // file over the low-water mark, because what is over the mark is not
        // history. Folding here buys nothing and costs detail, so the honest
        // move is to stop before touching anything and say the floor held.
        //
        // This is the guard that was missing. It fires on small budgets, where
        // SQLite's own fixed overhead is a large fraction of the target, and it
        // is why a soak at 8 MB now keeps 28,795 rows where it used to grind
        // down to 13,294 over successive launches without ever getting under.
        guard targetRows > 0 else {
            outcome.floorHeld = true
            log.warning("""
                compaction: surplus of \(Int(surplusBytes), privacy: .public) B exceeds what \
                \(liveRows, privacy: .public) row(s) can free at \
                \(Int(rate.bytesPerRow), privacy: .public) B/row — \
                keeping history, store stays over budget
                """)
            return outcome
        }

        let cal = Calendar.current
        guard let currentMonth = cal.startOfMonth(for: now),
              // Oldest month we may fold: everything newer keeps per-call detail.
              let foldBefore = cal.date(byAdding: .month, value: -(policy.keepDetailMonths - 1),
                                        to: currentMonth),
              // Oldest month we may keep at all.
              let deleteBefore = cal.date(byAdding: .month, value: -policy.retainMonths,
                                          to: currentMonth)
        else { return outcome }

        // Oldest first: the least useful history goes first, and the most recent
        // stays at full resolution for as long as possible.
        var months = Set<Date>()
        for m in metrics { if let s = cal.startOfMonth(for: m.timestamp) { months.insert(s) } }
        for u in usage { if let s = cal.startOfMonth(for: u.timestamp) { months.insert(s) } }
        let ordered = months.sorted()

        // Stage 1 — fold whole months into monthly aggregates.
        for month in ordered where month < foldBefore {
            guard liveRows > targetRows else {
                log.notice("compaction: reached target after \(outcome.monthsFolded, privacy: .public) month(s)")
                return outcome
            }
            let removed = foldMonth(month, context: context, calendar: cal)
            if removed > 0 {
                outcome.monthsFolded += 1
                outcome.rowsRemoved += removed
                liveRows -= removed
            }
        }

        // Stage 2 — only once everything foldable is folded. Deletion is the
        // last resort and stops dead at the coverage floor.
        for month in ordered where month < deleteBefore {
            guard liveRows > targetRows else { break }
            let removed = deleteMonth(month, context: context, calendar: cal)
            if removed > 0 {
                outcome.monthsDeleted += 1
                outcome.rowsRemoved += removed
                liveRows -= removed
            }
        }

        try? context.save()

        // Stage 3 — the floor holds. Say so rather than quietly eating history
        // the user was promised.
        if liveRows > targetRows {
            outcome.floorHeld = true
            log.warning("""
                compaction: still above target with \(policy.retainMonths, privacy: .public) \
                month(s) retained and fully folded — keeping history, store stays over budget
                """)
        }
        log.notice("""
            compaction: folded=\(outcome.monthsFolded, privacy: .public) \
            deleted=\(outcome.monthsDeleted, privacy: .public) \
            rowsRemoved=\(outcome.rowsRemoved, privacy: .public)
            """)
        return outcome
    }

    // MARK: - What a row is actually worth

    /// The marginal cost of one row, and where the figure came from.
    struct ExchangeRate: Sendable, Equatable {
        var bytesPerRow: Double
        /// `measured` — observed from a previous pass's realised reclaim.
        /// `estimated` — this store's own size over its own rows, used until
        /// there is a measurement to replace it.
        var source: String
    }

    /// How many bytes compaction can expect to free per row it destroys.
    ///
    /// ## Prefer what happened over what should happen
    ///
    /// Dividing the file by its rows answers a different question — the *average*
    /// bytes a row is carrying, fixed overhead and fragmentation included — and
    /// that number climbs without bound as rows are removed. What steering needs
    /// is the *marginal* figure: remove one more row, get how many bytes back.
    ///
    /// A previous run already measured exactly that. It recorded the rows it
    /// destroyed and, on the launch afterwards, the bytes the filesystem actually
    /// took back. `CompactionRun.bytesPerRowRemoved` is the realised exchange
    /// rate, and unlike the estimate it has fragmentation and partial vacuums
    /// already priced in — a run that folded 71,437 rows and recovered 4.05 MB
    /// really did trade at ~57 B/row, whatever the schema suggests.
    ///
    /// With no such run yet, fall back to the ratio. That fallback is at its most
    /// accurate precisely when it is needed: the first compaction happens on a
    /// store whose rows dominate it, where average and marginal nearly coincide
    /// — measured at 145 B/row against a true 145.
    ///
    /// Only runs that actually traded are eligible, and eligibility is part of
    /// the query rather than a check on the newest row. A pass whose second half
    /// has not happened (`reclaimAttempted == false`) has no realised figure yet;
    /// one that reclaimed nothing would report a rate of zero and be read as
    /// "rows are free", the most dangerous possible answer; and — the case that
    /// actually bit — **a pass that removed no rows measured nothing at all**.
    ///
    /// A `floorHeld` pass is exactly that: it keeps the history, removes nothing,
    /// and still reclaims stray pages on the launch afterwards. Matching only the
    /// most recent reclaiming run let one of those shadow the last real
    /// measurement, and the fallback estimate then over-folded on the very next
    /// launch — measured, in a soak, as 57 B/row on one launch and 316 B/row on
    /// the next, destroying 15,214 rows in between. Requiring `rowsRemoved > 0`
    /// in the predicate keeps the newest run that genuinely priced a row, however
    /// many quiet passes have happened since.
    @MainActor
    static func exchangeRate(context: ModelContext,
                             measuredBytes: Int64,
                             liveRows: Int) -> ExchangeRate {
        let estimate = ExchangeRate(
            bytesPerRow: max(1, Double(measuredBytes) / Double(max(1, liveRows))),
            source: "estimated")

        var descriptor = FetchDescriptor<CompactionRun>(
            predicate: #Predicate {
                $0.reclaimAttempted && $0.reclaimedBytes > 0 && $0.rowsRemoved > 0
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let previous = try? context.fetch(descriptor).first,
              previous.bytesPerRowRemoved > 0
        else { return estimate }

        return ExchangeRate(bytesPerRow: Double(previous.bytesPerRowRemoved),
                            source: "measured")
    }

    // MARK: - Folding one month

    /// Collapse one calendar month into one row per fold key. Returns rows removed.
    @MainActor
    private static func foldMonth(_ month: Date, context: ModelContext,
                                  calendar: Calendar) -> Int {
        guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { return 0 }
        var removed = 0

        let metrics = fetch(MetricEvent.self, from: month, to: next, context: context)
        removed += fold(metrics, context: context, key: foldKey(for:)) { survivor, others in
            for other in others {
                survivor.count += other.count
                survivor.timestamp = min(survivor.timestamp, other.timestamp)
                survivor.periodEnd = max(survivor.periodEnd ?? survivor.timestamp,
                                         other.periodEnd ?? other.timestamp)
            }
            // The key was dropped from the fold key for these types, so the
            // surviving row must not keep one tile combination's key and imply
            // the counts belong to it.
            if combinationSubjectTypes.contains(survivor.subjectType) {
                survivor.subjectKey = ""
            }
        }

        let usage = fetch(APIUsageEvent.self, from: month, to: next, context: context)
        removed += fold(usage, context: context, key: foldKey(for:)) { survivor, others in
            for other in others {
                survivor.count += other.count
                survivor.promptTokens += other.promptTokens
                survivor.cachedPromptTokens += other.cachedPromptTokens
                survivor.imageInputTokens += other.imageInputTokens
                survivor.completionTokens += other.completionTokens
                survivor.imageCount += other.imageCount
                survivor.costMicros += other.costMicros
                survivor.timestamp = min(survivor.timestamp, other.timestamp)
                survivor.periodEnd = max(survivor.periodEnd ?? survivor.timestamp,
                                         other.periodEnd ?? other.timestamp)
            }
        }
        return removed
    }

    /// Group by `key`, merge each group into its earliest row via `merge`, delete
    /// the rest. Returns rows deleted.
    @MainActor
    private static func fold<T: PersistentModel>(
        _ rows: [T], context: ModelContext,
        key: (T) -> String,
        merge: (T, ArraySlice<T>) -> Void
    ) -> Int {
        var groups: [String: [T]] = [:]
        for row in rows { groups[key(row), default: []].append(row) }

        var removed = 0
        for (_, group) in groups where group.count > 1 {
            // Mutate the earliest row rather than inserting a fresh aggregate:
            // one fewer row churned, and the survivor keeps its identity.
            let survivor = group[0]
            merge(survivor, group.dropFirst())
            for row in group.dropFirst() {
                context.delete(row)
                removed += 1
            }
        }
        return removed
    }

    @MainActor
    private static func deleteMonth(_ month: Date, context: ModelContext,
                                    calendar: Calendar) -> Int {
        guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { return 0 }
        var removed = 0
        for row in fetch(MetricEvent.self, from: month, to: next, context: context) {
            context.delete(row); removed += 1
        }
        for row in fetch(APIUsageEvent.self, from: month, to: next, context: context) {
            context.delete(row); removed += 1
        }
        return removed
    }

    // MARK: - Fold keys

    static let cacheSubjectType = "cache"

    /// Subject types whose `subjectKey` is a **cache key** — sorted tile keys
    /// plus grade plus version — rather than a name from a small vocabulary.
    ///
    /// Fold efficiency is entirely a function of key cardinality. `tile` events
    /// share 492 keys, so a month of them collapses to a few hundred rows. A
    /// cache key is close to unique per row, so any subject type carrying one
    /// folds to almost nothing while appearing to work.
    ///
    /// All three of these carry one (`SentenceEngine:910`, `:1008`, `:1091`).
    /// An earlier version listed only `cache`, which was the bug: `sentence` is
    /// written roughly once per utterance — comparable in volume to the cache
    /// rows beside it — and would have survived folding almost entirely. The
    /// compactor would have reported months folded and thousands of rows
    /// removed, and handed back a fraction of the space, with nothing in the
    /// output pointing at why.
    static let combinationSubjectTypes: Set<String> = ["cache", "sentence", "promoted"]

    /// Rows may only merge when everything that would make a sum meaningless is
    /// equal.
    ///
    /// **`subjectKey` is deliberately dropped for combination events** — see
    /// `combinationSubjectTypes`. Dropping it keeps the counts (how many
    /// lookups, how many hits, how many sentences) and loses only which
    /// combinations were involved.
    static func foldKey(for event: MetricEvent) -> String {
        let subject = combinationSubjectTypes.contains(event.subjectType)
            ? "" : event.subjectKey
        return "\(event.subjectType)|\(subject)|\(event.eventTypeRaw)"
    }

    /// As documented on `APIUsageEvent` itself, and binding: a sum across differing
    /// values in any of these would be meaningless. `priceTableAsOf` is in the key
    /// so a period spanning a price change cannot collapse rows that were priced
    /// under different tables.
    static func foldKey(for event: APIUsageEvent) -> String {
        [event.causeRaw, event.model, event.endpoint, event.detail, event.childID,
         String(event.priceTableAsOf.timeIntervalSince1970)].joined(separator: "|")
    }

    // MARK: - Helpers

    @MainActor
    private static func fetch<T: PersistentModel>(_: T.Type, from: Date, to: Date,
                                                  context: ModelContext) -> [T] {
        // Sorted so `group[0]` is the earliest row, which is what `fold` merges
        // into and what makes the aggregate's `timestamp` the start of its period.
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        return all.compactMap { row -> (T, Date)? in
            guard let date = (row as? any TimestampedEvent)?.timestamp else { return nil }
            return date >= from && date < to ? (row, date) : nil
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
    }
}

/// Lets the compactor treat both event models uniformly when slicing by month.
/// Both already have `timestamp`; this only names the shared shape.
protocol TimestampedEvent {
    var timestamp: Date { get }
}

extension MetricEvent: TimestampedEvent {}
extension APIUsageEvent: TimestampedEvent {}

extension Calendar {
    /// First instant of the calendar month containing `date`.
    func startOfMonth(for date: Date) -> Date? {
        self.date(from: dateComponents([.year, .month], from: date))
    }
}
