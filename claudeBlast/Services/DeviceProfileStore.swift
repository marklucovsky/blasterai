// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  DeviceProfileStore.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Thin singleton accessor for the per-device `DeviceProfile`. The device
/// store should hold exactly one row; this helper enforces that and
/// guarantees a row always exists (creates a `.caregiver` placeholder with
/// `onboardingCompleted = false` on first access).
///
/// The placeholder lets the onboarding gate read `onboardingCompleted` on
/// first launch without race conditions — the row is materialized
/// synchronously before any view appears.
enum DeviceProfileStore {

    /// Fetch the singleton, creating a placeholder if none exists. Always
    /// returns a non-nil value. Safe to call from `claudeBlastApp.init`
    /// after `setModelContainer`.
    @discardableResult
    static func ensure(context: ModelContext) -> DeviceProfile {
        do {
            let existing = try context.fetch(FetchDescriptor<DeviceProfile>())
            if let first = existing.first {
                // Defensive: if a CloudKit race or test seeded multiple,
                // keep the earliest-created row and drop the rest. The
                // current ModelConfiguration disables CloudKit for this
                // type, but the dedup makes test setup safer.
                if existing.count > 1 {
                    let kept = existing.sorted { $0.createdAt < $1.createdAt }.first!
                    for extra in existing where extra !== kept {
                        context.delete(extra)
                    }
                    return kept
                }
                return first
            }
        } catch {
            // Fall through to create.
        }
        let placeholder = DeviceProfile(role: .caregiver, onboardingCompleted: false)
        context.insert(placeholder)
        return placeholder
    }

    /// Read the singleton without creating one. Returns nil if onboarding
    /// hasn't run yet AND `ensure` hasn't been called.
    static func current(context: ModelContext) -> DeviceProfile? {
        (try? context.fetch(FetchDescriptor<DeviceProfile>()))?.first
    }

    /// The device's self-generated author id — the "phone number" that
    /// namespaces scenes this device authors. Minted + persisted on first use;
    /// stable thereafter. Zero onboarding friction (never captured up front).
    @discardableResult
    static func ensureAuthorID(context: ModelContext) -> String {
        let profile = ensure(context: context)
        if profile.authorID.isEmpty {
            profile.authorID = UUID().uuidString.lowercased()
            profile.modifiedAt = .now
        }
        return profile.authorID
    }

    /// The author's optional self-asserted display name ("" if unset).
    static func authorName(context: ModelContext) -> String {
        current(context: context)?.authorName ?? ""
    }
}
