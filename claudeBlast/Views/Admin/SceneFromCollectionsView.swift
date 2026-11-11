// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneFromCollectionsView.swift
//  claudeBlast
//
//  "Build from collections" — assemble a scene, with zero AI and no key, by
//  ticking vocabulary packs and word classes. Each becomes its own page; a home
//  page linking them all is generated.
//
//  This is the same picker the structure step uses (`SceneStructurePicker`) with
//  a scene-name field on top, because the two are the same question asked at
//  different moments: *which existing collections go on this board?* Building
//  them was once its own code path (`CollectionSource.buildScene`); it now
//  resolves through `SceneStructure.build` like every other addition, so a page
//  built here and a page added later are built by the same code.
//
//  It hands back a `GeneratedScene` rather than a saved one: a collections scene
//  goes through the same preview → structure → confirm walk as a generated one,
//  so nothing is written until Accept.
//

import SwiftUI
import SwiftData

struct SceneFromCollectionsView: View {
    let allTiles: [TileModel]
    /// Owned by the wizard so stepping back lands on the choices already made.
    @Binding var sceneName: String
    @Binding var plan: SceneStructurePlan
    /// The assembled scene and the result that produced it.
    let onNext: (GeneratedScene, SceneStructureResult) -> Void
    let onBack: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BlasterScene.name) private var allScenes: [BlasterScene]

    /// The shell the picks are folded into: one empty home page, which the
    /// structure result then fills with a link per page.
    private static let homeKey = "home"

    private var donorScenes: [BlasterScene] { allScenes.filter { !$0.pages.isEmpty && !$0.isCarriedTemplate } }

    private var canCreate: Bool {
        !sceneName.trimmingCharacters(in: .whitespaces).isEmpty && !plan.isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("e.g. Snack time", text: $sceneName)
                    .autocorrectionDisabled()
            } header: {
                Text("Scene Name")
            } footer: {
                Text("Each pack, class or copied page you pick below becomes its own page, and the home page gets a link to every one.")
            }

            SceneStructurePicker(plan: $plan,
                                 allTiles: allTiles,
                                 packs: PackCatalog.available(in: modelContext),
                                 donorScenes: donorScenes,
                                 existingPageKeys: [Self.homeKey])
        }
        .navigationTitle("Build from Collections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { onBack() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { advance() }
                    .disabled(!canCreate)
            }
        }
    }

    private func advance() {
        let result = SceneStructure.build(plan,
                                          existingPageKeys: [Self.homeKey],
                                          homeTileKeys: [],
                                          into: modelContext,
                                          allTiles: allTiles,
                                          packs: PackCatalog.available(in: modelContext),
                                          donorScenes: donorScenes)
        guard !result.isEmpty else { return }
        let shell = GeneratedScene(name: sceneName.trimmingCharacters(in: .whitespacesAndNewlines),
                                   description: "",
                                   homePageKey: Self.homeKey,
                                   pages: [GeneratedPage(key: Self.homeKey, tiles: [])])
        onNext(shell.adding(result), result)
    }
}
