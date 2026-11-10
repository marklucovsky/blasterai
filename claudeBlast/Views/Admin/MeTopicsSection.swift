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
    @State private var isEditingMe = false

    /// BlasterAI 60, whose pages a topic can be shown on.
    @Query(filter: #Predicate<BlasterScene> { $0.isDefault })
    private var systemScenes: [BlasterScene]

    private var me: BlasterScene? { scenes.first { $0.sceneID == MeScene.sceneID(forProfileID: profileID) } }

    private var topics: [BlasterScene] {
        guard let me else { return [] }
        return MeScene.topicIDs(in: me).compactMap { id in scenes.first { $0.sceneID == id } }
    }

    private var addable: [BlasterScene] {
        let on = Set(me.map(MeScene.topicIDs(in:)) ?? [])
        return scenes.filter { MeScene.isEligibleTopic($0) && !on.contains($0.sceneID) }
    }

    private func shownOn(_ topic: BlasterScene, me: BlasterScene, system: BlasterScene) -> String {
        let keys = MeScene.contexts(of: topic.sceneID, in: me)
        guard !keys.isEmpty else { return "Not shown on any page" }
        return "Shown on " + keys.map { key in
            MeScene.contextTitle(key, system: system, scenes: scenes)
        }.joined(separator: ", ")
    }

    var body: some View {
        Group {
            topicsSection
            if let me, let system = systemScenes.first {
                pageByPageSection(me: me, system: system)
            }
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

    /// What the Me page adds for each board page the child comes from.
    private func pageByPageSection(me: BlasterScene, system: BlasterScene) -> some View {
        let keys = me.pages.compactMap { MeScene.systemKey(ofContextPage: $0.key) }
        return Section {
            ForEach(keys, id: \.self) { key in
                NavigationLink {
                    ContextPageView(me: me, system: system, systemKey: key)
                } label: {
                    let count = me.page(withKey: MeScene.contextPageKey(for: key))?.tiles.count ?? 0
                    LabeledContent(MeScene.contextTitle(key, system: system, scenes: scenes),
                                   value: count == 1 ? "1 item" : "\(count) items")
                }
            }
            NavigationLink {
                // BlasterAI 60's pages, then the pages of the caregiver's own
                // scenes: a page is matched by name on any board.
                let groups = MeScene.contextChoices(system: system, scenes: scenes)
                let shared = MeScene.sharedContextKeys(groups)
                BoardSectionsList(groups: groups) { page in
                    NavigationLink {
                        ContextPageView(me: me, system: system, systemKey: page.key)
                    } label: {
                        ContextChoiceLabel(title: page.title, isShared: shared.contains(page.key))
                    }
                }
                .navigationTitle("Add a Page")
            } label: {
                Label("Add a Page", systemImage: "plus.circle")
            }
        } header: {
            Text("Me Page by Page")
        } footer: {
            Text("When the child presses the heart from one of these pages, the Me page adds what is listed: folders from column 8, and words below your own tiles. A page counts by its name, on BlasterAI 60 or any of your scenes.")
        }
    }

    private var topicsSection: some View {
        Section {
            ForEach(topics) { topic in
                if let me, let system = systemScenes.first {
                    NavigationLink {
                        TopicContextsView(topic: topic, me: me, system: system)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(topic.name)
                                Text(shownOn(topic, me: me, system: system))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "heart.fill")
                        }
                    }
                } else {
                    Label(topic.name, systemImage: "heart.fill")
                }
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
                Button { isEditingMe = true } label: {
                    Label("Edit Me Page", systemImage: "pencil")
                }
                // Full screen, not pushed inside the profile sheet: the page
                // editor is a 10 × 6 grid, and a form sheet gave it half the
                // screen and its tiles half their size.
                .fullScreenCover(isPresented: $isEditingMe) {
                    NavigationStack {
                        SceneEditorView(scene: me)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Done") { isEditingMe = false }
                                }
                            }
                    }
                }
            }
        } header: {
            Text("Me Page and Topics")
        } footer: {
            Text("The heart on the board opens this child's own page. My Topics lists the scenes added here, without replacing the main board. Tap a topic to show it on the Me page whenever the child comes from a page of the main board. Only scenes on the 10 × 6 layout can be topics. Changes apply right away.")
        }
    }
}

