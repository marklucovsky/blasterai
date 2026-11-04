// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  WordWellView.swift
//  claudeBlast
//
//  The page editor's word well: browse words beside the grid and drag them in.
//

import SwiftUI
import SwiftData

/// One word or folder the well offers, as the cell text that places it.
///
/// Carrying cell text (`BoardCell`) rather than a `TileEntry` means a word from
/// a pack that is not in the vocabulary yet travels as `key, class, Display`
/// and is made when it lands, exactly as if it had been typed; a folder from
/// BlasterAI 60 travels as `> sys:places` and finds the core board's own folder.
struct WellItem: Identifiable, Hashable {
    enum Kind: String, CaseIterable, Identifiable {
        case words = "Words", folders = "Folders", doorways = "Doorways"
        var id: String { rawValue }
    }

    var text: String
    /// The tile whose picture the item shows; nil for a word not made yet.
    var key: String?
    /// A word not made yet whose picture ships anyway (a pack's words do):
    /// the key it will be made under, so the well can show the art.
    var artKey: String? = nil
    var label: String
    var wordClass: String
    var kind: Kind
    /// The link's stored colour slot, so a folder or a talking link looks as
    /// it does on the board. Nil for a word, and for a folder never coloured.
    var linkColor: String? = nil
    var id: String { text }
}

/// Where the well's words come from.
enum WellSource: Hashable {
    case vocabulary
    case scenePage(String)
    case systemPage(String)
    case pack(String)
}

extension WellItem {
    /// The items `source` offers. Pure, so the well's contents can be tested
    /// without a view.
    static func items(from source: WellSource, lookup: [String: TileModel],
                      scenePages: [PageSpec], systemPages: [PageSpec]) -> [WellItem] {
        switch source {
        case .vocabulary:
            // Items first, then sort by label: each tile's display name is
            // read once, not twice per comparison (a model read, ~1,200 words).
            let words = lookup.values
                .filter { !$0.isHiddenFromChild && PageLink.targetPage(forKey: $0.key) == nil }
                .map { WellItem(text: $0.key, key: $0.key, label: $0.displayName,
                                wordClass: $0.wordClass, kind: .words) }
                .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
            // Every page of the scene as a folder, so a folder is a drag away.
            let folders = scenePages.map { page -> WellItem in
                let target = BoardCell.Target.scene(page.key)
                let key = BoardCell.folderKey(for: target, scenePages: scenePages, systemPages: systemPages)
                    ?? PageLink.key(forPage: page.key)
                return WellItem(text: "> \(page.key)", key: lookup[key] == nil ? nil : key,
                                label: page.title, wordClass: "", kind: .folders)
            }
            return folders + words
        case .scenePage(let pageKey):
            let page = scenePages.first { $0.key == pageKey }
            return (page?.tiles ?? []).compactMap { entry in
                item(entry, text: BoardCell.format(entry, scenePages: scenePages), lookup: lookup)
            }
        case .systemPage(let pageKey):
            let page = systemPages.first { $0.key == pageKey }
            return (page?.tiles ?? []).compactMap { entry in
                // A link on BlasterAI 60 names BlasterAI 60's page, whatever the
                // scene being edited calls its own.
                var text = entry.key
                if !entry.link.isEmpty, entry.link != TileToken.home {
                    let page = TileToken.systemPageKey(entry.link) ?? entry.link
                    text = (entry.isAudible ? entry.key + " " : "") + "> " + BoardCell.systemMarker + page
                }
                return item(entry, text: text, lookup: lookup)
            }
        case .pack(let id):
            return (PackCatalog.pack(id: id)?.words ?? []).map { word in
                let key = TileModel.normalizeKey(word.key)
                if let tile = lookup[key], tile.wordClass == word.wordClass {
                    return WellItem(text: key, key: key, label: tile.displayName,
                                    wordClass: tile.wordClass, kind: .words)
                }
                return WellItem(text: "\(word.key), \(word.wordClass), \(word.displayName)", key: nil,
                                artKey: key, label: word.displayName, wordClass: word.wordClass, kind: .words)
            }
        }
    }

