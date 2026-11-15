// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChildProfileResolver.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import Foundation

/// Single source of truth for "which child is active right now and what
/// are their settings." Injected into `SentenceEngine` so the prompt
/// builder, tile cap, and TTS voice all derive from the same place.
///
/// `ChildProfile.isActive` is treated as a *hint* — under CloudKit, two
/// devices can race and end up with multiple flags set. The resolver
/// runs every candidate through `ChildProfile.resolveActive(from:)` which
/// picks the canonical winner with a deterministic tiebreaker.
///
/// Mutations that change `isActive` should call `setActive(id:)` so the
/// resolver re-reads the store after a single atomic transaction.
@Observable
@MainActor
final class ChildProfileResolver {
    /// The currently active profile, resolved from SwiftData. Nil when no
    /// profile is marked active yet (fresh install pre-onboarding).
    private(set) var active: ChildProfile?

    private var context: ModelContext?

    /// Fallbacks for the no-active-profile case. Sized for a safe baseline
    /// rather than a "best guess" — better to under-serve than to hand a child
    /// sentences they cannot parse.
    static let fallbackStage: BrownsStage = .one
    static let fallbackMaxTiles: Int = 4
    static let fallbackTTSRate: Float = 0.5
    static let fallbackTTSVolume: Float = 1.0

    init() {}

    /// Wire the SwiftData context. Safe to call multiple times; each call
    /// re-resolves the active profile from the current store.
    func configure(modelContext: ModelContext) {
        self.context = modelContext
        refresh()
    }

    /// Re-read the active profile from SwiftData. Called from
    /// `configure` and after mutations.
    ///
    /// Resolution order:
    /// 1. Any *real* (`isSystem == false`) profile marked active wins, with
    ///    `ChildProfile.resolveActive` picking the canonical one under a
    ///    CloudKit race.
    /// 2. Otherwise the Sandbox (`isSystem == true`) profile becomes
    ///    active. ProfileMigration guarantees it exists.
    /// 3. If neither exists (bootstrap hasn't run yet), `active` is nil
    ///    and the synchronous getters use safe fallbacks.
    func refresh() {
        // Whoever ends up active, their palette goes with them. Done in `defer`
        // so every exit from this function keeps the two in step — a board drawn
        // in the previous child's colors is the exact failure the map exists to
        // prevent, and it would be invisible on a device with one profile.
        defer {
            retireDeviceOverride()
            TileColorResolver.refreshActiveMap(from: active)
        }
        guard let ctx = context else {
            active = nil
            return
        }
        let activeFetch = FetchDescriptor<ChildProfile>(
            predicate: #Predicate { $0.isActive && !$0.isSystem }
        )
        let realActive = (try? ctx.fetch(activeFetch)) ?? []
        if let winner = ChildProfile.resolveActive(from: realActive) {
            active = winner
            return
        }
        let sandboxFetch = FetchDescriptor<ChildProfile>(
            predicate: #Predicate { $0.isSystem }
        )
        let sandboxes = (try? ctx.fetch(sandboxFetch)) ?? []
        active = sandboxes.first
    }

    /// Fold the device-wide mode override earlier builds kept
    /// (`DeviceProfile.modeOverrideRaw`) into the profile that is talking, then
    /// clear it. Sentences are a profile setting now and the board's switch
    /// writes the profile; a leftover override would be a second answer that
    /// nothing on screen shows.
    private func retireDeviceOverride() {
        guard let ctx = context, let device = DeviceProfileStore.current(context: ctx),
              !device.modeOverrideRaw.isEmpty else { return }
        if let mode = device.modeOverride, let profile = active, profile.aiModeRaw.isEmpty {
            profile.aiMode = mode == .sentence ? .sentences : .on
        }
        device.modeOverrideRaw = ""
        try? ctx.save()
    }

    /// Switch the profile that is talking to `mode`: sentences on, or each
    /// word on its own. A profile with AI off is left off; the board only
    /// offers sentences when it can make them.
    func requestMode(_ mode: InteractionMode) {
        guard let profile = active else { return }
        switch mode {
        case .sentence:   profile.aiMode = .sentences
        case .singleWord: if profile.aiMode == .sentences { profile.aiMode = .on }
        }
        try? context?.save()
    }

    // MARK: - Synchronous getters with safe fallbacks

    /// The active child's developmental stage, or the conservative floor when
    /// no profile is active (Sandbox / pre-onboarding).
    var brownsStage: BrownsStage { active?.brownsStage ?? Self.fallbackStage }
    var voiceIdentifier: String { active?.voiceIdentifier ?? "" }
    var ttsRate: Float { active?.ttsRate ?? Self.fallbackTTSRate }
    var ttsVolume: Float { active?.ttsVolume ?? Self.fallbackTTSVolume }
    /// Words per message in force: the active profile's, or the fallback.
    var maxSelectedTiles: Int { active?.wordsPerMessage ?? Self.fallbackMaxTiles }

    /// How taps become a message: the active profile's choice. With no
    /// profile it is single words, the quiet direction to be wrong in.
    var interactionMode: InteractionMode { active?.interactionMode ?? .singleWord }
    var activeChildID: String? { active?.id }

    // MARK: - Mutation

    /// Set the given profile as the sole active one. Deactivates every
    /// other profile and bumps `modifiedAt` so the resolver's CloudKit-race
    /// tiebreaker (most-recent-modifiedAt wins) reflects the user's intent.
    func setActive(id: String) {
        guard let ctx = context else { return }
        let all = (try? ctx.fetch(FetchDescriptor<ChildProfile>())) ?? []
        let now = Date.now
        for profile in all {
            if profile.id == id {
                if !profile.isActive { profile.isActive = true }
                profile.modifiedAt = now
            } else if profile.isActive {
                profile.isActive = false
                profile.modifiedAt = now
            }
        }
        try? ctx.save()
        refresh()
    }
}
