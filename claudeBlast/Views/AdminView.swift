// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import Speech
import AVFoundation

struct AdminView: View {
    @Query(sort: \BlasterScene.created) var scenes: [BlasterScene]
    @Query(sort: \SentenceCache.hitCount, order: .reverse) var cacheEntries: [SentenceCache]
    @Query(sort: \TileModel.key) var allTiles: [TileModel]
    @Query var deviceProfiles: [DeviceProfile]
    @Query(sort: \ChildProfile.displayName) var childProfiles: [ChildProfile]
    @Environment(ChildProfileResolver.self) var profileResolver
    @Query(
        filter: #Predicate<SentenceCache> { entry in
            entry.hitCount >= 3 || entry.isPinned
        },
        sort: \SentenceCache.hitCount, order: .reverse
    ) var promotedCandidates: [SentenceCache]

    // Cache hit/miss metrics from MetricEvent log
    @Query(sort: \MetricEvent.timestamp) var allMetricEvents: [MetricEvent]

    // Finalized utterances — the activity-first Logs summary reads from here.
    @Query(sort: \LoggedUtterance.createdAt, order: .reverse) var loggedUtterances: [LoggedUtterance]

    /// Sums `MetricEvent.count` rather than counting rows, so a compacted
    /// aggregate row (one row standing for N occurrences) still reports the true
    /// total. Never replace this with `.count { }`.
    func metricTotal(subjectType: String, eventType: MetricType) -> Int {
        allMetricEvents.reduce(0) { total, event in
            (event.subjectType == subjectType && event.eventType == eventType)
                ? total + event.count : total
        }
    }

    var cacheHitCount: Int { metricTotal(subjectType: "cache", eventType: .hit) }
    var cacheMissCount: Int { metricTotal(subjectType: "sentence", eventType: .used) }
    @Environment(\.modelContext) var modelContext
    @Environment(SentenceEngine.self) var sentenceEngine

    // API key lives in the Keychain (per-device, non-synced). @State seeds
    // from the vault when the view is constructed; writes flow through
    // OpenAIKeyVault.setKey in the .onChange handler below.
    @State var apiKey: String = OpenAIKeyVault.currentKey() ?? ""
    @AppStorage(AppSettingsKey.providerChoice) var providerChoice: String = "openai"
    @AppStorage(AppSettingsKey.audioEnabled) var audioEnabled: Bool = true
    @AppStorage(AppSettingsKey.tileSpeechEnabled) var tileSpeechEnabled: Bool = true
    @AppStorage(AppSettingsKey.speechVoiceIdentifier) var voiceIdentifier: String = ""
    @AppStorage(AppSettingsKey.tileSizeStep) var tileSizeStep: Int = 0
    @AppStorage(AppSettingsKey.imageSet) var imageSetRaw: String = ImageSetID.playful3D.rawValue

    // Sentence tray timeline settings
    @AppStorage(AppSettingsKey.tileCapPerGroup) var tileCapPerGroup: Int = 4
    @AppStorage(AppSettingsKey.idleDebounceMs) var idleDebounceMs: Int = 2500
    @AppStorage(AppSettingsKey.trayBufferSize) var trayBufferSize: Int = 100
    @AppStorage(AppSettingsKey.autoDoneMs) var autoDoneMs: Int = 30000

    @Environment(TileImageResolver.self) var imageResolver

    @Environment(\.dismiss) var dismiss

    #if DEBUG
    @AppStorage(AppSettingsKey.icloudEnabled) var icloudEnabled: Bool = false
    @State var showResetConfirmation = false
    @State var isResetting = false
    #endif

    @State var navigateToNewScene: BlasterScene?
    @State var isCreatingScene = false
    @State var isImporting = false
    @State var importError: String?
    @State var pendingImportURL: ImportSheetURL?
    @State var sceneToExport: BlasterSceneFile?

    @State var profileSheet: ProfileSheet?

    /// Drives both create and edit flows through a single `.sheet(item:)`.
    /// Two separate `.sheet` modifiers on the same view would race — the
    /// second one wins and dismisses the first on the next render — which
    /// is exactly the "sheet self-dismisses" bug we hit in therapist mode.
    enum ProfileSheet: Identifiable {
        case create
        case edit(ChildProfile)

        var id: String {
            switch self {
            case .create:        return "create"
            case .edit(let p):   return "edit:\(p.id)"
            }
        }
    }

    /// Mirrors `device.role` for the picker. Lets us intercept a switch to
    /// `.patient` without committing it until the confirmation sheet wraps
    /// the loose ends (PIN setup + API key disposition).
    @State var displayedRole: DeviceRole = .caregiver
    @State var pendingPatientTransition = false
    @State var pendingCaregiverTransition = false

    /// Whether the bundled Core-First content differs from what's installed.
    /// Recomputed onAppear and after an update is applied. Drives the
    /// per-scene "Update Available" affordance.
    @State var bundleUpdateAvailable = false
    /// Set to the system scene the caregiver tapped "Update" on, to drive the
    /// confirmation dialog.
    @State var sceneToUpdate: BlasterScene?

    var envKeyOverride: Bool {
        ProcessInfo.processInfo.environment["OPENAI_API_KEY"] != nil
    }

    func tileDensityLabel(_ step: Int) -> String {
        switch step {
        case -3: return "Tightest"
        case -2: return "Tighter"
        case -1: return "Tight"
        case  0: return "Auto"
        case  1: return "Roomy"
        case  2: return "Roomier"
        case  3: return "Roomiest"
        default: return "Auto"
        }
    }

    var body: some View {
        // Tab segmentation:
        //   Now — parent-style quick tweaks (default landing)
        //   Profiles — child roster management
        //   Scenes — scene library + editor
        //   Device — device config (provider, API key, role, PIN, engine)
        //   Logs — diagnostics (cache, activity, promoted tiles)
        // Defaulting to Now means a parent landing in Admin to adjust
        // voice/volume/scene never has to scroll past therapist UI.
        TabView {
            nowTab
            profilesTab
            scenesTab
            deviceTab
            logsTab
        }
        .onAppear {
            // Global setup — request speech-recognition permission while
            // no sheet is open so the system dialog isn't occluded, and
            // check whether the bundled scenes have a pending update.
            SFSpeechRecognizer.requestAuthorization { _ in }
            bundleUpdateAvailable = BootstrapLoader.isBundleUpdateAvailable()
        }
    }

    // MARK: - Tile Lookup

    var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    func tileSelections(for entry: SentenceCache) -> [TileSelection] {
        entry.tileKeys.compactMap { key in
            guard let tile = tileLookup[key] else { return nil }
            return TileSelection(from: tile)
        }
    }

    // MARK: - Shared toolbar

    @ToolbarContentBuilder
    var adminDoneToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            EmptyView()
        }
    }
}

#Preview {
    AdminView()
        .previewEnvironment()
}
