// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptCommand.swift
//  claudeBlast
//

import Foundation

/// A single action within a tile row.
/// - `navigate`: switch to a page.
/// - `tap`: tap a tile in the grid (engine.addTile).
/// - `audibleNavigate`: shorthand for a PageTileModel where both `isAudible` and `link` are set
///   AND the link key matches the tile key — i.e. tapping the nav tile also adds it to the
///   active group. Runner expands this to a tile-add followed by a navigation; serializer
///   renders it as `<key isAudible=t/>`.
/// - `replay`: standalone control marker. A TileRow containing exactly `[.replay]` triggers
///   replay-with-escalation (reopening the most recent history group first if necessary).
/// - `noclose`: inline trailing marker on a tiles row. Suppresses the auto-Done at row end so
///   the active group stays locked for the next row to extend.
enum TileAction: Sendable, Equatable {
    case navigate(pageKey: String)
    case tap(tileKey: String)
    case audibleNavigate(pageKey: String)
    case replay
    case noclose
}

/// Parsed tile row: a sequence of actions that form one utterance.
struct TileRow: Sendable {
    let actions: [TileAction]
    /// The original text from the YAML (e.g. "<home>, mom, <food>, pizza")
    let rawText: String
    /// Trailing `# comment` from the YAML line, if any.
    let comment: String?

    /// The individual text tokens for display (e.g. ["<home>", "mom", "<food>", "pizza"]).
    var tokens: [String] {
        actions.map { action in
            switch action {
            case .navigate(let key): return "<\(key)>"
            case .tap(let key): return key
            case .audibleNavigate(let key): return "<\(key) isAudible=t/>"
            case .replay: return "<tilescript:replay>"
            case .noclose: return "<tilescript:noclose>"
            }
        }
    }

    /// True when this row is a standalone `<tilescript:replay>` control marker.
    var isReplay: Bool {
        actions.count == 1 && actions[0] == .replay
    }

    /// True when this row ends with `<tilescript:noclose>` — the runner should skip the
    /// auto-Done at row end so the active group stays locked for the next row to extend.
    var hasNoclose: Bool {
        actions.contains(.noclose)
    }

    /// Actions that should actually be executed at row run time (i.e. excluding control markers
    /// like `.noclose` which are metadata for the row itself, not user actions).
    var executableActions: [TileAction] {
        actions.filter { $0 != .noclose }
    }
}

/// Bulk tile generation spec.
struct BulkTileSpec: Sendable {
    let count: Int
    let source: BulkSource
    let minLength: Int
    let maxLength: Int
    /// Spread the generated events back over this many days of simulated history
    /// (`days:` in a script). Zero — the default — stamps everything `.now`, which
    /// is what bulk generation did before `SimulatedClock` existed.
    var spanDays: Int = 0
    /// Write metric events only, skipping the sentence cache (`metricsOnly:`).
    ///
    /// Growth is budgeted against the **device-local** store, and a cache write
    /// lands in the *synced* one — so filling the metric log the normal way drags
    /// an equal number of cached sentences into iCloud, which is both far larger
    /// and the wrong target. This mode grows only what the compactor measures.
    var metricsOnly: Bool = false
    /// Seed for combo selection and timestamps, so a run replays exactly.
    var seed: UInt64 = 0x5EED

    enum BulkSource: String, Sendable {
        case mostCommon = "most-common"
        case random
        case allCombos = "all-combos"
    }
}

/// Timing value: either a named preset or an explicit duration.
enum TimingValue: Sendable, Equatable {
    case human
    case fast
    case instant
    case explicit(milliseconds: Int)

    var duration: Duration {
        switch self {
        case .human: return .milliseconds(800)
        case .fast: return .milliseconds(100)
        case .instant: return .zero
        case .explicit(let ms): return .milliseconds(ms)
        }
    }
}

/// A single command in a TileScript.
enum TileScriptCommand: Sendable {
    case tiles(rows: [TileRow])
    case bulkTiles(spec: BulkTileSpec)
    case clear
    case comment(text: String)
    case wait(duration: Duration)
    case setAudio(enabled: Bool)
    case setTileWait(value: TimingValue)
    case setSentenceWait(value: TimingValue)
    case setProvider(name: String)
    case setScene(name: String)
    case setTileSet(imageSet: ImageSetID)
    /// Write a PNG of the current screen to `Documents/Screenshots/`.
    ///
    /// The point of capturing from *inside* a script rather than externally is
    /// timing: the states worth photographing — an overlay up, a sentence
    /// mid-generation, a board on page 3 — last a few hundred milliseconds and
    /// are reached by the script itself. It also works on a real device, which
    /// is where App Store assets have to come from.
    case screenshot(name: String)
    /// Navigate to a named destination — see `ScriptScreen`. Scripts name
    /// *where to be*, never how to get there, which is what keeps them working
    /// across layout changes.
    case screen(ScriptScreen)
    /// Turn demo mode on or off for the run.
    ///
    /// Demo mode suppresses the developer furniture a capture must not contain —
    /// the grid diagnostic badge, and the playback pill on a straight run. A
    /// screenshot script should set it for the same reason a screen recording
    /// does: what is on screen IS the artifact.
    case setDemoMode(enabled: Bool)
}
