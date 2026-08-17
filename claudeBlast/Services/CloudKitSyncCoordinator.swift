// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  CloudKitSyncCoordinator.swift
//  claudeBlast
//

import SwiftData
import Foundation
import CoreData  // .NSPersistentStoreRemoteChange notification name

/// Reacts to CloudKit writing remote changes into the store: re-runs
/// `CloudKitDedupReconciler`, and tells the rest of the app that synced data has
/// moved. Also runs a debounced pass on demand (foreground / launch).
///
/// The launch-time reconcile only cleans duplicates already present locally;
/// the ones that cause the real damage arrive *later* via async CloudKit
/// import. This observer catches that window. Remote-store notifications can
/// be flaky under SwiftData, so callers ALSO nudge `reconcileSoon()` on
/// `scenePhase` → active as a reliable belt-and-suspenders trigger.
@Observable
@MainActor
final class CloudKitSyncCoordinator {
    private var context: ModelContext?
    private var onReconciled: (() -> Void)?
    private var onRemoteChange: (() -> Void)?
    private var observer: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?

    init() {}

    /// Wire the context and two hooks. Runs one pass immediately.
    ///
    /// - `onReconciled`: the reconciler actually deleted something (e.g. refresh
    ///   `ChildProfileResolver`, whose active-profile cache goes stale when a
    ///   pass flips `isActive`).
    /// - `onRemoteChange`: **every** pass, deletions or not. Dedup is the rarer
    ///   case; the common one is a plain record arriving, and callers holding
    ///   caches over synced data need to hear about that too. Gating this on
    ///   `deleted > 0` is why art generated on one device synced to another and
    ///   stayed invisible until relaunch — see
    ///   `TileImageResolver.invalidateSyncedArt`.
    func configure(modelContext: ModelContext,
                   onRemoteChange: (() -> Void)? = nil,
                   onReconciled: (() -> Void)? = nil) {
        self.context = modelContext
        self.onReconciled = onReconciled
        self.onRemoteChange = onRemoteChange
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.reconcileSoon() }
            }
        }
        reconcileSoon()
    }

    /// Debounced reconcile — CloudKit imports arrive in bursts, so coalesce.
    func reconcileSoon() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, let context = self.context else { return }
            let deleted = CloudKitDedupReconciler.reconcile(context: context)
            if deleted > 0 { self.onReconciled?() }
            self.onRemoteChange?()
        }
    }
    // No deinit observer teardown: this coordinator is app-lifetime (@State on the
    // App), and the observer block is [weak self]-guarded, so it no-ops if the
    // object ever goes away. (deinit can't touch main-actor-isolated state anyway.)
}
