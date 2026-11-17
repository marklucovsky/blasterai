// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageChooser.swift
//  claudeBlast
//
//  One way to pick a page: browse each board as a tree of its folders, or
//  search and see every match by its route from home. See `PageChoice`.
//

import SwiftUI

struct PageChooser: View {
    enum Pick {
        /// One page, handed back when tapped; `selected` is checked.
        case one(selected: String?, (String) -> Void)
        /// Several, toggled in place.
        case many(Binding<Set<String>>)
    }

    let groups: [PageGroup]
    /// A first row that chooses no page (handed back as ""), e.g. "None".
    var noneLabel: String? = nil
    /// Pages shown but not choosable.
    var disabled: Set<String> = []
    /// A line under a page, e.g. why it is disabled.
    var note: (String) -> String? = { _ in nil }
    /// A line above the list, e.g. what choosing does.
    var intro: String? = nil
    var footer: String? = nil
    let pick: Pick

    @State private var query = ""
    @State private var collapsed: Set<String> = []
    /// Open folders, as `board + "\u{1F}" + value`: a Me page context's
    /// value is shared by every board that has the page.
    @State private var expanded: Set<String> = []
    @State private var didOpenChosen = false

    var body: some View {
        let shown = PageChoice.filter(groups, query: query)
        let searching = !WordFinder.normalize(query).isEmpty
        List {
            if let intro, !searching {
                Section {} header: { Text(intro).textCase(nil) }
            }
            if let noneLabel, !searching {
                Section {
                    Button { choose("") } label: {
                        HStack {
                            Text(noneLabel).foregroundStyle(.primary)
                            Spacer()
                            check(isOn("" ))
                        }
                    }
                }
            }
            ForEach(shown) { group in
                Section(isExpanded: Binding(
                    // A search opens every board: a match in a closed one
                    // would otherwise look like no match.
                    get: { searching || !collapsed.contains(group.board) },
                    set: { open in
                        if open { collapsed.remove(group.board) } else { collapsed.insert(group.board) }
                    })) {
                    if searching {
                        ForEach(group.options) { row($0, showsParents: true) }
                    } else {
                        ForEach(group.tree) { branch($0, in: group.board) }
                    }
                } header: {
                    Text(group.board)
                }
            }
            if let footer {
                Section {} footer: { Text(footer) }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Find a page or a word on it")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .overlay {
            if shown.isEmpty && searching { ContentUnavailableView.search(text: query) }
        }
        .onAppear(perform: openChosen)
    }

    // MARK: Browsing

    /// A page, and when it is a folder the pages it opens beneath it. The
    /// row picks the page; the chevron opens it.
    private func branch(_ node: PageNode, in board: String) -> AnyView {
        guard let children = node.children else {
            return AnyView(row(node.option, showsParents: false))
        }
        let id = board + "\u{1F}" + node.option.value
        return AnyView(DisclosureGroup(isExpanded: Binding(
            get: { expanded.contains(id) },
            set: { open in
                if open { expanded.insert(id) } else { expanded.remove(id) }
            })) {
                ForEach(children) { branch($0, in: board) }
            } label: {
                row(node.option, showsParents: false)
            })
    }

    /// Open the folders above every page already chosen, once, so the
    /// check is in view rather than buried under a closed folder.
    private func openChosen() {
        guard !didOpenChosen else { return }
        didOpenChosen = true
        let chosen: Set<String> = switch pick {
        case .one(let selected, _): selected.map { [$0] } ?? []
        case .many(let picked): picked.wrappedValue
        }
        guard !chosen.isEmpty else { return }
        for group in groups {
            func walk(_ node: PageNode) {
                guard let children = node.children else { return }
                if children.contains(where: { !chosen.isDisjoint(with: $0.allValues) }) {
                    expanded.insert(group.board + "\u{1F}" + node.option.value)
                }
                children.forEach(walk)
            }
            group.tree.forEach(walk)
        }
    }

    // MARK: Rows

    private func row(_ option: PageOption, showsParents: Bool) -> some View {
        Button { choose(option.value) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if showsParents, !option.parents.isEmpty {
                        Text(option.parents)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(option.title).foregroundStyle(.primary)
                    if showsParents, let word = PageChoice.matchedWord(in: option, query: query) {
                        Label("Has \u{201C}\(word)\u{201D}", systemImage: "text.magnifyingglass")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let line = note(option.value) {
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                check(isOn(option.value))
            }
        }
        .disabled(disabled.contains(option.value))
        .accessibilityLabel(option.board + ", " + option.path)
    }

    @ViewBuilder
    private func check(_ on: Bool) -> some View {
        if on { Image(systemName: "checkmark").foregroundStyle(.tint) }
    }

    private func isOn(_ value: String) -> Bool {
        switch pick {
        case .one(let selected, _): selected == value
        case .many(let picked): picked.wrappedValue.contains(value)
        }
    }

    private func choose(_ value: String) {
        switch pick {
        case .one(_, let onPick): onPick(value)
        case .many(let picked):
            if picked.wrappedValue.contains(value) {
                picked.wrappedValue.remove(value)
            } else {
                picked.wrappedValue.insert(value)
            }
        }
    }
}
