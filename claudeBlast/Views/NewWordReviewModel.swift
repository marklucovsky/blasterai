// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  NewWordReviewModel.swift
//  claudeBlast
//
//  Drives the AT-AUTHORING moderation review shown on Page Preview, Scene
//  Preview, and the Add-Tiles panel. Moderation happens HERE — in the open, with
//  a visible analysis pass and a per-word verdict rendered on each new tile —
//  not silently at image-generation time. Each proposed NEW word gets a state:
//    • pending  (⚪️ analysis running)
//    • approved (🟢 safe)
//    • flagged  (🟡 caregiver must keep or remove — gates Accept)
//    • blocked  (🔴 policy — excluded, cannot be added)
//  Existing (non-new) words are never audited.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class NewWordReviewModel {
    enum Phase: Equatable { case idle, analyzing, complete }

    /// Per-tile review state, resolving `kept` / `removed` overrides.
    enum State: Equatable { case pending, approved, flagged, blocked, removed }

    private(set) var phase: Phase = .idle
    /// Verdict per NEW-word key (only words the audit actually rated).
    private(set) var verdicts: [String: WordVerdict] = [:]
    /// Flagged/blocked keys the caregiver chose to keep — treated as approved.
    private(set) var kept: Set<String> = []
    /// Keys the caregiver marked for removal. Deferred — the tile is NOT removed
    /// from the preview during review (that would change the word set and re-fire
    /// the analysis, wiping keep/remove choices); it's dropped on Accept instead.
    private(set) var removed: Set<String> = []

    /// The word set last analyzed (keys), so `analyze` can no-op on an unchanged
    /// set (e.g. a re-render) but re-run when Retry/Refine changes the words.
    private var analyzedKeys: Set<String> = []

    /// Analyze the given NEW words. `words` = (tile key, display name). Runs the
    /// audit once per distinct word set; without a key there's nothing to gate, so
    /// it completes immediately (Accept isn't blocked when moderation can't run).
    func analyze(_ words: [(key: String, name: String)], apiKey: String) async {
        let keys = Set(words.map(\.key))
        if phase != .idle && keys == analyzedKeys { return }   // already analyzed this set
        analyzedKeys = keys
        kept = []
        removed = []

        guard !words.isEmpty, !apiKey.isEmpty else {
            verdicts = [:]
            phase = .complete
            return
        }
        phase = .analyzing
        let byName = await WordModerationService(apiKey: apiKey).audit(words.map(\.name))
        guard keys == analyzedKeys else { return }   // superseded by a newer set
        var out: [String: WordVerdict] = [:]
        for w in words where byName[w.name] != nil && byName[w.name] != .allowed {
            out[w.key] = byName[w.name]
        }
        verdicts = out
        phase = .complete
    }

    func state(for key: String) -> State {
        switch phase {
        case .idle, .analyzing: return .pending
        case .complete:
            if removed.contains(key) { return .removed }
            if kept.contains(key) { return .approved }
            switch verdicts[key] {
            case .blocked: return .blocked
            case .flagged: return .flagged
            default: return .approved
            }
        }
    }

    /// Caregiver keeps a word (resolves a 🟡, overrides a 🔴, or undoes a removal).
    func keep(_ key: String) { removed.remove(key); kept.insert(key) }

    /// Caregiver marks a word for removal (resolves a 🟡 or removes a 🟢). Deferred
    /// to Accept so the word set — and thus the analysis — doesn't change here.
    func remove(_ key: String) { kept.remove(key); removed.insert(key) }

    func isBlocked(_ key: String) -> Bool {
        if case .blocked = verdicts[key] { return true }
        return false
    }

    /// Flagged keys (among those present) the caregiver hasn't resolved (neither
    /// kept nor removed). Accept is gated on this being empty.
    func unresolvedFlags(present keys: Set<String>) -> [String] {
        guard phase == .complete else { return [] }
        return keys.filter { key in
            guard !kept.contains(key), !removed.contains(key) else { return false }
            if case .flagged = verdicts[key] { return true }
            return false
        }
    }

    /// Analysis is done AND every present flagged word has been resolved.
    func canAccept(present keys: Set<String>) -> Bool {
        phase == .complete && unresolvedFlags(present: keys).isEmpty
    }

    /// Keys dropped on Accept: everything the caregiver removed, plus blocked
    /// words they didn't override with Keep.
    func droppedKeys(present keys: Set<String>) -> Set<String> {
        keys.filter { key in
            if removed.contains(key) { return true }
            if kept.contains(key) { return false }
            return isBlocked(key)
        }
    }
}

