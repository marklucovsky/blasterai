// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftUI
import SwiftData

/// Identifies a freshly-created page that may want a link placed into the scene.
struct PageLinkTarget: Identifiable {
    let pageKey: String
    var id: String { pageKey }
}

/// Offers to drop a page's `page_link` tile (a silent navigation tile) onto
/// chosen pages, so the collection is reachable without hunting for the tile in
/// the picker.
///
/// Shown right after a page is created, and reachable any time afterwards from
/// the page's own row in the scene editor — a page can want a second way in
/// long after it was made, and until that entry point existed there was no way
/// to add one short of finding the tile by hand.
struct PageLinkPlacementSheet: View {
    @Bindable var scene: BlasterScene
    let target: PageLinkTarget
    let allTiles: [TileModel]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPages: Set<String> = []
    @State private var didSeed = false

    private var linkKey: String { PageLink.key(forPage: target.pageKey) }
    private var displayName: String {
        allTiles.first { $0.key == linkKey }?.displayName
            ?? target.pageKey.replacingOccurrences(of: "_", with: " ").capitalized
    }
    private var candidatePages: [PageSpec] {
        scene.pages.filter { $0.key != target.pageKey }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(candidatePages, id: \.key) { page in
                        if alreadyLinked(page) {
                            // Shown, not hidden, and not a toggle: the honest
                            // answer to "where does this page link from" includes
                            // the places it already does. Removing a link is an
                            // edit to that page, not something to bury in a
                            // checkbox that only ever adds.
                            HStack {
                                Text(pageLabel(page))
                                Spacer()
                                Label("Linked", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .labelStyle(.titleAndIcon)
                            }
                        } else {
                            Toggle(isOn: binding(for: page.key)) {
                                HStack {
                                    Text(pageLabel(page))
                                    Spacer()
                                    Text("\(page.tiles.count)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Add a “\(displayName)” link to…")
                } footer: {
                    Text("Drops a silent navigation tile that opens the \(displayName) page. You can also add it later from the tile picker’s Page Links filter.")
                }
            }
            .navigationTitle("Link this page in?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { finish() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add Link") { applyLinks(); finish() }
                        .disabled(selectedPages.isEmpty)
                }
            }
            .onAppear {
                // Default to linking from the home page — the common case.
                guard !didSeed else { return }
                didSeed = true
                if let home = candidatePages.first(where: { $0.key == scene.homePageKey }),
                   !alreadyLinked(home) {
                    selectedPages = [scene.homePageKey]
                }
            }
        }
    }

    private func binding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selectedPages.contains(key) },
            set: { on in if on { selectedPages.insert(key) } else { selectedPages.remove(key) } }
        )
    }

    private func alreadyLinked(_ page: PageSpec) -> Bool {
        page.tiles.contains { $0.key == linkKey }
    }

    private func pageLabel(_ page: PageSpec) -> String {
        page.key == scene.homePageKey ? "\(page.key)  ·  Home" : page.key
    }

    private func applyLinks() {
        var pages = scene.pages
        for i in pages.indices where selectedPages.contains(pages[i].key) {
            guard !pages[i].tiles.contains(where: { $0.key == linkKey }) else { continue }
            pages[i].tiles.append(TileEntry(key: linkKey, link: target.pageKey, isAudible: false))
        }
        scene.pages = pages
        try? modelContext.save()
    }

    private func finish() {
        // Done — returns to the scene editor; the new page is in the Pages list.
        dismiss()
    }
}
