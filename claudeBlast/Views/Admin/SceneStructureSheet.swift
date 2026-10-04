// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneStructureSheet.swift
//  claudeBlast
//
//  The structure step: choose the pages and core words a scene gets, after its
//  own words exist and before it is saved.
//
//  Three things live here, sharing one picker:
//
//  - `SceneStructurePicker` — the selection form itself.
//  - `SceneStructureStep`   — page three of the new-scene wizard
//                             (compose → preview → **structure** → confirm).
//  - `SceneStructureSheet`  — the same picker reached from the scene editor, for
//                             a scene that already exists.
//
//  Why a step rather than a toggle, and why everything here is additive, is
//  explained where the work happens: `Services/SceneStructure.swift`.
//

import SwiftUI
import SwiftData

// MARK: - The picker

/// The selection form. Owns no work: it edits a `SceneStructurePlan` and lets
/// its host decide when to resolve it.
struct SceneStructurePicker: View {
    @Binding var plan: SceneStructurePlan
    let allTiles: [TileModel]
    let packs: [VocabPack]
    let donorScenes: [BlasterScene]
    /// Page keys the scene already has — what's offered is checked against these
    /// so the picker can say "already on this scene" rather than quietly making
    /// a second copy.
    let existingPageKeys: Set<String>

    @State private var expandedScenes: Set<String> = []
    // Collapsed by default except core words: four open sections is a lot of
    // scrolling for what is usually one or two choices, and a collapsed section
    // still says how many it holds.
    @State private var showCore = true
    @State private var showPacks = false
    @State private var showClasses = false
    @State private var showDonors = false

    /// Sections, not a `Form` — the host supplies that, so "Build from
    /// Collections" can put a scene-name field above the same picker.
    var body: some View {
        Group {
            coreWordsSection
            packsSection
            classesSection
            donorScenesSection
            summarySection
        }
    }

