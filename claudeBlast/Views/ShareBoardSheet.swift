// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ShareBoardSheet.swift
//  claudeBlast
//
//  The one place a scene or a page leaves the app.
//

import SwiftUI
import SwiftData

/// What is being shared.
///
/// The unit is **whatever the caregiver navigated to**. Both levels offer the
/// same destinations; only the native file differs, because a scene and a page
/// mean different things on arrival — a scene becomes a board, a page becomes
/// vocabulary.
enum ShareSubject {
    case scene(BlasterScene)
    case page(PageSpec, in: BlasterScene)

    var scene: BlasterScene {
        switch self {
        case .scene(let s): return s
        case .page(_, let s): return s
        }
    }

    var title: String {
        switch self {
        case .scene(let s): return s.name.isEmpty ? "Scene" : s.name
        case .page(let p, _): return p.key
        }
    }

    /// Every tile key involved, in board order.
    var tileKeys: [String] {
        switch self {
        case .scene(let s): return s.pages.flatMap { $0.tiles.map(\.key) }
        case .page(let p, _): return p.tiles.map(\.key)
        }
    }

    var basename: String {
        let raw = title.sanitizedFilename
        return raw.isEmpty ? "blaster" : raw
    }
}

/// Where a share can go. PDF and OBZ join this list in later sessions; the sheet
/// is built to grow a row rather than be rewritten.
private enum ShareDestination: String, Identifiable, CaseIterable {
    case nativeFile
    case printablePDF
    case tileImages

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .nativeFile: return "square.and.arrow.up.on.square"
        case .printablePDF: return "printer"
        case .tileImages: return "photo.on.rectangle.angled"
        }
    }

    /// A native file has nothing to configure — it always carries every style —
    /// so it gets no disclosure and no empty settings panel.
    var hasOptions: Bool { self != .nativeFile }
}

struct ShareBoardSheet: View {
    let subject: ShareSubject

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(TileImageResolver.self) private var imageResolver
    @Query private var allTiles: [TileModel]

    @State private var setScope: ExportSetScope = .activeSet
    @State private var printOptions = BoardPrintOptions()
    @State private var exported: ExportedFile?
    @State private var errorMessage: String?
    @State private var work: Work?
    @State private var task: Task<Void, Never>?
    /// Which destination has its options open. One at a time: an accordion keeps
    /// the sheet short enough that nothing important falls below the fold.
    @State private var expanded: ShareDestination?

