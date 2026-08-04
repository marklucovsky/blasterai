// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentenceEngine.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import os

struct HistoryEntry: Identifiable {
    let id = UUID()
    let tiles: [TileSelection]
    let sentence: String
    let timestamp: Date
}

@Observable
@MainActor
final class SentenceEngine {
    // MARK: - Published state

    /// The rightmost (in-progress or just-spoken) group. Always present, may be empty.
    private(set) var activeGroup: TileGroup = TileGroup()

    /// Newest-first rolling buffer of closed groups (newest at index 0). Capped by trayBufferSize.
    private(set) var groupHistory: [TileGroup] = []

    private(set) var isThinking: Bool = false
    private(set) var isWaiting: Bool = false
    /// True after the idle wait has elapsed AND the active group is not yet locked. Drives the
    /// play-button rainbow pulse — only nags the user when tiles have changed and a sentence
    /// hasn't been generated. Cleared when the user adds/removes a tile, taps Go, or generates.
    private(set) var isIdleNudge: Bool = false
    /// Fires `doneAttentionLead` seconds after the active group locks (post-Play). Resets on any
    /// tile add/remove or fresh Play, since those re-arm the idle timer task and reset the
    /// flag. The Done button drives its own escalating animation (blue → green → red, ramping
    /// in border / weight / shadow) internally once this flips true.
    private(set) var isDoneNudge: Bool = false
    private(set) var comparisonSentence: String?
    var sessionNotes: String = ""

    /// Single-word (classic AAC) mode only: the running FIFO strip of spoken
    /// words, oldest first. New words append on the right; once it exceeds
    /// `spokenStripCap` the oldest drops off the left. Duplicates are allowed —
    /// tapping `dad` twice yields `[dad, dad]`. Empty / unused in sentence mode.
    private(set) var spokenStrip: [TileSelection] = []

    /// Hard cap on the FIFO strip so it can't grow unbounded; the view shows a
    /// rolling window and older words scroll off as new ones arrive.
    private let spokenStripCap = 20

    // MARK: - Backwards-compatible accessors

    /// The active group's tiles. Used by views built before the timeline refactor.
    var selectedTiles: [TileSelection] { activeGroup.tiles }

    /// The active group's generated sentence (or single-tile preview).
    var generatedSentence: String? { activeGroup.sentence }

    /// Closed groups exposed as legacy HistoryEntry items for the (soon-to-be-retired) history sheet.
    var recentHistory: [HistoryEntry] {
        groupHistory.prefix(maxHistorySheetEntries).compactMap { group in
            guard let sentence = group.sentence else { return nil }
            return HistoryEntry(tiles: group.tiles, sentence: sentence, timestamp: group.createdAt)
        }
    }

    /// Called with the active group's generatedSentence just before the group is flushed to history
    /// or the engine is reset. Used by TileScriptRecorder to finalize the current row.
    var onWillClear: ((String?) -> Void)?

    /// Called when a real multi-tile sentence is generated (from cache or API, 2+ tiles).
    /// Single-tile display names do NOT trigger this.
    var onSentenceReady: ((String) -> Void)?

    var isSpeaking: Bool { speechSynthesizer.isSpeaking }

    func appendNote(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !sessionNotes.isEmpty { sessionNotes += "\n" }
        sessionNotes += trimmed
    }

    // MARK: - Configuration

    private(set) var provider: any SentenceProvider
    var audioEnabled: Bool = true
    var voiceIdentifier: String = ""
    var compareProviders: Bool = false

    /// Max tiles per group. Prefers the active `ChildProfile.maxSelectedTiles`
    /// when the resolver has resolved one; otherwise falls back to the
    /// device-wide `tile_cap_per_group` UserDefault for backward compat
    /// with installs that haven't completed onboarding yet.
    var maxTilesPerGroup: Int {
        if let resolver = profileResolver, resolver.active != nil {
            let cap = resolver.maxSelectedTiles
            return (2...8).contains(cap) ? cap : 4
        }
        let stored = UserDefaults.standard.integer(forKey: AppSettingsKey.tileCapPerGroup)
        return (2...8).contains(stored) ? stored : 4
    }

    /// When set (during scripted TileScript playback), overrides the active
    /// child's interaction mode for the demo's duration, so a script can declare
    /// which mode it demonstrates. The runner sets it on play and clears it on
    /// stop/finish — transient, no model mutation, so it auto-restores.
    var scriptedModeOverride: InteractionMode? = nil

    /// Active child's interaction mode (AI sentences vs. classic single words).
    /// Defaults to `.sentence` before the resolver is wired or pre-onboarding.
    var interactionMode: InteractionMode {
        scriptedModeOverride ?? (profileResolver?.interactionMode ?? .sentence)
    }

    /// Idle debounce before auto-generation; backed by AppStorage.
    var idleDebounceDuration: Duration {
        let ms = UserDefaults.standard.integer(forKey: AppSettingsKey.idleDebounceMs)
        let clamped = (500...5000).contains(ms) ? ms : 2500
        return .milliseconds(clamped)
    }

    /// Max number of closed groups retained in groupHistory; backed by AppStorage.
    var trayBufferSize: Int {
        let stored = UserDefaults.standard.integer(forKey: AppSettingsKey.trayBufferSize)
        return (50...500).contains(stored) ? stored : 100
    }

    /// Long idle timeout that auto-commits the active group to history (auto-Done). 0 disables.
    /// Default 30s if no value stored, clamped to 5s..2min when set.
    var autoDoneDuration: Duration {
        let ms = UserDefaults.standard.integer(forKey: AppSettingsKey.autoDoneMs)
        if ms == 0 { return .seconds(0) }
        let clamped = (5000...120000).contains(ms) ? ms : 30000
        return .milliseconds(clamped)
    }