    private static func item(_ entry: TileEntry, text: String, lookup: [String: TileModel]) -> WellItem? {
        guard !entry.isSpacer, !text.isEmpty else { return nil }
        let tile = lookup[entry.key]
        let kind: Kind = entry.link.isEmpty ? .words : (entry.isAudible ? .doorways : .folders)
        return WellItem(text: text, key: tile == nil ? nil : entry.key,
                        label: entry.label ?? tile?.displayName ?? entry.key,
                        wordClass: tile?.wordClass ?? "", kind: kind, linkColor: entry.linkColor)
    }
}

/// Words beside the grid, to drag into a cell or tap into the cursor's.
///
/// Typing a cell is fastest when you know the word; the well is for when you
/// don't — what is in this pack, what Actions already has, which folders this
/// scene has. It does what the old Add Tiles picker did, beside the grid
/// instead of over it: search, a page of any scene or a pack as the source,
/// class and part-of-speech filters, several words at once, a new word, a
/// pasted list. Words, folders and talking folders are told apart by how they
/// look — colour and the arrow badge, as on the board — not by a filter.
/// Beside the grid on iPad landscape and Mac; above it, `isCompact`, on a
/// portrait iPad. On a phone the grid needs the room and the ⋯ menu's Add
/// Words opens the picker.
///
/// The search field also takes a page: `sys:i_page` shows BlasterAI 60's I
/// page, `page:snacks` this scene's Snacks.
struct WordWellView: View {
    let lookup: [String: TileModel]
    let scenePages: [PageSpec]
    let systemPages: [PageSpec]
    /// The scene being edited, left out of "Other Scenes".
    let sceneID: String
    /// Keys already on the page being edited, marked in the results.
    let onPage: Set<String>
    /// Bumped by ⌘F to put the cursor in the search field.
    let searchFocusToken: Int
    /// Places words into empty cells from the cursor, in order, as one step.
    let onPlace: ([String]) -> Void
    /// Search is done (Return or Escape): the grid takes the keyboard back.
    let onDone: () -> Void
    let dragPrefix: String
    /// A short strip above the grid: the controls go on two lines across,
    /// leaving the height for words.
    var isCompact = false

    @Environment(TileImageResolver.self) private var resolver
    @Query(sort: \BlasterScene.name) private var allScenes: [BlasterScene]
    @State private var query = ""
    @State private var source: WellSource = .vocabulary
    /// A page of another scene: its words only, since its links name pages
    /// of that scene.
    @State private var otherPage: (scene: String, page: PageSpec)?
    @State private var classes: Set<String> = []
    /// Part of speech — "show me the pronouns". A different axis from class:
    /// pronouns are scattered across `core` and `people`.
    @State private var parts: Set<PartOfSpeech> = []
    @State private var notOnPage = false
    @State private var noArt = false
    /// Tapping picks words instead of placing them; Place puts them all down.
    @State private var isPicking = false
    @State private var picked: [String] = []
    @State private var isAddingWord = false
    @State private var isPastingList = false
    @FocusState private var searchFocused: Bool
    @State private var cache = ItemsCache()

    /// The last source's items. Building them reads every word's model
    /// (~1,200) and sorts by label — 56 ms on an A17 Pro — and the well redraws
    /// on every frame of the keyboard rising and on every edit, so the editor
    /// stuttered each time the keyboard came up. Kept until the source, the
    /// vocabulary's size or a page changes.
    private final class ItemsCache {
        struct Key: Equatable {
            var source: WellSource
            var words: Int
            var scenePages: [PageSpec]
            var systemPages: [PageSpec]
        }
        var key: Key?
        var items: [WellItem] = []

        func items(_ key: Key, build: () -> [WellItem]) -> [WellItem] {
            if key != self.key {
                items = build()
                self.key = key
            }
            return items
        }
    }

