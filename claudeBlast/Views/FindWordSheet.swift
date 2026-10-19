// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  FindWordSheet.swift
//  claudeBlast
//
//  Find Word, from the Caregiver Menu. See `WordFinder`.
//

import SwiftUI

/// Type a word, see where it is on the board, tap a place to go there.
///
/// Places that cannot be gone to — above the current level, concealed, on a
/// page no folder reaches — are listed greyed with the reason rather than left
/// out, because "why can't I find it" is half of what a caregiver asks this.
struct FindWordSheet: View {
    let scene: BlasterScene
    let lookup: [String: TileModel]
    let onPick: (WordFinder.Finding) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var results: [WordFinder.Finding] {
        WordFinder.find(query, in: scene, lookup: lookup)
    }

    var body: some View {
        NavigationStack {
            List {
                let results = results
                if results.isEmpty && !WordFinder.normalize(query).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
                ForEach(results) { finding in
                    Button { pick(finding) } label: { row(finding) }
                        .disabled(!finding.isAvailable)
                }
            }
            .listStyle(.plain)
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Find a word on \(scene.baseName)")
            .searchFocused($isSearchFocused)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .onSubmit(of: .search) {
                // One place to go: Return goes there. More than one: choose.
                if let only = WordFinder.onlyMatch(in: results) { pick(only) }
            }
            .navigationTitle("Find Word")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { isSearchFocused = true }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ finding: WordFinder.Finding) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(finding.label)
                .font(.body.weight(.semibold))
            Text(finding.reason.map { "\(finding.place) · \($0)" } ?? finding.place)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .foregroundStyle(finding.isAvailable ? Color.primary : Color.secondary)
    }

    private func pick(_ finding: WordFinder.Finding) {
        guard finding.isAvailable else { return }
        onPick(finding)
        dismiss()
    }
}
