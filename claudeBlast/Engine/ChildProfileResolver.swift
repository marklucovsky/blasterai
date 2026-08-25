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

    /// This device's temporary interaction-mode override, or `nil` to follow the
    /// active child's stage. Cached from `DeviceProfile` on `refresh()` rather
    /// than fetched per read, because `interactionMode` sits on the tile-tap path.
    private(set) var modeOverride: InteractionMode?

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
        refreshOverride()
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

    /// Re-read this device's interaction-mode override.
    private func refreshOverride() {
        guard let ctx = context else {
            modeOverride = nil
            return
        }
        modeOverride = DeviceProfileStore.current(context: ctx)?.modeOverride
    }

    /// The mode the active child's stage implies, ignoring any device override.
    var stageMode: InteractionMode { active?.interactionMode ?? .sentence }

    /// Set (or clear, with `nil`) this device's temporary mode override.
    /// Deliberately does **not** touch the active child's Brown's Stage — see
    /// `DeviceProfile.modeOverrideRaw` for why those are different facts.
    func setModeOverride(_ mode: InteractionMode?) {
        guard let ctx = context else { return }
        let device = DeviceProfileStore.ensure(context: ctx)
        device.modeOverride = mode
        try? ctx.save()
        modeOverride = mode
    }

    /// Switch this device to `mode`. Clears the override when the requested mode
    /// is already what the child's stage implies, so the device goes back to
    /// simply following the profile rather than pinning a redundant override.
    func requestMode(_ mode: InteractionMode) {
        setModeOverride(mode == stageMode ? nil : mode)
    }

    // MARK: - Synchronous getters with safe fallbacks

    /// The active child's developmental stage, or the conservative floor when
    /// no profile is active (Sandbox / pre-onboarding).
    var brownsStage: BrownsStage { active?.brownsStage ?? Self.fallbackStage }
    var voiceIdentifier: String { active?.voiceIdentifier ?? "" }
    var ttsRate: Float { active?.ttsRate ?? Self.fallbackTTSRate }
    var ttsVolume: Float { active?.ttsVolume ?? Self.fallbackTTSVolume }
    /// Tile cap in force.
    ///
    /// With no override this is simply the child's own cap. When a device
    /// override *is* in force it borrows the cap of the lowest stage that
    /// override's mode belongs to, because a mode and a tile count are not
    /// independent — they are two faces of the same stage:
    ///
    /// - forced to single words → 1, what Stage I means
    /// - forced to sentences → 4, what Stage II-III means
    ///
    /// The second case is the one that matters. A Stage I child switched to
    /// sentence mode has a stored cap of 1, and simply honouring it (or nudging
    /// it to a floor of 2) generates a sentence on the second tap — which is not
    /// sentence mode in any useful sense. Borrowing Stage II-III's 4 gives the
    /// caregiver the board they actually asked for.
    ///
    /// The child's stored cap is never touched by any of this.
    var maxSelectedTiles: Int {
        let stored = active?.effectiveTileCap ?? Self.fallbackMaxTiles
        guard let override = modeOverride, override != stageMode else { return stored }
        switch override {
        case .singleWord:
            return BrownsStage.one.tileCapRange.lowerBound
        case .sentence:
            // Only borrow when the child's own cap is too small to build a
            // sentence with; a IV+ child dropped to I and back keeps their 7.
            return max(stored, BrownsStage.twoThree.tileCapRange.lowerBound)
        }
    }

    /// Interaction mode in force: this device's temporary override if set,
    /// otherwise the projection of the active child's Brown's Stage. Defaults
    /// to AI sentences when no real profile is active (Sandbox/pre-onboarding).
    var interactionMode: InteractionMode { modeOverride ?? stageMode }
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
