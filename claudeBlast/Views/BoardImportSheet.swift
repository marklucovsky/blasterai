// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardImportSheet.swift
//  claudeBlast
//
//  The one place a scene or pages come in from outside: a BlasterAI scene
//  file, or a board drawn in a spreadsheet — a Google Sheets link, an .xlsx,
//  or CSV — from a link or a file.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Import, in three steps, like every other way a scene or page is made:
///
/// 1. **From** — a link or a file. A BlasterAI file goes to its own preview
///    (`ImportRouteSheet`); a spreadsheet stays here.
/// 2. **Settle** — the words the sheet names that this device does not have, a
///    class this app does not know, a name several words share, pages that
///    would be replaced.
/// 3. **Preview** — the standard page preview (`PagePreviewView`), a section
///    per tab laid out cell for cell, its new words reviewed. Nothing is
///    written until Accept; Cancel goes back a step.
struct BoardImportSheet: View {
    /// The scene whose pages the import writes; nil makes a new scene.
    let scene: BlasterScene?
    /// Called once the import is done, with the scene written to and the
    /// pages it made that nothing links to yet — the ones to offer a link for.
    var onImported: (BlasterScene, [String]) -> Void = { _, _ in }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]
    @Query(filter: #Predicate<BlasterScene> { $0.isDefault })
    private var systemScenes: [BlasterScene]

    @State private var link = ""
    @State private var isPickingFile = false
    @State private var isLoading = false
    /// When the current load began, and how long it took, for the summary.
    @State private var loadStarted = Date()
    @State private var loadSeconds: Double?
    /// The source block expanded again after a load, to pick another.
    @State private var changingSource = false
    @State private var error: String?
    @State private var sourceName = ""
    @State private var tabs: [SpreadsheetTab] = []
    @State private var preview: BoardWorkbook.Preview?
    @State private var sceneName = ""
    /// Pages with words the caregiver chose to overwrite.
    @State private var replacing: Set<String> = []
    /// Fixes chosen here for words the sheet names that do not resolve.
    @State private var fixes: [String: BoardWorkbook.Fix] = [:]
    /// Step 3: the pages as the page preview shows them.
    /// Step 3: the pages as the page preview shows them. Not optional, with
    /// `isPreviewing` choosing the step: a `Binding($optional)` handed to the
    /// preview trapped on Cancel, when the preview read it once more on its
    /// way out after the value was cleared.
    @State private var pagePreview = GeneratedPageResult(primaryPage: GeneratedPage(key: "", tiles: []), subPages: [])
    @State private var isPreviewing = false
    /// A BlasterAI file, handed to its own import preview.
    @State private var blasterFile: ImportSheetURL?
    /// Where a tab's board starts, by tab name, where the caregiver moved it.
    @State private var origins: [String: BoardWorkbook.Origin] = [:]
    /// The tab whose start is being chosen.
    @State private var choosingOrigin: BoardWorkbook.PagePlan?
    @State private var sceneDescription = ""

    private var isScene: Bool { scene == nil }

    private var fileTypes: [UTType] {
        let sheets: [UTType] = [UTType(filenameExtension: "xlsx") ?? .spreadsheet,
                                .commaSeparatedText, .tabSeparatedText, .plainText]
        return isScene ? [.blasterScene, .blasterPack, .blasterColorway, .blasterKey, .json] + sheets : sheets
    }

    var body: some View {
        NavigationStack {
            Group {
                if isPreviewing {
                    PagePreviewView(
                        preview: $pagePreview,
                        pageName: writing.first.map(title) ?? "",
                        allTiles: allTiles,
                        apiKey: OpenAIKeyVault.currentKey() ?? "",
                        provenance: "From \(sourceName)",
                        allowEdit: false,
                        placed: { page in boards[page.key] },
                        onAccept: { runImport() },
                        onEdit: {},
                        onRetry: nil,
                        onCancel: { isPreviewing = false },
                        fixedLayout: true)
                } else {
                    settleForm
                }
            }
            .navigationTitle(isScene ? "Import Scene" : "Import Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isPreviewing { Button("Cancel") { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !isPreviewing {
                        Button("Preview") { showPreview() }
                            .disabled(!canPreview)
                    }
                }
            }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: fileTypes) { result in
                switch result {
                case .success(let url): load(url)
                case .failure(let failure): error = failure.localizedDescription
                }
            }
            .sheet(item: $choosingOrigin) { page in
                if let tab = tabs.first(where: { $0.name == page.tabName }) {
                    TabOriginSheet(tab: tab, cols: cols, origin: page.origin,
                                   detected: detectedOrigin(of: tab)) { chosen in
                        origins[tab.name] = chosen
                        refresh()
                    }
                }
            }
            .sheet(item: $blasterFile) { item in
                ImportRouteSheet(url: item.url) {
                    blasterFile = nil
                    dismiss()
                }
            }
        }
    }

    private var settleForm: some View {
        Form {
            if showsSummary {
                loadSummary
            } else {
                sourceSection
            }
            if let error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
            if let preview { settleSections(preview) }
        }
    }

    // MARK: - Step 1: From

    /// Once a load starts, the source block gives its room to what came in:
    /// one line that turns from progress to a result, where the eye already is.
    private var showsSummary: Bool {
        !changingSource && error == nil && (isLoading || preview?.hasWork == true)
    }

    private var loadSummary: some View {
        Section {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(isLoading ? "Reading…" : "Loaded \(sourceName)")
                        .font(.headline)
                    Text(isLoading ? loadingWhat : loadedWhat)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                if !isLoading {
                    Button("Change") { changingSource = true }
                        .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var loadingWhat: String {
        link.isEmpty ? "the file" : link
    }

    private var loadedWhat: String {
        let pages = preview?.pages.count ?? 0
        let time = loadSeconds.map { String(format: " · %.1f s", $0) } ?? ""
        return "\(pages) page\(pages == 1 ? "" : "s")\(time)"
    }

    private var sourceSection: some View {
        Section {
            TextField(isScene ? "Paste a link to a sheet or scene file" : "Paste a Google Sheets link", text: $link)
                .textContentType(.URL)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onSubmit { fetchLink() }
            // Its own row and plainly a button: beside a freshly pasted link it
            // read as part of the text.
            Button { fetchLink() } label: {
                Label(isScene ? "Get Scene from Link" : "Get Pages from Link", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(link.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            Button {
                isPickingFile = true
            } label: {
                Label("Choose a File…", systemImage: "doc.badge.plus")
            }
        } header: {
            Text(isScene
                 ? "Bring in a BlasterAI scene (.blasterscene) or a spreadsheet — Google Sheets, Excel, Numbers or CSV — from a link or a file."
                 : "Bring in pages from a spreadsheet — Google Sheets, Excel, Numbers or CSV — from a link or a file. Each tab is a page.")
                .textCase(nil)
        } footer: {
            Text("In a spreadsheet each tab is a page, named by the tab; the first tab, or one named home, is the home page. Each row is a row of the board, ten cells wide, below the top row every board shares. Write a cell as you would in the page editor: a word, “word, class” for a new one, “> page” for a folder, “go > page” for a word that opens a page, “sys:page” for a BlasterAI 60 page. A Google sheet must be shared as “Anyone with the link”.\n\n[The spreadsheet format and word classes](https://github.com/marklucovsky/blasterai/blob/main/docs/board-format/README.md)")
        }
    }

    // MARK: - Step 2: Settle

    @ViewBuilder
    private func settleSections(_ preview: BoardWorkbook.Preview) -> some View {
        Section("Scene") {
            if let scene {
                LabeledContent("Into", value: scene.name)
            } else {
                TextField("Scene name", text: $sceneName)
                if !sceneDescription.isEmpty {
                    LabeledContent("Description", value: sceneDescription)
                }
            }
            LabeledContent("Source", value: sourceName)
        }
        Section {
            ForEach(preview.pages) { page in pageRow(page, isHome: page.key == preview.homeKey && isScene) }
        } header: {
            Text("Pages (\(preview.pages.count))")
        }
        if !preview.newWords.isEmpty {
            Section {
                ForEach(preview.newWords, id: \.self) { word in
                    HStack(spacing: 10) {
                        Text(word.displayName)
                        Text(word.wordClass).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if fixes[BoardWorkbook.fixKey(word.key)] != nil {
                            Button("Undo") { setFix(nil, for: word.key) }
                                .font(.caption)
                                .buttonStyle(.borderless)
                        }
                    }
                }
            } header: {
                Text("New words (\(preview.newWords.count))")
            } footer: {
                Text("Checked in the preview, like any new word, before they reach the board. Made without pictures; generate art for them from the scene afterwards.")
            }
        }
        if !preview.emptyPages.isEmpty {
            Section {
                Text(preview.emptyPages.map(PageNaming.displayName).joined(separator: ", "))
                    .font(.callout)
            } header: {
                Text("Linked pages with no tab (\(preview.emptyPages.count))")
            } footer: {
                Text("A link names these pages but no tab draws them, so they are made empty, ready to fill — in the page editor, or by importing a tab of the same name later. If you meant BlasterAI 60's page, write sys: before its name.")
            }
        }
        let missing = missingWords(preview)
        if !missing.isEmpty {
            Section {
                ForEach(missing, id: \.word) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.word).font(.callout.weight(.semibold))
                            Text(item.cells.joined(separator: ", "))
                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                            if let note = item.note {
                                Text(note).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        if let keys = item.choices {
                            Menu("Which one?") {
                                ForEach(keys, id: \.self) { key in
                                    Button(choiceLabel(key)) { setFix(.word(key: key), for: item.word) }
                                }
                            }
                        } else {
                            // One action whatever the reason: the word needs a class.
                            Menu("Add a class…") {
                                ForEach(VocabularyClasses.caregiverSelectable.map(\.name), id: \.self) { cls in
                                    Button(cls) { setFix(.newWord(wordClass: cls), for: item.word) }
                                }
                            }
                        }
                    }
                }
            } header: {
                Text("Words to settle (\(missing.count))")
            } footer: {
                Text("A new word needs a class — what kind of word it is. A name several words share needs one picked. Settle them here, or leave them and those cells stay empty.")
            }
        }
        let notes = preview.problems.filter { $0.kind == .note }
        if !notes.isEmpty {
            Section {
                ForEach(notes) { note in
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(note.page) · \(note.column)\(note.row)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        Text(note.text).font(.callout)
                    }
                }
            } header: {
                Text("Notes left out (\(notes.count))")
            } footer: {
                Text("Sentences in a cell read as notes to whoever opens the sheet, not as words. If one is meant to be on the board, make it a word in the page editor.")
            }
        }
        let others = preview.problems.filter { $0.kind == .other }
        if !others.isEmpty {
            Section {
                ForEach(others) { problem in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(problem.row > 0 ? "\(problem.page) · \(problem.column)\(problem.row)" : problem.page)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                            Text(problem.text).font(.callout.weight(.semibold))
                        }
                        Text(problem.message).font(.caption).foregroundStyle(.orange)
                    }
                }
            } header: {
                Text("Cells left empty (\(others.count))")
            } footer: {
                Text("Fix these in the sheet and import again, or type them in the page editor.")
            }
        }
    }

    @ViewBuilder
    private func pageRow(_ page: BoardWorkbook.PagePlan, isHome: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            pageRowContent(page, isHome: isHome)
            // Where the board was found, and the way to move it.
            Button { choosingOrigin = page } label: {
                Label(page.origin.summary ?? "Starts at A1", systemImage: "scope")
                    .font(.caption)
                    .foregroundStyle(page.origin.summary == nil ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func pageRowContent(_ page: BoardWorkbook.PagePlan, isHome: Bool) -> some View {
        switch page.existing {
        case .filled(let count):
            Toggle(isOn: Binding(
                get: { replacing.contains(page.key) },
                set: { if $0 { replacing.insert(page.key) } else { replacing.remove(page.key) } })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title(page))
                    Text("Replace its \(count) word\(count == 1 ? "" : "s") with \(page.placed)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        default:
            HStack {
                if isHome { Image(systemName: "house.fill").foregroundStyle(.secondary) }
                Text(title(page))
                Spacer()
                Text(page.existing == .empty ? "fills the empty page · \(page.placed)" : "\(page.placed) cell\(page.placed == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func title(_ page: BoardWorkbook.PagePlan) -> String {
        page.title.isEmpty ? PageNaming.displayName(page.key) : page.title
    }

    // MARK: - Step 3: Preview

    /// The pages the import writes: a page with words is left alone unless
    /// the caregiver chose to replace it.
    private var writing: [BoardWorkbook.PagePlan] {
        (preview?.pages ?? []).filter { page in
            if case .filled = page.existing { return replacing.contains(page.key) }
            return true
        }
    }

    private var boards: [String: PageSpec] {
        Dictionary(writing.map { ($0.key, $0.board(cols: cols)) }, uniquingKeysWith: { a, _ in a })
    }

    private func showPreview() {
        let pages = writing.map(\.generated)
        guard let first = pages.first else { return }
        pagePreview = GeneratedPageResult(primaryPage: first, subPages: Array(pages.dropFirst()))
        isPreviewing = true
    }

    // MARK: - Loading

    private var systemPages: [PageSpec] {
        guard let system = systemScenes.first, system.id != scene?.id else { return [] }
        return system.pages
    }

    private var cols: Int {
        guard let scene else { return Self.designedFor.grid.cols }
        return GridLayoutCalculator.authoringGrid(
            designed: scene.designedLayout,
            isPhone: GridLayoutCalculator.isPhone(screenSize: GridLayoutCalculator.deviceScreenSize),
            deviceLayout: .standard).cols
    }

    /// A new scene is drawn for the iPad board the sheet's ten columns match.
    private static let designedFor = DesignedLayout(phone: false, layout: .standard)

    /// Missing and ambiguous words, each once, with the cells that name it.
    private func missingWords(_ preview: BoardWorkbook.Preview)
        -> [(word: String, cells: [String], choices: [String]?, note: String?)] {
        var order: [String] = []
        var found: [String: (word: String, cells: [String], choices: [String]?, note: String?)] = [:]
        for problem in preview.problems {
            let word: String, choices: [String]?
            var note: String? = nil
            if case .unknownClass(_, let cls) = problem.kind { note = "\u{201C}\(cls)\u{201D} isn't a word class" }
            switch problem.kind {
            case .missingWord(let w), .unknownClass(let w, _): word = w; choices = nil
            case .ambiguous(let w, let keys): word = w; choices = keys
            case .other, .note: continue
            }
            let key = BoardWorkbook.fixKey(word)
            if found[key] == nil { order.append(key); found[key] = (word, [], choices, note) }
            found[key]?.cells.append("\(problem.page) \(problem.column)\(problem.row)")
        }
        return order.compactMap { found[$0] }
    }

    private func choiceLabel(_ key: String) -> String {
        guard let tile = allTiles.first(where: { $0.key == key }) else { return key }
        return "\(tile.displayName) (\(tile.wordClass))"
    }

    private func setFix(_ fix: BoardWorkbook.Fix?, for word: String) {
        fixes[BoardWorkbook.fixKey(word)] = fix
        refresh()
    }

    private var canPreview: Bool {
        guard let preview, preview.hasWork, !isLoading, !writing.isEmpty else { return false }
        if isScene, sceneName.trimmingCharacters(in: .whitespaces).isEmpty { return false }
        return true
    }

    private func fetchLink() {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme?.lowercased().hasPrefix("http") == true else {
            error = GoogleSheetLink.FetchError.notALink.localizedDescription
            return
        }
        isLoading = true
        error = nil
        changingSource = false
        loadStarted = Date()
        loadSeconds = nil
        Task {
            do {
                let fetched = try await ImportSource.fetch(text)
                route(fetched.data, fileExtension: fetched.fileExtension, name: fetched.name)
            } catch {
                self.error = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func load(_ url: URL) {
        error = nil
        changingSource = false
        loadStarted = Date()
        let ext = url.pathExtension.lowercased()
        if BlasterFileFormat.openableExtensions.contains(ext) || ext == "json" {
            guard isScene else { error = ImportSource.RouteError.notASpreadsheet.localizedDescription; return }
            blasterFile = ImportSheetURL(url: url)
            return
        }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            route(try Data(contentsOf: url), fileExtension: ext, name: url.deletingPathExtension().lastPathComponent)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// A downloaded or picked file, to the importer it belongs to.
    private func route(_ data: Data, fileExtension: String, name: String) {
        do {
            switch try ImportSource.kind(of: data, fileExtension: fileExtension) {
            case .blaster(let ext):
                guard isScene else { throw ImportSource.RouteError.notASpreadsheet }
                blasterFile = ImportSheetURL(url: try ExportedFile.write(data, named: "\(name).\(ext)").url)
            case .spreadsheet(let ext):
                show(try Spreadsheet.tabs(from: data, fileExtension: ext, name: name), from: name)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func show(_ tabs: [SpreadsheetTab], from name: String) {
        loadSeconds = Date().timeIntervalSince(loadStarted)
        self.tabs = tabs
        sourceName = name
        replacing = []
        fixes = [:]
        origins = [:]
        isPreviewing = false
        refresh()
        // The sheet's own details name the scene, when it gives them.
        let details = preview?.details ?? [:]
        if sceneName.isEmpty { sceneName = details["name"] ?? details["title"] ?? details["scene"] ?? name }
        sceneDescription = details["description"] ?? ""
        if preview?.hasWork != true { error = "The sheet has no tabs with cells to import." }
    }

    private func refresh() {
        preview = BoardWorkbook.preview(BoardWorkbook.applying(fixes, to: tabs), cols: cols,
                                        scenePages: scene?.pages ?? [],
                                        lookup: lookup, systemPages: systemPages, origins: origins,
                                        unnamedTab: unnamedTab)
    }

    /// A tab nobody named is Home in a new scene; added to a scene, where
    /// Home already is, it is named after the sheet.
    private var unnamedTab: String { isScene ? "home" : (sourceName.isEmpty ? "Imported" : sourceName) }

    private var lookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Where detection puts `tab`'s board, for the origin sheet's Reset.
    private func detectedOrigin(of tab: SpreadsheetTab) -> BoardWorkbook.Origin {
        let preview = BoardWorkbook.preview([tab], cols: cols, scenePages: scene?.pages ?? [],
                                            lookup: lookup, systemPages: systemPages, unnamedTab: unnamedTab)
        return preview.pages.first?.origin ?? .topLeft
    }

    /// Accept from the preview: the review's removals arrive as new words no
    /// longer on any page, and are not made.
    private func runImport() {
        guard let preview, isPreviewing else { return }
        let accepted = pagePreview
        let kept = Set(([accepted.primaryPage] + accepted.subPages).flatMap(\.tiles).map(\.key))
        let proposed = Set(preview.newWords.map { TileModel.normalizeKey($0.key) })
        let dropped = proposed.subtracting(kept)
        let target: BlasterScene
        if let scene {
            target = scene
        } else {
            target = BlasterScene(name: sceneName.trimmingCharacters(in: .whitespaces),
                                  homePageKey: preview.homeKey ?? TileToken.home)
            target.ensureIdentity(authorID: DeviceProfileStore.ensureAuthorID(context: modelContext),
                                  authorName: DeviceProfileStore.authorName(context: modelContext))
            target.designedFor = Self.designedFor.rawValue
            target.descriptionText = sceneDescription
            modelContext.insert(target)
        }
        let result = BoardWorkbook.apply(preview, to: target, cols: cols, replacing: replacing,
                                         dropping: dropped, systemPages: systemPages, context: modelContext)
        // A page made here that no tile of the scene opens is unreachable
        // until a folder to it is placed — Add Page offers that, so this does.
        let made = Set(preview.pages.filter { $0.existing == .none }.map(\.key))
        let linked = Set(target.pages.flatMap(\.tiles).filter { !$0.isSpacer }.map(\.link))
        let unlinked = result.pagesWritten.filter {
            made.contains($0) && !linked.contains($0) && $0 != target.homePageKey
        }
        dismiss()
        onImported(target, unlinked)
    }
}

/// Where an import's bytes go: a BlasterAI file to its own importer, anything
/// else to the spreadsheet reader.
enum ImportSource {
    enum Kind: Equatable {
        /// A BlasterAI file, by the extension its importer routes on.
        case blaster(String)
        /// A spreadsheet, by the extension `Spreadsheet.tabs` reads it as.
        case spreadsheet(String)
    }

    enum RouteError: LocalizedError {
        case notASpreadsheet
        var errorDescription: String? {
            "Pages come in from a spreadsheet. To bring in a BlasterAI scene, use Import Scene in Settings › Scenes."
        }
    }

    /// By extension first, then by the bytes: a zip is a workbook, a JSON
    /// object a BlasterAI file, anything else delimited text.
    static func kind(of data: Data, fileExtension: String) throws -> Kind {
        let ext = fileExtension.lowercased()
        if BlasterFileFormat.openableExtensions.contains(ext) { return .blaster(ext) }
        if Spreadsheet.extensions.contains(ext) { return .spreadsheet(ext) }
        if data.starts(with: [0x50, 0x4B]) { return .spreadsheet("xlsx") }
        let head = String(decoding: data.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
        if head.hasPrefix("{") {
            for format in [BlasterPackFormat.mediaType, BlasterColorwayFormat.mediaType, BlasterKeyFormat.mediaType]
            where head.contains(format) {
                return .blaster(extensionFor(format))
            }
            return .blaster(BlasterSceneFormat.fileExtension)
        }
        return .spreadsheet("csv")
    }

    private static func extensionFor(_ mediaType: String) -> String {
        switch mediaType {
        case BlasterPackFormat.mediaType: BlasterPackFormat.fileExtension
        case BlasterColorwayFormat.mediaType: BlasterColorwayFormat.fileExtension
        case BlasterKeyFormat.mediaType: BlasterKeyFormat.fileExtension
        default: BlasterSceneFormat.fileExtension
        }
    }

    /// A link's bytes: a Google Sheets link as its workbook, any other link as
    /// it is served.
    static func fetch(_ link: String, session: URLSession = .shared) async throws
        -> (data: Data, name: String, fileExtension: String) {
        if GoogleSheetLink.exportURL(for: link) != nil {
            let (data, name) = try await GoogleSheetLink.fetch(link, session: session)
            return (data, name, "xlsx")
        }
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw GoogleSheetLink.FetchError.notALink
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw GoogleSheetLink.FetchError.failed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw GoogleSheetLink.FetchError.failed("the server answered \(http.statusCode)")
        }
        let served = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        let name = GoogleSheetLink.filename(from: served)
            ?? (url.deletingPathExtension().lastPathComponent.isEmpty ? "Import" : url.deletingPathExtension().lastPathComponent)
        return (data, name, url.pathExtension)
    }
}
