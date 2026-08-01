// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptRecorderTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

/// Tests for TileScriptRecorder under the new tile-group / explicit-Play model.
///
/// DSL tokens in the input string (comma-separated):
/// - `<page>`     → recordNavigate(page)
/// - `tile`       → engine.addTile + recordTap (audible tile)
/// - `~tile~`     → engine.removeTile (no recorder call; mirrors a remove via the chip tap)
/// - `*play*`     → recorder.recordPlay()  (user taps Play on an unlocked group)
/// - `*replay*`   → recorder.recordReplay() (user taps Play on a locked group or history chip)
/// - `*done*`     → engine.commitActiveAndStartNew() (user taps Done OR auto-Done fires)
extension SerialTests {
@MainActor
@Suite(.serialized)
struct TileScriptRecorderTests {

    private func makeTestContainer() throws -> ModelContainer {
        return TestStore.freshContainer()
    }

    /// Parse a DSL string and drive the recorder + engine.
    /// Returns the row strings from the resulting TileScript.
    private func runRecording(_ input: String) throws -> [String] {
        let container = try makeTestContainer()
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: container.mainContext)

        let recorder = TileScriptRecorder()
        recorder.configure(engine: engine, runner: TileScriptRunner(), coordinator: NavigationCoordinator())
        recorder.startRecording(sceneName: "Default")

        let tokens = input.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        for token in tokens {
            if token == "*play*" {
                recorder.recordPlay()
            } else if token == "*replay*" {
                recorder.recordReplay()
            } else if token == "*done*" {
                engine.commitActiveAndStartNew()
            } else if token.hasPrefix("~") && token.hasSuffix("~") {
                let key = String(token.dropFirst().dropLast())
                if let index = engine.selectedTiles.firstIndex(where: { $0.key == key }) {
                    engine.removeTile(at: index)
                }
            } else if token.hasPrefix("<") && token.hasSuffix(">") {
                let pageKey = String(token.dropFirst().dropLast())
                recorder.recordNavigate(pageKey: pageKey)
            } else {
                let tile = TileModel(key: token, wordClass: "actions")
                engine.addTile(tile)
                recorder.recordTap(tileKey: token)
            }
        }

        recorder.stopRecording()
        guard let script = recorder.lastRecordedScript else { return [] }

        var rows: [String] = []
        for command in script.commands {
            if case .tiles(let tileRows) = command {
                for row in tileRows {
                    rows.append(row.rawText)
                }
            }
        }
        return rows
    }

    // MARK: - Basic cases

    @Test func buildPlayProducesTilesRow() throws {
        let rows = try runRecording("mom, pizza, *play*")
        #expect(rows.count == 1)
        #expect(rows[0] == "mom, pizza")
    }

    @Test func navsAndTilesPlay() throws {
        let rows = try runRecording("<home>, mom, <food>, pizza, *play*")
        #expect(rows.count == 1)
        #expect(rows[0] == "<home>, mom, <food>, pizza")
    }

    @Test func noPlayProducesRowOnStopAsSafetyNet() throws {
        // The user built tiles and tapped Stop without first tapping Play. The recorder
        // finalizes the current state as a trailing row so the recording matches what was
        // on-screen at stop time.
        let rows = try runRecording("mom, pizza")
        #expect(rows.count == 1)
        #expect(rows[0] == "mom, pizza")
    }

    @Test func stopAfterPlayDoesNotDuplicateRow() throws {
        // Stop right after a Play tap. The Play already captured the row; the safety net at
        // stopRecording should not emit a duplicate.
        let rows = try runRecording("mom, pizza, *play*")
        #expect(rows.count == 1)
        #expect(rows[0] == "mom, pizza")
    }

    @Test func stopAfterExtendingPlayedGroup() throws {
        // The user Played [mom, pizza], then added fries, then Stopped without Playing again.
        // The safety net should capture the extended state as a second row.
        let rows = try runRecording("mom, pizza, *play*, fries")
        #expect(rows.count == 2)
        #expect(rows[0] == "mom, pizza")
        #expect(rows[1] == "mom, pizza, fries")
    }

    @Test func emptyRecording() throws {
        let container = try makeTestContainer()
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: container.mainContext)

        let recorder = TileScriptRecorder()
        recorder.configure(engine: engine, runner: TileScriptRunner(), coordinator: NavigationCoordinator())
        recorder.startRecording(sceneName: "Default")
        recorder.stopRecording()

