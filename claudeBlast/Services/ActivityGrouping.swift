// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ActivityGrouping.swift
//  claudeBlast
//
//  Turning a flat utterance log into something a caregiver can read.
//

import Foundation

/// One tile combination, and every time it was said in the window.
struct ActivityCluster: Identifiable {
    /// Sorted tile keys — the combination's identity. "eat apple" and
    /// "apple eat" are the same want said twice, not two wants.
    let tileKeys: [String]
    let entries: [LoggedUtterance]
    /// Most recent sentence for this combination, for the collapsed row.
    let latestSentence: String

    var id: String { tileKeys.joined(separator: "+") }
    var count: Int { entries.count }
    var firstAt: Date { entries.map(\.createdAt).min() ?? .distantPast }
    var latestAt: Date { entries.map(\.createdAt).max() ?? .distantPast }

    /// How many of these were escalated — the child re-tapped Play to say the
    /// same thing louder.
    ///
    /// Kept separate from `count` on purpose. Recurring across the window ("I
    /// said it again later") and escalating within one utterance ("I said it
    /// louder") are different events with different clinical readings, and a
    /// single ×N badge that merged them would misreport both.
    var escalatedCount: Int { entries.filter { $0.repetitionCount > 0 }.count }

    /// Wall-clock time from first to last. This is what makes a count mean
    /// something: "tired ×15 in two hours" is an unmet need, "tired ×15 this
    /// month" is a common word. Same tally, opposite readings.
    var span: TimeInterval { latestAt.timeIntervalSince(firstAt) }
}

/// A one-hour window that actually contains speech.
struct ActivityHourBand: Identifiable {
    let start: Date
    let entries: [LoggedUtterance]

    var id: Date { start }
    var count: Int { entries.count }
}

/// A run of speech with no long silence in it — one sitting at the board.
///
/// ## Why this is derived, not stored
///
/// A session is computed from the timestamps every time it is asked for. There
/// is no session row, no session id, and nothing about sessions in the schema.
/// That is deliberate on three counts:
///
/// 1. **It survives promotion.** After the CloudKit promotion in S6 the synced
///    schema is additive-only forever. A grouping rule that lives in code can be
///    retuned; a stored `sessionID` could not be taken back.
/// 2. **It merges across devices.** Utterances from an iPad and an iPhone land
///    in one timeline and group into one sitting. Sessions recorded per-device
///    would double-count the same lunch.
/// 3. **`sessionGap` stays a one-line change.** Nothing has to be migrated when
///    the number moves.
///
/// ## Why not app lifecycle
///
/// The obvious alternative — foreground to background — is wrong, and Mac makes
/// it obvious. A caregiver checking mail shatters one lunch into six "sessions",
/// while an iPad left open on the board all day collapses a whole day into one.
/// Neither is something the child did: backgrounding is a device event, not a
/// communication event. Reading the timestamps instead means iPhone, iPad and
/// Mac all produce the same answer, because none of them is consulted.
///
/// One consequence to know about: a session cannot exist with nothing in it. A
/// day where the board was opened and nothing was said produces no session at
/// all, and has to be told from `MetricEvent` instead.
struct ActivitySession: Identifiable {
    /// Chronological — oldest first, the order they were said in.
    let entries: [LoggedUtterance]

    /// The first entry's id. Sessions are derived, so this is stable only for as
    /// long as the underlying rows are — which is exactly as long as the session
    /// itself is.
    var id: String { entries.first?.id ?? "empty" }

    var startedAt: Date { entries.first?.createdAt ?? .distantPast }
    var endedAt: Date { entries.last?.createdAt ?? .distantPast }

    /// First to last. Zero for a single-utterance session, which is honest: one
    /// thing said takes no measurable time.
    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    var count: Int { entries.count }

    /// Distinct tile keys across the session — how many different words, not how
    /// many presses. The pair is the point: 12 said / 5 different reads very
    /// differently from 12 said / 11 different, and neither number alone says it.
    var distinctWordCount: Int {
        Set(entries.flatMap(\.tileKeys)).count
    }

    /// How many utterances were escalated. See `ActivityCluster.escalatedCount` —
    /// said louder is not said again.
    ///
    /// Always zero in single-word mode, where there is no generated sentence to
    /// escalate. Callers should omit the badge rather than render a zero.
    var escalatedCount: Int { entries.filter { $0.repetitionCount > 0 }.count }

    /// Whether this sitting was spent in single-word mode.
    ///
    /// Read from the rows rather than from the current setting, because the
    /// report describes history: a child switched to sentences on Thursday still
    /// has three single-word days behind them, and labelling those by today's
    /// mode would misreport every one.
    ///
    /// The test is exact rather than a guess. `SentenceEngine.selectTile` logs a
    /// single-word press as one tile key whose `sentence` is the tile's own
    /// `value`; the sentence path logs generated text. So a session is
    /// single-word when every row is one tile that says exactly itself. A
    /// sentence-mode utterance built from one tile still carries a generated
    /// sentence, and on the vanishing chance generation returns the bare word,
    /// reading it as single-word costs nothing — the two renderings agree on a
    /// one-word row.
    ///
    /// Needs the tile table for the same reason `sceneDisplayName` needs the
    /// scenes: the row stores a key, and only the caller can turn it into a word.
    func isSingleWord(resolving tiles: [String: TileModel]) -> Bool {
        guard !entries.isEmpty else { return false }
        return entries.allSatisfy { entry in
            guard entry.tileKeys.count == 1,
                  let value = tiles[entry.tileKeys[0]]?.value else { return false }
            return entry.sentence == value
        }
    }

