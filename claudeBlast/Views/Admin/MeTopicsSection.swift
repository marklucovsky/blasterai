// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MeTopicsSection.swift
//  claudeBlast
//
//  A child's Me page and My Topics, in their profile. See `MeScene`.
//

import SwiftUI
import SwiftData

/// The profile form's Topics section: what is on this child's My Topics, a
/// way to add more, and the door to their Me page's editor.
///
/// Changes apply at once, not on the form's Save: they edit the Me scene, a
/// board like any other, and the scene editor saves the same way.
struct MeTopicsSection: View {
    let profileID: String

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BlasterScene.name) private var scenes: [BlasterScene]

    private var me: BlasterScene? { scenes.first { $0.sceneID == MeScene.sceneID(forProfileID: profileID) } }

    private var topics: [BlasterScene] {
        guard let me else { return [] }
        return MeScene.topicIDs(in: me).compactMap { id in scenes.first { $0.sceneID == id } }
    }

    private var addable: [BlasterScene] {
        let on = Set(me.map(MeScene.topicIDs(in:)) ?? [])
        return scenes.filter { MeScene.isEligibleTopic($0) && !on.contains($0.sceneID) }
    }

    var body: some View {
        Section {
            ForEach(topics) { topic in
                Label(topic.name, systemImage: "heart.fill")
            }
            .onDelete { offsets in
                guard let me else { return }
                for topic in offsets.map({ topics[$0] }) {
                    MeScene.removeTopic(sceneID: topic.sceneID, from: me)
                }
                try? modelContext.save()
            }
            if !addable.isEmpty {
                Menu {
                    ForEach(addable) { scene in
                        Button(scene.name) {
                            let me = MeScene.ensure(profileID: profileID, context: modelContext)
                            MeScene.addTopic(scene, to: me, context: modelContext)
                            try? modelContext.save()
                        }
                    }
                } label: {
                    Label("Add a Topic", systemImage: "plus.circle")
                }
            }
            if let me {
                NavigationLink {
                    SceneEditorView(scene: me)
                } label: {
                    Label("Edit Me Page", systemImage: "pencil")
                }
            }
        } header: {
            Text("Me Page and Topics")
        } footer: {
            Text("The heart on the board opens this child's own page. My Topics lists the scenes added here, without replacing the main board. Only scenes on the 10 × 6 layout can be topics. Changes apply right away.")
        }
        // Made here, not while a view is being built: a model written from a
        // body is the "setting value during update" crash.
        .onAppear {
            if me == nil {
                MeScene.ensure(profileID: profileID, context: modelContext)
                try? modelContext.save()
            }
        }
    }
}