    private var isPage: Bool {
        if case .page = subject { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ShareDestination.allCases) { destination in
                        destinationRow(destination)
                        if expanded == destination {
                            optionRows(for: destination)
                        }
                    }
                    sparseArtWarning
                } header: {
                    Text("Share \(isPage ? "Page" : "Scene")")
                } footer: {
                    Text(isPage
                         ? "A shared page travels as a vocabulary pack: the words and their pictures, with no layout. Whoever receives it can build a page from those words whenever they like."
                         : "A shared scene arrives as a scene — the same pages, laid out the same way.")
                }
            }
            .navigationTitle(subject.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $exported) { file in
                ActivityView(items: [file.url])
            }
            .alert("Share failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - A destination row

    /// One row per destination — and, while that destination is exporting, the
    /// **same row** becomes its progress control.
    ///
    /// Progress used to live in its own section at the bottom of the form, below
    /// two sections of options. On an iPad sheet that is off-screen: the only
    /// feedback a caregiver got for tapping Export was the button turning grey,
    /// and nothing suggested there was anything to scroll to. Putting the bar
    /// where the finger already is means it cannot be missed, and it says which
    /// of the three exports is running without having to label it.
    @ViewBuilder
    private func destinationRow(_ destination: ShareDestination) -> some View {
        if let work, work.destination == destination {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Image(systemName: destination.icon)
                        .foregroundStyle(.secondary)
                    Text(work.label)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("Cancel", role: .cancel) { task?.cancel() }
                        .buttonStyle(.borderless)
                        .font(.callout)
                }
                if let fraction = work.fraction {
                    ProgressView(value: fraction)
                    Text("\(work.done) of \(work.total)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
            }
            .padding(.vertical, 2)
        } else {
            Button { produce(destination) } label: {
                HStack(spacing: 12) {
                    Image(systemName: destination.icon)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(for: destination))
                            .foregroundStyle(.primary)
                        Text(summary(for: destination))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if destination.hasOptions {
                        optionsToggle(destination)
                    }
                }
            }
            .disabled(work != nil)
        }
    }

    /// Options open inline, under the destination they belong to.
    ///
    /// They were two separate sections further down the form, which detached
    /// every setting from the thing it configures — a "Printing" header floating
    /// under three share buttons, and picture styles far enough down that the
    /// iPad never showed them at all. Collapsed by default, they also give the
    /// sheet back the vertical room it was spending on settings most exports
    /// never touch.
    private func optionsToggle(_ destination: ShareDestination) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                expanded = expanded == destination ? nil : destination
            }
        } label: {
            Label(expanded == destination ? "Hide options" : "Options",
                  systemImage: "chevron.right")
                .labelStyle(.iconOnly)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded == destination ? 90 : 0))
                .padding(.leading, 8)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(expanded == destination
                            ? "Hide \(title(for: destination)) options"
                            : "\(title(for: destination)) options")
    }

    @ViewBuilder
    private func optionRows(for destination: ShareDestination) -> some View {
        switch destination {
        case .printablePDF: pdfOptionRows
        case .tileImages: pictureOptionRows
        case .nativeFile: EmptyView()
        }
    }

    // MARK: - Sparse art

    /// Words you authored that don't have art in every installed style.
    ///
    /// A pack carries a custom word's art for the styles its author actually
    /// has. That is the most it can do — but if you only ever generated
    /// Playful-3D, someone using High Contrast gets your Playful-3D pictures
    /// sitting among their own, and nothing on their side can fix it. They
    /// cannot generate art for a word they didn't invent the style rules for,
    /// and they won't know why it looks wrong.
    ///
    /// The sender is the only person who can do anything about this, and only
    /// before sending — so it is called out here, and only when it is true.
    private var styleSparseWords: [TileModel] {
        guard isPage else { return [] }
        let installed = ExportArtResolver.allInstalledSets
        guard installed.count > 1 else { return [] }
        var seen = Set<String>()
        return subject.tileKeys.compactMap { key -> TileModel? in
            guard seen.insert(key).inserted,
                  let tile = tileLookup[key],
                  !tile.isSystem, !tile.isStructuralChrome else { return nil }
            let have = installed.count { imageResolver.hasArt(for: tile.bundleImage, in: $0) }
            return (have > 0 && have < installed.count) ? tile : nil
        }
    }

    @ViewBuilder
    private var sparseArtWarning: some View {
        let sparse = styleSparseWords
        if !sparse.isEmpty {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sparse.count) of your words have art for only some styles")
                        .foregroundStyle(.primary)
                    Text("\(sparse.prefix(3).map(\.displayName).joined(separator: ", "))\(sparse.count > 3 ? "…" : ""). Whoever receives this pack will see those words in your style rather than theirs. Completing the missing styles first avoids that.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Options, inline under their destination

    /// PDF settings. Named for what they configure — they sat under a "Printing"
    /// header floating three rows below the button they belong to, which named a
    /// activity rather than an artifact.
    @ViewBuilder
    private var pdfOptionRows: some View {
        let layout = SheetLayout.compute(paper: printOptions.paper,
                                         orientation: printOptions.orientation,
                                         columns: resolvedColumns)
        Picker("Paper", selection: $printOptions.paper) {
            ForEach(PaperSize.all) { paper in
                Text(paper.displayName).tag(paper)
            }
        }
        Picker("Orientation", selection: $printOptions.orientation) {
            ForEach(PrintOrientation.allCases) { orientation in
                Text(orientation.label).tag(orientation)
            }
        }
        .pickerStyle(.segmented)
        // The lower bound moves with paper and orientation — landscape Letter
        // cannot go below four columns without the art softening — so the
        // stepper reads its range from the options rather than a constant.
        Stepper(value: columnsBinding,
                in: printOptions.minColumns...BoardPrintOptions.maxColumns) {
            LabeledContent("Tiles across", value: "\(resolvedColumns)")
        }
        Toggle("Cut lines", isOn: $printOptions.cutLines)
        Text("\(measurement(layout)). Each page of the board starts on a new sheet.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var pictureOptionRows: some View {
        Picker("Styles", selection: $setScope) {
            ForEach(ExportSetScope.allCases) { scope in
                Text(scope.label).tag(scope)
            }
        }
        Text("Blaster files always carry every style, so whoever receives one sees your words in whichever style they use. This is only for exported images.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: - Row summaries

    /// The subtitle doubles as the settings readout, so the collapsed row still
    /// says what will come out — sheet count, paper, how many pictures.
    private func summary(for destination: ShareDestination) -> String {
        switch destination {
        case .nativeFile:
            return isPage ? "Words and pictures, for another Blaster"
                          : "The whole board, for another Blaster"
        case .printablePDF:
            let layout = SheetLayout.compute(paper: printOptions.paper,
                                             orientation: printOptions.orientation,
                                             columns: resolvedColumns)
            return "\(sheetSummary(layout)) · \(printOptions.paper.displayName) \(printOptions.orientation.label.lowercased())"
        case .tileImages:
            let sets = setScope == .allSets ? ExportArtResolver.allInstalledSets.count : 1
            let count = Set(subject.tileKeys).count * sets
            return "\(count) PNG image\(count == 1 ? "" : "s") · \(setScope.label.lowercased())"
        }
    }

    /// Reads the *resolved* count and writes an explicit one.
    ///
    /// `printOptions.columns` is 0 until the caregiver chooses, which is outside
    /// the stepper's range — stepping from 0 would jump to the minimum rather
    /// than nudging the value they can see. This makes the first tap continue
    /// from the default that is actually on screen.
    private var columnsBinding: Binding<Int> {
        Binding(get: { resolvedColumns },
                set: { printOptions.columns = $0 })
    }

    /// Tiles on the busiest page — what the density default has to accommodate.
    private var largestPageTileCount: Int {
        BoardPagination.filtered(printablePages, filter: printOptions.filter,
                                 tileLookup: tileLookup)
            .map(\.tiles.count).max() ?? 0
    }

    /// The density in force: the caregiver's choice, or a default that fits this
    /// board's biggest page on one sheet.
    private var resolvedColumns: Int {
        guard printOptions.columns == 0 else { return printOptions.resolvedColumns }
        return printOptions.defaultColumns(fittingLargestPage: largestPageTileCount)
    }

    private func measurement(_ layout: SheetLayout) -> String {
        String(format: "%.1f-inch tiles, %d per sheet", layout.tileInches, layout.perSheet)
    }

    private func sheetSummary(_ layout: SheetLayout) -> String {
        let filtered = BoardPagination.filtered(printablePages, filter: printOptions.filter,
                                                tileLookup: tileLookup)
        let count = BoardPagination.paginate(filtered, perSheet: layout.perSheet).count
        return "\(count) sheet\(count == 1 ? "" : "s")"
    }

    private var printablePages: [PageSpec] {
        switch subject {
        case .scene(let scene): return scene.pages
        case .page(let page, _): return [page]
        }
    }

    // MARK: - Copy

    private func title(for destination: ShareDestination) -> String {
        switch destination {
        case .nativeFile: return isPage ? "Blaster Pack" : "Blaster Scene"
        case .printablePDF: return "Printable PDF"
        case .tileImages: return "Tile Pictures"
        }
    }

    // MARK: - Producing the file

    /// Export runs as a cancellable task, and says how far along it is.
    ///
    /// It used to be a synchronous call with `defer { isWorking = false }`, which
    /// meant the flag went up and down inside one blocking block — the spinner
    /// never had a frame to render in, and the app simply froze. Exporting every
    /// picture in every style is roughly 2,500 encodes, long enough that a
    /// caregiver reasonably concludes it has hung and force-quits mid-write.
    private func produce(_ destination: ShareDestination) {
        guard work == nil else { return }
        expanded = nil
        work = Work(destination: destination, label: waitingLabel(for: destination))
        task = Task {
            do {
                let file: ExportedFile
                switch destination {
                case .nativeFile:   file = try nativeFile()
                case .printablePDF: file = try await printablePDF()
                case .tileImages:   file = try await tileImages()
                }
                try Task.checkCancellation()
                work = nil
                exported = file
            } catch is CancellationError {
                work = nil
            } catch {
                work = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    private func waitingLabel(for destination: ShareDestination) -> String {
        switch destination {
        case .nativeFile: return "Packaging words and pictures…"
        case .printablePDF: return "Drawing sheets…"
        case .tileImages: return "Saving pictures…"
        }
    }

    /// Progress for one export. `total` is known up front for both slow paths, so
    /// the caregiver sees how much is left rather than an unbounded spinner.
    private struct Work {
        let destination: ShareDestination
        var label: String
        var done = 0
        var total = 0
        var fraction: Double? {
            total > 0 ? Double(done) / Double(total) : nil
        }
    }

    @MainActor private func note(_ done: Int, _ total: Int) {
        work?.done = done
        work?.total = total
    }

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private func nativeFile() throws -> ExportedFile {
        switch subject {
        case .scene(let scene):
            // Stamp identity and provenance before the file leaves, exactly as
            // the old scenes-tab export did — a shared scene without an id can
            // never be recognised as an update on the far side.
            let authorID = DeviceProfileStore.ensureAuthorID(context: modelContext)
            let authorName = DeviceProfileStore.authorName(context: modelContext)
            scene.ensureIdentity(authorID: authorID, authorName: authorName)
            if scene.authorName.isEmpty, !authorName.isEmpty,
               scene.sceneID.hasPrefix(authorID + "/") {
                scene.authorName = authorName
            }
            try? modelContext.save()

            let defaultKeys = Set(allTiles.filter(\.isSystem).map(\.key))
            let data = try SceneExporter.exportJSON(scene,
                                                    defaultTileKeys: defaultKeys,
                                                    tileLookup: tileLookup,
                                                    context: modelContext)
            return try ExportedFile.write(data, named: "\(subject.basename).\(BlasterSceneFormat.fileExtension)")

        case .page(let page, let scene):
            let data = try PackExporter.exportPageJSON(page, from: scene,
                                                       tileLookup: tileLookup,
                                                       context: modelContext)
            return try ExportedFile.write(data, named: "\(subject.basename).\(BlasterPackFormat.fileExtension)")
        }
    }

    private func printablePDF() async throws -> ExportedFile {
        // Pin the density the caregiver is looking at. `printOptions.columns` is
        // still 0 when they have not touched the stepper, and the renderer has no
        // way to work out the content-aware default on its own.
        var printOptions = printOptions
        printOptions.columns = resolvedColumns

        let data = try await BoardPDFRenderer.render(pages: printablePages,
                                                     scene: subject.scene,
                                                     tileLookup: tileLookup,
                                                     options: printOptions,
                                                     imageSet: imageResolver.activeSet,
                                                     resolver: imageResolver,
                                                     progress: note)
        return try ExportedFile.write(data, named: "\(subject.basename).pdf")
    }

    private func tileImages() async throws -> ExportedFile {
        let url = try await TileImageExporter.exportZip(keys: subject.tileKeys,
                                                        scope: setScope,
                                                        resolver: imageResolver,
                                                        basename: subject.basename,
                                                        progress: note)
        return ExportedFile(url: url, displayName: url.lastPathComponent)
    }
}
