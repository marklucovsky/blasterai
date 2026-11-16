// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+ScenesTab.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

extension AdminView {

    /// Settings › Boards and Vocabulary: Vocabulary, then the boards, with a
    /// filter, a search field, and one + menu for making and bringing them in.
    /// Built for 20 or more boards: one line each, the active board pinned at
    /// the top, templates folded into a group at the bottom.
    var boardsPage: some View {
        List {
            Section {
                NavigationLink("Vocabulary", value: AdminPage.vocabulary)
            }
            Section {
                Picker("Show", selection: $boardFilter) {
                    ForEach(BoardFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            scenesSection
        }
        .searchable(text: $boardSearch, placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: "Search boards")
        .navigationTitle("Boards and Vocabulary")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { isCreatingScene = true } label: {
                        Label("New Board", systemImage: "plus")
                    }
                    Button { isImportingBoard = true } label: {
                        Label("Import Board or Spreadsheet", systemImage: "square.and.arrow.down")
                    }
                    Divider()
                    Picker("Sort", selection: $boardsSortByName) {
                        Text("Recent").tag(false)
                        Text("Name").tag(true)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
    }

    /// The board pages' sheets and dialogs, hosted on Settings' one
    /// NavigationStack: "Edit this board" on the first screen raises the same
    /// clone-on-write question as a row on Boards and Vocabulary.
    func scenesModals(_ content: some View) -> some View {
        content
        .sheet(isPresented: $isCreatingScene) {
            SceneGeneratorSheet(allTiles: allTiles, apiKey: resolvedAPIKey) { scene in
                navigateToNewScene = scene
            } onManual: { name in
                createBlankScene(name: name)
            }
        }
        .sheet(item: $sceneToShare) { scene in
            ShareBoardSheet(subject: .scene(scene))
        }
        .sheet(isPresented: $isImportingBoard) {
            BoardImportSheet(scene: nil) { scene, _ in navigateToNewScene = scene }
        }
        .confirmationDialog(
            sceneToClone?.isLockedTemplate == true ? "This template is someone else\u{2019}s" : "This is a built-in board",
            isPresented: Binding(get: { sceneToClone != nil },
                                 set: { if !$0 { sceneToClone = nil } }),
            titleVisibility: .visible,
            presenting: sceneToClone
        ) { scene in
            Button("Make My Copy") { cloneSystemSceneForEditing(scene) }
            Button("Cancel", role: .cancel) { sceneToClone = nil }
        } message: { scene in
            if scene.isLockedTemplate {
                Text(BlasterScene.lockedTemplateNote(scene) + " We\u{2019}ll make you a copy built on it and switch to it: the pages you change are yours, and the rest keeps following its updates.")
            } else {
                Text("\(scene.baseName) is supplied and updated by BlasterAI, so it can't be edited directly. We'll make you an editable copy and switch to it. Your copy is yours — app updates won't touch it.")
            }
        }
        // An alert, not a dialog: on iPad a dialog is a popover whose Cancel
        // is a tap outside it, and this choice wants Cancel in plain sight.
        .alert(
            templateToDelete.map { "Delete \(BlasterScene.copyRoot(of: $0.name))?" } ?? "",
            isPresented: Binding(get: { templateToDelete != nil },
                                 set: { if !$0 { templateToDelete = nil } }),
            presenting: templateToDelete
        ) { template in
            // The scenes built on it keep the pages and bar they use, so
            // nothing they show changes.
            Button("Delete", role: .destructive) {
                TemplateRemoval.keepLookOfAll(templateDependents(template), without: template,
                                              templates: scenes.filter(\.isTemplate),
                                              system: scenes.first(where: \.isDefault))
                removeScene(template)
            }
            Button("Cancel", role: .cancel) { templateToDelete = nil }
        } message: { template in
            Text(templateDeleteMessage(template))
        }
        .sheet(item: $pendingImportURL) { item in
            ImportRouteSheet(url: item.url) { pendingImportURL = nil }
        }
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    // MARK: - Sections

    /// The boards a filter shows, searched and sorted, Me pages and carried
    /// templates left out: a Me page is reached from its profile, and a
    /// carried template is how another board works (Settings › Advanced ›
    /// Authoring lists those).
    var listedScenes: [BlasterScene] {
        let topicIDs: Set<String> = {
            guard boardFilter == .topics, let profile = profileResolver.active,
                  let me = MeScene.find(profileID: profile.id, context: modelContext) else { return [] }
            return Set(MeScene.topicIDs(in: me))
        }()
        let query = boardSearch.trimmingCharacters(in: .whitespaces)
        let shown = scenes.filter { scene in
            guard !MeScene.isMeScene(scene), !scene.isCarriedTemplate else { return false }
            switch boardFilter {
            case .all: break
            case .mine: if scene.provenance == .firstParty { return false }
            case .builtIn: if scene.provenance != .firstParty { return false }
            case .topics: if !topicIDs.contains(scene.sceneID) { return false }
            }
            return query.isEmpty
                || scene.name.localizedCaseInsensitiveContains(query)
                || scene.descriptionText.localizedCaseInsensitiveContains(query)
        }
        return boardsSortByName
            ? shown.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            : shown.sorted { $0.lastModified > $1.lastModified }
    }

    @ViewBuilder
    var scenesSection: some View {
        let listed = listedScenes
        // One list, the current board first and checked.
        let boards = listed.filter(\.isActive) + listed.filter { !$0.isActive && !$0.isTemplate }
        let templates = listed.filter { !$0.isActive && $0.isTemplate }
        if listed.isEmpty {
            Section {
                Text(boardSearch.isEmpty ? boardFilter.emptyText : "No boards match \u{201C}\(boardSearch)\u{201D}.")
                    .foregroundStyle(.secondary)
            }
        }
        if !boards.isEmpty {
            Section {
                ForEach(boards) { boardRow($0) }
            } footer: {
                Text("Swipe a board, or touch and hold it, for more.")
            }
        }
        if !templates.isEmpty {
            Section {
                // Open while searching, so a match is never hidden in a fold.
                DisclosureGroup("Templates (\(templates.count))", isExpanded: Binding(
                    get: { isTemplatesExpanded || !boardSearch.isEmpty },
                    set: { isTemplatesExpanded = $0 })) {
                    ForEach(templates) { boardRow($0) }
                }
            } footer: {
                Text("A template is a board other boards are built on.")
            }
        }
    }

    /// One board, one line: its name, then pages and date. The checkmark is
    /// the current board. The row opens the editor; a board we ship, or
    /// someone else's template, offers an editable copy first.
    func boardRow(_ scene: BlasterScene) -> some View {
        Group {
            if scene.isSystemOwned || scene.isLockedTemplate {
                Button { sceneToClone = scene } label: {
                    BoardRow(scene: scene, builtOn: templateNote(scene))
                }
                .buttonStyle(.plain)
            } else {
                NavigationLink(destination: SceneEditorView(scene: scene)) {
                    BoardRow(scene: scene, builtOn: templateNote(scene))
                }
            }
        }
        .swipeActions(edge: .leading) {
            activateButton(scene)
            topicButton(scene)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            deleteButton(scene)
            shareButton(scene)
            duplicateButton(scene)
        }
        // The same actions on touch-and-hold: a swipe is invisible until you
        // know it is there, and on a Mac a right-click is what people reach for.
        .contextMenu {
            activateButton(scene)
            topicButton(scene)
            shareButton(scene)
            duplicateButton(scene)
            if isDeletable(scene) {
                Divider()
                deleteButton(scene)
            }
        }
    }

    // MARK: - Row actions
    //
    // Written once and used by both the swipe and the menu, so the two cannot
    // drift into offering different things.

    /// A board we ship is undeletable as well as uneditable: a caregiver who
    /// wants rid of one keeps their own copy and stops activating this.
    func isDeletable(_ scene: BlasterScene) -> Bool {
        !scene.isDefault && !scene.isSystemOwned
    }

    @ViewBuilder
    func activateButton(_ scene: BlasterScene) -> some View {
        if !scene.isActive {
            Button {
                activateScene(scene)
            } label: {
                Label("Make Current Board", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }
    }

    /// Add to (or take off) the active child's My Topics, which mounts the
    /// scene under their Me page instead of making it the board.
    @ViewBuilder
    func topicButton(_ scene: BlasterScene) -> some View {
        if MeScene.isEligibleTopic(scene), let profile = profileResolver.active {
            let me = MeScene.find(profileID: profile.id, context: modelContext)
            if let me, MeScene.contains(scene, in: me) {
                Button {
                    MeScene.removeTopic(sceneID: scene.sceneID, from: me)
                    try? modelContext.save()
                } label: {
                    Label("Remove from My Topics", systemImage: "heart.slash")
                }
                .tint(.pink)
            } else {
                Button {
                    let me = MeScene.ensure(profileID: profile.id, context: modelContext)
                    MeScene.addTopic(scene, to: me, context: modelContext)
                    try? modelContext.save()
                } label: {
                    Label(profile.isSystem || profile.displayName.isEmpty
                          ? "Add to My Topics" : "Add to \(profile.visibleName)'s Topics",
                          systemImage: "heart")
                }
                .tint(.pink)
            }
        }
    }

    @ViewBuilder
    func shareButton(_ scene: BlasterScene) -> some View {
        Button {
            sceneToShare = scene
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .tint(.blue)
    }

    @ViewBuilder
    func duplicateButton(_ scene: BlasterScene) -> some View {
        Button {
            duplicateScene(scene)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }
        .tint(.indigo)
    }

    @ViewBuilder
    func deleteButton(_ scene: BlasterScene) -> some View {
        if isDeletable(scene) {
            Button(role: .destructive) {
                deleteScene(scene)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Scene actions

    func duplicateScene(_ scene: BlasterScene) {
        _ = BlasterScene.duplicate(of: scene, in: modelContext,
                                   authorID: DeviceProfileStore.ensureAuthorID(context: modelContext),
                                   authorName: DeviceProfileStore.authorName(context: modelContext))
        try? modelContext.save()
    }

    /// Activate, and say what happened.
    ///
    /// Every call site used to be `try?`, which is how §9's "never silently"
    /// was actually being broken: `activate` already repaired a dangling home
    /// page, and the caregiver's board changed under them with no explanation.
    /// A thrown refusal went nowhere either.
    func activateScene(_ scene: BlasterScene) {
        do {
            let outcome = try scene.activate(context: modelContext)
            try? modelContext.save()
            if let message = outcome.message {
                activationNotice = ActivationNotice(title: "Board Activated", message: message)
            }
        } catch {
            // Nothing was mutated — `activate` validates before it touches
            // anything — so the previously active scene is still the board.
            activationNotice = ActivationNotice(
                title: "Can't Use This Board",
                message: error.localizedDescription)
        }
    }

    /// Clone-on-write for an immutable system scene: take an editable copy,
    /// make it active, and open the editor on it. The caregiver asked to edit,
    /// so they land in something they can actually edit rather than being told
    /// no. See `BlasterScene.isSystemOwned`.
    func cloneSystemSceneForEditing(_ scene: BlasterScene) {
        let copy = BlasterScene.cloneForEditing(
            scene, in: modelContext,
            authorID: DeviceProfileStore.ensureAuthorID(context: modelContext),
            authorName: DeviceProfileStore.authorName(context: modelContext))
        activateScene(copy)
        sceneToClone = nil
        navigateToNewScene = copy       // reuse the post-generation editor route
    }

    func deleteScenes(at offsets: IndexSet) {
        // One way to delete, so a template in use is always warned about.
        for scene in offsets.map({ scenes[$0] }) { deleteScene(scene) }
    }

    func deleteScene(_ scene: BlasterScene) {
        guard !scene.isDefault else { return }
        // A template someone else sent, that scenes here are built on, only
        // leaves the list: it goes on supplying them, under Templates in Use,
        // until the last of them is deleted.
        if scene.isLockedTemplate, !templateDependents(scene).isEmpty {
            let wasActive = scene.isActive
            scene.isCarriedTemplate = true
            if wasActive, let system = scenes.first(where: \.isDefault) { _ = try? system.activate(context: modelContext) }
            try? modelContext.save()
            return
        }
        // A template other scenes are built on is not deleted out from under
        // them: the warning names them and asks how they should go on.
        if scene.isTemplate, !templateDependents(scene).isEmpty {
            templateToDelete = scene
            return
        }
        removeScene(scene)
    }

    /// The list's line about what a scene is built on.
    func templateNote(_ scene: BlasterScene) -> SceneRow.TemplateNote? {
        guard !scene.templateID.isEmpty else { return nil }
        if let template = scenes.first(where: { $0.isTemplate && $0.sceneID == scene.templateID }) {
            return .template(BlasterScene.copyRoot(of: template.name))
        }
        return .missing(TemplateChain.missingName(scene.templateID))
    }

    /// The scenes built on `template`, and what deleting it would strand.
    func templateDependents(_ template: BlasterScene) -> [TemplateRemoval.Dependent] {
        TemplateRemoval.dependents(of: template, scenes: scenes, system: scenes.first(where: \.isDefault))
    }

    func templateDeleteMessage(_ template: BlasterScene) -> String {
        let names = templateDependents(template).map { BlasterScene.copyRoot(of: $0.scene.name) }
        let list = ListFormatter.localizedString(byJoining: names)
        return names.count == 1
            ? "\(list) is built on it and will keep its pages and navigation bar."
            : "\(list) are built on it and will keep their pages and navigation bars."
    }

    /// Delete a scene outright.
    func removeScene(_ scene: BlasterScene) {
        templateToDelete = nil
        let wasActive = scene.isActive
        MeScene.removeTopicEverywhere(sceneID: scene.sceneID, context: modelContext)
        modelContext.delete(scene)
        if wasActive {
            if let defaultScene = scenes.first(where: { $0.isDefault }) {
                defaultScene.isActive = true
            }
        }
        // A carried template goes with the last scene that used it.
        let remaining = scenes.filter { $0.persistentModelID != scene.persistentModelID }
        for unused in TemplateRemoval.unusedCarried(in: remaining) {
            modelContext.delete(unused)
        }
        try? modelContext.save()
    }

    // MARK: - Templates in Use

    /// Templates here only because a scene built on them brought them along
    /// (`BlasterScene.isCarriedTemplate`). Collapsed: they are how those
    /// scenes work, not boards of the caregiver's own.
    @ViewBuilder
    var carriedTemplatesSection: some View {
        let carried = scenes.filter(\.isCarriedTemplate)
        if !carried.isEmpty {
            Section {
                DisclosureGroup("Templates in Use (\(carried.count))") {
                    ForEach(carried) { template in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(BlasterScene.copyRoot(of: template.name)).font(.headline)
                            Text(carriedUsers(template))
                                .font(.caption).foregroundStyle(.secondary)
                            Button("Add to My Boards") {
                                template.isCarriedTemplate = false
                                try? modelContext.save()
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                        }
                        .padding(.vertical, 2)
                    }
                }
            } footer: {
                Text("Boards here are built on these. They came with those boards and update when a newer one arrives; each is removed with the last board that uses it.")
            }
        }
    }

    /// "Used by Bible Board" — the scenes a carried template supplies.
    func carriedUsers(_ template: BlasterScene) -> String {
        let names = templateDependents(template)
            .filter { !$0.scene.isCarriedTemplate }
            .map { BlasterScene.copyRoot(of: $0.scene.name) }
        return names.isEmpty ? "Used by another template" : "Used by " + ListFormatter.localizedString(byJoining: names)
    }

    var resolvedAPIKey: String {
        OpenAIKeyVault.currentKey() ?? ""
    }

    func createBlankScene(name: String) {
        let scene = BlasterScene(name: name.isEmpty ? "New Board" : name)
        scene.ensureIdentity(authorID: DeviceProfileStore.ensureAuthorID(context: modelContext),
                             authorName: DeviceProfileStore.authorName(context: modelContext))
        modelContext.insert(scene)
        navigateToNewScene = scene
    }

    /// Keys a fresh install already owns, so an export need not carry them.
    ///
    /// `vocabulary.json`, NOT `isSystem`. The two look interchangeable and are
    /// not: `isSystem` means first-party, and bundled PACK words are first-party
    /// while being absent until the pack is installed. Filtering on it dropped
    /// every pack word from every export. See `BundledVocabulary`.
    var defaultTileKeys: Set<String> { BundledVocabulary.keys }

}

/// Which boards Boards and Vocabulary shows.
enum BoardFilter: String, CaseIterable, Identifiable {
    case all, mine, builtIn, topics
    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .mine: "Mine"
        case .builtIn: "Built-in"
        case .topics: "Topics"
        }
    }

    var emptyText: String {
        switch self {
        case .all: "No boards yet. Tap + to make one or bring one in."
        case .mine: "No boards of your own yet. Tap + to make one, or duplicate a built-in board."
        case .builtIn: "No built-in boards."
        case .topics: "Nothing on My Topics yet. Swipe a board right to add it."
        }
    }
}

/// A board on one line, for a list of 20 or more: name, then pages and the
/// date it last changed; a mark for a template or a built-in board, a
/// warning when its template is missing, and a check on the current board.
struct BoardRow: View {
    let scene: BlasterScene
    var builtOn: SceneRow.TemplateNote? = nil

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(scene.name).lineLimit(1)
                    if scene.isTemplate {
                        Image(systemName: "square.stack.3d.up")
                            .font(.caption)
                            .foregroundStyle(.indigo)
                            .accessibilityLabel("Template")
                    }
                    if case .missing = builtOn {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Its template is missing")
                    }
                }
                HStack(spacing: 5) {
                    // Where it came from, at a glance: the same dot the old
                    // rows used (purple BlasterAI, green yours, orange shared).
                    Circle().fill(provenanceColor).frame(width: 7, height: 7)
                        .accessibilityHidden(true)
                    Text(detail).lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if scene.isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Current board")
            }
        }
        .contentShape(Rectangle())
    }

    private var provenanceColor: Color {
        switch scene.provenance {
        case .firstParty: .purple
        case .local: .green
        case .imported: .orange
        }
    }

    /// Pages, where it came from, and when it last changed:
    /// "12 pages · Built-in", "12 pages · Mine · Nov 14",
    /// "12 pages · Shared by Greta, edited · Nov 14".
    private var detail: String {
        var parts = ["\(scene.pages.count) page\(scene.pages.count == 1 ? "" : "s")"]
        let edited = scene.isLocallyModified ? ", edited" : ""
        switch scene.provenance {
        case .firstParty:
            parts.append("Built-in")
        case .local:
            parts.append("Mine")
        case .imported:
            parts.append((scene.authorName.isEmpty ? "Shared" : "Shared by \(scene.authorName)") + edited)
        }
        if scene.provenance != .firstParty {
            parts.append(scene.lastModified.formatted(.dateTime.month(.abbreviated).day()))
        }
        switch builtOn {
        case .template(let name): parts.append("on \(name)")
        case .missing(let name): parts.append("\(name) missing")
        case nil: break
        }
        return parts.joined(separator: " · ")
    }
}
