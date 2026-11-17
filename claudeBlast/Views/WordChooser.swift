// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordChooser.swift
//  claudeBlast
//
//  One way to pick a word: search plus class chips. Used for a cover, a
//  word's borrowed art, a profile picture and a Me page's words.
//

import SwiftUI
import SwiftData

/// A filter chip in a word class's own color, so the chip row reads like the
/// board: Actions is the color every action word wears.
struct ClassChip: View {
    let label: String
    let color: Color
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? color : color.opacity(0.22)))
                .overlay(Capsule().strokeBorder(color.opacity(isSelected ? 0 : 0.6), lineWidth: 1))
                .foregroundStyle(isSelected ? TileColorResolver.label(on: color) : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The color a chip for `wordClass` wears: navigation for folders.
    static func color(ofClass wordClass: String) -> Color {
        wordClass == PageLink.wordClass
            ? TileColorResolver.navigation
            : TileColorResolver.color(forWordClass: wordClass)
    }
}

/// All, then one chip per class. `nil` is All.
struct ClassChipRow: View {
    let classes: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ClassChip(label: "All", color: .accentColor, isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(classes, id: \.self) { wc in
                    ClassChip(label: WordChoice.label(ofClass: wc),
                              color: ClassChip.color(ofClass: wc),
                              isSelected: selection == wc) {
                        selection = selection == wc ? nil : wc
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

/// Search and class chips over the vocabulary. The caller supplies the
/// NavigationStack, title and toolbar; this is the content.
struct WordChooser: View {
    enum Layout { case list, grid }

    enum Pick {
        /// One word, handed back the moment it is tapped.
        case one((TileModel) -> Void)
        /// Several, numbered in the order tapped.
        case ordered(Binding<[String]>)
    }

    var layout: Layout = .list
    var rules = WordChoice.Rules()
    /// Words to offer first, before any search or chip narrows the list.
    var suggested: [String] = []
    var suggestedTitle = "Suggested"
    /// The word already chosen, shown with a checkmark.
    var checked: String? = nil
    var prompt = "Search all words"
    let pick: Pick

    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @State private var query = ""
    @State private var wordClass: String?

    private var candidates: [TileModel] { WordChoice.candidates(allTiles, rules: rules) }

    var body: some View {
        let offered = candidates
        let searched = WordChoice.filter(offered, query: query, wordClass: nil)
        let shown = wordClass.map { wc in searched.filter { $0.wordClass == wc } } ?? searched
        // Chips for the classes the search left, so none opens an empty list;
        // the selected one stays even when the search has emptied it.
        var chips = WordChoice.classes(of: searched)
        if let wordClass, !chips.contains(wordClass) { chips.insert(wordClass, at: 0) }
        let lookup = Dictionary(offered.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let firsts = query.isEmpty && wordClass == nil ? suggested.compactMap { lookup[$0] } : []

        return Group {
            switch layout {
            case .list: list(firsts: firsts, rest: shown)
            case .grid: grid(firsts: firsts, rest: shown)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            ClassChipRow(classes: chips, selection: $wordClass)
                .background(.bar)
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: prompt)
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .overlay {
            if shown.isEmpty && firsts.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
    }

    // MARK: List

    private func list(firsts: [TileModel], rest: [TileModel]) -> some View {
        List {
            if !firsts.isEmpty {
                Section(suggestedTitle) {
                    ForEach(firsts, id: \.key) { row($0) }
                }
                Section("All Words") {
                    ForEach(rest, id: \.key) { row($0) }
                }
            } else {
                ForEach(rest, id: \.key) { row($0) }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ tile: TileModel) -> some View {
        Button { tap(tile) } label: {
            HStack(spacing: 12) {
                TileImageView(key: tile.key, wordClass: tile.wordClass)
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text(tile.displayName).foregroundStyle(.primary)
                Spacer()
                mark(for: tile)
            }
        }
    }

    // MARK: Grid

    private func grid(firsts: [TileModel], rest: [TileModel]) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                if !firsts.isEmpty {
                    gridSection(suggestedTitle, firsts)
                    gridSection("All Words", rest)
                } else {
                    ForEach(rest, id: \.key) { cell($0) }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func gridSection(_ title: String, _ tiles: [TileModel]) -> some View {
        Section {
            ForEach(tiles, id: \.key) { cell($0) }
        } header: {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        }
    }

    private func cell(_ tile: TileModel) -> some View {
        Button { tap(tile) } label: {
            VStack(spacing: 4) {
                TileImageView(key: tile.key, wordClass: tile.wordClass)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(alignment: .topTrailing) { mark(for: tile).padding(4) }
                Text(tile.displayName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Picking

    @ViewBuilder
    private func mark(for tile: TileModel) -> some View {
        switch pick {
        case .one:
            if tile.key == checked {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white, .tint)
            }
        case .ordered(let picked):
            if let n = picked.wrappedValue.firstIndex(of: tile.key) {
                Text("\(n + 1)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.tint))
            }
        }
    }

    private func tap(_ tile: TileModel) {
        switch pick {
        case .one(let onPick):
            onPick(tile)
        case .ordered(let picked):
            if let i = picked.wrappedValue.firstIndex(of: tile.key) {
                picked.wrappedValue.remove(at: i)
            } else {
                picked.wrappedValue.append(tile.key)
            }
        }
    }
}