    private var sourceItems: [WellItem] {
        if let otherPage {
            return otherPage.page.tiles.compactMap { entry in
                guard !entry.isSpacer, let tile = lookup[entry.key], entry.isAudible || entry.link.isEmpty
                else { return nil }
                return WellItem(text: entry.key, key: entry.key, label: entry.label ?? tile.displayName,
                                wordClass: tile.wordClass, kind: .words)
            }
        }
        let key = ItemsCache.Key(source: source, words: lookup.count,
                                 scenePages: scenePages, systemPages: systemPages)
        return cache.items(key) {
            WellItem.items(from: source, lookup: lookup, scenePages: scenePages, systemPages: systemPages)
        }
    }

    /// `items` narrowed by the search and filters. The body works these out
    /// once and hands them down: as computed properties they ran ten times a
    /// redraw, and the page editor redraws on every edit.
    private func results(in items: [WellItem]) -> [WellItem] {
        let q = WordFinder.normalize(query)
        return items.filter { item in
            if !classes.isEmpty, !classes.contains(item.wordClass) { return false }
            if !parts.isEmpty {
                guard let part = partOfSpeech(item), parts.contains(part) else { return false }
            }
            if notOnPage, let key = item.key, onPage.contains(key) { return false }
            if noArt, let key = item.key, resolver.hasResolvedArt(for: key) { return false }
            if q.isEmpty { return true }
            return WordFinder.normalize(item.label).contains(q)
                || (item.key.map { WordFinder.normalize($0.replacingOccurrences(of: "_", with: " ")).contains(q) } ?? false)
        }
    }

    var body: some View {
        let items = sourceItems
        let results = results(in: items)
        let pageFolders = pageFolders(in: results)
        let gridItems = pageFolders.isEmpty ? results : results.filter { $0.kind != .folders }
        let parts = availableParts(in: items)
        let classes = availableClasses(in: items)
        return VStack(alignment: .leading, spacing: 8) {
            if isCompact {
                HStack(spacing: 8) {
                    searchField
                    sourcePicker.fixedSize()
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterMenus(parts: parts, classes: classes)
                        Group {
                            Toggle("Not on this page", isOn: $notOnPage)
                            Toggle("No art yet", isOn: $noArt)
                        }
                        .toggleStyle(.button)
                        .buttonStyle(.bordered)
                        .font(.caption)
                    }
                }
            } else {
                searchField
            }
            // One scroll area under the search field: with the on-screen
            // keyboard up there is only a strip of the well left, and the
            // controls used to fill it with nothing left for the words.
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if !isCompact {
                        sourcePicker
                        // Folded while searching: the keyboard has the room.
                        if !searchFocused { filters(parts: parts, classes: classes) }
                        Divider()
                    }
                    if results.isEmpty {
                        emptyState
                    }
                    if !pageFolders.isEmpty {
                        pagesRow(pageFolders)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                        ForEach(gridItems) { item in
                            itemView(item)
                                .onTapGesture { tap(item) }
                                .draggable(dragPrefix + item.text) {
                                    itemView(item).frame(width: 72).environment(resolver)
                                }
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            footer(results)
        }
        .padding(10)
        .background(.bar)
        .onChange(of: searchFocusToken) { searchFocused = true }
        .sheet(isPresented: $isAddingWord) {
            AddWordSheet(initialWord: query, existingTiles: Array(lookup.values),
                         defaultWordClass: classes.first ?? "object") { tile in
                onPlace([tile.key])
                query = ""
            }
        }
        .sheet(isPresented: $isPastingList) {
            BulkWordSheet(existingTiles: Array(lookup.values)) { tiles in
                onPlace(tiles.map(\.key))
            }
        }
    }

    private var searchField: some View {
        TextField("Search, or sys:page", text: $query)
            .textFieldStyle(.roundedBorder)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($searchFocused)
            .onSubmit {
                if let first = results(in: sourceItems).first { onPlace([first.text]) }
                onDone()
            }
            .onKeyPress(.escape) { onDone(); return .handled }
            .onChange(of: query) { takePageFromQuery() }
    }

    // MARK: - Source

    private var sourcePicker: some View {
        Menu {
            Button("All Words") { setSource(.vocabulary) }
            Menu("This Scene") {
                ForEach(scenePages, id: \.key) { page in
                    Button(page.title) { setSource(.scenePage(page.key)) }
                }
            }
            if !systemPages.isEmpty {
                Menu("BlasterAI 60") {
                    ForEach(systemPages, id: \.key) { page in
                        Button(page.title) { setSource(.systemPage(page.key)) }
                    }
                }
            }
            let others = allScenes.filter { !$0.isDefault && $0.sceneID != sceneID && !$0.pages.isEmpty }
            if !others.isEmpty {
                Menu("Other Scenes") {
                    ForEach(others, id: \.persistentModelID) { scene in
                        Menu(scene.name.isEmpty ? "Untitled scene" : scene.name) {
                            ForEach(scene.pages, id: \.key) { page in
                                Button(page.title) {
                                    setSource(.vocabulary)
                                    otherPage = (scene.name, page)
                                }
                            }
                        }
                    }
                }
            }
            Menu("Word Packs") {
                ForEach(PackCatalog.all) { pack in
                    Button(pack.displayName) { setSource(.pack(pack.id)) }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("From").foregroundStyle(.secondary)
                Text(sourceTitle).fontWeight(.semibold).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.15)))
        }
    }

