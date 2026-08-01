// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TilePickerView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

struct TilePickerView: View {
    @Bindable var scene: BlasterScene
    let pageKey: String
    var initialSelectedKeys: Set<String> = []
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    /// All scenes — source for the "From a page…" tile-source picker.
    @Query private var allScenes: [BlasterScene]

    @State private var selectedKeys: Set<String> = []
    /// When set, the grid is filtered to these tile keys (in page order): the
    /// word tiles of a page picked via "From a page…". `nil` = no page source.
    @State private var pageSourceKeys: [String]? = nil
    @State private var pageSourceLabel = ""
    @State private var searchText = ""
    @State private var selectedWordClass = "all"
    @State private var suggestionGoal = ""
    @State private var isSuggesting = false
    @State private var suggestionError: String? = nil
    /// Note surfaced after a suggestion adds new vocabulary words.
    @State private var newWordsNote: String? = nil
    /// New-word keys materialized during this picker session. Any that don't end
    /// up on a page are rolled back on dismiss (suggested-then-cancelled), so the
    /// vocabulary doesn't accrete orphan AI words.
    @State private var sessionNewWordKeys: Set<String> = []
    @State private var showAddWord = false
    @State private var showBulkWord = false
    @FocusState private var searchFocused: Bool

    // P3: editable `key, class[, Display]` list bound to the selection. Tapping
    // tiles fills it in; editing it reconciles back into `selectedKeys` (new words
    // materialized). Two-way with a focus guard so taps never clobber typing.
    @State private var listExpanded = false
    @State private var selectionText = ""
    @FocusState private var listFocused: Bool
    /// class/display for words materialized from the list, so the list renders
    /// them correctly even before the `@Query` for `allTiles` refreshes.
    @State private var sessionNewWords: [String: BulkWordParser.Word] = [:]

    private var apiKey: String {
        OpenAIKeyVault.currentKey() ?? ""
    }

    private var existingKeys: Set<String> {
        Set(scene.pages.first { $0.key == pageKey }?.tiles.map(\.key) ?? [])
    }

    private var wordClasses: [String] {
        // Pin Page Links after "All"; word classes alphabetically. Packs get their
        // own prominent row (see packFilter), not buried at the end of this list.
        let present = Set(allTiles.map(\.wordClass))
        var ordered = ["all"]
        if present.contains(PageLink.wordClass) { ordered.append(PageLink.wordClass) }
        ordered += present.subtracting([PageLink.wordClass]).sorted()
        return ordered
    }

    /// Packs with at least one installed word — worth a filter chip.
    private var installedPacks: [VocabPack] {
        let keys = Set(allTiles.map(\.key))
        return PackCatalog.all.filter { pack in pack.words.contains { keys.contains($0.key) } }
    }

    private func packKeys(_ slug: String) -> Set<String> {
        Set(PackCatalog.all.first { $0.slug == slug }?.words.map(\.key) ?? [])
    }

    private func classLabel(_ wc: String) -> String {
        if wc == "all" { return "All" }
        if wc == PageLink.wordClass { return "Page Links" }
        if wc.hasPrefix("pack:") {
            let slug = String(wc.dropFirst("pack:".count))
            return "📦 " + (PackCatalog.all.first { $0.slug == slug }?.displayName ?? slug)
        }
        return wc
    }

    private func matchesSearch(_ tile: TileModel) -> Bool {
        searchText.isEmpty
            || tile.displayName.localizedCaseInsensitiveContains(searchText)
            || tile.key.localizedCaseInsensitiveContains(searchText)
    }

