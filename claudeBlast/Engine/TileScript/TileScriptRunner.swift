// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptRunner.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import os

/// Execution engine for TileScript playback with debugger-style stepping.
@Observable
@MainActor
final class TileScriptRunner {
    // MARK: - State

    enum State: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    private(set) var state: State = .idle
    private(set) var commandIndex: Int = 0
    private(set) var rowIndex: Int = 0
    private(set) var actionIndex: Int = 0
    private(set) var totalCommands: Int = 0
    private(set) var currentComment: String?
    private(set) var currentScript: TileScript?

    /// The tile row currently being pointed at (for the overlay to render).
    private(set) var currentRow: TileRow?
    /// Total rows in the current tiles command (0 if not in a tiles command).
    private(set) var currentRowCount: Int = 0

    /// Grid tap feedback for playback. `tapPulseKey` is the tile the script just
    /// "tapped"; `tapPulseCount` increments on EVERY tap so repeated taps of the
    /// SAME tile still re-fire the grid tile's bounce — essential for repetition
    /// demos, where the static selection ring doesn't show the mashing.
    private(set) var tapPulseKey: String?
    private(set) var tapPulseCount: Int = 0

    /// Bulk generation progress (completed, total). Nil when not generating.
    private(set) var bulkProgress: (completed: Int, total: Int)?
    /// Number of duplicate combos skipped during bulk generation.
    private(set) var bulkDuplicates: Int = 0

    /// Human-readable description of the current command (non-tiles commands).
    var nextCommandDescription: String? {
        guard let script = currentScript,
              commandIndex < script.commands.count else { return nil }
        let cmd = script.commands[commandIndex]
        if case .tiles = cmd { return nil }
        return describeCommand(cmd)
    }

    // MARK: - Dependencies

    private var engine: SentenceEngine?
    private var coordinator: NavigationCoordinator?
    private var modelContext: ModelContext?
    private var imageResolver: TileImageResolver?
    /// The user's tile set at play time — restored on stop/finish (a tileSet
    /// command is a transient demo change, not a persisted preference).
    private var originalImageSet: ImageSetID?