    private func setSource(_ new: WellSource) {
        source = new
        otherPage = nil
        picked = []
    }

    /// `sys:i_page` or `page:snacks` in the search field becomes the source,
    /// matched by key or title, and leaves the field.
    private func takePageFromQuery() {
        let text = query.trimmingCharacters(in: .whitespaces)
        let lower = text.lowercased()
        func match(_ name: String, in pages: [PageSpec]) -> PageSpec? {
            let key = BoardCell.pageKey(name)
            return pages.first { $0.key == key }
                ?? pages.first { WordFinder.normalize($0.title) == WordFinder.normalize(name) }
        }
        if lower.hasPrefix(BoardCell.systemMarker),
           let page = match(String(text.dropFirst(BoardCell.systemMarker.count)), in: systemPages) {
            setSource(.systemPage(page.key)); query = ""
        } else if lower.hasPrefix("page:"), let page = match(String(text.dropFirst(5)), in: scenePages) {
            setSource(.scenePage(page.key)); query = ""
        }
    }

    private var sourceTitle: String {
        if let otherPage { return "\(otherPage.scene) › \(otherPage.page.title)" }
        switch source {
        case .vocabulary: return "All Words"
        case .scenePage(let key): return scenePages.first { $0.key == key }?.title ?? key
        case .systemPage(let key): return "BlasterAI › " + PageNaming.displayName(key)
        case .pack(let id): return PackCatalog.pack(id: id)?.displayName ?? id
        }
    }

    // MARK: - Filters