    private var filteredTiles: [TileModel] {
        // A "From a page…" source takes over the grid: exactly that page's word
        // tiles, in page order, narrowed by search.
        if let pageSourceKeys {
            let byKey = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
            return pageSourceKeys.compactMap { key in
                guard let tile = byKey[key], matchesSearch(tile) else { return nil }
                return tile
            }
        }
        let packKeySet: Set<String>? = selectedWordClass.hasPrefix("pack:")
            ? packKeys(String(selectedWordClass.dropFirst("pack:".count))) : nil
        return allTiles.filter { tile in
            // On-page tiles are NOT excluded — they render marked "on page" in the
            // grid (see pickerCell), so a search like "Golde" that matches an
            // already-added "Golden Retriever" shows it instead of an empty state.
            if let packKeySet {
                if !packKeySet.contains(tile.key) { return false }
            } else if selectedWordClass != "all" && tile.wordClass != selectedWordClass {
                return false
            }
            if !searchText.isEmpty
                && !tile.displayName.localizedCaseInsensitiveContains(searchText)
                && !tile.key.localizedCaseInsensitiveContains(searchText) {
                return false
            }
            return true
        }
    }

    /// Grid tiles that can actually be selected — on-page ones show for context
    /// but are locked, so a "select all" must skip them.
    private var selectableFilteredKeys: [String] {
        filteredTiles.compactMap { existingKeys.contains($0.key) ? nil : $0.key }
    }
    private var allFilteredSelected: Bool {
        let keys = selectableFilteredKeys
        return !keys.isEmpty && keys.allSatisfy { selectedKeys.contains($0) }
    }
    /// Offer the select-all accelerator only when a class/pack/page/search filter
    /// is narrowing the grid — never a one-tap "select all 480" on the full list.
    private var showSelectAllBar: Bool {
        (selectedWordClass != "all" || !trimmedSearch.isEmpty || pageSourceKeys != nil)
            && !selectableFilteredKeys.isEmpty
    }

    private func toggleSelectAllFiltered() {
        let keys = selectableFilteredKeys
        if allFilteredSelected {
            selectedKeys.subtract(keys)
        } else {
            for k in keys { selectKey(k) }
        }
    }

    /// Scenes with at least one page — the "From a page…" menu's sources.
    private var pageSourceScenes: [BlasterScene] {
        allScenes.filter { !$0.pages.isEmpty }
    }

    /// Filter the grid to `page`'s word tiles (structural links/navigation
    /// dropped), replacing any class/pack chip filter.
    private func selectPageSource(_ scene: BlasterScene, _ page: PageSpec) {
        let byKey = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        pageSourceKeys = page.tiles.compactMap { entry in
            guard let t = byKey[entry.key],
                  t.wordClass != PageLink.wordClass, t.wordClass != "navigation" else { return nil }
            return t.key
        }
        pageSourceLabel = "\(scene.name.isEmpty ? "Scene" : scene.name) · \(page.key)"
        selectedWordClass = "all"
    }

    private func clearPageSource() {
        pageSourceKeys = nil
        pageSourceLabel = ""
    }

