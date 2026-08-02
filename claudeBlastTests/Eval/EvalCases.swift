// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  EvalCases.swift
//  claudeBlastTests
//
//  The curated, version-controlled eval set — the golden inputs. Same inputs
//  every run, so scores are comparable run-over-run. Kept small and inline
//  (no JSON-loading machinery) per the "don't over-build" scope: enough breadth
//  to catch gross failures and exercise escalation, not a benchmark suite.

import Foundation
@testable import claudeBlast

/// One sentence-generation input: a tile combination plus a note on what it's
/// probing. Tiles are (key, value, wordClass) triples → TileSelection.
struct SentenceEvalCase {
    let id: String
    let tiles: [TileSelection]
    /// What this case is meant to exercise (for the report; not scored).
    let probe: String

    init(_ id: String, _ raw: [(String, String, String)], probe: String) {
        self.id = id
        self.tiles = raw.map { TileSelection(key: $0.0, value: $0.1, wordClass: $0.2) }
        self.probe = probe
    }
}

/// One escalation input: a base combination plus how many extra repeats to run.
struct EscalationEvalCase {
    let id: String
    let tiles: [TileSelection]
    let extraSteps: Int
    let probe: String

    init(_ id: String, _ raw: [(String, String, String)], extraSteps: Int, probe: String) {
        self.id = id
        self.tiles = raw.map { TileSelection(key: $0.0, value: $0.1, wordClass: $0.2) }
        self.extraSteps = extraSteps
        self.probe = probe
    }
}

enum EvalCases {
    /// Representative single + multi-tile combinations, including the
    /// wordClass-disambiguation cases the prompt's category rule exists for.
    static let sentences: [SentenceEvalCase] = [
        .init("mom_hungry", [("mom", "mom", "people"), ("hungry", "hungry", "feeling")],
              probe: "self-centered request framing"),
        .init("eat_pizza", [("eat", "eat", "actions"), ("pizza", "pizza", "food")],
              probe: "simple want"),
        .init("mom_eat_pizza", [("mom", "mom", "people"), ("eat", "eat", "actions"), ("pizza", "pizza", "food")],
              probe: "three-tile request"),
        .init("tired_bed", [("tired", "tired", "feeling"), ("bed", "bed", "places")],
              probe: "feeling + place"),
        .init("snackbar_food", [("snack bar", "snack bar", "food")],
              probe: "homograph: should be the food, not the place"),
        .init("pony_animal", [("pony", "pony", "animal"), ("ride", "ride", "actions")],
              probe: "animal sense honored"),
        .init("dad_help", [("dad", "dad", "people"), ("help", "help", "actions")],
              probe: "asking a person for help"),
        .init("more_drink", [("more", "more", "core"), ("drink", "drink", "drinks")],
              probe: "core word + noun"),
        .init("happy", [("happy", "happy", "feeling")],
              probe: "single feeling word"),
        .init("go_outside_play", [("go", "go", "actions"), ("outside", "outside", "places"), ("play", "play", "actions")],
              probe: "activity chain"),
    ]

    /// Escalation ladders — the priority. Includes the canonical "volume knob"
    /// scenarios from the PRD (chocolate / pinkfong / hungry).
    static let escalations: [EscalationEvalCase] = [
        .init("chocolate", [("chocolate", "chocolate", "food")], extraSteps: 3,
              probe: "single-want intensity ramp"),
        .init("mom_hungry", [("mom", "mom", "people"), ("hungry", "hungry", "feeling")], extraSteps: 3,
              probe: "the prompt's anchor example — must not just echo the few-shot"),
        .init("pinkfong_video", [("pinkfong", "pinkfong", "play"), ("video", "video", "play")], extraSteps: 4,
              probe: "PRD pinkfong example, deep ramp"),
        .init("go_home", [("go", "go", "actions"), ("home", "home", "places")], extraSteps: 3,
              probe: "insistence on leaving"),
    ]
}