    private func filters(parts: [PartOfSpeech], classes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Wraps to a second line when three filters do not fit across.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { filterMenus(parts: parts, classes: classes) }
                VStack(alignment: .leading, spacing: 6) { filterMenus(parts: parts, classes: classes) }
            }
            Toggle("Not on this page", isOn: $notOnPage).font(.caption)
            Toggle("No art yet", isOn: $noArt).font(.caption)
        }
    }

    @ViewBuilder
    private func filterMenus(parts availableParts: [PartOfSpeech], classes availableClasses: [String]) -> some View {
        Menu {
            Button("Any Kind") { parts = [] }
            ForEach(availableParts) { part in
                Button {
                    if parts.contains(part) { parts.remove(part) } else { parts.insert(part) }
                } label: {
                    if parts.contains(part) { Label(part.label, systemImage: "checkmark") } else { Text(part.label) }
                }
            }
        } label: {
            filterLabel(parts.isEmpty ? "Any kind"
                        : parts.map(\.label).sorted().joined(separator: ", "),
                        icon: "textformat")
        }
        Menu {
            Button("Any Class") { classes = [] }
            ForEach(availableClasses, id: \.self) { name in
                Button {
                    if classes.contains(name) { classes.remove(name) } else { classes.insert(name) }
                } label: {
                    if classes.contains(name) { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
            }
        } label: {
            filterLabel(classes.isEmpty ? "Any class" : classes.sorted().joined(separator: ", "),
                        icon: "line.3.horizontal.decrease.circle")
        }
    }

    private func filterLabel(_ text: String, icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(Capsule().fill(Color.secondary.opacity(0.15)))
    }

    private func partOfSpeech(_ item: WellItem) -> PartOfSpeech? {
        item.key.flatMap { lookup[$0]?.resolvedPartOfSpeech }
    }

    /// The parts of speech the source has, in the enum's order.
    private func availableParts(in items: [WellItem]) -> [PartOfSpeech] {
        let present = Set(items.compactMap(partOfSpeech))
        return PartOfSpeech.allCases.filter(present.contains)
    }

    private func availableClasses(in items: [WellItem]) -> [String] {
        Set(items.map(\.wordClass).filter { !$0.isEmpty }).sorted()
    }

    // MARK: - Results

    /// In All Words, the scene's pages are a row of folders above the words,
    /// so a folder is always a drag away without filtering for it. A page as
    /// the source shows its tiles in board order instead.
    private func pageFolders(in results: [WellItem]) -> [WellItem] {
        guard source == .vocabulary, otherPage == nil else { return [] }
        return results.filter { $0.kind == .folders }
    }

    private func pagesRow(_ pageFolders: [WellItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Pages").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(pageFolders) { item in
                        itemView(item)
                            .frame(width: 76)
                            .onTapGesture { tap(item) }
                            .draggable(dragPrefix + item.text) {
                                itemView(item).frame(width: 72).environment(resolver)
                            }
                    }
                }
            }
            Text("Words").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(.bottom, 4)
    }

    private func tap(_ item: WellItem) {
        guard isPicking else { onPlace([item.text]); return }
        if let i = picked.firstIndex(of: item.text) { picked.remove(at: i) } else { picked.append(item.text) }
    }

    @ViewBuilder
    private var emptyState: some View {
        let word = query.trimmingCharacters(in: .whitespaces)
        if !word.isEmpty {
            Button { isAddingWord = true } label: {
                Label("New word \u{201C}\(word)\u{201D}…", systemImage: "plus.circle")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private func footer(_ results: [WellItem]) -> some View {
        if isPicking {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(picked.count == results.count ? "Select None" : "Select All \(results.count)") {
                        picked = picked.count == results.count ? [] : results.map(\.text)
                    }
                    Spacer()
                    Button("Done") { isPicking = false; picked = [] }
                }
                .font(.caption.weight(.semibold))
                Button {
                    onPlace(picked)
                    picked = []
                    isPicking = false
                } label: {
                    Text(picked.isEmpty ? "Pick words to place" : "Place \(picked.count) from the Cursor")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(picked.isEmpty)
            }
        } else {
            HStack {
                Button { isPicking = true } label: {
                    Label("Select", systemImage: "checkmark.circle").font(.caption)
                }
                Button { isPastingList = true } label: {
                    Label("Paste List", systemImage: "list.bullet.clipboard").font(.caption)
                }
                Spacer()
                Text("\(results.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func itemView(_ item: WellItem) -> some View {
        Group {
            if let key = item.key, let tile = lookup[key] {
                // Any non-empty link draws the arrow badge; the page itself
                // does not matter here.
                PageTileCell(tile: tile, link: item.kind == .words ? "" : "link",
                             linkColor: item.linkColor, isAudible: item.kind != .folders)
            } else if let art = item.artKey, resolver.hasResolvedArt(for: art) {
                // Coloured as it will be once made: its class's part of speech.
                TileFace(imageKey: art, label: item.label, wordClass: item.wordClass,
                         accent: TileColorResolver.color(
                            for: VocabularyClasses.known(item.wordClass)?.defaultPartOfSpeech),
                         labelFontSize: 10)
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.12))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        Text(item.label)
                            .font(.caption2.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .padding(3)
                    }
            }
        }
        .overlay(alignment: .topTrailing) {
            if let key = item.key, onPage.contains(key) {
                Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(3)
                    .accessibilityLabel("On this page")
            }
        }
        .overlay {
            if isPicking, let n = picked.firstIndex(of: item.text) {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3)
                Text("\(n + 1)")
                    .font(.caption.weight(.bold))
                    .padding(5)
                    .background(Circle().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
        }
        .contentShape(Rectangle())
        .accessibilityLabel(item.label)
    }
}