    private let columns = [GridItem(.adaptive(minimum: 72, maximum: 96))]

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespaces) }

    /// Does ANY tile match the search (same `contains` rule the grid uses)?
    private var searchHasTileMatch: Bool {
        let q = trimmedSearch
        guard !q.isEmpty else { return true }
        return allTiles.contains {
            $0.displayName.localizedCaseInsensitiveContains(q)
            || $0.key.localizedCaseInsensitiveContains(q)
        }
    }

    /// The search names a brand-new word (no tile matches at all) — drives the
    /// full-height "add new word" takeover, all filter/AI chrome collapsed.
    /// Because it's `contains`-based, typing a longer non-matching string flips it
    /// exactly ONCE (when the grid truly empties): no flicker, no debounce, no
    /// "no match" intermediary. Exit is implicit (edit/clear) or explicit (Cancel).
    private var isAddingNewWord: Bool { !trimmedSearch.isEmpty && !searchHasTileMatch }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            searchField
            Group {
              if isAddingNewWord {
                newWordInlineView(trimmedSearch)
                    .transition(.opacity)
              } else {
            ScrollView {
                suggestionBar
                    .padding(.horizontal)
                    .padding(.top, 12)

                packFilter

                wordClassFilter
                    .padding(.vertical, 8)

                HStack(spacing: 8) {
                    Button { showBulkWord = true } label: {
                        Label("Paste a word list", systemImage: "list.bullet.clipboard")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)

                    if !pageSourceScenes.isEmpty {
                        Menu {
                            ForEach(pageSourceScenes, id: \.persistentModelID) { scene in
                                Menu(scene.name.isEmpty ? "Untitled scene" : scene.name) {
                                    ForEach(scene.pages, id: \.key) { page in
                                        Button {
                                            selectPageSource(scene, page)
                                        } label: {
                                            Text(page.key == scene.homePageKey ? "\(page.key) — Home" : page.key)
                                        }
                                    }
                                }
                            }
                        } label: {
                            Label("From a page…", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.bottom, 4)

                if pageSourceKeys != nil {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.doc").font(.caption2)
                        Text(pageSourceLabel).font(.caption).lineLimit(1)
                        Button { clearPageSource() } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.blue.opacity(0.12)))
                    .foregroundStyle(.blue)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }

                // When a search has matches the grid shows them, which otherwise
                // hides the "create" path — so an existing word (any class, with
                // or without spaces) couldn't be extended without changing the
                // filter to empty the grid. Surface create here too.
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty && !filteredTiles.isEmpty {
                    addWordBanner
                }

                if showSelectAllBar {
                    HStack {
                        Text("\(selectableFilteredKeys.count) tile\(selectableFilteredKeys.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button(allFilteredSelected ? "Deselect All" : "Select All") {
                            toggleSelectAllFiltered()
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 4)
                }

                if filteredTiles.isEmpty {
                    emptyState
                        .padding(.top, 40)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(filteredTiles) { tile in
                            pickerCell(tile)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
              }
            }
            .animation(.easeInOut(duration: 0.15), value: isAddingNewWord)
            }
            .safeAreaInset(edge: .bottom) { selectionPanel }
            .onChange(of: selectedKeys) { _, _ in
                if !listFocused { regenerateSelectionText() }
            }
            .onChange(of: listFocused) { _, focused in
                if !focused { applySelectionText() }
            }
            .onChange(of: listExpanded) { _, expanded in
                if expanded, !listFocused { regenerateSelectionText() }
            }
            .sheet(isPresented: $showAddWord) {
                AddWordSheet(
                    initialWord: searchText,
                    existingTiles: allTiles,
                    defaultWordClass: addWordDefaultClass
                ) { tile in
                    selectKey(tile.key)
                    searchText = ""
                }
            }
            .sheet(isPresented: $showBulkWord) {
                BulkWordSheet(existingTiles: allTiles) { tiles in
                    for tile in tiles { selectKey(tile.key) }
                }
            }
            .onAppear {
                if !initialSelectedKeys.isEmpty {
                    selectedKeys = initialSelectedKeys.subtracting(existingKeys)
                }
            }
            .navigationTitle("Add Tiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(selectedKeys.isEmpty ? "Dismiss" : "Discard") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selectedKeys.count)") {
                        addSelectedTiles()
                        dismiss()
                    }
                    .disabled(selectedKeys.isEmpty)
                }
            }
            .onDisappear { pruneUnusedNewWords() }
        }
    }

    /// Plain, fully-controlled search field — replaces `.searchable`, whose
    /// inactive state renders collapsed/occluded inside this sheet on iOS 26.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search or add a word", text: $searchText)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.tertiarySystemFill)))
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }


    /// Always-available "create" affordance shown above the grid during an
    /// active search. Routes to the New Word sheet (which disables any classes
    /// the word already uses, so this only ever makes a free-class homograph or
    /// a brand-new word).
    @ViewBuilder
    private var addWordBanner: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        let normalized = TileModel.normalizeKey(trimmed)
        let exists = allTiles.contains {
            $0.key == normalized || $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        Button {
            showAddWord = true
        } label: {
            Label(exists ? "Add “\(trimmed)” as a different type" : "Add “\(trimmed)” as a new word",
                  systemImage: "plus.circle")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .padding(.horizontal)
        .padding(.bottom, 4)
    }

    /// Word class to pre-select when adding a new word: the active filter if one
    /// is chosen, otherwise the first real class.
    private var addWordDefaultClass: String {
        if selectedWordClass != "all" { return selectedWordClass }
        return wordClasses.first { $0 != "all" } ?? "describe"
    }

    @ViewBuilder
    private var emptyState: some View {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            ContentUnavailableView("No tiles found", systemImage: "magnifyingglass")
        } else {
            // The grid hides tiles already on the page / filtered by class, so an
            // empty grid doesn't mean the word is new. Check the whole vocabulary
            // for an exact match and surface it rather than claiming it's new.
            let normalized = TileModel.normalizeKey(trimmed)
            let matches = allTiles.filter {
                $0.key == normalized || $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
            }
            if matches.isEmpty {
                // A true no-match is the add-word takeover (isAddingNewWord), so we
                // only get here when a tile matches but the filter / on-page state
                // hides it.
                ContentUnavailableView {
                    Label("Nothing here for “\(trimmed)”", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("A match exists but the current class/pack filter hides it — set the filter to All.")
                }
            } else {
                existingWordView(trimmed, matches)
            }
        }
    }

    /// Search found nothing — add `word` as a new tile inline: the word is already
    /// known, so we only need its class. Tapping a type materializes the word
    /// (artless, isSystem=false — the bulk art pass fills art) and stages it into
    /// the selection. The heavy New Word sheet stays as a "more options" escape
    /// hatch for a photo or a same-name different-type homograph.
    @ViewBuilder
    private func newWordInlineView(_ word: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                Label("Add “\(word)”", systemImage: "plus.circle.fill")
                    .font(.headline)
                Spacer()
                Button("Cancel") { searchText = "" }
                    .font(.subheadline)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    Text("Pick a type — the word is added now and gets art from the batch pass.")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 14).padding(.horizontal)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                        ForEach(VocabularyClasses.caregiverSelectable, id: \.name) { cls in
                            Button { addNewWordInline(word, wordClass: cls.name) } label: {
                                HStack(spacing: 6) {
                                    Circle().fill(cls.color).frame(width: 9, height: 9)
                                    Text(cls.label).font(.subheadline).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)

                    Button { showAddWord = true } label: {
                        Label("More options (photo, different type)…", systemImage: "ellipsis.circle")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 2)
                }
                .padding(.bottom, 20)
            }
        }
    }

    /// Materialize `word` with `wordClass` (through the shared choke point, tracked
    /// for rollback) and stage it into the selection; clears the search.
    private func addNewWordInline(_ word: String, wordClass: String) {
        let key = TileModel.normalizeKey(word)
        guard !key.isEmpty else { return }
        var lookup = tileLookup
        if lookup[key] == nil {
            let created = SceneBuilder.materializeNewWords(
                [GeneratedNewWord(key: key, displayName: word, wordClass: wordClass)],
                into: modelContext, existing: &lookup)
            if !created.isEmpty { try? modelContext.save() }
            sessionNewWordKeys.formUnion(created)
            for k in created {
                sessionNewWords[k] = BulkWordParser.Word(key: k, wordClass: wordClass, displayName: word)
            }
        }
        selectKey(key)
        searchText = ""
    }

    /// The searched word already exists. Show which classes it exists as (and
    /// whether already on this page), let the user add an off-page one directly,
    /// and offer to create a different-type homograph.
    @ViewBuilder
    private func existingWordView(_ trimmed: String, _ matches: [TileModel]) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("“\(trimmed)” is already in your vocabulary")
                .font(.headline)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                ForEach(matches) { tile in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(TileColorResolver.color(for: tile.wordClass))
                            .frame(width: 10, height: 10)
                        Text(tile.wordClass)
                        Spacer()
                        if existingKeys.contains(tile.key) {
                            Text("On this page")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Add") {
                                selectKey(tile.key)
                                searchText = ""
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding(.horizontal)

            Button {
                showAddWord = true
            } label: {
                Label("Add “\(trimmed)” as a different type", systemImage: "plus.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .frame(maxWidth: 440)
    }

    /// Stage a tile into the picker's selection — the single commit path — rather
    /// than dropping it on the page immediately. So hand-created (New Word),
    /// pasted (Bulk), and quick-added tiles all flow through the same
    /// refine / reorder / Selected-list surface and commit together on "Add".
    private func selectKey(_ key: String) {
        guard !existingKeys.contains(key) else { return }
        selectedKeys.insert(key)
    }

    /// A tile placement. A page_link tile drops as a SILENT link to its target
    /// page; everything else drops as an audible terminal tile.
    private func pageEntry(for key: String) -> TileEntry {
        if allTiles.first(where: { $0.key == key })?.wordClass == PageLink.wordClass,
           let target = PageLink.targetPage(forKey: key) {
            return TileEntry(key: key, link: target, isAudible: false)
        }
        return TileEntry(key: key, link: "", isAudible: true)
    }

    /// Pack chips get a dedicated, visually-prominent row above the word classes
    /// (📦 + accent tint) so vocabulary packs are easy to spot and filter to.
    @ViewBuilder
    private var packFilter: some View {
        if !installedPacks.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(installedPacks) { pack in
                        let value = "pack:\(pack.slug)"
                        let isOn = selectedWordClass == value
                        Button {
                            selectedWordClass = isOn ? "all" : value
                            clearPageSource()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "shippingbox.fill").font(.caption2)
                                Text(pack.displayName).font(.caption.weight(.semibold))
                            }
                            .padding(.horizontal, 13)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(isOn ? Color.accentColor : Color.accentColor.opacity(0.15))
                            )
                            .foregroundStyle(isOn ? .white : Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    private var wordClassFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(wordClasses, id: \.self) { wc in
                    Button {
                        selectedWordClass = wc
                        clearPageSource()
                    } label: {
                        Text(classLabel(wc))
                            .font(.caption)
                            .fontWeight(selectedWordClass == wc ? .semibold : .regular)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(selectedWordClass == wc
                                          ? Color.accentColor
                                          : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(selectedWordClass == wc ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private func pickerCell(_ tile: TileModel) -> some View {
        let onPage = existingKeys.contains(tile.key)
        let isSelected = selectedKeys.contains(tile.key)
        Button {
            if onPage { return }   // already on the page — shown for context, not selectable
            if isSelected { selectedKeys.remove(tile.key) }
            else { selectedKeys.insert(tile.key) }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    TileImageView(key: tile.bundleImage, wordClass: tile.wordClass)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    .opacity(onPage ? 0.45 : 1)

                    if onPage {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, Color.secondary)
                            .offset(x: 4, y: -4)
                    } else if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(tile.displayName)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .foregroundStyle(onPage ? .tertiary : .secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
    }

    private var suggestionBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Suggest tiles for… (e.g. emotions for a 6-year-old)", text: $suggestionGoal)
                    .font(.subheadline)
                    .submitLabel(.go)
                    .onSubmit { suggestTiles() }
                    .disabled(isSuggesting)

                if isSuggesting {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Go") { suggestTiles() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(suggestionGoal.trimmingCharacters(in: .whitespaces).isEmpty
                                  || apiKey.isEmpty)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary))

            if let error = suggestionError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let note = newWordsNote {
                Label(note, systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tint)
            }

            if apiKey.isEmpty {
                Text("Add an OpenAI API key in Admin to enable AI suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func suggestTiles() {
        let goal = suggestionGoal.trimmingCharacters(in: .whitespaces)
        guard !goal.isEmpty, !apiKey.isEmpty else { return }
        isSuggesting = true
        suggestionError = nil
        newWordsNote = nil
        let service = TileSuggestionService(apiKey: apiKey)
        let tiles = allTiles  // capture before async hop
        Task {
            do {
                let result = try await service.suggest(goal: goal, allTiles: tiles)
                // Materialize proposed new words as artless caregiver tiles so they
                // can be selected here and are picked up by the batch art pass —
                // the same path scene/page generation uses. @Query refreshes the
                // grid to include them.
                var lookup = Dictionary(tiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
                let created = SceneBuilder.materializeNewWords(result.newWords,
                                                               into: modelContext, existing: &lookup)
                if !created.isEmpty { try? modelContext.save() }
                sessionNewWordKeys.formUnion(created)
                let picks = result.existingKeys.union(Set(created))
                selectedKeys = selectedKeys.union(picks.subtracting(existingKeys))
                // Clear the word class filter so suggested tiles are all visible
                selectedWordClass = "all"
                if !created.isEmpty {
                    newWordsNote = "Added \(created.count) new word\(created.count == 1 ? "" : "s"): "
                        + created.sorted().joined(separator: ", ")
                }
            } catch {
                suggestionError = error.localizedDescription
            }
            isSuggesting = false
        }
    }

    // MARK: - Editable selection list (P3)

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Bottom panel: the live, editable `key, class[, Display]` list bound to the
    /// selection. Tapping tiles fills it in; editing it (on blur / Apply)
    /// reconciles back into `selectedKeys`, materializing brand-new words.
    private var selectionPanel: some View {
        VStack(spacing: 0) {
            Button {
                if listFocused { listFocused = false }
                withAnimation(.easeInOut(duration: 0.15)) { listExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet.rectangle.portrait")
                    Text("Selected \(selectedKeys.count)")
                        .contentTransition(.numericText())
                    Spacer()
                    Image(systemName: listExpanded ? "chevron.down" : "chevron.up").font(.caption)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if listExpanded {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Edit or paste `key, class` lines — new words are created. Tapping tiles above adds here.")
                        .font(.caption2).foregroundStyle(.secondary)
                    classPaletteRow
                    TextEditor(text: $selectionText)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 84, maxHeight: 150)
                        .focused($listFocused)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(6)
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
                    HStack {
                        if let hint = selectionListHint {
                            Label(hint, systemImage: "exclamationmark.triangle")
                                .font(.caption2).foregroundStyle(.orange)
                        }
                        Spacer()
                        if listFocused {
                            Button("Apply") { listFocused = false }
                                .font(.caption).buttonStyle(.borderedProminent).controlSize(.small)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
        .background(.bar)
    }

    /// Tap-to-insert class palette for the list editor (mirrors the Paste sheet).
    private var classPaletteRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(VocabularyClasses.caregiverSelectable, id: \.name) { cls in
                    Button { insertClassIntoSelection(cls.name) } label: {
                        Text(cls.name)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Capsule().fill(cls.color.opacity(0.28)))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    /// Append a class to the list text, mending the separator (after a bare
    /// "rocket" → "rocket, object") — same behavior as the Paste sheet's palette.
    private func insertClassIntoSelection(_ name: String) {
        if selectionText.isEmpty || selectionText.hasSuffix("\n") || selectionText.hasSuffix(", ") {
            selectionText += name
        } else if selectionText.hasSuffix(",") {
            selectionText += " \(name)"
        } else {
            selectionText += ", \(name)"
        }
    }

    /// Non-fatal warnings about the current list text (unknown class / bad lines).
    private var selectionListHint: String? {
        let parsed = BulkWordParser.parse(selectionText)
        let unknown = Set(parsed.words.map(\.wordClass)).subtracting(BulkWordParser.knownClasses)
        if !unknown.isEmpty {
            return "Unknown class: \(unknown.sorted().joined(separator: ", ")) — added with a neutral color."
        }
        if !parsed.skipped.isEmpty {
            return "\(parsed.skipped.count) line(s) need `key, class`."
        }
        return nil
    }

    private func csvLine(key: String, wordClass: String, displayName: String) -> String {
        let plain = key.replacingOccurrences(of: "_", with: " ")
        return displayName.lowercased() == plain.lowercased()
            ? "\(key), \(wordClass)"
            : "\(key), \(wordClass), \(displayName)"
    }

    /// Render the selection as `key, class[, Display]` lines.
    private func regenerateSelectionText() {
        let lookup = tileLookup
        selectionText = selectedKeys.sorted().compactMap { key -> String? in
            if let t = lookup[key] { return csvLine(key: key, wordClass: t.wordClass, displayName: t.displayName) }
            if let w = sessionNewWords[key] { return csvLine(key: key, wordClass: w.wordClass, displayName: w.displayName) }
            return nil
        }.joined(separator: "\n")
    }

    /// Reconcile edited list → selection: existing words are selected; brand-new
    /// words are materialized (artless, isSystem=false) through the shared choke
    /// point and tracked for rollback (identical to the suggest path).
    private func applySelectionText() {
        var lookup = tileLookup
        var newSelection = Set<String>()
        var toMaterialize: [GeneratedNewWord] = []
        for w in BulkWordParser.parse(selectionText).words {
            let key = TileModel.normalizeKey(w.key)
            guard !key.isEmpty else { continue }
            if lookup[key] != nil {
                newSelection.insert(key)
            } else {
                toMaterialize.append(GeneratedNewWord(key: key, displayName: w.displayName, wordClass: w.wordClass))
                sessionNewWords[key] = BulkWordParser.Word(key: key, wordClass: w.wordClass, displayName: w.displayName)
                newSelection.insert(key)
            }
        }
        let created = SceneBuilder.materializeNewWords(toMaterialize, into: modelContext, existing: &lookup)
        if !created.isEmpty { try? modelContext.save() }
        sessionNewWordKeys.formUnion(created)
        selectedKeys = newSelection.subtracting(existingKeys)
        regenerateSelectionText()
    }

    /// Roll back new words this session materialized that didn't end up on any
    /// page — i.e. suggested, then the picker was dismissed or those tiles were
    /// deselected before Add. Runs on the picker's disappearance, after any Add
    /// has committed, so genuinely-used new words are kept.
    private func pruneUnusedNewWords() {
        guard !sessionNewWordKeys.isEmpty else { return }
        let used = Set(scene.pages.flatMap { $0.tiles.map(\.key) })
        let orphans = sessionNewWordKeys.subtracting(used)
        sessionNewWordKeys.removeAll()
        guard !orphans.isEmpty else { return }
        for tile in allTiles where orphans.contains(tile.key) {
            modelContext.delete(tile)
        }
        try? modelContext.save()
    }

    private func addSelectedTiles() {
        var seenKeys = Set<String>()
        let keysToAdd = allTiles.compactMap { tile -> String? in
            guard selectedKeys.contains(tile.key),
                  !existingKeys.contains(tile.key),
                  seenKeys.insert(tile.key).inserted else { return nil }
            return tile.key
        }
        guard !keysToAdd.isEmpty else { return }
        var pages = scene.pages
        guard let idx = pages.firstIndex(where: { $0.key == pageKey }) else { return }
        // Insert at the FRONT (next to the slot-0 add cell) so just-added tiles are
        // immediately visible on a long page rather than buried at the end. The
        // bulk-move tools make repositioning a group easy afterward.
        pages[idx].tiles.insert(contentsOf: keysToAdd.map { pageEntry(for: $0) }, at: 0)
        scene.pages = pages
        try? modelContext.save()
    }
}