    private var coreWordsSection: some View {
        Section(isExpanded: $showCore) {
            Picker("Core words", selection: $plan.chrome) {
                ForEach(SceneNavigation.ChromeBundle.allCases) { bundle in
                    Text(bundle.title).tag(bundle)
                }
            }
            .pickerStyle(.segmented)
            Text(plan.chrome.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Added after the words the scene is already about. Use Select Tiles in the page editor to move them wherever you want them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            header("Add core words to the home page",
                   count: plan.chrome == .none ? 0 : 1,
                   isExpanded: $showCore)
        }
    }

    @ViewBuilder
    private var packsSection: some View {
        if !packs.isEmpty {
            Section(isExpanded: $showPacks) {
                ForEach(packs) { pack in
                    row(title: pack.displayName,
                        subtitle: "\(pack.words.count) words · \(pack.attribution)",
                        alreadyThere: existingPageKeys.contains(pack.slug),
                        isOn: plan.packIDs.contains(pack.id)) {
                        toggle(pack.id, in: &plan.packIDs)
                    }
                }
            } header: {
                header("Add pages from vocabulary packs",
                       count: plan.packIDs.count, isExpanded: $showPacks)
            }
        }
    }

    /// A tappable section header: title, a count of what's chosen inside (so a
    /// collapsed section isn't silent about it), and a chevron.
    private func header(_ title: String, count: Int, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.snappy) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.accentColor.opacity(0.2)))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var classOptions: [(cls: VocabularyClass, count: Int)] {
        let counts = allTiles.reduce(into: [String: Int]()) { totals, tile in
            guard !tile.isRetired else { return }
            totals[tile.wordClass, default: 0] += 1
        }
        return VocabularyClasses.caregiverSelectable.compactMap { cls in
            let n = counts[cls.name] ?? 0
            return n > 0 ? (cls, n) : nil
        }
    }

    private var classesSection: some View {
        Section(isExpanded: $showClasses) {
            ForEach(classOptions, id: \.cls.id) { option in
                row(title: option.cls.label,
                    subtitle: "\(option.count) words",
                    alreadyThere: existingPageKeys.contains(TileModel.normalizeKey(option.cls.name)),
                    isOn: plan.wordClasses.contains(option.cls.name),
                    swatch: TileColorResolver.color(for: option.cls.defaultPartOfSpeech)) {
                    toggle(option.cls.name, in: &plan.wordClasses)
                }
            }
        } header: {
            header("Add pages from word classes",
                   count: plan.wordClasses.count, isExpanded: $showClasses)
        }
    }

    private var donorScenesSection: some View {
        Section(isExpanded: $showDonors) {
            if donorScenes.isEmpty {
                Text("No other scenes to copy from yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(donorScenes) { donor in
                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedScenes.contains(donor.sceneID) },
                        set: { _ in toggle(donor.sceneID, in: &expandedScenes) })
                ) {
                    ForEach(donor.pages) { page in
                        let token = SceneStructurePlan.donorToken(sceneID: donor.sceneID,
                                                                  pageKey: page.key)
                        row(title: page.title,
                            subtitle: "\(page.tiles.count) tiles",
                            alreadyThere: existingPageKeys.contains(page.key),
                            isOn: plan.donorPages.contains(token)) {
                            toggle(token, in: &plan.donorPages)
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(donor.name)
                        Text("\(donor.pages.count) page\(donor.pages.count == 1 ? "" : "s")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            // In the content rather than a footer: the collapsible Section has no
            // footer slot, and a note about copying belongs with the copying.
            Text("Copies the words. Navigation links inside a copied page are dropped, because they point at pages that scene has and this one may not.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            header("Add pages from another scene",
                   count: plan.donorPages.count, isExpanded: $showDonors)
        }
    }

    @ViewBuilder
    private var summarySection: some View {
        Section {
            if plan.isEmpty {
                Text("Nothing selected — the scene stays exactly as it is. That is a fine answer; you can add pages later from the scene editor.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Adds \(plan.additionCount) thing\(plan.additionCount == 1 ? "" : "s"). Nothing is removed or rearranged.",
                      systemImage: "plus.circle")
                    .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func row(title: String, subtitle: String, alreadyThere: Bool, isOn: Bool,
                     swatch: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                if let swatch {
                    Circle().fill(swatch).frame(width: 10, height: 10)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(alreadyThere ? "already on this scene" : subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if alreadyThere {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
                } else if isOn {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                } else {
                    Image(systemName: "circle").foregroundStyle(.tertiary)
                }
            }
        }
        .disabled(alreadyThere)
    }

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
}

// MARK: - Live preview

/// The home page as the current plan would leave it, drawn live above the form.
///
/// The first draft of this step put the core-word picker on the scene preview
/// itself, and the thing that made it work was watching the board change as you
/// switched. Moving the choice to its own screen lost that, so the board comes
/// along: existing tiles, then the core words the plan adds, then a chip per new
/// page. It runs off `SceneStructure.outline`, which is pure, so it can update on
/// every tap without installing anything.
struct SceneStructureBoardPreview: View {
    /// One drawable home-page tile.
    ///
    /// Carries its own name and class rather than only a key, because the tiles
    /// that matter most here — the words the model just proposed — have no
    /// `TileModel` yet. Resolving purely through the vocabulary lookup drew an
    /// empty board for exactly the scene the caregiver came to look at.
    struct BoardTile: Identifiable, Equatable {
        let key: String
        let displayName: String
        let wordClass: String
        var id: String { key }

        /// From an in-flight generated tile: real vocabulary if we have it,
        /// otherwise the proposed word's own metadata.
        init?(_ tile: GeneratedTile, lookup: [String: TileModel]) {
            if let model = lookup[tile.key] {
                self.init(model)
            } else if let name = tile.displayName, let wordClass = tile.wordClass {
                self.init(key: tile.key, displayName: name, wordClass: wordClass)
            } else {
                return nil
            }
        }

        private init(key: String, displayName: String, wordClass: String) {
            self.key = key
            self.displayName = displayName
            self.wordClass = wordClass
        }

        /// From a placement on a saved scene.
        init?(_ entry: TileEntry, lookup: [String: TileModel]) {
            guard let model = lookup[entry.key] else { return nil }
            self.init(model)
        }

        init(_ model: TileModel) {
            self.init(key: model.bundleImage, displayName: model.displayName,
                      wordClass: model.wordClass)
        }
    }

    let existingHomeTiles: [BoardTile]
    let outline: SceneStructureOutline
    let tileLookup: [String: TileModel]
    @Binding var isExpanded: Bool

    private let columns = [GridItem(.adaptive(minimum: 52, maximum: 64), spacing: 8)]

    private var addedWords: [BoardTile] {
        outline.homeWords.compactMap { tileLookup[$0].map { BoardTile($0) } }
    }

    private var summary: String {
        let words = existingHomeTiles.count + outline.homeWords.count + outline.homeLinks.count
        let pages = outline.pages.count
        guard pages > 0 else { return "Home page · \(words) tiles" }
        return "Home page · \(words) tiles · \(pages) new page\(pages == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.grid.3x2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary)
                        .font(.caption.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if isExpanded {
                ScrollView {
                    if existingHomeTiles.isEmpty && addedWords.isEmpty && outline.homeLinks.isEmpty {
                        Text("This scene's home page is empty. Anything you add below lands here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                    } else {
                        LazyVGrid(columns: columns, spacing: 8) {
                            ForEach(existingHomeTiles) { tile in
                                cell(tile, isAdded: false)
                            }
                            ForEach(addedWords) { tile in
                                cell(tile, isAdded: true)
                            }
                            ForEach(outline.homeLinks, id: \.self) { title in
                                pageChip(title)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                    }
                }
                // Enough for three rows; the board is a reference here, not the
                // thing being edited, so it must not crowd out the controls.
                .frame(maxHeight: 210)
            }
        }
        .background(.bar)
    }

    private func cell(_ tile: BoardTile, isAdded: Bool) -> some View {
        VStack(spacing: 2) {
            TileImageView(key: tile.key, wordClass: tile.wordClass)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.accentColor, lineWidth: isAdded ? 2 : 0)
                )
            Text(tile.displayName)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(isAdded ? Color.accentColor : .secondary)
        }
        // The tiles the plan adds are outlined, so "what did that toggle do" is
        // answerable at a glance rather than by counting.
        .transition(.scale.combined(with: .opacity))
    }

    private func pageChip(_ title: String) -> some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.accentColor.opacity(0.18))
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 7).stroke(Color.accentColor, lineWidth: 2)
                )
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(Color.accentColor)
        }
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Wizard step

/// Page three of the new-scene wizard. Takes the scene as previewed, hands back
/// the same scene with the chosen structure folded in.
///
/// Next is always enabled: adding nothing is a legitimate answer, and the step
/// then costs one tap. The alternative — disabling Next until something is
/// ticked — would make a flat single-page scene, which is the right shape for a
/// Stage I child, feel like an unfinished one.
struct SceneStructureStep: View {
    let scene: GeneratedScene
    let allTiles: [TileModel]
    /// Owned by the wizard, not by this view: stepping back from the confirm
    /// page must show the choices that were made, not an empty form.
    @Binding var plan: SceneStructurePlan
    /// The augmented scene and the result that produced it. The confirm step
    /// needs the result's `createdTiles` to render (its own `allTiles` snapshot
    /// predates them), and the cached-starter accept path needs the pages
    /// themselves, since it builds its scene by importing a bundle.
    let onNext: (GeneratedScene, SceneStructureResult) -> Void
    let onBack: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BlasterScene.name) private var allScenes: [BlasterScene]
    @State private var showBoard = true

    private var existingPageKeys: Set<String> { Set(scene.pages.map(\.key)) }

    private var homePage: GeneratedPage? {
        scene.pages.first(where: { $0.key == scene.homePageKey }) ?? scene.pages.first
    }
    private var homeTileKeys: Set<String> { Set((homePage?.tiles ?? []).map(\.key)) }
    private var donors: [BlasterScene] { allScenes.filter { !$0.pages.isEmpty } }
    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        VStack(spacing: 0) {
            SceneStructureBoardPreview(
                existingHomeTiles: (homePage?.tiles ?? []).compactMap {
                    .init($0, lookup: tileLookup)
                },
                outline: SceneStructure.outline(plan,
                                                existingPageKeys: existingPageKeys,
                                                homeTileKeys: homeTileKeys,
                                                allTiles: allTiles,
                                                packs: PackCatalog.available(in: modelContext),
                                                donorScenes: donors),
                tileLookup: tileLookup,
                isExpanded: $showBoard)
            Divider()
            Form {
                SceneStructurePicker(plan: $plan,
                                     allTiles: allTiles,
                                     packs: PackCatalog.available(in: modelContext),
                                     donorScenes: donors,
                                     existingPageKeys: existingPageKeys)
            }
        }
            .animation(.snappy, value: plan)
            .navigationTitle("Add Structure")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { onBack() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { advance() }
                }
            }
    }

    private func advance() {
        guard !plan.isEmpty else { onNext(scene, SceneStructureResult()); return }
        let result = SceneStructure.build(plan,
                                          existingPageKeys: existingPageKeys,
                                          homeTileKeys: homeTileKeys,
                                          into: modelContext,
                                          allTiles: allTiles,
                                          packs: PackCatalog.available(in: modelContext),
                                          donorScenes: donors)
        onNext(scene.adding(result), result)
    }
}