    /// The scene the child was most often in during this session, or nil when
    /// nothing was recorded. A session can cross scenes; this names where most
    /// of it happened rather than pretending it was one place.
    func sceneDisplayName(resolving scenes: [BlasterScene]) -> String? {
        let names = entries.compactMap { $0.sceneDisplayName(resolving: scenes) }
        guard !names.isEmpty else { return nil }
        let counts = names.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        return counts.max { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key > rhs.key
        }?.key
    }
}

/// Grouping the activity log, as pure functions over the entries.
///
/// Deliberately not computed properties on a view. The Admin snippet and the
/// full log must show the *same* answer — the snippet is the top of the list
/// the full view renders — and a caregiver comparing the two and finding them
/// different would be right to distrust both. Pure functions also make this
/// testable, which the previous view-embedded grouping was not: that is how a
/// "Most Used" filter that silently ignored the time window survived.
enum ActivityGrouping {

    /// Combinations said fewer than this many times are rolled into the
    /// said-once bucket rather than listed individually.
    ///
    /// Two is the floor that means anything: a "cluster" of one is not a
    /// cluster, it is a line in a timeline. It is also the smallest number that
    /// can be justified without real usage data to tune against — a higher cut
    /// would be a guess about a distribution nobody has measured yet. Revisit
    /// once pilot logs exist; the number is here, alone, so that is a one-line
    /// change.
    static let minimumClusterCount = 2

    struct ClusterResult {
        /// Combinations said `minimumClusterCount`+ times, most-said first.
        let clusters: [ActivityCluster]
        /// Everything below the cut, newest first. Collapsed behind one row so
        /// the long tail of once-said words cannot bury the repetition that
        /// makes this view worth opening.
        let infrequent: [LoggedUtterance]
    }

    /// Group by tile combination.
    static func clusters(_ entries: [LoggedUtterance],
                         minimumCount: Int = minimumClusterCount) -> ClusterResult {
        let buckets = Dictionary(grouping: entries) { $0.tileKeys.sorted().joined(separator: "+") }

        var clusters: [ActivityCluster] = []
        var infrequent: [LoggedUtterance] = []

        for (_, group) in buckets {
            guard group.count >= minimumCount else {
                infrequent.append(contentsOf: group)
                continue
            }
            let newest = group.max(by: { $0.createdAt < $1.createdAt })
            clusters.append(ActivityCluster(
                tileKeys: group.first?.tileKeys.sorted() ?? [],
                entries: group.sorted { $0.createdAt > $1.createdAt },
                latestSentence: newest?.sentence ?? ""
            ))
        }

        clusters.sort { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.latestAt > rhs.latestAt
        }
        infrequent.sort { $0.createdAt > $1.createdAt }
        return ClusterResult(clusters: clusters, infrequent: infrequent)
    }

    /// Group into hour bands, **omitting every hour with nothing in it**.
    ///
    /// A day is mostly silence — a child does not talk for 24 hours — so
    /// rendering empty hours would bury the handful that matter. Nothing is
    /// lost by dropping them: each band carries its own timestamp, so a jump
    /// from 9 AM to 2 PM shows the gap more compactly than five empty rows
    /// could.
    static func hourBands(_ entries: [LoggedUtterance],
                          calendar: Calendar = .current) -> [ActivityHourBand] {
        let buckets = Dictionary(grouping: entries) { entry -> Date in
            calendar.dateInterval(of: .hour, for: entry.createdAt)?.start
                ?? entry.createdAt
        }
        return buckets
            .map { ActivityHourBand(start: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
            .sorted { $0.start > $1.start }
    }

    /// How long a silence ends a session.
    ///
    /// Ten minutes, not five. Five splits one slow sitting in two: a child
    /// composing tile by tile, or a partner modelling between turns, routinely
    /// leaves more than five minutes between utterances, and cutting there
    /// reports two short sessions where there was one ordinary one.
    ///
    /// The number is here, alone, because it is a guess until pilot logs exist.
    /// Nothing is stored per session, so changing it is a recompile rather than
    /// a migration.
    static let sessionGap: TimeInterval = 600

    /// Group entries into sittings, **newest session first**, each session's own
    /// entries oldest first.
    ///
    /// The two orders are deliberate and opposite. A caregiver scans sessions
    /// newest-first — today before last Tuesday — but reads *within* a session
    /// forwards, because the interesting thing about a sitting is how it
    /// developed: what was tried, what was repeated, what it escalated to.
    static func sessions(_ entries: [LoggedUtterance],
                         gap: TimeInterval = sessionGap) -> [ActivitySession] {
        guard !entries.isEmpty else { return [] }

        let chronological = entries.sorted { $0.createdAt < $1.createdAt }
        var sessions: [ActivitySession] = []
        var current: [LoggedUtterance] = [chronological[0]]

        for entry in chronological.dropFirst() {
            let previous = current[current.count - 1].createdAt
            if entry.createdAt.timeIntervalSince(previous) > gap {
                sessions.append(ActivitySession(entries: current))
                current = [entry]
            } else {
                current.append(entry)
            }
        }
        sessions.append(ActivitySession(entries: current))

        return sessions.reversed()
    }
}
