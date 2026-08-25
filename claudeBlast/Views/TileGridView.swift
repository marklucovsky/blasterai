// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileGridView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import AVFoundation
import UIKit

private let promotedHitThreshold = 3

struct TileGridView: View {
    @Query(filter: #Predicate<BlasterScene> { $0.isActive })
    var activeScenes: [BlasterScene]

    /// All vocabulary tiles. Used to resolve a TileEntry.key back to the
    /// underlying TileModel for display (image, label, wordClass).
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]

    @Query(
        filter: #Predicate<SentenceCache> { entry in
            entry.hitCount >= promotedHitThreshold || entry.isPinned
        },
        sort: \SentenceCache.hitCount, order: .reverse
    )
    private var promotedEntries: [SentenceCache]

    private var tileLookup: [String: TileModel] {
        Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @Environment(SentenceEngine.self) private var engine
    @Environment(NavigationCoordinator.self) private var coordinator
    @Environment(TileScriptRunner.self) private var scriptRunner
    @Environment(TileScriptRecorder.self) private var recorder
    @Environment(ChildProfileResolver.self) private var profileResolver
    @Environment(CaregiverMenuCoordinator.self) private var caregiverMenu
    @Environment(\.modelContext) private var modelContext
    @State private var showCaregiverMenu = false
    @State private var currentDisplayPage: Int? = 0
    @AppStorage("tile_speech_enabled") private var tileSpeechEnabled: Bool = true
    @State private var haptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var pendingNote: String = ""
    @State private var showNoteAlert: Bool = false
    @State private var promotedExpanded: Bool = false
    /// The tile that most recently fired a press pulse — lifted above its grid
    /// neighbors (via cell zIndex) so the grow animation isn't clipped by the
    /// adjacent cell. LazyVGrid ignores zIndex set inside the cell's subtree, so
    /// it has to live on the cell view itself.
    @State private var lastTappedKey: String?
    @AppStorage(AppSettingsKey.demoMode) private var demoMode = false

    @AppStorage(AppSettingsKey.tileSizeStep) private var tileSizeStep: Int = 0

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var compactOverlay: CompactOverlay = .none
    @State private var overlayEpoch: Int = 0

    private var isCompact: Bool { hSizeClass == .compact }

    enum CompactOverlay: Equatable {
        case none
        case sentence
        case favorites
    }

    private var activeScene: BlasterScene? { activeScenes.first }

    /// All tile keys reachable anywhere in the active scene.
    private var sceneKeySet: Set<String> {
        guard let scene = activeScene else { return [] }
        return Set(scene.pages.flatMap { $0.tiles.map(\.key) })
    }

    /// key → wordClass for all tiles in the active scene (used for icon color coding).
    private var tileWordClass: [String: String] {
        guard let scene = activeScene else { return [:] }
        let lookup = tileLookup
        var result: [String: String] = [:]
        for page in scene.pages {
            for entry in page.tiles {
                result[entry.key] = lookup[entry.key]?.wordClass ?? ""
            }
        }
        return result
    }

    private var currentPage: PageSpec? {
        guard let scene = activeScene else { return nil }
        let key = coordinator.currentPageKey ?? scene.homePageKey
        return scene.pages.first { $0.key == key }
    }

    // MARK: - Tray

    /// The tray varies by interaction mode and width, and each variant takes a
    /// dozen closures. Inlining all three in `body` pushed the expression past
    /// what the Swift type-checker will solve — it gave up outright when the
    /// history parameters were removed. Splitting them is what keeps compile
    /// times sane, and each variant now reads on its own.
    @ViewBuilder
    private var trayForCurrentMode: some View {
        if engine.interactionMode == .singleWord {
            singleWordTray
        } else if isCompact {
            compactTray
        } else {
            padTray
        }
    }

    /// Classic AAC: a running FIFO strip of spoken words, no AI. One adaptive
    /// view for both form factors.
    private var singleWordTray: some View {
            SingleWordTrayView(
                onRemove: { index in engine.removeStripWord(at: index) },
                onClear: { engine.clearStrip() },
            )
            .padding(.top, 8)
    }

    private var compactTray: some View {
            CompactTrayStrip(
                onTileTap: { index in engine.removeTile(at: index) },
                onGo: {
                    if recorder.state == .recording { recorder.recordPlay() }
                    engine.triggerGo()
                },
                onReplay: {
                    if recorder.state == .recording { recorder.recordReplay() }
                    engine.replay()
                },
                onCancelSingle: { engine.clearSelection() },
                onPlaySingle: { engine.playSingleTile() },
                onCommitActive: { engine.commitActiveAndStartNew() },
                onShowSentence: { showCompactOverlay(.sentence) },
                onShowFavorites: { showCompactOverlay(.favorites) },
                favoritesCount: min(promotedEntries.count, 99),
                isSentenceShown: compactOverlay == .sentence,
                isFavoritesShown: compactOverlay == .favorites
            )
    }

    private var padTray: some View {
            SentenceTrayView(
                onTileTap: { index in
                    engine.removeTile(at: index)
                },
                onGo: {
                    if recorder.state == .recording {
                        recorder.recordPlay()
                    }
                    engine.triggerGo()
                },
                onReplay: {
                    if recorder.state == .recording {
                        recorder.recordReplay()
                    }
                    engine.replay()
                },
                onExpandSentence: { showCompactOverlay(.sentence) },
                onShowFavorites: { showCompactOverlay(.favorites) },
                favoritesCount: min(promotedEntries.count, 99),
                isSentenceShown: compactOverlay == .sentence,
                isFavoritesShown: compactOverlay == .favorites,
                onDismissActive: {
                    engine.clearSelection()
                },
                onCommitActive: {
                    engine.commitActiveAndStartNew()
                },
                onCancelSingle: {
                    engine.clearSelection()
                },
                onPlaySingle: {
                    engine.playSingleTile()
                }
            )
            .padding(.top, 8)
    }

    /// The board itself, or an empty state when no scene is active.
    @ViewBuilder
    private var gridContent: some View {
        if let page = currentPage {
            pagedGrid(for: page)
                .overlay(alignment: .top) {
                    compactOverlayContent
                }
        } else {
            ContentUnavailableView(
                "No Active Scene",
                systemImage: "questionmark.square",
                description: Text("No scene is currently active.")
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            trayForCurrentMode
            gridContent
        }
        .overlay(alignment: .bottom) {
            if scriptRunner.state == .idle {
                TileScriptRecordingOverlay()
            } else if !(demoMode && !scriptRunner.isStepping) {
                // Demo mode hides the playback pill on a straight Run for clean
                // screen recordings; stepping keeps it (you need the controls).
                TileScriptPlaybackOverlay()
            }
        }
        // Caregiver menu — opened by long-pressing Home, which is now cell 0 of
        // the board rather than a tray button. Anchored top-leading, the corner
        // Home sits nearest, so it pops up beside it rather than centered
        // mid-screen where the caregiver's reaching arm would occlude it.
        // Admin is gated by AdminGate when ContentView presents it; on a
        // patient device it is the only entry the menu offers.
        .popover(isPresented: $showCaregiverMenu,
                 attachmentAnchor: .point(.topLeading),
                 arrowEdge: .top) {
            caregiverMenuContent
                .presentationCompactAdaptation(.popover)
        }
        .onChange(of: engine.canReplay) { _, isReady in
            guard isCompact else { return }
            if isReady {
                showCompactOverlay(.sentence)
            } else if compactOverlay == .sentence {
                dismissCompactOverlay()
            }
        }
        .task(id: overlayEpoch) {
            // Only the sentence overlay auto-dismisses; Favorites stays until tapped.
            guard isCompact, compactOverlay == .sentence else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                if compactOverlay == .sentence { compactOverlay = .none }
            }
        }
        .task {
            haptic.prepare()
            coordinator.navigationPath = [activeScene?.homePageKey ?? "home"]
        }
        .onChange(of: activeScene?.id) {
            coordinator.navigateHome(homePageKey: activeScene?.homePageKey ?? "home")
            currentDisplayPage = 0
            engine.clearSelection()
        }
        .onChange(of: activeScene?.pages.map(\.key)) { _, pageNames in
            // If the current page was deleted or renamed, navigate home
            guard let pageNames, let key = coordinator.currentPageKey else { return }
            if !pageNames.contains(key) {
                coordinator.navigateHome(homePageKey: activeScene?.homePageKey ?? "")
                currentDisplayPage = 0
            }
        }
        .onChange(of: currentPage?.tiles.map(\.key)) { _, _ in
            // Reset display page position when tile count changes significantly
            currentDisplayPage = 0
        }
        .onChange(of: coordinator.currentPageKey) { _, _ in
            currentDisplayPage = 0
        }
        .alert("Add Note", isPresented: $showNoteAlert) {
            TextField("Note", text: $pendingNote)
            Button("Add") { engine.appendNote(pendingNote) }
            Button("Cancel", role: .cancel) {}
        }
    }

    // Precomputed breadcrumb steps — avoids @ViewBuilder let-binding type-inference pitfalls.
    private struct BreadcrumbStep: Identifiable {
        let id: String        // unique per render (index + segment)
        let segment: String
        let isFirst: Bool
        let isLast: Bool
        let label: String
    }

    private var breadcrumbSteps: [BreadcrumbStep] {
        coordinator.navigationPath.enumerated().map { i, seg in
            BreadcrumbStep(
                id: "\(i)-\(seg)",
                segment: seg,
                isFirst: i == 0,
                isLast: i == coordinator.navigationPath.count - 1,
                label: i == 0 ? "Home" : seg.replacingOccurrences(of: "_", with: " ").capitalized
            )
        }
    }

    // Combined nav bar: breadcrumbs (leading) + frequent toggle (trailing).
    // Shares a single row of vertical space when both are active.
    private var navBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Breadcrumbs — leading
                if coordinator.navigationPath.count > 1 {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            ForEach(breadcrumbSteps, id: \.id) { step in
                                breadcrumbStepView(step)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                // Frequent toggle — trailing
                if !promotedEntries.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            promotedExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                            Text("\(promotedEntries.prefix(8).count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .rotationEffect(.degrees(promotedExpanded ? 90 : 0))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 26)

            // Expanded chip strip
            if promotedExpanded && !promotedEntries.isEmpty {
                PromotedChipStrip(
                    entries: Array(promotedEntries.prefix(8)),
                    sceneKeySet: sceneKeySet,
                    tileWordClass: tileWordClass
                ) { entry in
                    engine.speakPromoted(entry)
                }
            }

            Divider()
        }
    }

    @ViewBuilder
    private func breadcrumbStepView(_ step: BreadcrumbStep) -> some View {
        if !step.isFirst {
            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 5)
        }
        if step.isLast {
            Text(step.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)
        } else {
            Button {
                if step.isFirst {
                    coordinator.navigateToRoot()
                } else {
                    coordinator.navigate(to: step.segment)
                }
            } label: {
                HStack(spacing: 3) {
                    if step.isFirst {
                        Image(systemName: "house.fill")
                            .font(.caption2)
                    }
                    Text(step.label)
                        .font(.caption)
                }
                .foregroundStyle(.tertiary)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func pagedGrid(for page: PageSpec) -> some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let spec = GridLayoutCalculator.compute(
                screenSize: UIScreen.main.bounds.size,
                geo: geo.size,
                userStep: tileSizeStep
            )
            // Retired (hidden) and unreviewed (moderation-flagged) tiles never
            // render for the child — both stay invisible in running scenes until
            // the caregiver resolves them. A missing tile stays a no-op as before.
            let lookup = tileLookup
            // Cell 0 of every page is Home, so each page carries one fewer
            // vocabulary tile. Reserving it here — rather than only on page 1 —
            // is what makes the position invariant: Home is in the same place
            // on page 4 of a long board as on page 1. `max(1,)` guards a
            // pathologically small grid.
            let vocabPerPage = max(1, spec.perPage - 1)
            let chunkedTiles = page.tiles
                .filter { lookup[$0.key]?.isHiddenFromChild != true }
                .chunked(into: vocabPerPage)
            Group {
                if isLandscape {
                    landscapeTabView(chunks: chunkedTiles, spec: spec)
                } else {
                    portraitScrollView(chunks: chunkedTiles, pageHeight: geo.size.height, spec: spec)
                }
            }
            #if DEBUG
            .overlay(alignment: .centerLastTextBaseline) {
                // Hidden in demo mode so the geometry/density badge isn't recorded.
                if !demoMode {
                    gridDebugBadge(spec: spec, tileCount: page.tiles.count)
                }
            }
            #endif
            .onChange(of: isLandscape) { _, _ in
                currentDisplayPage = 0
            }
            .onChange(of: scriptRunner.tapPulseKey) { _, key in
                // During TileScript playback, page the grid to the display-chunk that
                // holds the just-tapped tile so the tap is visible even when it's off
                // the current page. (The script navigates to the tile's board page
                // first, so the tile is always somewhere on `page`.)
                guard let key,
                      let idx = page.tiles.firstIndex(where: { $0.key == key }) else { return }
                // Pages hold `perPage - 1` vocabulary tiles; cell 0 is Home.
                let chunk = idx / max(1, spec.perPage - 1)
                if currentDisplayPage != chunk {
                    withAnimation { currentDisplayPage = chunk }
                }
            }
        }
    }

    // MARK: - Compact (iPhone) overlays

    @ViewBuilder
    private var compactOverlayContent: some View {
        switch compactOverlay {
        case .none:
            EmptyView()
        case .sentence:
            if let sentence = engine.activeGroup.sentence {
                GlassSentencePopover(
                    sentence: sentence,
                    onDismiss: { dismissCompactOverlay() }
                )
                .allowsHitTesting(true)
            }
        case .favorites:
            GlassFavoritesOverlay(
                entries: Array(promotedEntries.prefix(12)),
                sceneKeySet: sceneKeySet,
                tileWordClass: tileWordClass,
                onPlay: { entry in engine.speakPromoted(entry) },
                onDismiss: { dismissCompactOverlay() }
            )
            .allowsHitTesting(true)
        }
    }

    private func showCompactOverlay(_ kind: CompactOverlay) {
        withAnimation(.spring(duration: 0.35)) { compactOverlay = kind }
        overlayEpoch &+= 1
    }

    private func dismissCompactOverlay() {
        withAnimation(.easeOut(duration: 0.25)) { compactOverlay = .none }
    }

    #if DEBUG
    @ViewBuilder
    private func gridDebugBadge(spec: GridLayoutSpec, tileCount: Int) -> some View {
        let pages = max(1, Int(ceil(Double(tileCount) / Double(max(1, spec.perPage)))))
        Text("\(spec.cols)×\(spec.rows) · \(spec.perPage)/pg · \(tileCount)t/\(pages)p · \(Int(spec.tileSize))pt")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(6)
            .allowsHitTesting(false)
    }
    #endif

    @ViewBuilder
    private func landscapeTabView(chunks: [[TileEntry]], spec: GridLayoutSpec) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: spec.cols)
        TabView(selection: $currentDisplayPage) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, tiles in
                LazyVGrid(columns: columns, spacing: spec.verticalSpacing) {
                    homeCell(spec: spec)
                    ForEach(tiles, id: \.key) { entry in
                        tileCellView(for: entry, labelFontSize: spec.labelFontSize)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .tag(index as Int?)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .onChange(of: currentDisplayPage) { _, _ in
            haptic.impactOccurred()
        }
    }

    @ViewBuilder
    private func portraitScrollView(chunks: [[TileEntry]], pageHeight: CGFloat, spec: GridLayoutSpec) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: spec.cols)
        ScrollView {
            // VStack (not Lazy) ensures all page frames are committed upfront,
            // giving scrollTargetBehavior(.paging) correct snap offsets and
            // preventing layout artifacts on pages beyond the first.
            VStack(spacing: 0) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { index, tiles in
                    LazyVGrid(columns: columns, spacing: spec.verticalSpacing) {
                        homeCell(spec: spec)
                        ForEach(tiles, id: \.key) { entry in
                            tileCellView(for: entry, labelFontSize: spec.labelFontSize)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                    .frame(height: pageHeight, alignment: .top)
                    .id(index)
                }
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollClipDisabled(false)
        .clipped()
        .scrollPosition(id: $currentDisplayPage)
        .onScrollPhaseChange { old, new in
            if old != .idle && new == .idle {
                haptic.impactOccurred()
            }
        }
    }

    /// Home, at cell 0 of every page. See `HomeGridCell` for why it is in the
    /// grid rather than the tray.
    private func homeCell(spec: GridLayoutSpec) -> some View {
        HomeGridCell(
            isEnabled: coordinator.navigationPath.count > 1 || currentDisplayPage != 0,
            action: {
                coordinator.navigateToRoot()
                currentDisplayPage = 0
            },
            onOpenMenu: { showCaregiverMenu = true },
            labelFontSize: spec.labelFontSize
        )
    }

    @ViewBuilder
    private func tileCellView(for entry: TileEntry, labelFontSize: CGFloat) -> some View {
        if let tile = tileLookup[entry.key] {
            TileView(
                tile: tile,
                link: entry.link,
                isAudible: entry.isAudible,
                isSelected: engine.selectedTiles.contains { $0.key == entry.key },
                labelFontSize: labelFontSize,
                scriptPulseKey: scriptRunner.tapPulseKey,
                scriptPulseCount: scriptRunner.tapPulseCount
            ) {
                lastTappedKey = entry.key
                handleTileTap(entry)
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .onEnded { _ in
                        pendingNote = "\(tile.key) [\(tile.wordClass)]"
                        showNoteAlert = true
                    }
            )
            // Lift the tile that just pulsed (live tap or scripted) above its
            // neighbors so the grow animation draws on top — not half-under the
            // cell to its right.
            .zIndex(lastTappedKey == entry.key || scriptRunner.tapPulseKey == entry.key ? 1 : 0)
        }
    }

    // MARK: - Caregiver menu

    /// Is this device in a child's hands? Patient devices get a deliberately
    /// smaller caregiver menu — see `caregiverMenuContent`.
    private var isPatientDevice: Bool {
        DeviceProfileStore.current(context: modelContext)?.role == .patient
    }

    /// Compact menu shown in the Home-anchored popover.
    ///
    /// ## What appears depends on who is holding the device
    ///
    /// On a **patient** device this shows **Admin only**. The other two entries
    /// are unguarded actions sitting one long-press away from the child whose
    /// device it is: "Switch modes" changes how their board behaves, and
    /// TileScript starts a scripted playback over the top of it. Neither is
    /// something a child should be able to trigger, and neither is urgent enough
    /// for a caregiver to need outside the gate — both are reachable in Admin,
    /// which is exactly what the gate is for.
    ///
    /// On a **caregiver** device all three stay. That device is for authoring,
    /// demoing and testing, its Admin is ungated by default, and flipping modes
    /// quickly is the point of having the shortcut at all.
    private var caregiverMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Caregiver Menu")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            if !isPatientDevice {
                caregiverMenuRow(
                    engine.interactionMode == .singleWord ? "Switch to AI Sentences" : "Switch to Single Words",
                    systemImage: "arrow.left.arrow.right"
                ) {
                    showCaregiverMenu = false
                    toggleInteractionMode()
                }
                Divider()
            }
            caregiverMenuRow("Admin", systemImage: "lock.fill") {
                showCaregiverMenu = false
                caregiverMenu.requested = .admin
            }
            if !isPatientDevice {
                caregiverMenuRow("TileScript", systemImage: "play.rectangle.fill") {
                    showCaregiverMenu = false
                    caregiverMenu.requested = .tileScript
                }
            }
        }
        .frame(minWidth: 240)
        .padding(.bottom, 8)
    }

    private func caregiverMenuRow(_ title: String, systemImage: String,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Flip **this device** to the other interaction mode. Wired to the
    /// "Switch to…" item in the caregiver menu (long-press Home), which only
    /// appears on caregiver devices.
    ///
    /// This writes `DeviceProfile.modeOverrideRaw`, which is device-local and
    /// never syncs, and it deliberately does **not** touch the child's Brown's
    /// Stage: a caregiver flipping modes for one session is describing that
    /// session, not the child's development. `requestMode` clears the override
    /// when the requested mode is what the stage already implies, so flipping
    /// back leaves the device simply following the profile again.
    ///
    /// Until 2026-08-24 this wrote `ChildProfile.interactionMode` — a synced
    /// field — so a situational flip on one iPad rewrote a clinical setting on
    /// every device the child's profile touched. Changing a child's stage is a
    /// deliberate act and lives in Admin → Now.
    private func toggleInteractionMode() {
        let target: InteractionMode =
            engine.interactionMode == .singleWord ? .sentence : .singleWord
        profileResolver.requestMode(target)
        engine.clearSelection()
        engine.clearStrip()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    private func handleTileTap(_ entry: TileEntry) {
        let key = entry.key
        guard let tile = tileLookup[key] else { return }
        // Resolve the symbolic "<home>" link to the active scene's homePageKey
        // at navigation time (Step J). Tiles store "<home>" literally so a
        // runtime change of homePageKey is honored without rebuilding pages.
        let resolvedLink = entry.link == "<home>"
            ? (activeScene?.homePageKey ?? "home")
            : entry.link
        // An "audible nav tile" is a single gesture that both adds a tile to the active group
        // AND navigates. We treat it as such in recordings only when the tile key matches the
        // link key (the conventional case for nav tiles like <drinks isAudible=t/>).
        let isAudibleNavTile = entry.isAudible
            && !resolvedLink.isEmpty
            && resolvedLink == key

        if entry.isAudible {
            // Speak the word on tap. Always in single-word mode (the word IS the
            // communication); in sentence mode only when the preview is enabled.
            if tileSpeechEnabled || engine.interactionMode == .singleWord {
                engine.speakTile(tile.displayName)
            }
            // Universal: a grid tap adds, never deletes. The engine appends to
            // the FIFO strip (single-word, duplicates allowed) or to the active
            // group (sentence, no-op if the tile is already present). Removal is
            // a tray-chip tap.
            engine.addTile(tile)
            if recorder.state == .recording {
                if isAudibleNavTile {
                    recorder.recordAudibleNavigate(pageKey: resolvedLink)
                } else {
                    recorder.recordTap(tileKey: key)
                }
            }
        }
        if !resolvedLink.isEmpty {
            coordinator.navigate(to: resolvedLink)
            if recorder.state == .recording {
                // Skip a separate navigate record if we already recorded an audible-nav for
                // this gesture (it covers both the tile and the navigation).
                if !isAudibleNavTile {
                    recorder.recordNavigate(pageKey: resolvedLink)
                }
            }
        }
    }
}

// MARK: - Promoted Tile Strip

/// Horizontal scroll of promoted chips — shown when expanded from the nav bar.
struct PromotedChipStrip: View {
    let entries: [SentenceCache]
    let sceneKeySet: Set<String>
    let tileWordClass: [String: String]
    let onTap: (SentenceCache) -> Void

    private func isInScene(_ entry: SentenceCache) -> Bool {
        entry.tileKeys.allSatisfy { sceneKeySet.contains($0) }
    }

    private var inScene: [SentenceCache] { entries.filter { isInScene($0) } }
    private var outOfScene: [SentenceCache] { entries.filter { !isInScene($0) } }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(inScene) { entry in
                    PromotedChip(entry: entry, isInScene: true,
                                 tileWordClass: tileWordClass, onTap: onTap)
                }

                if !outOfScene.isEmpty {
                    if !inScene.isEmpty {
                        Rectangle()
                            .fill(.separator)
                            .frame(width: 1, height: 36)
                            .padding(.horizontal, 4)
                    }
                    Text("other")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    ForEach(outOfScene) { entry in
                        PromotedChip(entry: entry, isInScene: false,
                                     tileWordClass: tileWordClass, onTap: onTap)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }
}

private struct PromotedChip: View {
    let entry: SentenceCache
    let isInScene: Bool
    let tileWordClass: [String: String]
    let onTap: (SentenceCache) -> Void

    private let iconSize: CGFloat = 30
    private let cornerRadius: CGFloat = 10

    private var borderColor: Color {
        if entry.isPinned && isInScene { return .orange.opacity(0.7) }
        if isInScene { return .primary.opacity(0.15) }
        return .secondary.opacity(0.25)
    }

    var body: some View {
        Button { onTap(entry) } label: {
            HStack(spacing: 3) {
                ForEach(entry.tileKeys.prefix(4), id: \.self) { key in
                    let wordClass = tileWordClass[key] ?? "default"
                    TileImageView(key: key, wordClass: wordClass)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
            }
            .padding(6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(borderColor, lineWidth: 1.5)
            )
            .opacity(isInScene ? 1 : 0.6)
        }
        .buttonStyle(.plain)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

#Preview {
    TileGridView()
        .previewEnvironment()
}