        #expect(recorder.lastRecordedScript?.commands.isEmpty == true)
    }

    // MARK: - Multi-row flows

    @Test func doneBetweenRowsClearsCarryOver() throws {
        // Two complete utterances, separated by an explicit Done.
        let rows = try runRecording("mom, pizza, *play*, *done*, dad, fries, *play*")
        #expect(rows.count == 2)
        #expect(rows[0] == "mom, pizza")
        #expect(rows[1] == "dad, fries")
    }

    @Test func twoPlaysExtendRow() throws {
        // No Done between two Plays — the user kept adding to the same active group. Each Play
        // snapshots the current tile set, so row 2 includes everything from row 1 plus the new
        // tile (matches the playback behavior where each tiles row builds from scratch).
        let rows = try runRecording("mom, pizza, *play*, fries, *play*")
        #expect(rows.count == 2)
        #expect(rows[0] == "mom, pizza")
        #expect(rows[1] == "mom, pizza, fries")
    }

    @Test func removedTileExcludedFromSnapshot() throws {
        // Build mom + pizza, then remove pizza before tapping Play. Row should contain only mom.
        let rows = try runRecording("mom, pizza, ~pizza~, *play*")
        #expect(rows.count == 1)
        #expect(rows[0] == "mom")
    }

    @Test func removedTileMidFlow() throws {
        // Play with both tiles, then remove one, Play again. Row 2 should reflect the smaller set.
        let rows = try runRecording("mom, pizza, *play*, ~pizza~, *play*")
        #expect(rows.count == 2)
        #expect(rows[0] == "mom, pizza")
        #expect(rows[1] == "mom")
    }

    // MARK: - Replay

    @Test func replayEmitsReplayRow() throws {
        let rows = try runRecording("mom, pizza, *play*, *replay*")
        #expect(rows.count == 2)
        #expect(rows[0] == "mom, pizza")
        #expect(rows[1] == "<tilescript:replay>")
    }

    @Test func replayWithoutPriorPlay() throws {
        // Replay tap before any tiles row. The recorder still emits a replay row; runtime will
        // log a warning when the script is played (no history to replay) but the recording is
        // structurally valid.
        let rows = try runRecording("*replay*")
        #expect(rows.count == 1)
        #expect(rows[0] == "<tilescript:replay>")
    }

    @Test func twoReplaysAfterPlay() throws {
        let rows = try runRecording("mom, pizza, *play*, *replay*, *replay*")
        #expect(rows.count == 3)
        #expect(rows[0] == "mom, pizza")
        #expect(rows[1] == "<tilescript:replay>")
        #expect(rows[2] == "<tilescript:replay>")
    }

    // MARK: - Serialization

    @Test func noCommentsInOutput() throws {
        let container = try makeTestContainer()
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: container.mainContext)
        let recorder = TileScriptRecorder()
        recorder.configure(engine: engine, runner: TileScriptRunner(), coordinator: NavigationCoordinator())
        recorder.startRecording(sceneName: "Default")

        for token in ["mom", "pizza"] {
            let tile = TileModel(key: token, wordClass: "actions")
            engine.addTile(tile)
            recorder.recordTap(tileKey: token)
        }
        recorder.recordPlay()

        recorder.stopRecording()
        let yaml = TileScriptSerializer.serialize(recorder.lastRecordedScript!)
        #expect(!yaml.contains("#"))
    }

    // MARK: - Audible nav + noclose grammar

    @Test func parserRecognizesAudibleNavigate() {
        let row = TileScriptParser.parseTileRow("<home>, <drinks isAudible=t/>, water")
        #expect(row.actions.count == 3)
        if case .navigate(let key) = row.actions[0] {
            #expect(key == "home")
        } else {
            Issue.record("first action should be .navigate")
        }
        if case .audibleNavigate(let key) = row.actions[1] {
            #expect(key == "drinks")
        } else {
            Issue.record("second action should be .audibleNavigate")
        }
        if case .tap(let key) = row.actions[2] {
            #expect(key == "water")
        } else {
            Issue.record("third action should be .tap")
        }
    }

    @Test func parserRecognizesNoclose() {
        let row = TileScriptParser.parseTileRow("mom, pizza, <tilescript:noclose>")
        #expect(row.actions.count == 3)
        #expect(row.hasNoclose == true)
        #expect(row.executableActions.count == 2)
    }

    @Test func parserAcceptsIsAudibleVariants() {
        // Various forms of the boolean value should all parse as audible.
        for token in ["<drinks isAudible=t/>", "<drinks isAudible=true>",
                      "<drinks isAudible=\"true\"/>", "<drinks isAudible=yes/>"] {
            let row = TileScriptParser.parseTileRow(token)
            #expect(row.actions.count == 1)
            if case .audibleNavigate(let key) = row.actions.first {
                #expect(key == "drinks")
            } else {
                Issue.record("token \(token) should parse as .audibleNavigate")
            }
        }
    }

    @Test func serializerRendersNewActions() {
        let actions: [TileAction] = [
            .navigate(pageKey: "home"),
            .audibleNavigate(pageKey: "drinks"),
            .tap(tileKey: "water"),
            .noclose,
        ]
        let row = TileRow(actions: actions, rawText: "", comment: nil)
        let script = TileScript(
            name: "test",
            description: "",
            audio: true,
            tileWait: .human,
            sentenceWait: .human,
            provider: nil,
            scene: nil,
            mode: nil,
            commands: [.tiles(rows: [row])]
        )
        let yaml = TileScriptSerializer.serialize(script)
        #expect(yaml.contains("<home>"))
        #expect(yaml.contains("<drinks isAudible=t/>"))
        #expect(yaml.contains("water"))
        #expect(yaml.contains("<tilescript:noclose>"))
    }

    @Test func replayRowRoundTrips() throws {
        // Build a script with a replay row, serialize, parse back, and verify the action is preserved.
        let container = try makeTestContainer()
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: container.mainContext)
        let recorder = TileScriptRecorder()
        recorder.configure(engine: engine, runner: TileScriptRunner(), coordinator: NavigationCoordinator())
        recorder.startRecording(sceneName: "Default")

        for token in ["mom", "pizza"] {
            let tile = TileModel(key: token, wordClass: "actions")
            engine.addTile(tile)
            recorder.recordTap(tileKey: token)
        }
        recorder.recordPlay()
        recorder.recordReplay()
        recorder.stopRecording()

        let yaml = TileScriptSerializer.serialize(recorder.lastRecordedScript!)
        #expect(yaml.contains("<tilescript:replay>"))

        // Round-trip
        let parsed = try TileScriptParser.parse(yaml)
        guard case .tiles(let rows) = parsed.commands.first(where: { if case .tiles = $0 { return true } else { return false } }) else {
            Issue.record("Parsed script has no tiles command")
            return
        }
        #expect(rows.count == 2)
        #expect(rows[0].isReplay == false)
        #expect(rows[1].isReplay == true)
    }
}
}
