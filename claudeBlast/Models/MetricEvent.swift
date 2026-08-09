// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MetricEvent.swift
//  claudeBlast
//

import SwiftData
import Foundation

enum MetricType: String, Codable {
    case selected
    case used
    case edited
    case created
    case lookup
    case hit
    case flush
    case refreshed
}

/// Raw analytics event. **Device-local** — lives in the `DeviceLocal`
/// ModelConfiguration (`cloudKitDatabase: .none`), never CloudKit.
///
/// This is the highest write-volume model in the app: one record per cache
/// lookup and per hit, on essentially every child interaction, plus bulk writes
/// from `BulkCacheGenerator`. Syncing that to CloudKit would be a large amount
/// of push traffic for data that is disposable and only ever read as local
/// aggregate counts. Hit rate is a property of *this device's* cache, so
/// device-local is also the more correct meaning.
///
/// Because it never enters the CloudKit schema, this model is free to evolve
/// without the additive-only constraints that bind the synced models.
@Model
final class MetricEvent {
    var id: String = UUID().uuidString
    var subjectType: String = ""
    var subjectKey: String = ""
    /// `MetricType.rawValue`. Stored as a String rather than the enum directly,
    /// matching `ChildProfile.interactionModeRaw` / `DeviceProfile.roleRaw`.
    /// Unknown values fall back to `.selected` so an older build reading a newer
    /// event type degrades instead of failing.
    var eventTypeRaw: String = MetricType.selected.rawValue
    var timestamp: Date = Date.now

    /// How many occurrences this row represents. Always 1 for a live event; a
    /// compaction pass can fold a time range of same-subject events into a single
    /// row with `count > 1` rather than deleting the history outright.
    /// **Every reader must sum `count`, never count rows.**
    var count: Int = 1

    /// End of the range this row covers when it represents compacted history.
    /// Nil for a live single event (`timestamp` is the moment it happened).
    var periodEnd: Date?

    /// True once this row is an aggregate rather than a single observed event.
    var isAggregate: Bool { count > 1 || periodEnd != nil }

    /// Typed accessor over `eventTypeRaw`. Note this is computed, so it cannot
    /// be used inside a `#Predicate` — filter on `eventTypeRaw` there.
    var eventType: MetricType {
        get { MetricType(rawValue: eventTypeRaw) ?? .selected }
        set { eventTypeRaw = newValue.rawValue }
    }

    init(subjectType: String, subjectKey: String, eventType: MetricType,
         count: Int = 1, timestamp: Date = .now, periodEnd: Date? = nil) {
        self.subjectType = subjectType
        self.subjectKey = subjectKey
        self.eventTypeRaw = eventType.rawValue
        self.count = count
        self.timestamp = timestamp
        self.periodEnd = periodEnd
    }
}