    // MARK: - Dependencies

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "claudeBlast", category: "SentenceEngine")
    private var cacheManager: SentenceCacheManager?
    private let speechSynthesizer = SpeechSynthesizer()
    /// Active-child resolver wired in `configure(modelContext:resolver:)`.
    /// `nil` until configured — `maxTilesPerGroup` and `speak()` handle that
    /// with UserDefaults fallbacks.
    private(set) var profileResolver: ChildProfileResolver?

    // MARK: - Internal state

    /// The idle / auto-advance timeline (pulse → Done attention → auto-Done). Owns
    /// ONLY idle timing — never an in-flight request — so re-arming it can't cancel
    /// a generation. Paired with `generationTask` below; keeping them on separate
    /// handles is what removes the "cancelling the timer cancels the request" bug.
    private var idleTask: Task<Void, Never>?
    /// The in-flight sentence generation, if any. Cancelled only when a newer
    /// request supersedes it or the active group is cleared — never by idle timing.
    private var generationTask: Task<Void, Never>?

    /// Launch a generation, superseding any prior request and stopping idle timing.
    /// The generation's own completion re-arms the idle timers (via `generate`).
    private func launchGeneration(_ operation: @escaping () async -> Void) {
        idleTask?.cancel()
        generationTask?.cancel()
        generationTask = Task { await operation() }
    }
    /// Number of consecutive replays / repeats on the current active group.
    /// Resets when the user starts a new selection. Surfaced to the UI as
    /// the escalation counter next to the play button's replay badge.
    private(set) var repetitionCount: Int = 0
    private var lastTileKey: String?
    private let maxConversationHistory = 5
    private let maxHistorySheetEntries = 10

    /// Last N generated sentences fed back as conversational context to the model.
    private var conversationHistory: [String] {
        Array(
            groupHistory
                .compactMap { $0.sentence }
                .prefix(maxConversationHistory)
                .reversed()
        )
    }

    // MARK: - Init

    init(provider: any SentenceProvider) {
        self.provider = provider
    }

    /// Must be called after init to wire up SwiftData cache. Pass the shared
    /// `ChildProfileResolver` so the engine reads age, voice, and tile cap
    /// from the active child instead of UserDefaults.
    func configure(modelContext: ModelContext, profileResolver: ChildProfileResolver? = nil) {
        self.cacheManager = SentenceCacheManager(modelContext: modelContext)
        self.profileResolver = profileResolver
    }

    // MARK: - Provider switching

    func switchProvider(_ newProvider: any SentenceProvider) {
        resetAll()
        provider = newProvider
    }

    // MARK: - Tile management

    /// Add a tile in response to a grid tap.
    ///
    /// Single-word mode routes to the FIFO spoken strip (duplicates allowed).
    ///
    /// Sentence mode: a grid tap **adds, never deletes** (the universal rule —
    /// re-tapping a tile already in the group is a no-op; remove it by tapping
    /// its tray chip). If there's room under the cap the tile is appended; a
    /// locked group transitions to `.unlockedEditable` (its sentence is now
    /// stale) and the idle timers restart. At cap the tap is ignored.
    func addTile(_ tile: TileModel) {
        // A grid tap resumes normal flow — clears any lingering edit-pause left by
        // a bubble long-press the caregiver dismissed without acting.
        caregiverEditing = false
        if interactionMode == .singleWord {
            appendSpokenWord(tile)
            return
        }

        let selection = TileSelection(from: tile)

        // Mash-to-escalate: re-tapping the MOST RECENT tile is the child turning
        // up the volume ("she really means chocolate"). Route it into the
        // escalation machinery instead of the old no-op — mashing the tile on the
        // grid now raises urgency, the same signal as repeatedly hitting Play/Done.
        if activeGroup.tiles.last?.key == selection.key {
            mashEscalate()
            return
        }

        // Universal: adds, never deletes. Re-tapping a present (non-last) tile is
        // a no-op (no toggle-off, no duplicate). Removal happens from the tray chip.
        if activeGroup.tiles.contains(where: { $0.key == selection.key }) { return }

        guard activeGroup.tiles.count < maxTilesPerGroup else { return }

        // Locked → unlocked: the stale sentence will be cleared by scheduleGeneration().
        if activeGroup.state == .locked {
            activeGroup.state = .unlockedEditable
        }

        activeGroup.tiles.append(selection)
        refreshActiveSuppressed()   // re-detect a suppressed combo as it's rebuilt
        cacheManager?.logEvent(subjectType: "tile", subjectKey: tile.key, eventType: .selected)
        scheduleGeneration()
    }

    /// A grid tap on the most-recent tile — the "mash the tile harder" volume
    /// knob. A lone tile bumps its repeat count and re-speaks the word; a 2+ tile
    /// group generates if it hasn't locked yet, then escalates (rising urgency)
    /// on each further mash. Ignored while a generation is already in flight so
    /// rapid taps debounce naturally.
    private func mashEscalate() {
        guard !isThinking else { return }
        if activeGroup.tiles.count == 1 {
            // A lone tile has no sentence to escalate — a mash just re-speaks the
            // word ("say it again"). Do NOT populate the sentence bubble with the
            // raw word (that read as a bogus one-word "sentence").
            if let tile = activeGroup.tiles.first { speakTile(tile.value) }
        } else if canReplay {
            replay()
        } else if activeGroup.tiles.count >= 2 {
            triggerGo()
        }
    }

    // MARK: - Single-word (classic AAC) strip

    /// Append a spoken word to the FIFO strip (single-word mode). Duplicates are
    /// allowed; the oldest word drops off once the cap is exceeded. Each word is
    /// logged as its own utterance so the therapist activity log stays
    /// meaningful in this mode. Speech itself is driven by the grid tap (the
    /// view), so this is data-only and won't double-speak.
    private func appendSpokenWord(_ tile: TileModel) {
        let selection = TileSelection(from: tile)

        // Mash-to-escalate: re-tapping the same word bumps a run count on the last
        // strip tile (surfaced as an escalation badge) instead of flooding the
        // strip with duplicates. The grid tap still speaks the word (view-driven),
        // so the child hears each insistent tap; the strip just stops growing.
        if spokenStrip.last?.key == selection.key {
            repetitionCount += 1
            lastTileKey = selection.key
            cacheManager?.logEvent(subjectType: "tile", subjectKey: tile.key, eventType: .selected)
            return
        }

        // A different word starts a fresh run — reset the escalation counter.
        repetitionCount = 0
        lastTileKey = selection.key
        spokenStrip.append(selection)
        if spokenStrip.count > spokenStripCap {
            spokenStrip.removeFirst(spokenStrip.count - spokenStripCap)
        }
        cacheManager?.logEvent(subjectType: "tile", subjectKey: tile.key, eventType: .selected)
        cacheManager?.logUtterance(
            tiles: [selection],
            sentence: selection.value,
            repetitionCount: 0,
            childID: profileResolver?.activeChildID
        )
    }

    /// Remove one word from the FIFO strip (tapping its chip in the strip).
    func removeStripWord(at index: Int) {
        guard spokenStrip.indices.contains(index) else { return }
        spokenStrip.remove(at: index)
        // Editing the strip ends the current escalation run.
        repetitionCount = 0
        lastTileKey = nil
    }

    /// Clear the entire spoken strip (the strip's ✕ button).
    func clearStrip() {
        spokenStrip.removeAll()
        repetitionCount = 0
        lastTileKey = nil
    }

    /// Remove a tile from the active group.
    /// - From a locked group: transitions to .unlockedEditable; the stale sentence stays visible
    ///   until the next generation completes.
    /// - From an editable group: simply removes and reschedules generation.
    func removeTile(at index: Int) {
        guard activeGroup.tiles.indices.contains(index) else { return }

        let wasLocked = activeGroup.state == .locked
        activeGroup.tiles.remove(at: index)
        refreshActiveSuppressed()   // combo changed → may no longer be suppressed

        if wasLocked {
            activeGroup.state = .unlockedEditable
        }

        if activeGroup.tiles.isEmpty {
            idleTask?.cancel()
            generationTask?.cancel()
            activeGroup.sentence = nil
            activeGroup.state = .building
            comparisonSentence = nil
            isThinking = false
            isWaiting = false
            isIdleNudge = false
            isDoneNudge = false
            speechSynthesizer.stop()
        } else {
            scheduleGeneration()
        }
    }

    /// Explicit "Go" tap — generate immediately. The default path now (auto-generation on idle is
    /// disabled except at cap). No-op if there aren't enough tiles or the group is already locked.
    func triggerGo() {
        guard activeGroup.tiles.count >= 2 else { return }
        guard activeGroup.state != .locked else { return }

        isWaiting = true
        isIdleNudge = false
        isDoneNudge = false

        let tilesSnapshot = activeGroup.tiles
        let repetition = updateRepetitionState(for: tilesSnapshot)
        launchGeneration { [weak self] in
            await self?.generate(tiles: tilesSnapshot, repetition: repetition)
        }
    }

    // MARK: - Caregiver refinement (refine / hand-type / suppress)

    /// True while the caregiver is interacting with the sentence bubble (long-press
    /// menu open, or a refine / hand-type sheet up). Pauses auto-advance so the
    /// idle pulse + auto-Done timeout can't clear the tray and lose the tiles or
    /// the original sentence a refine/hand-type depends on — or the text being typed.
    private var caregiverEditing = false

    /// Pause auto-advance (call when the bubble long-press / edit sheet opens).
    /// Only stops idle timing; an in-flight generation (`generationTask`) is
    /// untouched.
    func beginCaregiverEdit() {
        caregiverEditing = true
        idleTask?.cancel()
        isIdleNudge = false
        isDoneNudge = false
    }

    /// Resume auto-advance (call when the caregiver finishes / the sheet dismisses).
    /// `startIdleTimers` only touches `idleTask`, so this can no longer cancel an
    /// in-flight refine/un-suppress; and it self-guards on `isThinking`, so if a
    /// generation is running the timers simply re-arm when it completes.
    func endCaregiverEdit() {
        caregiverEditing = false
        startIdleTimers()
    }

    /// Refine: regenerate the active sentence with a caregiver `instruction`
    /// (e.g. "make it shorter", "she's asking, not telling") plus the sentence
    /// they're reacting to, so the model revises rather than blindly rerolls.
    /// Bypasses cache/override, and keeps the fresh result as a durable (pinned)
    /// accepted-refine override. An empty instruction is a plain try-again.
    func refineActive(instruction: String) {
        let tiles = activeGroup.tiles
        guard tiles.count >= 2 else { return }
        let original = activeGroup.sentence
        isThinking = true
        isIdleNudge = false
        isDoneNudge = false
        launchGeneration { [weak self] in
            await self?.generate(tiles: tiles, repetition: 0, refine: true,
                                 refineInstruction: instruction, originalSentence: original)
        }
    }

    /// Replace the active sentence with a caregiver-typed one and store it as a
    /// durable, authoritative override for this tile combination + child.
    func handTypeActive(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let tiles = activeGroup.tiles
        guard !trimmed.isEmpty, !tiles.isEmpty else { return }
        cacheManager?.setHandTyped(tiles: tiles, grade: currentGrade, sentence: trimmed,
                                   childID: profileResolver?.activeChildID)
        activeGroup.sentence = trimmed
        activeGroup.state = .locked
        onSentenceReady?(trimmed)
        speak(trimmed)
        startIdleTimers()
    }

    /// True when the active tile combination is a caregiver-suppressed (blocked)
    /// set — the tray shows a muted bubble that long-presses to un-suppress.
    /// CACHED: recomputed only on combo/override changes (`refreshActiveSuppressed`),
    /// never on render, so the tray view doesn't fetch SwiftData every frame.
    private(set) var activeIsSuppressed = false

    /// Recompute `activeIsSuppressed` from the current combo + override store.
    /// Called whenever the active tiles or their override state change.
    private func refreshActiveSuppressed() {
        activeIsSuppressed = !activeGroup.tiles.isEmpty
            && cacheManager?.overrideLookup(tiles: activeGroup.tiles,
                                            childID: profileResolver?.activeChildID)?.isSuppressed == true
    }

    /// Un-suppress the active combination: clear the block and regenerate a fresh
    /// sentence so the caregiver immediately sees it restored.
    func unsuppressActive() {
        let tiles = activeGroup.tiles
        guard !tiles.isEmpty else { return }
        cacheManager?.clearOverride(tiles: tiles, childID: profileResolver?.activeChildID)
        activeIsSuppressed = false
        isThinking = true
        isIdleNudge = false
        launchGeneration { [weak self] in
            await self?.generate(tiles: tiles, repetition: 0)
        }
    }

    /// Suppress the active tile combination: a HARD BLOCK — this set never speaks
    /// a generated sentence again (it shows the tiles only). Drops any matching
    /// history bubble so a suppressed set can't be replayed, and clears the active
    /// sentence. Reversible via a later refine/hand-type (or the admin manager).
    func suppressActive() {
        let tiles = activeGroup.tiles
        guard !tiles.isEmpty else { return }
        cacheManager?.setSuppressed(tiles: tiles, grade: currentGrade,
                                    childID: profileResolver?.activeChildID)
        speechSynthesizer.stop()
        let keys = Set(tiles.map(\.key))
        groupHistory.removeAll { Set($0.tiles.map(\.key)) == keys }
        activeGroup.sentence = nil
        activeGroup.state = .locked
        activeIsSuppressed = true
    }

    /// Clear the active group (no history change). Used by scene switching, the bubble's "×"
    /// dismiss, and speakPromoted's overwrite path. Fires onWillClear so script recording can
    /// finalize the row.
    func clearSelection() {
        onWillClear?(activeGroup.sentence)
        idleTask?.cancel()
        generationTask?.cancel()
        activeGroup = TileGroup()
        activeIsSuppressed = false
        comparisonSentence = nil
        isThinking = false
        isWaiting = false
        isIdleNudge = false
        isDoneNudge = false
        // Preserve repetitionCount and lastTileKey so escalation works across clear cycles
        // (e.g., TileScript rows). They reset naturally when a different combo is selected.
        speechSynthesizer.stop()
    }

    /// Full reset: clear active group AND history AND escalation state.
    /// Used by AdminView "Reset session" and by switchProvider.
    func resetAll() {
        clearSelection()
        groupHistory.removeAll()
        spokenStrip.removeAll()
        repetitionCount = 0
        lastTileKey = nil
    }

    /// Admin-only: reset the visible session (active + history).
    func resetSession() {
        resetAll()
    }

    // MARK: - Replay

    var canReplay: Bool {
        // 2+ tiles only: a single word has no generated sentence to replay or
        // escalate, so a locked single-tile group stays in the cancel-✕ path
        // rather than showing Play + a stale escalation badge.
        activeGroup.state == .locked && activeGroup.sentence != nil
            && activeGroup.tiles.count >= 2 && !isThinking
    }

    /// Replay the active group's sentence using escalation (repetition increments, cache bypassed).
    /// Only valid when the active group is locked.
    func replay() {
        guard canReplay else { return }
        repetitionCount += 1
        let tilesSnapshot = activeGroup.tiles
        let repetition = repetitionCount
        // Set isThinking synchronously so external observers (notably TileScriptRunner.waitFor-
        // Sentence) can race-freely detect that generation is in flight. generate() will also set
        // it at its top; the redundant assignment is harmless.
        isThinking = true
        isIdleNudge = false
        launchGeneration { [weak self] in
            await self?.generate(tiles: tilesSnapshot, repetition: repetition)
        }
    }

    /// Speak the lone selected tile, counting repeats — the "mashing the
    /// chocolate tile when she really wants chocolate" volume knob applied to a
    /// single word. Wired to the repurposed Done-slot control when one tile is
    /// active. It only ever says the *raw word*: a single tile is never run
    /// through the sentence model. Generating from one word produced odd,
    /// context-bled results (escalating "sick", clearing, then playing "down"
    /// yielded "I feel sick down"), and a single word should stay literal.
    /// Repeated presses bump the count (surfaced as the button's badge — the
    /// visible "how insistent" signal; prosody escalation is a later step) and
    /// re-arm the idle timers so the mashed tile stays alive.
    func playSingleTile() {
        guard activeGroup.tiles.count == 1, let tile = activeGroup.tiles.first else { return }
        // Bump the repeat count for the badge; a different tile resets it.
        _ = updateRepetitionState(for: activeGroup.tiles)
        // Lock with the word as its own "sentence" so the badge gating
        // (locked → show count) distinguishes a played tile from a freshly
        // selected one. Single tiles never flush to history (see
        // flushActiveToHistory), so this is display-only.
        activeGroup.sentence = tile.value
        activeGroup.state = .locked
        isIdleNudge = false
        speak(tile.value)
        startIdleTimers()
    }

    // MARK: - History group interactions

    /// Speak + reopen an older history group. The current active group flushes to history first,
    /// then the target group is promoted to the active slot as .unlockedEditable so it can be
    /// further edited.
    func reopenHistoryGroup(id: UUID) {
        // Verify target exists before doing any work — but DON'T cache its index here.
        // flushActiveToHistory() may prepend the current active to history and shift indices.
        guard groupHistory.contains(where: { $0.id == id }) else { return }
        flushActiveToHistory()

        guard let index = groupHistory.firstIndex(where: { $0.id == id }) else { return }
        var target = groupHistory.remove(at: index)

        // Re-resolve against durable overrides so a hand-typed / accepted edit — or
        // a suppression — applied AFTER this group was closed is honored on replay,
        // instead of speaking the stale stored snapshot.
        let override = cacheManager?.overrideLookup(tiles: target.tiles,
                                                    childID: profileResolver?.activeChildID)
        let suppressed = override?.isSuppressed == true
        activeIsSuppressed = suppressed
        if suppressed {
            // Suppressed set: reopen for editing, show tiles only, say nothing.
            target.sentence = nil
            target.state = .unlockedEditable
            activeGroup = target
            startIdleTimers()
            return
        }

        if let sentence = override?.sentence ?? target.sentence {
            // Reopening a group with a sentence is equivalent to a fresh Play: lock the group
            // and speak it. The startIdleTimers task below will see state == .locked, skip the
            // play-button pulse (no nag — the user just heard it), and fire the Done attention
            // ramp + auto-Done as if the user had just tapped Play. Adding a new tile later
            // unlocks and clears the sentence as usual via addTile().
            if let override {
                override.hitCount += 1
                override.lastUsed = .now
            }
            target.sentence = sentence
            target.state = .locked
            activeGroup = target
            speak(sentence)
        } else {
            // No sentence on the history entry (defensive — current code always assigns one).
            // Treat as editable so the user can keep building.
            target.state = .unlockedEditable
            activeGroup = target
        }

        startIdleTimers()
    }


    /// Delete a history group. Power-user gesture, surfaced in PR2 UI.
    func deleteHistoryGroup(id: UUID) {
        groupHistory.removeAll { $0.id == id }
    }

    /// Legacy history-sheet replay path. Reconstructs an old utterance into the active group.
    /// Kept for any callers that still bind to HistoryEntry; will be removed when the sheet is
    /// fully retired in PR3.
    func replayFromHistory(_ entry: HistoryEntry) {
        if let match = groupHistory.first(where: {
            $0.tiles.map(\.key) == entry.tiles.map(\.key) && $0.sentence == entry.sentence
        }) {
            reopenHistoryGroup(id: match.id)
            return
        }
        // Fallback: synthesize an active group from the legacy entry.
        clearSelection()
        activeGroup.tiles = entry.tiles
        refreshActiveSuppressed()   // tiles set directly — keep the cached flag honest
        activeGroup.sentence = entry.sentence
        activeGroup.state = .unlockedEditable
        speak(entry.sentence)
    }

    // MARK: - Idle timer (no-op shim)

    /// Retained for callers that used to cancel the 30s idle clear. The idle clear is gone in
    /// the timeline model, so this is now a no-op. Kept to avoid touching every call site.
    func cancelIdleTimer() {
        // Intentionally no-op.
    }

    // MARK: - Flush

    /// Move the active group into history (newest-first) and reset the active slot.
    /// By default only flushes groups that produced a sentence — empty or in-flight groups are
    /// discarded. Pass `allowWithoutSentence: true` (used by the tray's explicit clear/Done
    /// button) to commit a partially-built group; the spelled-out tile values are stored as the
    /// sentence so the history chip and conversation context both have text to show.
    private func flushActiveToHistory(allowWithoutSentence: Bool = false) {
        onWillClear?(activeGroup.sentence)
        idleTask?.cancel()
        generationTask?.cancel()
        isIdleNudge = false
        isDoneNudge = false

        // 2+ tiles only. A single tile is ephemeral (spoken on tap; the ✕ /
        // auto-clear discard it) and must never land in history — otherwise a
        // recalled single word reopens as a locked group and loses its
        // cancel-✕ behavior. Empty groups are likewise never flushed. A
        // suppressed combination is a hard block and must never enter history.
        // `activeIsSuppressed` is kept current on every tile/override change, so
        // read the cached flag rather than re-fetching the override store here.
        let shouldFlush = activeGroup.tiles.count >= 2 && !activeIsSuppressed
            && (activeGroup.sentence != nil || allowWithoutSentence)

        if shouldFlush {
            var finalized = activeGroup
            finalized.state = .locked
            if finalized.sentence == nil {
                finalized.sentence = activeGroup.tiles.map(\.value).joined(separator: " ")
            }
            // Stamp the live escalation depth onto the group. The engine tracks
            // escalation in `self.repetitionCount` (bumped on each replay); the
            // TileGroup's own field is otherwise never updated, so without this
            // every logged utterance recorded 0 escalations.
            finalized.repetitionCount = repetitionCount
            groupHistory.insert(finalized, at: 0)
            // Trim to configured buffer size.
            let limit = trayBufferSize
            if groupHistory.count > limit {
                groupHistory.removeLast(groupHistory.count - limit)
            }
            // Persist the finalized utterance for therapist review (AdminView → Activity Log).
            // Final-state only: replay escalation is captured by repetitionCount, not as
            // separate rows.
            cacheManager?.logUtterance(
                tiles: finalized.tiles,
                sentence: finalized.sentence ?? "",
                repetitionCount: finalized.repetitionCount,
                childID: profileResolver?.activeChildID
            )
        }

        activeGroup = TileGroup()
        comparisonSentence = nil
        isThinking = false
        isWaiting = false
        speechSynthesizer.stop()
    }

    /// Explicit commit: flush the active group to history (even without a generated sentence)
    /// and reset. Wired to the tray's Done/clear button under the play control.
    func commitActiveAndStartNew() {
        flushActiveToHistory(allowWithoutSentence: true)
    }

    // MARK: - Generation pipeline

    /// The active child's grade level — folded into every cache key so a
    /// sentence generated for one grade is never served to another. Stable
    /// within a generation call (the resolver doesn't change mid-flight).
    private var currentGrade: Int {
        profileResolver?.ageGrade ?? ChildProfileResolver.fallbackAgeGrade
    }

    private func updateRepetitionState(for tiles: [TileSelection]) -> Int {
        let currentKey = SentenceCacheManager.cacheKey(for: tiles, grade: currentGrade)
        if currentKey == lastTileKey {
            repetitionCount += 1
        } else {
            repetitionCount = 0
            lastTileKey = currentKey
        }
        return repetitionCount
    }

    private func scheduleGeneration() {
        idleTask?.cancel()
        generationTask?.cancel()
        activeGroup.sentence = nil
        comparisonSentence = nil
        isThinking = false
        isIdleNudge = false
        isDoneNudge = false

        // Single tile: no sentence generation (the view shows the spelled-out
        // tile and the primary button becomes a cancel-✕). Still run the idle
        // timeline so the ✕ pulses after the pulse-after interval and a
        // lingering single tile auto-clears at the auto-Done interval.
        guard activeGroup.tiles.count >= 2 else {
            isWaiting = false
            if activeGroup.tiles.count == 1 { startIdleTimers() }
            return
        }

        let hitCap = activeGroup.tiles.count >= maxTilesPerGroup

        if hitCap {
            // Hit cap: auto-generate immediately, no idle nudge needed.
            isWaiting = true
            let tilesSnapshot = activeGroup.tiles
            let repetition = updateRepetitionState(for: tilesSnapshot)
            launchGeneration { [weak self] in
                await self?.generate(tiles: tilesSnapshot, repetition: repetition)
            }
        } else {
            // Pre-cap: do NOT auto-generate. Run the two-stage idle timer (pulse → auto-Done).
            isWaiting = false
            startIdleTimers()
        }
    }

    /// Idle-timeline staging anchored to T=0 = "user just did something tile-related" — either
    /// added/removed a tile (state is building or unlocked-editable) or tapped Play and locked
    /// the group. Stages fire in time order:
    ///
    ///   1. Play-button pulse at `idleDebounceDuration` (~2.5s) — only for non-locked groups
    ///      (locked groups have already been spoken; no nag).
    ///   2. Done-button attention at `doneAttentionLead` (~5s post-lock) — only for locked
    ///      groups. Once true, the Done button owns its own internal escalation animation; the
    ///      engine just provides the binary trigger.
    ///   3. Auto-Done at `autoDoneWait` — `commitActiveAndStartNew()`.
    ///
    /// Auto-Done is skipped when `autoDoneDuration == .seconds(0)`. The Done attention stage is
    /// skipped when its trigger time falls behind a prior stage (e.g. user picked a very short
    /// pulse or auto-Done that overlaps).
    private static let doneAttentionLead: Duration = .seconds(5)

    private func startIdleTimers() {
        idleTask?.cancel()
        // Never auto-advance while the caregiver is editing the bubble (a timeout
        // must not clear the tray from under a refine/hand-type), nor while a
        // generation is in flight (idle timing is meaningless mid-request — the
        // request re-arms the timers when it finishes).
        guard !caregiverEditing, !isThinking else { return }
        // Runs for a single tile (cancel-✕ pulse + auto-clear) as well as 2+
        // tiles (play pulse + auto-Done). Empty groups have no timeline.
        guard activeGroup.tiles.count >= 1 else { return }
        let isSingle = activeGroup.tiles.count == 1

        let pulseWait = idleDebounceDuration
        let autoDoneWait = autoDoneDuration
        idleTask = Task { [weak self] in
            // Stage 1: primary-button pulse (play for 2+ tiles, cancel-✕ for a
            // single tile). Skipped once a group locks (it's already been spoken).
            do { try await Task.sleep(for: pulseWait) } catch { return }
            guard !Task.isCancelled, let self else { return }
            if self.activeGroup.state != .locked {
                self.isIdleNudge = true
            }

            // Auto-Done disabled → stop here.
            guard autoDoneWait > pulseWait else { return }

            var elapsed = pulseWait

            // Stage 2: Done attention at T=doneAttentionLead. Only for locked groups; the Done
            // button handles its own ramp from here.
            let attentionAt = Self.doneAttentionLead
            if attentionAt > elapsed && attentionAt < autoDoneWait {
                let until = attentionAt - elapsed
                do { try await Task.sleep(for: until) } catch { return }
                guard !Task.isCancelled else { return }
                if self.activeGroup.state == .locked {
                    self.isDoneNudge = true
                }
                elapsed = attentionAt
            }

            // Stage 3: auto-finish. A single tile is ephemeral — it auto-clears
            // (discarded, not logged), matching the cancel-✕. A 2+ tile group
            // auto-Dones (committed to history).
            let remaining = autoDoneWait - elapsed
            guard remaining > .seconds(0) else { return }
            do { try await Task.sleep(for: remaining) } catch { return }
            guard !Task.isCancelled else { return }
            if isSingle {
                self.clearSelection()
            } else {
                self.commitActiveAndStartNew()
            }
        }
    }

    private func generate(tiles: [TileSelection], repetition: Int, refine: Bool = false,
                          refineInstruction: String? = nil, originalSentence: String? = nil) async {
        isWaiting = false
        isThinking = true
        isIdleNudge = false
        isDoneNudge = false

        // One override lookup, matched on the version-independent stableKey so it
        // outlives prompt/model/grade/class changes. `refine` forces a fresh
        // instruction-guided regeneration, so it ignores overrides entirely.
        let childID = profileResolver?.activeChildID
        let override = refine ? nil : cacheManager?.overrideLookup(tiles: tiles, childID: childID)

        // SUPPRESSED is a HARD BLOCK on EVERY path — escalation/replay included.
        // (Deliberately NOT gated on repetition==0: re-tapping a suppressed set
        // counts as a repeat, which must still stay silent, never escalate.)
        if let override, override.isSuppressed {
            guard tiles == activeGroup.tiles else { isThinking = false; return }
            Self.logger.info("generate: source=override.suppressed (blocked)")
            activeIsSuppressed = true
            activeGroup.sentence = nil          // show the tiles, say nothing
            activeGroup.state = .locked
            isThinking = false
            startIdleTimers()
            return
        }
        activeIsSuppressed = false   // reaching here means this combo isn't blocked

        // Escalation: still count the hit even though we bypass the cached sentence
        if repetition > 0 {
            cacheManager?.recordHit(tiles: tiles, grade: currentGrade)
        }

        // Durable hand-typed / accepted-refine override — served on first play.
        if repetition == 0, let override {
            guard tiles == activeGroup.tiles else { isThinking = false; return }
            override.hitCount += 1
            override.lastUsed = .now
            let src = override.isCaregiverEdited ? "override.handTyped" : "override.refine"
            Self.logger.info("generate: source=\(src) sentence=\"\(override.sentence)\"")
            activeGroup.sentence = override.sentence
            activeGroup.state = .locked
            onSentenceReady?(override.sentence)
            speak(override.sentence)
            isThinking = false
            startIdleTimers()
            return
        }

        // Cache lookup (skip for replay/escalation/refine)
        if repetition == 0, !refine, let cached = cacheManager?.lookup(tiles: tiles, grade: currentGrade) {
            guard tiles == activeGroup.tiles else {
                isThinking = false
                return
            }
            // Demo mode: hold the "Generating…" beat even on a cache hit so a
            // scripted demo reads as live AI, not an instant cache fetch.
            if DemoMode.isOn {
                try? await Task.sleep(for: .milliseconds(900))
                guard tiles == activeGroup.tiles else { isThinking = false; return }
            }
            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            Self.logger.info("generate: source=cache tiles=[\(tileKeys)] sentence=\"\(cached.sentence)\"")
            cacheManager?.logEvent(subjectType: "cache", subjectKey: cached.cacheKey, eventType: .hit)
            activeGroup.sentence = cached.sentence
            activeGroup.state = .locked
            onSentenceReady?(cached.sentence)
            speak(cached.sentence)
            isThinking = false
            startIdleTimers()
            return
        }

        // Build prompt. Grade comes from the active child profile when
        // resolver is wired; fallback keeps tests/preview paths working.
        let grade = currentGrade
        var promptBuilder = SentencePromptBuilder(ageGradeLevel: grade)
        promptBuilder.repetitionCount = repetition
        promptBuilder.conversationContext = conversationHistory
        var systemPrompt = promptBuilder.buildSystemPrompt()
        // Instruction-guided refine (mirrors the tile-art refine flow): feed the
        // caregiver's suggestion plus the sentence they're reacting to, so the
        // model revises rather than blindly rerolls. An empty instruction is a
        // plain "try again".
        if refine, let instruction = refineInstruction,
           !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            systemPrompt.append(PromptMessage(role: .system, content: """
            The caregiver reviewed your previous sentence for these tiles and wants it revised. \
            Previous sentence: "\(originalSentence ?? "")". Caregiver's instruction: "\(instruction)". \
            Produce ONE revised sentence for the same tiles that follows the instruction and stays \
            age-appropriate. Return only the sentence.
            """))
        }
        let userPrompt = promptBuilder.formatUserPrompt(tiles: tiles)

        // Fire comparison provider in parallel when enabled
        let shouldCompare = compareProviders && repetition == 0
        let comparisonProvider: (any SentenceProvider)? = shouldCompare ? makeAppleProviderIfAvailable() : nil

        // Provider treats the conversation context as a sequence of prior assistant turns, with
        // the last entry replaced as the user prompt. For escalation/replay we want the model to
        // see the exact sentence it is escalating from — but `conversationHistory` (derived from
        // `groupHistory`) doesn't include it (the group was popped by `reopenHistoryGroup`, or
        // the active group's sentence simply hasn't been flushed). Splice it in here so escalation
        // requests carry the prior turn explicitly.
        var contextWithPrior = conversationHistory
        if repetition > 0, let prior = activeGroup.sentence {
            contextWithPrior.append(prior)
        }
        // Refine: give the model the sentence it's revising as its prior turn, so
        // the instruction in the system prompt has an explicit target to rework.
        if refine, let original = originalSentence,
           !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            contextWithPrior.append(original)
        }
        let context = contextWithPrior + [userPrompt]
        let apiStart = ContinuousClock.now
        do {
            let result: SentenceResult
            let comparisonText: String?

            if let compProvider = comparisonProvider {
                // Run both providers concurrently
                async let primaryTask = provider.generateSentence(
                    tiles: tiles, systemPrompt: systemPrompt, conversationContext: context)
                async let compTask = Self.safeGenerate(
                    provider: compProvider, tiles: tiles, systemPrompt: systemPrompt, context: context)

                result = try await primaryTask
                comparisonText = await compTask
            } else {
                result = try await provider.generateSentence(
                    tiles: tiles, systemPrompt: systemPrompt, conversationContext: context)
                comparisonText = nil
            }

            let elapsed = apiStart.duration(to: .now)

            if repetition == 0 {
                if refine {
                    // Keep the fresh result as a durable, pinned accepted-refine override.
                    cacheManager?.setAcceptedRefine(tiles: tiles, grade: grade,
                                                    sentence: result.text, childID: childID)
                } else {
                    cacheManager?.store(tiles: tiles, grade: grade, sentence: result.text, childID: childID)
                }
                let usedKey = SentenceCacheManager.cacheKey(for: tiles, grade: grade)
                cacheManager?.logEvent(subjectType: "sentence", subjectKey: usedKey, eventType: .used)
            }

            guard tiles == activeGroup.tiles else {
                isThinking = false
                return
            }

            activeGroup.sentence = result.text
            activeGroup.state = .locked
            comparisonSentence = comparisonText
            onSentenceReady?(result.text)

            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            let secs = String(format: "%.3f", elapsed.timeInterval)
            if let u = result.usage {
                Self.logger.info("""
                generate: source=api elapsed=\(secs)s tiles=[\(tileKeys)] model=\(u.model) \
                sentence=\"\(result.text)\" \
                tokens(total=\(u.totalTokens) prompt=\(u.promptTokens) completion=\(u.completionTokens) cached=\(u.promptCachedTokens))
                """)
            } else {
                Self.logger.info("generate: source=api elapsed=\(secs)s tiles=[\(tileKeys)] sentence=\"\(result.text)\"")
            }
            if let comp = comparisonText {
                Self.logger.info("generate: comparison(apple)=\"\(comp)\"")
            }

            speak(result.text)
            isThinking = false
            startIdleTimers()
            return
        } catch {
            let elapsed = apiStart.duration(to: .now)
            let tileKeys = tiles.map(\.key).joined(separator: ", ")
            let secs = String(format: "%.3f", elapsed.timeInterval)
            Self.logger.error("generate: source=api elapsed=\(secs)s tiles=[\(tileKeys)] error=\"\(error.localizedDescription)\"")
            guard tiles == activeGroup.tiles else {
                isThinking = false
                return
            }
            comparisonSentence = nil
            // Never destroy a sentence that's already on screen when a request
            // fails. Generation never overwrites `activeGroup.sentence` until it
            // succeeds, so a refine or a replay (escalation) that fails simply
            // keeps the sentence it was working from — a harmless offline no-op,
            // NOT a blanked `.locked` limbo. Only a fresh generation (no sentence
            // yet) drops back to editable so Play can be retried.
            if let sentence = activeGroup.sentence {
                // A failed REPLAY couldn't reach the model to escalate, but the
                // user tapped to hear it — repeat the existing sentence unchanged
                // so there's still audible feedback (just not louder/escalated).
                if repetition > 0 { speak(sentence) }
            } else {
                activeGroup.state = .unlockedEditable
            }
            isThinking = false
            startIdleTimers()   // recover auto-advance after the failure
            return
        }

        isThinking = false
    }

    /// Play a promoted (cached) phrase directly — no API call, instant feedback.
    /// Populates the active group with the entry's tiles so the child sees what was selected.
    func speakPromoted(_ entry: SentenceCache) {
        clearSelection()
        // Reconstruct tile selections from cached keys
        if let ctx = cacheManager?.context {
            let keys = entry.tileKeys
            let descriptor = FetchDescriptor<TileModel>()
            if let allTiles = try? ctx.fetch(descriptor) {
                let lookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
                for key in keys {
                    if let tile = lookup[key] {
                        activeGroup.tiles.append(TileSelection(from: tile))
                    }
                }
            }
        }
        activeGroup.sentence = entry.sentence
        activeGroup.state = .locked
        cacheManager?.logEvent(subjectType: "promoted", subjectKey: entry.cacheKey, eventType: .hit)
        speak(entry.sentence)
    }

    func speakTile(_ text: String) {
        speak(text)
    }

    private func speak(_ text: String) {
        guard audioEnabled else { return }
        // Resolution order for voice: engine override (still set by some
        // AdminView code paths) → active ChildProfile.voiceIdentifier →
        // nil (system default). Rate + volume come straight from the
        // resolver when an active profile exists; otherwise nil leaves
        // the AVSpeechUtterance defaults in place.
        let override = voiceIdentifier.isEmpty ? nil : voiceIdentifier
        let resolverVoice = profileResolver?.voiceIdentifier
        let fromResolver: String? = (resolverVoice?.isEmpty ?? true) ? nil : resolverVoice
        let rate: Float? = profileResolver?.active != nil ? profileResolver?.ttsRate : nil
        let volume: Float? = profileResolver?.active != nil ? profileResolver?.ttsVolume : nil
        speechSynthesizer.speak(text,
                                voiceIdentifier: override ?? fromResolver,
                                rate: rate,
                                volume: volume)
    }

    // MARK: - Comparison helpers

    private func makeAppleProviderIfAvailable() -> (any SentenceProvider)? {
        if #available(iOS 26, *) {
            return AppleSentenceProvider()
        }
        return nil
    }

    /// Runs a provider's generateSentence without throwing — returns nil on failure.
    private static func safeGenerate(
        provider: any SentenceProvider,
        tiles: [TileSelection],
        systemPrompt: [PromptMessage],
        context: [String]
    ) async -> String? {
        do {
            let result = try await provider.generateSentence(
                tiles: tiles, systemPrompt: systemPrompt, conversationContext: context)
            return result.text
        } catch {
            logger.warning("comparison provider failed: \(error.localizedDescription)")
            return nil
        }
    }
}

private extension Duration {
    var timeInterval: Double {
        let c = components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }
}