// MARK: - Editor entry point

/// The same picker, reached from the scene editor for a scene that already
/// exists. "Add a couple of pages" is not something you only want to do in the
/// first thirty seconds of a scene's life.
struct SceneStructureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var scene: BlasterScene
    let allTiles: [TileModel]

    @Query(sort: \BlasterScene.name) private var allScenes: [BlasterScene]
    @State private var plan = SceneStructurePlan()
    @State private var showBoard = true

    private var donorScenes: [BlasterScene] {
        allScenes.filter { $0.persistentModelID != scene.persistentModelID && !$0.pages.isEmpty }
    }

    private var existingPageKeys: Set<String> { Set(scene.pages.map(\.key)) }

    private var homePage: PageSpec? {
        scene.pages.first(where: { $0.key == scene.homePageKey }) ?? scene.pages.first
    }
    private var homeTileKeys: Set<String> { Set((homePage?.tiles ?? []).map(\.key)) }
    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SceneStructureBoardPreview(
                    existingHomeTiles: (homePage?.tiles ?? []).compactMap {
                        .init($0, lookup: tileLookup)
                    },
                    outline: SceneStructure.outline(plan,
                                                    existingPageKeys: existingPageKeys,
                                                    homeTileKeys: homeTileKeys,
                                                    allTiles: allTiles,
                                                    packs: PackCatalog.available(in: modelContext),
                                                    donorScenes: donorScenes),
                    tileLookup: tileLookup,
                    isExpanded: $showBoard)
                Divider()
                Form {
                    SceneStructurePicker(plan: $plan,
                                         allTiles: allTiles,
                                         packs: PackCatalog.available(in: modelContext),
                                         donorScenes: donorScenes,
                                         existingPageKeys: existingPageKeys)
                }
            }
                .animation(.snappy, value: plan)
                .navigationTitle("Add Structure")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { apply() }
                            .disabled(plan.isEmpty)
                    }
                }
        }
    }

    private func apply() {
        let result = SceneStructure.build(plan,
                                          existingPageKeys: existingPageKeys,
                                          homeTileKeys: homeTileKeys,
                                          into: modelContext,
                                          allTiles: allTiles,
                                          packs: PackCatalog.available(in: modelContext),
                                          donorScenes: donorScenes)
        scene.applyStructure(result)
        try? modelContext.save()
        dismiss()
    }
}