/// The moderation annotation overlaid on a proposed-new tile in Page/Scene
/// preview: a spinner while analyzing, then a green check (approved), or a
/// tappable red X / yellow flag whose menu lets the caregiver Keep or Remove.
/// Shared so both previews render identical review UI.
struct NewWordReviewBadge: View {
    let key: String
    let review: NewWordReviewModel

    var body: some View {
        switch review.state(for: key) {
        case .pending:
            ProgressView().scaleEffect(0.5).padding(2).background(.thinMaterial, in: Circle())
        case .approved:
            // Safe — offer Remove for full caregiver control.
            menu(reviewBadgeIcon("checkmark.circle.fill", .green), keep: false, remove: true)
        case .flagged:
            // Must be resolved (Keep or Remove) — gates Accept.
            menu(reviewBadgeIcon("flag.fill", .orange), keep: true, remove: true)
        case .blocked:
            // Dropped on Accept if untouched, doesn't gate — but keepable.
            menu(reviewBadgeIcon("xmark.circle.fill", .red), keep: true, remove: true)
        case .removed:
            // Caregiver-marked for removal; drops on Accept. Keep undoes it.
            menu(reviewBadgeIcon("minus.circle.fill", .red), keep: true, remove: false)
        }
    }

    private func menu(_ label: some View, keep: Bool, remove: Bool) -> some View {
        Menu {
            if keep { Button { review.keep(key) } label: { Label("Keep", systemImage: "checkmark") } }
            if remove {
                Button(role: .destructive) { review.remove(key) } label: { Label("Remove", systemImage: "trash") }
            }
        } label: { label }
    }
}

/// Shared circular badge glyph used by the review annotations.
func reviewBadgeIcon(_ system: String, _ color: Color) -> some View {
    Image(systemName: system)
        .font(.system(size: 15, weight: .bold))
        .foregroundStyle(color)
        .padding(1)
        .background(Circle().fill(.white))
        .padding(2)
}

/// Persistent review annotation for a MATERIALIZED tile in the page editor — the
/// Add-Tiles path stamps `needsReview` (🟡) or `isRetired` (🔴) on the tile, and
/// this surfaces it in the page view with a Keep / Remove menu. No badge for a
/// clean (approved) tile.
struct TileReviewBadge: View {
    let tile: TileModel
    let onKeep: () -> Void
    let onRemove: () -> Void

    var body: some View {
        if tile.isRetired {
            menu(reviewBadgeIcon("xmark.circle.fill", .red))
        } else if tile.needsReview {
            menu(reviewBadgeIcon("flag.fill", .orange))
        }
    }

    private func menu(_ label: some View) -> some View {
        Menu {
            Button(action: onKeep) { Label("Keep", systemImage: "checkmark") }
            // "Hide" (not "Remove") — it retires the word (reversible, lands in the
            // Vocab manager's Hidden), matching that surface's language.
            Button(role: .destructive, action: onRemove) { Label("Hide", systemImage: "eye.slash") }
        } label: { label }
    }
}

/// The at-a-glance review status shown above the Accept row in Page/Scene
/// preview: analyzing, "N flagged — resolve to continue", "N blocked", or all-clear.
struct NewWordReviewStatus: View {
    let review: NewWordReviewModel
    let present: Set<String>

    var body: some View {
        let unresolved = review.unresolvedFlags(present: present).count
        let dropped = review.droppedKeys(present: present).count
        Group {
            switch review.phase {
            case .idle:
                EmptyView()
            case .analyzing:
                Label("Checking new words…", systemImage: "sparkles").foregroundStyle(.secondary)
            case .complete:
                if unresolved > 0 {
                    Label("\(unresolved) flagged — keep or remove the 🟡 tiles to continue", systemImage: "flag.fill")
                        .foregroundStyle(.orange)
                } else if dropped > 0 {
                    Label("\(dropped) will be left off on Accept", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                } else if !present.isEmpty {
                    Label("All new words checked", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }
}