    // MARK: - Internal

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "claudeBlast", category: "TileScriptRunner")
    private var executionTask: Task<Void, Never>?
    private var pauseContinuation: CheckedContinuation<Void, Never>?

    /// Per-run JSONL event log (Demo Mode only) — a screen-recording alignment aid.
    /// See `TileScriptRunLogger`. `loggingEnabled` is captured at play time.
    private let runLog = TileScriptRunLogger()
    private var loggingEnabled = false

    private var tileWait: TimingValue = .human
    private var sentenceWait: TimingValue = .human

    /// True when the script was started in step/debug mode (playPaused).
    private var startedPaused = false

    /// True when running under the debugger (Step), false for a straight Run.
    /// Demo mode hides the playback pill only on a Run — stepping still needs it.
    var isStepping: Bool { startedPaused }

    /// Voice each word as it's tapped when there's time to hear it: human-paced
    /// tile delays, or any stepping session (the user controls the advance).
    /// Fast/instant auto-runs stay silent per-tile (only the sentence speaks),
    /// to avoid overlapping speech.
    private var voicePerTile: Bool {
        startedPaused || tileWait.duration >= .milliseconds(400)
    }

    /// The mode the script is running in (the engine's override during playback).
    private var activeMode: InteractionMode { engine?.interactionMode ?? .sentence }

    /// The implicit end-of-row terminal token shown in the overlay: Play (sentence
    /// mode) or Clear (single-word mode).
    var terminalToken: String { activeMode == .singleWord ? "\u{2715} Clear" : "\u{25B6} Play" }

    private enum StepMode {
        case stepOver
        case stepInto
        case continueTo
    }
    private var stepMode: StepMode?

    /// Set by the tail of a tiles row that ended with `<tilescript:noclose>`. The next tiles
    /// row will skip its pre-action commit so its tile-adds extend the still-locked active
    /// group (matching the "add a tile to an existing row" demo pattern). Replay rows reset
    /// this back to false.
    private var skipNextPreCommit: Bool = false

    /// Tab switching callback — runner sets this to switch to Home tab on play.
    var onSwitchToHome: (() -> Void)?
    /// Present a named destination. Wired by `ContentView`, which owns the
    /// full-screen cover and the Admin tab selection.
    var onNavigateToScreen: ((ScriptScreen) -> Void)?

    // MARK: - Configuration

    func configure(engine: SentenceEngine, coordinator: NavigationCoordinator,
                   modelContext: ModelContext, resolver: TileImageResolver) {
        self.engine = engine
        self.coordinator = coordinator
        self.modelContext = modelContext
        self.imageResolver = resolver
    }

    // MARK: - Controls

    /// Preflight failure from the last play attempt — the UI shows it, then clears.
    private(set) var validationError: TileScriptValidator.Result?
    func clearValidationError() { validationError = nil }

    func play(script: TileScript) {
        guard state == .idle || state == .finished else { return }
        guard preflightOK(script) else { return }
        startScript(script, paused: false)
    }

    func playPaused(script: TileScript) {
        guard state == .idle || state == .finished else { return }
        guard preflightOK(script) else { return }
        startScript(script, paused: true)
    }

    /// Validate references before playing; on failure record the error (for the
    /// UI) and refuse, rather than play a demo with dropped tiles / dead navs.
    private func preflightOK(_ script: TileScript) -> Bool {
        guard let modelContext else { return true }
        let result = TileScriptValidator.validate(script, context: modelContext)
        validationError = result.isValid ? nil : result
        return result.isValid
    }

    private func startScript(_ script: TileScript, paused: Bool) {
        startedPaused = paused
        originalImageSet = imageResolver?.activeSet
        currentScript = script
        commandIndex = 0
        rowIndex = 0
        actionIndex = 0
        totalCommands = script.commands.count
        currentComment = nil
        currentRow = nil
        currentRowCount = 0
        bulkProgress = nil
        tileWait = script.tileWait
        sentenceWait = script.sentenceWait

        // Start every run from a clean slate: clear the active tray AND the utterance
        // history so a fresh Play doesn't inherit a prior run's committed sentences.
        // Without this, replaying a demo (state .idle/.finished) leaves the previous
        // run's history pills on screen — a spoiler strip that shows the whole demo's
        // punchlines from frame 0. Only stop() reset before; play() didn't.
        engine?.resetAll()

        engine?.audioEnabled = script.audio
        engine?.scriptedModeOverride = script.mode ?? .sentence   // declared mode, else sentence
        if let providerName = script.provider {
            applyProvider(providerName)
        }

        // TODO(single-word mode): TileScript playback assumes sentence/AI mode —
        // if the active child is in `.singleWord` mode, scripts won't generate
        // sentences and playback will misbehave. Before running, capture the
        // device's current interaction mode, force `.sentence`, and restore the
        // captured mode in stop()/finish(). Mirrors how audioEnabled/provider
        // are overridden here for the duration of a script. (Noted 2026-06-23.)

        // Point currentRow at the first tiles row if applicable
        updateCurrentRow()

        loggingEnabled = DemoMode.isOn
        if loggingEnabled {
            runLog.begin(scriptName: script.name)
            if let scene = script.scene { runLog.event("scene", ["name": scene]) }
            runLog.event("mode", ["mode": "\(script.mode ?? .sentence)"])
        }

        if paused {
            state = .paused
        } else {
            state = .running
        }
        onSwitchToHome?()

        executionTask = Task {
            await executeScript(script)
        }
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        engine?.cancelIdleTimer()
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        stepMode = nil
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    func stop() {
        executionTask?.cancel()
        executionTask = nil
        pauseContinuation?.resume()
        pauseContinuation = nil
        state = .idle
        currentScript = nil
        currentComment = nil
        currentRow = nil
        currentRowCount = 0
        bulkProgress = nil
        engine?.scriptedModeOverride = nil
        if let set = originalImageSet { imageResolver?.activeSet = set }
        originalImageSet = nil
        engine?.resetAll()
        if loggingEnabled { runLog.event("stopped"); runLog.finish(); loggingEnabled = false }
    }

    func rewind() {
        let script = currentScript
        stop()
        if let script {
            playPaused(script: script)
        }
    }

    func stepOver() {
        guard state == .paused else { return }
        stepMode = .stepOver
        state = .running
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    func stepInto() {
        guard state == .paused else { return }
        stepMode = .stepInto
        state = .running
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    func continueToEnd() {
        guard state == .paused else { return }
        stepMode = .continueTo
        state = .running
        pauseContinuation?.resume()
        pauseContinuation = nil
    }

    // MARK: - Execution

    private func executeScript(_ script: TileScript) async {
        // Self-contained scene: activate the script's declared scene first so its
        // pages/tiles are present regardless of what was active, then let the
        // board switch settle before the first action.
        if let sceneName = script.scene {
            await activateScene(named: sceneName)
            try? await Task.sleep(for: .milliseconds(350))
        }
        while commandIndex < script.commands.count {
            guard !Task.isCancelled else { break }

            // Pause-before-execute: wait if paused
            if state == .paused {
                await waitForResume()
                if Task.isCancelled { break }
            }

            let command = script.commands[commandIndex]

            // For tiles commands, delegate entirely (it handles its own stepping)
            if case .tiles(let rows) = command {
                await executeTileRows(rows)
                if Task.isCancelled { break }
            } else {
                // Execute non-tiles command
                await executeCommand(command)
                if Task.isCancelled { break }
            }

            // Advance to next command
            commandIndex += 1
            rowIndex = 0
            actionIndex = 0
            updateCurrentRow()

            // In step mode, pause before the next command
            if stepMode == .stepOver || stepMode == .stepInto {
                if commandIndex < script.commands.count {
                    state = .paused
                    stepMode = nil
                    engine?.cancelIdleTimer()
                }
            }
        }

        if !Task.isCancelled {
            // End-of-script cleanup: a tiles or replay row leaves the active group locked. Commit
            // it to history so the tray ends in a clean state (and the final sentence is
            // preserved for inspection / further replays).
            if let engine, !engine.activeGroup.tiles.isEmpty {
                engine.commitActiveAndStartNew()
            }
            engine?.scriptedModeOverride = nil
            if let set = originalImageSet { imageResolver?.activeSet = set }
            originalImageSet = nil
            skipNextPreCommit = false
            currentRow = nil
            currentRowCount = 0
            state = .finished
            if loggingEnabled { runLog.finish(); loggingEnabled = false }
        }
    }

    /// Sync currentRow/currentRowCount from commandIndex + rowIndex.
    private func updateCurrentRow() {
        guard let script = currentScript,
              commandIndex < script.commands.count else {
            currentRow = nil
            currentRowCount = 0
            return
        }
        if case .tiles(let rows) = script.commands[commandIndex] {
            currentRow = rowIndex < rows.count ? rows[rowIndex] : nil
            currentRowCount = rows.count
        } else {
            currentRow = nil
            currentRowCount = 0
        }
    }

    private func executeCommand(_ command: TileScriptCommand) async {
        switch command {
        case .tiles:
            break // handled separately in executeScript

        case .bulkTiles(let spec):
            await executeBulkTiles(spec)

        case .clear:
            engine?.clearSelection()
            if loggingEnabled { runLog.event("cleared") }

        case .comment(let text):
            currentComment = text
            Self.logger.info("TileScript comment: \(text)")
            if loggingEnabled { runLog.event("comment", ["text": text]) }

        case .wait(let duration):
            do { try await Task.sleep(for: duration) } catch { return }

        case .setAudio(let enabled):
            engine?.audioEnabled = enabled

        case .setTileWait(let value):
            tileWait = value

        case .setSentenceWait(let value):
            sentenceWait = value

        case .setDemoMode(let enabled):
            UserDefaults.standard.set(enabled, forKey: AppSettingsKey.demoMode)
            if loggingEnabled { runLog.event("demo", ["enabled": "\(enabled)"]) }

        case .screen(let screen):
            guard let navigate = onNavigateToScreen else {
                Self.logger.error("TileScript: screen: \(screen.description) ignored — no navigator wired")
                if loggingEnabled {
                    runLog.event("screen", ["to": screen.description, "result": "no-navigator"])
                }
                return
            }
            navigate(screen)
            // Presenting a full-screen cover and settling its first layout takes
            // longer than a tile tap, and a `screenshot:` usually follows.
            try? await Task.sleep(for: .milliseconds(450))
            if loggingEnabled { runLog.event("screen", ["to": screen.description]) }

        case .screenshot(let name):
            // One frame of settle time. The command usually follows a state
            // change, and drawHierarchy captures what is on screen *now* —
            // without yielding, that can be the frame before the change lands.
            try? await Task.sleep(for: .milliseconds(120))
            let url = ScreenCapture.capture(named: name)
            if loggingEnabled {
                runLog.event("screenshot", ["name": name,
                                            "file": url?.lastPathComponent ?? "failed"])
            }

        case .setProvider(let name):
            applyProvider(name)

        case .setScene(let name):
            await activateScene(named: name)

        case .setTileSet(let imageSet):
            imageResolver?.activeSet = imageSet
        }
    }

    // MARK: - Tile Row Execution

    private func executeTileRows(_ rows: [TileRow]) async {
        currentRowCount = rows.count

        while rowIndex < rows.count {
            guard !Task.isCancelled else { return }

            currentRow = rows[rowIndex]
            actionIndex = 0

            // In step mode, pause BEFORE executing each row so the user sees what's next
            if state == .paused {
                await waitForResume()
                if Task.isCancelled { return }
            }

            let row = rows[rowIndex]

            if stepMode == .stepInto {
                await executeRowStepInto(row)
            } else {
                await executeRow(row)
            }

            if Task.isCancelled { return }

            rowIndex += 1
            actionIndex = 0

            // Point to next row for display
            if rowIndex < rows.count {
                currentRow = rows[rowIndex]
            }

            // stepOver: pause after executing this row, before the next
            if stepMode == .stepOver {
                if rowIndex < rows.count {
                    state = .paused
                    stepMode = nil
                    engine?.cancelIdleTimer()
                } else {
                    // Last row in block — let executeScript handle the pause
                    // so it can advance commandIndex first
                }
            }
        }

        // continueTo: pause after the entire tiles block
        if stepMode == .continueTo {
            state = .paused
            stepMode = nil
            engine?.cancelIdleTimer()
        }
    }

    /// Execute a row action-by-action, pausing after each for step-into.
    private func executeRowStepInto(_ row: TileRow) async {
        if row.isReplay {
            await executeReplayRow()
            if stepMode == .stepInto {
                state = .paused
                stepMode = nil
            }
            return
        }

        await preCommitIfNeeded()

        let executable = row.executableActions
        while actionIndex < executable.count {
            guard !Task.isCancelled else { return }

            await executeAction(executable[actionIndex])
            actionIndex += 1

            // Pause to show the next step highlighted — including, after the last
            // tile (actionIndex == count), the implicit terminal (Play / Clear) as
            // its own step.
            if stepMode == .stepInto {
                state = .paused
                stepMode = nil
                await waitForResume()
                if Task.isCancelled { return }
            }
        }

        // We paused on the terminal step above; resuming runs it.
        await runTerminal(noclose: row.hasNoclose)
        skipNextPreCommit = row.hasNoclose

        // After the row completes, pause
        if stepMode == .stepInto {
            state = .paused
            stepMode = nil
        }
    }

    private func executeRow(_ row: TileRow) async {
        if row.isReplay {
            await executeReplayRow()
            return
        }

        await preCommitIfNeeded()

        let executable = row.executableActions
        for (i, action) in executable.enumerated() {
            guard !Task.isCancelled else { return }
            actionIndex = i
            await executeAction(action)

            if tileWait.duration > .zero {
                do { try await Task.sleep(for: tileWait.duration) } catch { return }
            }
        }
        actionIndex = executable.count

        await runTerminal(noclose: row.hasNoclose)
        skipNextPreCommit = row.hasNoclose
    }

    /// Commit the active group from a previous row to history before building a fresh tiles
    /// row, so each script-level tiles row produces its own history entry. Skipped when the
    /// previous row ended with `<tilescript:noclose>` (the demo's "extend the open group"
    /// pattern), in which case the new row's tile-adds will extend the still-locked active
    /// group via the engine's locked→unlocked-editable+append path.
    private func preCommitIfNeeded() async {
        guard !skipNextPreCommit, let engine, !engine.activeGroup.tiles.isEmpty else {
            skipNextPreCommit = false
            return
        }
        engine.commitActiveAndStartNew()
        skipNextPreCommit = false
    }

    /// The implicit end-of-row terminal: Play (sentence mode) generates + speaks
    /// the sentence; Clear (single-word) clears the accumulated spoken strip. In
    /// step mode this is its own step (see executeRowStepInto).
    private func runTerminal(noclose: Bool) async {
        if activeMode == .singleWord {
            if noclose { return }   // "+" → keep the strip; the next row continues it
            await clearRow()
        } else {
            await playTilesRow()   // Done is deferred to the next row's preCommit (skipped on noclose)
        }
    }

    /// Single-word terminal: let the strip sit (each word was already voiced as it
    /// landed), then clear it — the implicit end-of-row clear.
    private func clearRow() async {
        guard let engine else { return }
        if sentenceWait.duration > .zero {
            do { try await Task.sleep(for: sentenceWait.duration) } catch { return }
        }
        await waitForSpeech()
        engine.clearStrip()
        if loggingEnabled { runLog.event("strip.cleared") }
        if tileWait.duration > .zero {
            do { try await Task.sleep(for: tileWait.duration) } catch { return }
        }
    }

    /// Tail of a tiles row. Waits `sentenceWait` (the play-button pulse plays during this), then
    /// fires Play (`triggerGo`), waits for the sentence + speech, pauses `tileWait`. The active
    /// group stays locked — it will be committed either by the next tiles row's `preCommit` or
    /// by the end-of-script cleanup.
    private func playTilesRow() async {
        guard let engine else { return }

        if sentenceWait.duration > .zero {
            do { try await Task.sleep(for: sentenceWait.duration) } catch { return }
        }

        // Single-tile rows never trigger generation, so skip the Play. The next pre-commit
        // (or end-of-script cleanup) will flush the single tile to history with the spelled-out
        // fallback sentence.
        if engine.activeGroup.tiles.count >= 2 {
            engine.triggerGo()
            await waitForSentence()
            if loggingEnabled {
                runLog.event("sentence", ["text": engine.generatedSentence ?? "",
                                          "tiles": engine.activeGroup.tiles.map(\.key),
                                          "rep": engine.repetitionCount])
            }
            await waitForSpeech()
            if loggingEnabled { runLog.event("tts.done") }
        }

        if tileWait.duration > .zero {
            do { try await Task.sleep(for: tileWait.duration) } catch { return }
        }
    }

    /// Replay row (`<tilescript:replay>`). Mirrors the user "smashing the Play button on a
    /// locked active group" — just calls `engine.replay()` to escalate the active sentence in
    /// place. No reopen, no extra speech. Active stays locked with the new (escalated) sentence;
    /// the next tiles row's pre-commit (or end-of-script cleanup) will flush it to history.
    private func executeReplayRow() async {
        guard let engine else { return }

        guard engine.canReplay else {
            Self.logger.warning("TileScript: <tilescript:replay> with no locked active group; skipping")
            return
        }

        if tileWait.duration > .zero {
            do { try await Task.sleep(for: tileWait.duration) } catch { return }
        }

        engine.replay()
        await waitForSentence()
        if loggingEnabled {
            runLog.event("escalate", ["text": engine.generatedSentence ?? "",
                                      "tiles": engine.activeGroup.tiles.map(\.key),
                                      "rep": engine.repetitionCount])
        }
        await waitForSpeech()
        if loggingEnabled { runLog.event("tts.done") }

        if tileWait.duration > .zero {
            do { try await Task.sleep(for: tileWait.duration) } catch { return }
        }

        // Replay leaves the active group locked with the escalated sentence. The next tiles row
        // will pre-commit it; we explicitly reset the noclose carry-over because a replay row
        // doesn't propagate the previous tiles row's noclose intent.
        skipNextPreCommit = false
    }

    private func executeAction(_ action: TileAction) async {
        guard let engine, let coordinator else { return }

        switch action {
        case .navigate(let pageKey):
            navigateTo(pageKey, coordinator: coordinator)

        case .tap(let tileKey):
            addTile(tileKey, engine: engine)

        case .audibleNavigate(let pageKey):
            // Audible nav tile: add the tile to the active group AND navigate. The TileModel
            // key matches the page key by convention.
            addTile(pageKey, engine: engine)
            navigateTo(pageKey, coordinator: coordinator)

        case .replay:
            // Dispatched at the row level (executeReplayRow); ignore at action level.
            break

        case .noclose:
            // Metadata marker handled by finishTilesRow; not executed as an action.
            break
        }
    }

    private func navigateTo(_ pageKey: String, coordinator: NavigationCoordinator) {
        if loggingEnabled { runLog.event("navigate", ["page": pageKey]) }
        if pageKey == "home" {
            coordinator.navigateToRoot()
        } else {
            coordinator.navigate(to: pageKey)
        }
    }

    private func addTile(_ tileKey: String, engine: SentenceEngine) {
        guard let modelContext else { return }
        var descriptor = FetchDescriptor<TileModel>(
            predicate: #Predicate { $0.key == tileKey }
        )
        descriptor.fetchLimit = 1
        guard let tile = try? modelContext.fetch(descriptor).first else {
            Self.logger.warning("TileScript: tile '\(tileKey)' not found, skipping")
            return
        }
        if voicePerTile { engine.speakTile(tile.displayName) }   // voice the word as it lands
        engine.addTile(tile)
        // Pulse the tapped tile in the grid so the tap is visible on playback —
        // count bumps every time, so repeated taps of the same tile re-animate.
        tapPulseKey = tileKey
        tapPulseCount += 1
        if loggingEnabled {
            runLog.event("tap", ["key": tileKey, "group": engine.activeGroup.tiles.map(\.key)])
        }
    }

    // MARK: - Sentence / Speech Wait

    private func waitForSpeech() async {
        guard let engine else { return }
        while engine.isSpeaking && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }

    private func waitForSentence() async {
        guard let engine else { return }
        if engine.isWaiting {
            while engine.isWaiting && !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
            }
        }
        while engine.isThinking && !Task.isCancelled {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
    }

    // MARK: - Bulk

    private func executeBulkTiles(_ spec: BulkTileSpec) async {
        guard let modelContext else { return }
        let generator = BulkCacheGenerator(modelContext: modelContext)
        generator.onProgress = { [weak self] completed, duplicates, total in
            self?.bulkProgress = (completed, total)
            self?.bulkDuplicates = duplicates
        }
        bulkProgress = (0, spec.count)
        bulkDuplicates = 0
        await generator.generate(spec: spec)
        // Keep final stats visible until cleared
        bulkProgress = (spec.count, spec.count)
        bulkDuplicates = generator.duplicateCount
    }

    // MARK: - Pause/Resume

    private func waitForResume() async {
        await withCheckedContinuation { continuation in
            pauseContinuation = continuation
        }
    }

    // MARK: - Helpers

    private func applyProvider(_ name: String) {
        switch name.lowercased() {
        case "mock":
            engine?.switchProvider(MockSentenceProvider())
        case "openai":
            if let key = OpenAIKeyVault.currentKey() {
                engine?.switchProvider(OpenAISentenceProvider(apiKey: key))
            }
        default:
            Self.logger.warning("TileScript: unknown provider '\(name)'")
        }
    }

    private func activateScene(named name: String) async {
        guard let modelContext else { return }
        let scenes = (try? modelContext.fetch(FetchDescriptor<BlasterScene>())) ?? []
        guard let target = TileScriptValidator.resolveScene(name, in: scenes) else {
            Self.logger.warning("TileScript: scene '\(name)' not found")
            return
        }
        try? target.activate(context: modelContext)
    }

    // MARK: - Command Description

    private func describeCommand(_ command: TileScriptCommand) -> String {
        switch command {
        case .tiles:
            return "tiles"
        case .bulkTiles(let spec):
            return "bulk: \(spec.count) entries"
        case .clear:
            return "clear"
        case .comment(let text):
            return text
        case .wait(let duration):
            let ms = duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000
            return "wait: \(ms)ms"
        case .setAudio(let enabled):
            return "audio: \(enabled ? "on" : "off")"
        case .setTileWait(let value):
            return "tileWait: \(describeTimingValue(value))"
        case .setSentenceWait(let value):
            return "sentenceWait: \(describeTimingValue(value))"
        case .setProvider(let name):
            return "provider: \(name)"
        case .setScene(let name):
            return "scene: \(name)"
        case .setTileSet(let imageSet):
            return "tileSet: \(imageSet.displayName)"
        case .screenshot(let name):
            return "screenshot: \(name)"
        case .screen(let screen):
            return "screen: \(screen.description)"
        case .setDemoMode(let enabled):
            return "demo: \(enabled ? "on" : "off")"
        }
    }

    private func describeTimingValue(_ value: TimingValue) -> String {
        switch value {
        case .human: return ".human"
        case .fast: return ".fast"
        case .instant: return ".instant"
        case .explicit(let ms): return "\(ms)ms"
        }
    }
}
