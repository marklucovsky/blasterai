// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PreviewHelpers.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// In-memory model container pre-loaded with the default vocabulary
/// so previews show a realistic tile grid with an active scene.
@MainActor
let previewContainer: ModelContainer = {
    let schema = Schema([
        TileModel.self, TileArtVariant.self,
        BlasterScene.self, SentenceCache.self, MetricEvent.self,
        RecordedScript.self, LoggedUtterance.self,
    ])  // previews use one in-memory store; the app's synced/local split doesn't apply
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: schema, configurations: [config])
    _ = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)
    return container
}()

extension View {
    /// Injects all environment objects and a bootstrapped in-memory model
    /// container needed by the main view hierarchy. Use in `#Preview` blocks.
    func previewEnvironment() -> some View {
        self
            .environment(SentenceEngine(provider: MockSentenceProvider()))
            .environment(NavigationCoordinator())
            .environment(TileScriptRunner())
            .environment(TileScriptRecorder())
            .environment(ImportCoordinator())
            .environment(SceneArtCoordinator())
            .modelContainer(previewContainer)
    }
}
