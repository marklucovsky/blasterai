// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  claudeBlastApp.swift
//  claudeBlast
//
//  Created by MARK LUCOVSKY on 2/5/26.
//

import SwiftUI
import SwiftData
import AVFoundation

@main
struct claudeBlastApp: App {
    private let modelContainer: ModelContainer
    @State private var sentenceEngine: SentenceEngine
    @State private var navigationCoordinator = NavigationCoordinator()
    @State private var scriptRunner = TileScriptRunner()
    @State private var scriptRecorder = TileScriptRecorder()
    @State private var imageResolver = TileImageResolver()
    @State private var profileResolver = ChildProfileResolver()
    @State private var sceneArtCoordinator = SceneArtCoordinator()
    @State private var caregiverMenu = CaregiverMenuCoordinator()
    @State private var syncCoordinator = CloudKitSyncCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Register fallback defaults for any keys the engine reads via
        // UserDefaults.standard directly (not via @AppStorage). @AppStorage's
        // default applies only when *reading* through the wrapper — the engine
        // bypasses it, so an unset key returns 0 and engine paths that treat
        // 0 as "disabled" (notably autoDoneMs) end up never firing. Register
        // here so the engine and AdminView see the same defaults.
        UserDefaults.standard.register(defaults: [
            AppSettingsKey.autoDoneMs: 30000,
            AppSettingsKey.idleDebounceMs: 2500,
            AppSettingsKey.trayBufferSize: 100,
            AppSettingsKey.tileCapPerGroup: 4,
        ])
        // iCloud sync default depends on build:
        // - RELEASE: ON. For an AAC app whose threat model is "stop a curious
        //   child," cross-device sync (reinstall recovers data, therapist's
        //   iPad + family iPhone stay in sync, reduces PIN-loss blast radius)
        //   outweighs the marginal privacy concern of the user's own iCloud.
        // - DEBUG: OFF. Local-only store makes testing deterministic — a
        //   factory reset stays local and nothing re-syncs test data back, and
        //   it avoids a dev device clobbering a synced device on the same
        //   account. Toggle in Admin to exercise sync explicitly.
        #if DEBUG
        UserDefaults.standard.register(defaults: [AppSettingsKey.icloudEnabled: false])
        #else
        UserDefaults.standard.register(defaults: [AppSettingsKey.icloudEnabled: true])
        #endif

        let icloudEnabled = UserDefaults.standard.bool(forKey: AppSettingsKey.icloudEnabled)
        let container = setModelContainer(icloudEnabled: icloudEnabled)
        self.modelContainer = container

        // Snapshot the "installed before this launch?" signal BEFORE
        // BootstrapLoader.markBootstrapComplete flips it. Drives whether
        // ProfileMigration seeds a Legacy ChildProfile from prior UserDefaults
        // (returning user) or skips the seed (fresh install).
        let wasInstalled = UserDefaults.standard.bool(forKey: AppSettingsKey.bootstrapInstalled)

