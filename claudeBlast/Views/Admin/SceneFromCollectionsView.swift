// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneFromCollectionsView.swift
//  claudeBlast
//
//  "New Scene from Collections" — assemble a scene, with zero AI and no key, by
//  ticking vocabulary packs and word classes. Each becomes its own page; a home
//  page linking them all is generated. This makes the hand-built combine-packs
//  scene (e.g. the demo "Vocab") a one-action build. Resolves through
//  `CollectionSource.buildScene`.
//

import SwiftUI
import SwiftData

struct SceneFromCollectionsView: View {
    let allTiles: [TileModel]
    /// Called with the freshly-inserted scene (already saved) — the caller
    /// typically activates it / opens the editor, exactly like the AI path.
    let onCreate: (BlasterScene) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var sceneName = ""
    @State private var selectedPackIDs: Set<String> = []
    @State private var selectedClasses: Set<String> = []

    private var packs: [VocabPack] { PackCatalog.all }

    /// Caregiver-selectable classes present in the current vocabulary, with counts.
    private var classOptions: [(cls: VocabularyClass, count: Int)] {
        let counts = allTiles.reduce(into: [String: Int]()) { $0[$1.wordClass, default: 0] += 1 }
        return VocabularyClasses.caregiverSelectable.compactMap { c in
            let n = counts[c.name] ?? 0
            return n > 0 ? (c, n) : nil
        }
    }

    private var selectedCount: Int { selectedPackIDs.count + selectedClasses.count }
    private var canCreate: Bool {
        !sceneName.trimmingCharacters(in: .whitespaces).isEmpty && selectedCount > 0
    }

    var body: some View {
        Form {
            Section("Scene Name") {
                TextField("e.g. Snack time", text: $sceneName)
                    .autocorrectionDisabled()
            }

            if !packs.isEmpty {
                Section {
                    ForEach(packs) { pack in
                        Toggle(isOn: packBinding(pack.id)) {
                            HStack {
                                Image(systemName: "shippingbox.fill")
                                    .font(.caption).foregroundStyle(.tint)
                                Text(pack.displayName)
                                Spacer()
                                Text("\(pack.words.count)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Vocabulary Packs")
                }
            }

            if !classOptions.isEmpty {
                Section {
                    ForEach(classOptions, id: \.cls.id) { opt in
                        Toggle(isOn: classBinding(opt.cls.name)) {
                            HStack {
                                Circle().fill(opt.cls.color).frame(width: 10, height: 10)
                                Text(opt.cls.label)
                                Spacer()
                                Text("\(opt.count)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Word Classes")
                } footer: {
                    Text("Each pack and class you pick becomes its own page. A home page is created with a link to every one.")
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Build from Collections")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") { create() }
                    .disabled(!canCreate)
            }
        }
    }

    private func packBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { selectedPackIDs.contains(id) },
            set: { on in if on { selectedPackIDs.insert(id) } else { selectedPackIDs.remove(id) } }
        )
    }
    private func classBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { selectedClasses.contains(name) },
            set: { on in if on { selectedClasses.insert(name) } else { selectedClasses.remove(name) } }
        )
    }

    private func create() {
        let existing = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        // Preserve catalog / display order: packs first (catalog order), then
        // classes (canonical class order).
        var sources: [CollectionSource] = []
        for pack in packs where selectedPackIDs.contains(pack.id) { sources.append(.pack(pack)) }
        for opt in classOptions where selectedClasses.contains(opt.cls.name) {
            sources.append(.wordClass(classes: [opt.cls.name]))
        }
        guard let scene = CollectionSource.buildScene(
            name: sceneName.trimmingCharacters(in: .whitespacesAndNewlines),
            sources: sources, into: modelContext,
            allTiles: allTiles, existing: existing
        ) else { return }
        try? modelContext.save()
        onCreate(scene)
        dismiss()
    }
}