/// One board page's list on the Me page: the items shown when the child
/// presses the heart from it, in order. Each is a source (a topic page or a
/// board page) shown as a folder, as words, or both. See `MeScene.compose`.
struct ContextPageView: View {
    @Bindable var me: BlasterScene
    let system: BlasterScene
    let systemKey: String

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BlasterScene.name) private var scenes: [BlasterScene]
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @State private var isPickingWords = false

    /// Pages of the main board an item can come from or be shown for: all
    /// but its home, which clears the context.
    static func boardPages(_ system: BlasterScene) -> [PageSpec] {
        system.pages.filter { $0.key != system.homePageKey }
    }

    private var title: String { MeScene.contextTitle(systemKey, system: system, scenes: scenes) }
    private var items: [TileEntry] { me.page(withKey: MeScene.contextPageKey(for: systemKey))?.tiles ?? [] }
    private var topics: [BlasterScene] { scenes.filter(MeScene.isEligibleTopic) }

    var body: some View {
        List {
            Section {
                // Words share an empty link, so they are told apart by key.
                ForEach(items, id: \.self.listID) { item in
                    if MeScene.isWordItem(item) {
                        row(item, wordClass: lookup[item.key]?.wordClass ?? "",
                            name: lookup[item.key]?.displayName ?? item.label ?? item.key)
                    } else {
                        NavigationLink {
                            ContextItemView(me: me, systemKey: systemKey, link: item.link, pageTitle: title)
                        } label: {
                            row(item, wordClass: PageLink.wordClass, name: item.label ?? item.key)
                        }
                    }
                }
                .onMove { from, to in
                    var moved = items
                    moved.move(fromOffsets: from, toOffset: to)
                    MeScene.setItems(moved, onPage: systemKey, in: me)
                    try? modelContext.save()
                }
                .onDelete { offsets in
                    var kept = items
                    kept.remove(atOffsets: offsets)
                    MeScene.setItems(kept, onPage: systemKey, in: me)
                    try? modelContext.save()
                }
            } footer: {
                Text("Folders go from column 8 into the free cells of columns 9 and 10. Words, yours and those taken from pages, go below your own tiles in list order, after an empty row when there is room. What does not fit is left off; turn the folder on to keep the rest one tap away.")
            }
        }
        .navigationTitle("On " + title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { addMenu }
            ToolbarItem(placement: .primaryAction) { EditButton() }
        }
        .sheet(isPresented: $isPickingWords) {
            ContextWordPicker(listed: Set(items.filter(MeScene.isWordItem).map(\.key))) { keys in
                MeScene.addWords(keys, onPage: systemKey, in: me, title: title)
                try? modelContext.save()
            }
        }
    }

    private var lookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func row(_ item: TileEntry, wordClass: String, name: String) -> some View {
        HStack(spacing: 12) {
            TileImageView(key: item.key, wordClass: wordClass)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(Self.mode(of: item)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var addMenu: some View {
        let present = Set(items.map(\.link))
        return Menu {
            Button("Words…") { isPickingWords = true }
            Menu("A Topic Page") {
                ForEach(topics) { topic in
                    Menu(topic.name) {
                        ForEach(topicPages(topic), id: \.key) { page in
                            let link = TileToken.sceneLink(topic.sceneID, to: page.key)
                            Button(page.key == topic.homePageKey ? topic.name : page.title) {
                                add(topicItem(topic, page: page))
                            }
                            .disabled(present.contains(link))
                        }
                    }
                }
            }
            Menu("A Board Page") {
                ForEach(Self.boardPages(system), id: \.key) { page in
                    Button(page.title) {
                        add(TileEntry(key: MeScene.folderKey(forPage: page.key, in: system),
                                      link: TileToken.systemLink(to: page.key),
                                      isAudible: false, label: page.title))
                    }
                    .disabled(present.contains(TileToken.systemLink(to: page.key)))
                }
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    /// Home first, then the topic's other pages.
    private func topicPages(_ topic: BlasterScene) -> [PageSpec] {
        let pages = topic.visiblePages
        return pages.filter { $0.key == topic.homePageKey } + pages.filter { $0.key != topic.homePageKey }
    }

    private func topicItem(_ topic: BlasterScene, page: PageSpec) -> TileEntry {
        let isHome = page.key == topic.homePageKey
        let key = isHome ? SceneCover.ensure(for: topic, context: modelContext).key
                         : MeScene.folderKey(forPage: page.key, in: topic)
        return TileEntry(key: key, link: TileToken.sceneLink(topic.sceneID, to: page.key),
                         isAudible: false, label: isHome ? topic.name : page.title)
    }

    private func add(_ item: TileEntry) {
        MeScene.setItem(item, onPage: systemKey, in: me, title: title)
        try? modelContext.save()
    }

    /// "Folder", "4 words + folder", "All words".
    static func mode(of item: TileEntry) -> String {
        if MeScene.isWordItem(item) { return "Word" }
        let words: String? = item.inline.map { $0 == TileEntry.inlineAll ? "All words" : $0 == 1 ? "1 word" : "\($0) words" }
        switch (words, item.hidesFolder) {
        case (nil, false): return "Folder"
        case (let w?, false): return w + " + folder"
        case (let w?, true): return w
        case (nil, true): return "Nothing shown"
        }
    }
}

/// How one item shows on the Me page: a folder, words, or both.
struct ContextItemView: View {
    @Bindable var me: BlasterScene
    let systemKey: String
    let link: String
    let pageTitle: String

    @Environment(\.modelContext) private var modelContext

    private var item: TileEntry? {
        me.page(withKey: MeScene.contextPageKey(for: systemKey))?.tiles.first { $0.link == link }
    }

    /// −1 none, 0 all, N the first N — a Picker tag cannot be nil.
    private static let none = -1

    var body: some View {
        Form {
            if let item {
                Section {
                    Toggle("Folder", isOn: Binding(
                        get: { !item.hidesFolder },
                        set: { on in update { $0.hidesFolder = !on } }))
                    Picker("Words", selection: Binding(
                        get: { item.inline ?? Self.none },
                        set: { n in update { $0.inline = n == Self.none ? nil : n } })) {
                        Text("None").tag(Self.none)
                        ForEach(1...8, id: \.self) { Text("\($0)").tag($0) }
                        Text("All").tag(TileEntry.inlineAll)
                    }
                } footer: {
                    Text("Words are this page's words in order, leaving out folders and words the Me page already shows.")
                }
            }
        }
        .navigationTitle(item?.label ?? "Item")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func update(_ change: (inout TileEntry) -> Void) {
        guard var changed = item else { return }
        change(&changed)
        MeScene.setItem(changed, onPage: systemKey, in: me, title: pageTitle)
        try? modelContext.save()
    }
}

/// Which pages of BlasterAI 60 a topic is shown for on the Me page. See
/// `MeScene.setContexts`.
struct TopicContextsView: View {
    let topic: BlasterScene
    @Bindable var me: BlasterScene
    let system: BlasterScene

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BlasterScene.name) private var scenes: [BlasterScene]

    /// Every page a context can be for, by board: BlasterAI 60's, then the
    /// caregiver's own scenes'. The topic's own pages are left out.
    private var groups: [(board: String, pages: [PageSpec])] {
        MeScene.contextChoices(system: system, scenes: scenes.filter { $0.sceneID != topic.sceneID })
    }

    private var pages: [PageSpec] { groups.flatMap(\.pages) }

    var body: some View {
        let on = Set(MeScene.contexts(of: topic.sceneID, in: me))
        let shared = MeScene.sharedContextKeys(groups)
        BoardSectionsList(groups: groups,
                          footer: "When the child presses the heart from one of these pages, \(topic.name) appears on their Me page, from column 8 into the free cells of columns 9 and 10. A page counts by its name, on any board. Each page's order is set in Edit Me Page, on its \"On …\" page.") { page in
                    Button {
                        var keys = on
                        if keys.contains(page.key) { keys.remove(page.key) } else { keys.insert(page.key) }
                        MeScene.setContexts(keys, for: topic, in: me, context: modelContext,
                                            titles: Dictionary(pages.map { ($0.key, $0.title) },
                                                               uniquingKeysWith: { first, _ in first }))
                        try? modelContext.save()
                    } label: {
                        HStack {
                            ContextChoiceLabel(title: page.title, isShared: shared.contains(page.key))
                            Spacer()
                            if on.contains(page.key) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
        }
        .navigationTitle("Show \(topic.name) On")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension TileEntry {
    /// A row's identity on a context page: a source by its link, a word by
    /// its key.
    var listID: String { link.isEmpty ? "w:" + key : link }
}

/// Existing words to put on a Me context page, in the order tapped. Nothing
/// here makes a new word.
struct ContextWordPicker: View {
    /// Words already on the list, left out.
    let listed: Set<String>
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @State private var query = ""
    @State private var picked: [String] = []

    private var words: [TileModel] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return allTiles
            .filter { $0.wordClass != PageLink.wordClass && !listed.contains($0.key) }
            .filter { q.isEmpty || $0.key.contains(q) || $0.displayName.lowercased().contains(q) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List(words, id: \.key) { tile in
                Button { toggle(tile.key) } label: {
                    HStack(spacing: 12) {
                        TileImageView(key: tile.key, wordClass: tile.wordClass)
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text(tile.displayName).foregroundStyle(.primary)
                        Spacer()
                        if let n = picked.firstIndex(of: tile.key) {
                            Text("\(n + 1)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(.tint))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Find a word")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .navigationTitle("Add Words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(picked.count)") {
                        onAdd(picked)
                        dismiss()
                    }
                    .disabled(picked.isEmpty)
                }
            }
        }
    }

    private func toggle(_ key: String) {
        if let i = picked.firstIndex(of: key) { picked.remove(at: i) } else { picked.append(key) }
    }
}

/// A page a context can be for. A name more than one board has is one
/// context, so it says so: choosing Places on Sunday School chooses
/// BlasterAI 60's Places too.
struct ContextChoiceLabel: View {
    let title: String
    let isShared: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).foregroundStyle(.primary)
            if isShared {
                Text("Same name on another board: one list for both")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Pages grouped by board, each board's section collapsible: a caregiver
/// with several scenes would otherwise scroll past all of BlasterAI 60 to
/// reach their own. Every section starts open.
struct BoardSectionsList<Row: View>: View {
    let groups: [(board: String, pages: [PageSpec])]
    var footer: String? = nil
    @ViewBuilder let row: (PageSpec) -> Row
    @State private var collapsed: Set<String> = []

    var body: some View {
        List {
            ForEach(groups, id: \.board) { group in
                Section(isExpanded: Binding(
                    get: { !collapsed.contains(group.board) },
                    set: { open in
                        if open { collapsed.remove(group.board) } else { collapsed.insert(group.board) }
                    })) {
                    ForEach(group.pages, id: \.key) { page in row(page) }
                } header: {
                    Text(group.board)
                }
            }
            if let footer {
                Section {} footer: { Text(footer) }
            }
        }
        .listStyle(.sidebar)
    }
}
