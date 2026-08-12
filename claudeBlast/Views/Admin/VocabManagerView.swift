// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  VocabManagerView.swift
//  claudeBlast
//
//  Caregiver vocabulary moderation + management. Search, filter by review state
//  and word class, sort by recency or name, and act per-word: Keep/Remove a
//  moderation-flagged word, Restore a hidden one, or Hide any active word.
//  Hiding retires the word (reversible, preserves history) and purges its cached
//  sentences so a later restore can't resurrect a stale line (see TileModel.isRetired).
//

import SwiftUI
import SwiftData

struct VocabManagerView: View {
    @Environment(\.modelContext) private var context
    // Recency default: newest first (created desc). Alpha re-sorts in `filtered`.
    @Query(sort: \TileModel.created, order: .reverse) private var allTiles: [TileModel]

    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", review = "Needs review", hidden = "Hidden", added = "Added by you"
        var id: String { rawValue }
    }
    enum Order: String, CaseIterable, Identifiable {
        case recent = "Recent", alpha = "A–Z"
        var id: String { rawValue }
    }

    @State private var search = ""
    @State private var scope: Scope = .all
    @State private var classFilter: String? = nil
    @State private var order: Order = .recent

    /// Structural / auto-minted classes (page links, navigation, core, question)
    /// aren't caregiver vocabulary — never list them for management (hiding a
    /// page-link would break navigation, and they're not "added by you").
    private static let structuralClasses: Set<String> =
        Set(VocabularyClasses.all.filter { !$0.isCaregiverSelectable }.map(\.name))

    private func isManageable(_ tile: TileModel) -> Bool {
        !Self.structuralClasses.contains(tile.wordClass)
    }

    private func matches(_ tile: TileModel, _ s: Scope) -> Bool {
        switch s {
        case .all:    return true
        case .review: return tile.needsReview && !tile.isRetired
        case .hidden: return tile.isRetired
        case .added:  return !tile.isSystem && !tile.isRetired && !tile.needsReview
        }
    }

    private func count(_ s: Scope) -> Int { allTiles.filter { isManageable($0) && matches($0, s) }.count }

    /// Word classes actually present (excluding structural), for the class filter.
    private var presentClasses: [String] {
        Array(Set(allTiles.filter(isManageable).map(\.wordClass))).sorted()
    }

    private var filtered: [TileModel] {
        let q = search.trimmingCharacters(in: .whitespaces)
        var list = allTiles.filter { tile in
            guard isManageable(tile) else { return false }
            guard matches(tile, scope) else { return false }
            if let classFilter, tile.wordClass != classFilter { return false }
            if !q.isEmpty,
               !tile.displayName.localizedCaseInsensitiveContains(q),
               !tile.key.localizedCaseInsensitiveContains(q) { return false }
            return true
        }
        if order == .alpha {
            list.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return list
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $scope) {
                    ForEach(Scope.allCases) { s in
                        let n = count(s)
                        Text(n > 0 && s != .all ? "\(s.rawValue) (\(n))" : s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                HStack {
                    Menu {
                        Button("All classes") { classFilter = nil }
                        Divider()
                        ForEach(presentClasses, id: \.self) { c in
                            Button(c.capitalized) { classFilter = c }
                        }
                    } label: {
                        Label(classFilter?.capitalized ?? "All classes", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.subheadline)
                    }
                    Spacer()
                    Picker("Sort", selection: $order) {
                        ForEach(Order.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                }
            }

            Section {
                if filtered.isEmpty {
                    Text("No words match.").foregroundStyle(.secondary)
                } else {
                    ForEach(filtered) { tile in row(tile) }
                }
            } footer: {
                Text("\(filtered.count) word\(filtered.count == 1 ? "" : "s"). Hiding removes a word from the board and clears its cached sentences; it's reversible.")
            }
        }
        .searchable(text: $search, prompt: "Search words")
        .navigationTitle("Vocabulary")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ tile: TileModel) -> some View {
        HStack(spacing: 12) {
            TileImageView(key: tile.key, wordClass: tile.wordClass)
                .frame(width: 34, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .opacity(tile.isRetired ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(tile.displayName)
                subtitle(for: tile)
            }
            Spacer()
            actions(for: tile)
        }
    }

    @ViewBuilder
    private func subtitle(for tile: TileModel) -> some View {
        if tile.isRetired, !tile.retiredReason.isEmpty {
            Text(tile.retiredReason).font(.caption2).foregroundStyle(.red)
        } else if tile.isRetired {
            Text("hidden").font(.caption2).foregroundStyle(.secondary)
        } else if tile.needsReview {
            Text("flagged — may be inappropriate").font(.caption2).foregroundStyle(.orange)
        } else {
            Text(tile.wordClass).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func actions(for tile: TileModel) -> some View {
        if tile.isRetired {
            Button("Restore") { restore(tile) }
                .buttonStyle(.bordered).controlSize(.small).tint(.blue)
        } else if tile.needsReview {
            Button("Keep") { keepReview(tile) }
                .buttonStyle(.bordered).controlSize(.small).tint(.green)
            Button("Hide", role: .destructive) { hide(tile) }
                .buttonStyle(.bordered).controlSize(.small)
        } else {
            Button("Hide", role: .destructive) { hide(tile) }
                .buttonStyle(.bordered).controlSize(.small)
        }
    }

    // MARK: - Actions

    private func hide(_ tile: TileModel) {
        tile.retire()
        _ = SentenceCacheManager(modelContext: context).invalidate(containingTileKey: tile.key)
        try? context.save()
    }

    private func restore(_ tile: TileModel) {
        tile.restore()
        try? context.save()
    }

    private func keepReview(_ tile: TileModel) {
        tile.approveReview()
        try? context.save()
    }
}