        // Bootstrap only on first launch (or after a forced version bump).
        // Always wipe first — on a fresh store this is a no-op; on a version
        // bump it prevents duplicate records when re-seeding from the bundle.
        if BootstrapLoader.needsBootstrap() {
            // Under CloudKit, a second device may already hold the synced dataset
            // by the time it launches (the seed-once flag is local-only). Don't
            // seed a duplicate full copy — adopt the synced one. Best-effort: if
            // the initial import hasn't landed yet the device still seeds, and
            // CloudKitDedupReconciler collapses the resulting duplicates below.
            if BootstrapLoader.storeAlreadySeeded(context: container.mainContext) {
                BootstrapLoader.markBootstrapComplete()
            } else {
                BootstrapLoader.wipeAllData(context: container.mainContext)
                _ = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)
                BootstrapLoader.markBootstrapComplete()
            }
        }

        // Push a newer bundled system board silently. This is only safe — and is
        // the reason it's automatic rather than a prompt — because system scenes
        // are immutable (`BlasterScene.isSystemOwned`): there is no caregiver work
        // inside one to lose, since edits go to a clone. It replaces the old
        // "Update Available" affordance, which asked permission and offered to
        // save a copy first, and which a naive user could decline forever.
        // No-op on a fresh bootstrap (markBootstrapComplete stamps the hash).
        if BootstrapLoader.isBundleUpdateAvailable() {
            BootstrapLoader.updateSystemScene(context: container.mainContext)
        }

        ProfileMigration.ensureProfilesAfterBootstrap(
            context: container.mainContext,
            seedLegacy: wasInstalled
        )

        // One-time: mark bundled tiles as system on installs that predate
        // TileModel.isSystem. No-op on fresh bootstraps (already flagged).
        BootstrapLoader.backfillTileProvenance(context: container.mainContext)

        // Collapse any CloudKit multi-device duplicates already present at launch
        // and enforce single-active invariants. Duplicates that arrive later via
        // async CloudKit import are handled by CloudKitSyncCoordinator (below).
        CloudKitDedupReconciler.reconcile(context: container.mainContext)

        // Sweep the sentence cache: drop stale-version and expired entries and
        // enforce the size cap (pinned exempt). Runs after dedup so duplicates
        // are already collapsed before entries are counted. Cheap; every launch.
        let cacheSwept = SentenceCacheManager(modelContext: container.mainContext).evictStale()
        if cacheSwept > 0 {
            try? container.mainContext.save()
        }

        // Stamp decentralized identity onto any pre-identity scenes so existing
        // installs show provenance + bind scripts by stable id. Idempotent.
        SceneIdentityBackfill.run(context: container.mainContext)

        // Move any prior UserDefaults-stored API key into the Keychain on
        // the first launch after upgrade. Idempotent; no-op on fresh installs.
        OpenAIKeyVault.migrateFromUserDefaultsIfNeeded()

        // Select provider: env var wins (consumed silently — env users get
        // their key persisted to Keychain so standalone re-launches keep
        // working), then Keychain, then Mock.
        let provider: any SentenceProvider
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]?
            .trimmingCharacters(in: .whitespaces),
           !envKey.isEmpty {
            OpenAIKeyVault.setKey(envKey)
            provider = OpenAISentenceProvider(apiKey: envKey)
        } else {
            let choice = UserDefaults.standard.string(forKey: AppSettingsKey.providerChoice) ?? "openai"
            if choice == "openai", let storedKey = OpenAIKeyVault.currentKey() {
                provider = OpenAISentenceProvider(apiKey: storedKey)
            } else {
                provider = MockSentenceProvider()
            }
        }
        let engine = SentenceEngine(provider: provider)
        let storedAudio = UserDefaults.standard.object(forKey: AppSettingsKey.audioEnabled)
        engine.audioEnabled = (storedAudio as? Bool) ?? true
        engine.voiceIdentifier = UserDefaults.standard.string(forKey: AppSettingsKey.speechVoiceIdentifier) ?? ""
        self._sentenceEngine = State(initialValue: engine)

        // Restore image set preference
        let resolver = TileImageResolver()
        if let storedSet = UserDefaults.standard.string(forKey: AppSettingsKey.imageSet),
           let setID = ImageSetID(rawValue: storedSet) {
            resolver.activeSet = setID
        }
        self._imageResolver = State(initialValue: resolver)

        // Configure audio session at launch so speech plays regardless of the
        // ringer/silent switch. .playback bypasses the mute switch; .spokenAudio
        // mode ducks other audio and resumes it after each utterance.
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }

    @State private var importCoordinator = ImportCoordinator()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sentenceEngine)
                .environment(navigationCoordinator)
                .environment(scriptRunner)
                .environment(scriptRecorder)
                .environment(imageResolver)
                .environment(profileResolver)
                .environment(sceneArtCoordinator)
                .environment(caregiverMenu)
                .onAppear {
                    profileResolver.configure(modelContext: modelContainer.mainContext)
                    imageResolver.configure(modelContext: modelContainer.mainContext)
                    sentenceEngine.configure(
                        modelContext: modelContainer.mainContext,
                        profileResolver: profileResolver
                    )
                    scriptRunner.configure(
                        engine: sentenceEngine,
                        coordinator: navigationCoordinator,
                        modelContext: modelContainer.mainContext,
                        resolver: imageResolver
                    )
                    scriptRecorder.configure(engine: sentenceEngine, runner: scriptRunner, coordinator: navigationCoordinator)
                    // Keep collapsing CloudKit duplicates as they arrive via async
                    // import; refresh the active-profile cache if a pass changed it.
                    syncCoordinator.configure(modelContext: modelContainer.mainContext) {
                        profileResolver.refresh()
                    }
                }
                .environment(importCoordinator)
                .onChange(of: scenePhase) { _, phase in
                    // Reliable belt-and-suspenders: remote-change notifications can
                    // be flaky under SwiftData, so reconcile on every foreground too.
                    if phase == .active { syncCoordinator.reconcileSoon() }
                }
                .onOpenURL { url in
                    guard url.pathExtension == BlasterSceneFormat.fileExtension else { return }
                    importCoordinator.pendingURL = url
                }
        }
        .modelContainer(modelContainer)
    }
}
