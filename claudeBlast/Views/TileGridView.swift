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
import os

private let promotedHitThreshold = 3

struct TileGridView: View {
    @Query(filter: #Predicate<BlasterScene> { $0.isActive })
    var activeScenes: [BlasterScene]
    /// Every scene, for the Caregiver Menu's scene switcher.
    @Query(sort: \BlasterScene.name) private var allScenes: [BlasterScene]
    /// BlasterAI 60, whose pages a `<system>:` link opens from any scene.
    @Query(filter: #Predicate<BlasterScene> { $0.isDefault })
    private var systemScenes: [BlasterScene]

    /// All vocabulary tiles. Used to resolve a TileEntry.key back to the
    /// underlying TileModel for display (image, label, wordClass).
    @Query(sort: \TileModel.key) private var allTiles: [TileModel]


    /// Built over every TileModel, reading a SwiftData property on each — so
    /// build it once per render and pass it down. Each cell used to read this
    /// property itself: 749 tiles × every cell on the board, on every render.
    /// The board stays alive under Admin, so every edit there re-rendered it.
    private var tileLookup: [String: TileModel] {
        let state = PerfSignposts.signposter.beginInterval(
            "board.tileLookup", "\(allTiles.count) tiles")
        defer { PerfSignposts.signposter.endInterval("board.tileLookup", state) }
        return Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    @Environment(SentenceEngine.self) private var engine
    @Environment(NavigationCoordinator.self) private var coordinator
    @Environment(TileScriptRunner.self) private var scriptRunner
    @Environment(TileScriptRecorder.self) private var recorder
    @Environment(ChildProfileResolver.self) private var profileResolver
    @Environment(CaregiverMenuCoordinator.self) private var caregiverMenu
    @Environment(\.modelContext) private var modelContext
    @State private var showCaregiverMenu = false
    /// The caregiver rail's Edit menu, opened off the Edit button.
    @State private var showEditMenu = false
    /// The grid's tiles and the side rail on screen, for the tray to line up
    /// with. Measured on iPad only: the phone's tray is its own design.
    @State private var gridFrame: CGRect = .zero
    @State private var railFrame: CGRect?

    private var railAlignment: RailAlignment? {
        guard !isCompact, gridFrame.width > 0 else { return nil }
        return RailAlignment(grid: gridFrame, rail: railFrame)
    }
    @State private var currentDisplayPage: Int? = 0
    @AppStorage("tile_speech_enabled") private var tileSpeechEnabled: Bool = true
    @State private var haptic = UIImpactFeedbackGenerator(style: .heavy)
    @State private var pendingNote: String = ""
    @State private var showNoteAlert: Bool = false
    /// The tile that most recently fired a press pulse — lifted above its grid
    /// neighbors (via cell zIndex) so the grow animation isn't clipped by the
    /// adjacent cell. LazyVGrid ignores zIndex set inside the cell's subtree, so
    /// it has to live on the cell view itself.
    @State private var lastTappedKey: String?
    /// Navigation keys from the path's first folder to the page showing; see
    /// `WayMark`. Worked out once per page, not once per tile.
    @State private var wayTrail: [String] = []
    @AppStorage(AppSettingsKey.demoMode) private var demoMode = false
    @AppStorage(AppSettingsKey.quickActionsEnabled) private var quickActionsEnabled = true
    @AppStorage(AppSettingsKey.imageSet) private var imageSetRaw: String = ImageSetID.defaultSet.rawValue
    @Environment(TileImageResolver.self) private var imageResolver
    /// A scene switch the menu could not make, or made with a caveat — the same
    /// messages Admin › Scenes shows.
    @State private var sceneNotice: SceneNotice?
    @State private var showFindWord = false
    /// Set by the menu's Find Word row; the sheet opens once the popover is gone.
    @State private var findWordAfterMenu = false
    /// The word Find Word went to. It breathes until any tap on the board.
    @State private var findHighlight: FindHighlight?

    struct FindHighlight: Equatable {
        let key: String
        let pageKey: String
        /// A fresh find of the same word still re-pages the grid to it.
        let token = UUID()
    }

    struct SceneNotice: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// Defaults to what the old density stepper implied, until a layout is
    /// chosen. See `BoardLayout.current`.
    @AppStorage(AppSettingsKey.boardLayout) private var boardLayoutRaw: String =
        BoardLayout.current().rawValue
    @AppStorage(AppSettingsKey.honorSceneLayouts) private var honorSceneLayouts = true
    @AppStorage(AppSettingsKey.tileLook) private var tileLookRaw: String = TileLook.square.rawValue
    private var tileLook: TileLook { TileLook(rawValue: tileLookRaw) ?? .square }
    /// Child mode on a caregiver device. See `RailProfile`.
    @AppStorage(AppSettingsKey.railChildLock) private var railChildLock = false

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var compactOverlay: CompactOverlay = .none
    @State private var overlayEpoch: Int = 0

    private var isCompact: Bool { hSizeClass == .compact }

    /// How a page change animates: not at all.
    ///
    /// It used to be a 0.3s crossfade with a 40pt push. On BlasterAI 60 the
    /// system row, Home and every same-cell word are identical on both pages,
    /// so the fade drew each of them twice, 80pt apart — the board juddered
    /// exactly where it was meant to stand still. Avaz swaps the page
    /// instantly, and so do we. The "you are here" folder marker and the
    /// changed words are the cue that the board moved. Every navigation the
    /// child or the Find sheet triggers goes through this one value, so a
    /// short fade (`.easeOut(duration: 0.12)`) is a one-line experiment.
    static let pageChange: Animation? = nil

    /// The reader's Dynamic Type multiplier, taken from the system rather than
    /// from a hand-written table of category → factor. Reading
    /// `dynamicTypeSize` as well is what makes SwiftUI re-run this when the
    /// setting changes; `UIFontMetrics` alone is a snapshot and would leave the
    /// grid at whatever scale it was built with.
    private var textScale: CGFloat {
        _ = dynamicTypeSize
        return UIFontMetrics.default.scaledValue(for: 100) / 100
    }

    /// Roughly what the compact tray's bubble can show before truncating.
    /// Deliberately a blunt character count: the exact threshold matters far
    /// less than not covering the board for a sentence the caregiver can
    /// already read.
    private static func isTooLongForTray(_ sentence: String) -> Bool {
        sentence.count > 60
    }

    enum CompactOverlay: Equatable {
        case none
        case sentence
    }

    private var activeScene: BlasterScene? { activeScenes.first }
    private var systemScene: BlasterScene? { systemScenes.first }

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
        // The board at its level: words above it draw as concealed cells.
        // A core-board page follows the same dial (`BoardLevels`).
        return SystemLinks.page(forKey: key, scenePages: scene.visiblePages,
                                systemPages: BoardLevels(scene: scene, system: systemScene).systemPages)
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
                railAlignment: railAlignment
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
                isSentenceShown: compactOverlay == .sentence,
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
                isSentenceShown: compactOverlay == .sentence,
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
                },
                railAlignment: railAlignment
            )
            .padding(.top, 8)
    }

    /// The board itself, or an empty state when no scene is active.
    @ViewBuilder
    private var gridContent: some View {
        if let page = currentPage {
            pagedGrid(for: page)
                // Keyed by page, so a page change is an insertion and a removal
                // — which is what gives the transition below something to
                // animate — and so no tile view is ever reused across pages.
                .id(page.key)
                // Only used if `pageChange` is ever an animation: a fade in
                // place, never a push, so unchanged cells cannot draw double.
                .transition(.opacity)
                .overlay(alignment: .top) {
                    compactOverlayContent
                }
        } else {
            noBoardState
        }
    }

    /// The board has nothing to draw — and the only way out is here.
    ///
    /// ## Why this needs its own escape hatch
    ///
    /// Every other route into Admin is a long-press on the Home cell, and the
    /// Home cell lives *inside* the grid. So the one state where the grid cannot
    /// render is exactly the state with no way to reach the settings that would
    /// fix it: activate a scene whose `homePageKey` names no page and the app is
    /// bricked until it is deleted and reinstalled. Reachable purely by
    /// authoring a scene by hand and getting the home page wrong.
    ///
    /// ## Two different nothings
    ///
    /// `currentPage` is nil when there is no active scene at all, and *also*
    /// when a scene is active but its home page does not resolve. The second is
    /// the far likelier one and the old copy — "No scene is currently active" —
    /// stated the opposite of what had happened, sending anyone reading it to
    /// look in the wrong place.
    @ViewBuilder
    private var noBoardState: some View {
        ContentUnavailableView {
            Label(activeScene == nil ? "No Active Scene" : "This Scene Has No Home Page",
                  systemImage: "questionmark.square")
        } description: {
            if let scene = activeScene {
                Text("“\(scene.name)” is active, but its home page (“\(scene.homePageKey)”) does not match any page in it. Set a home page, or activate another scene.")
            } else {
                Text("No scene is currently active. Activate one to show the board.")
            }
        } actions: {
            Button("Open Admin") { caregiverMenu.requested = .admin }
                .buttonStyle(.borderedProminent)
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
        // The caregiver menu opens from a long-press on the rail's Home and is
        // anchored there (`ControlRail`). Admin is gated by AdminGate when
        // ContentView presents it; on a child's rail it is the only entry the
        // menu offers besides unlocking the caregiver's.
        .alert(item: $sceneNotice) { notice in
            Alert(title: Text(notice.title), message: Text(notice.message))
        }
        .onChange(of: showCaregiverMenu) { _, isOpen in
            guard !isOpen, findWordAfterMenu else { return }
            findWordAfterMenu = false
            // A sheet asked for while the popover is still animating away is
            // dropped on iPad; wait it out.
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                showFindWord = true
            }
        }
        .sheet(isPresented: $showFindWord) {
            if let scene = activeScene {
                FindWordSheet(scene: scene, lookup: tileLookup) { finding in
                    go(to: finding, in: scene)
                }
            }
        }
        // Any tap anywhere ends the highlight, and still does what it does —
        // a tap on the found word speaks it. Off when there is nothing to end.
        .simultaneousGesture(
            TapGesture().onEnded { findHighlight = nil },
            including: findHighlight == nil ? .subviews : .all
        )
        .onChange(of: engine.canReplay) { _, isReady in
            guard isCompact else { return }
            // Only auto-present the popover when the tray cannot show the
            // sentence itself.
            //
            // The compact tray already renders the sentence in its bubble, so
            // popping a duplicate over the board hid the top row — including
            // the Home cell, the one control whose whole value is being in the
            // same place every time. A caregiver reads the tray; the popover is
            // for the sentence too long to fit there, and stays available on tap.
            if isReady, engine.activeGroup.sentence.map({ Self.isTooLongForTray($0) }) == true {
                showCompactOverlay(.sentence)
            } else if !isReady, compactOverlay == .sentence {
                dismissCompactOverlay()
            }
        }
        .task(id: overlayEpoch) {
            // Auto-dismiss is NOT compact-only. It used to be, which meant the
            // popover — reachable on iPad by tapping the tray bubble — had no
            // timer, no tap-out, and one small × as its only exit. On an iPad
            // mini in portrait, where the bubble is small enough that a
            // caregiver actually taps it, that stuck.
            guard compactOverlay == .sentence else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                if compactOverlay == .sentence { compactOverlay = .none }
            }
        }
        .task {
            haptic.prepare()
            coordinator.navigationPath = [activeScene?.homePageKey ?? "home"]
            coordinator.onPress = { [engine] from, to, linkKey in
                engine.logNavigation(from: from, to: to, linkKey: linkKey)
            }
        }
        .onChange(of: activeScene?.id) {
            coordinator.navigateHome(homePageKey: activeScene?.homePageKey ?? "home")
            currentDisplayPage = 0
            findHighlight = nil
            engine.clearSelection()
        }
        .onChange(of: activeScene?.pages.map(\.key)) { _, pageNames in
            // If the current page was deleted or renamed, navigate home
            guard let pageNames, let key = coordinator.currentPageKey else { return }
            // A system page belongs to BlasterAI 60, not to this scene.
            if TileToken.systemPageKey(key) == nil, !pageNames.contains(key) {
                coordinator.navigateHome(homePageKey: activeScene?.homePageKey ?? "")
                currentDisplayPage = 0
            }
        }
        .onChange(of: currentPage?.tiles.map(\.key)) { _, _ in
            // Reset display page position when tile count changes significantly
            currentDisplayPage = 0
        }
        .onChange(of: coordinator.currentPageKey) { _, _ in
            // The lift belongs to the tap that caused it, and that tap is over.
            lastTappedKey = nil
            currentDisplayPage = 0
            engine.currentPageKey = identityPageKey
        }
        .onChange(of: identityPageKey, initial: true) { _, key in
            // The board tells the engine where the child is, so a press can be
            // stamped with the page it came from. Pushed rather than pulled:
            // navigation is a view concern, and this is the single fact the
            // engine needs out of it.
            engine.currentPageKey = key
            wayTrail = computeWayTrail()
        }
        .alert("Add Note", isPresented: $showNoteAlert) {
            TextField("Note", text: $pendingNote)
            Button("Add") { engine.appendNote(pendingNote) }
            Button("Cancel", role: .cancel) {}
        }
    }

    /// The path line under the tray: `Home › Actions › Moving`.
    private static let pathLineHeight: CGFloat = 22

    /// Which rail this device shows. See `RailProfile`.
    private var railProfile: RailProfile {
        RailProfile.resolve(role: DeviceProfileStore.current(context: modelContext)?.role,
                            childLock: railChildLock)
    }

    /// A cell's height: the tile, and on the classic look its label beneath.
    private func cellHeight(_ spec: GridLayoutSpec) -> CGFloat {
        tileLook == .square ? spec.tileSize : spec.tileSize + spec.labelHeight
    }

    /// The board: the path line, the system row, the page, and the rail.
    ///
    /// The rail is a column beside the grid in iPad landscape. Turned to
    /// portrait, and on iPhone, the same slots in the same order run along the
    /// bottom. The tile is sized for grid and rail together, so the rail's
    /// slots are tiles too.
    private func pagedGrid(for page: PageSpec) -> some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            let isPhone = GridLayoutCalculator.isPhone(screenSize: GridLayoutCalculator.deviceScreenSize)
            let rail: RailPlacement = !isPhone && isLandscape
                ? .side
                : .bottom(slots: railProfile.slots.count, pairs: railProfile.hasPairs)
            let spec = GridLayoutCalculator.compute(
                screenSize: GridLayoutCalculator.deviceScreenSize,
                geo: CGSize(width: geo.size.width, height: geo.size.height - Self.pathLineHeight),
                // The scene's declared grid on a matching device, else this
                // device's own. See `GridLayoutCalculator.liveLayout`.
                layout: GridLayoutCalculator.liveLayout(
                    designed: activeScene?.designedLayout,
                    isPhone: isPhone,
                    deviceLayout: BoardLayout(rawValue: boardLayoutRaw) ?? .standard,
                    honorSceneLayouts: honorSceneLayouts),
                textScale: textScale,
                look: tileLook,
                rail: rail
            )
            // Retired (hidden) and unreviewed (moderation-flagged) tiles never
            // render for the child — both stay invisible in running scenes until
            // the caregiver resolves them. A missing tile stays a no-op as before.
            let lookup = tileLookup
            // Row 1 is the system row on a scene that inherits it, the same on
            // every screen of every page; the rest of the grid is the page.
            let inherits = activeScene.map(BoardChrome.inherits) ?? false
            let contentRows = inherits ? max(1, spec.rows - 1) : spec.rows
            let perScreen = max(1, spec.cols * contentRows)
            // Nothing is filtered out: a hidden word, a concealed placement and
            // a spacer all keep their cell and draw empty. Removing any of them
            // would reflow the board and move every word the child had learned.
            let visible = TileEntry.holdingHiddenCells(page.tiles) {
                lookup[$0]?.isHiddenFromChild == true
            }
            // Always at least one chunk, so an empty page still draws a board
            // with its rail — the rail's Home is the way into Admin.
            let chunkedTiles = visible.isEmpty ? [[]] : visible.chunked(into: perScreen)
            let cellH = cellHeight(spec)
            let contentHeight = CGFloat(contentRows) * cellH + CGFloat(contentRows - 1) * spec.verticalSpacing
            let isSide = rail == .side
            let gridPadding = isSide ? 0 : spec.horizontalPadding
            let gridWidth = CGFloat(spec.cols) * spec.tileSize + CGFloat(spec.cols - 1) * spec.horizontalSpacing
            let board = VStack(spacing: spec.verticalSpacing) {
                if inherits, let scene = activeScene {
                    chromeRow(BoardChrome.row(for: scene, level: chromeLevel(scene)),
                              spec: spec, lookup: lookup, padding: gridPadding)
                }
                Group {
                    if isLandscape {
                        landscapeTabView(chunks: chunkedTiles, spec: spec, lookup: lookup, padding: gridPadding)
                    } else {
                        portraitScrollView(chunks: chunkedTiles, pageHeight: contentHeight, spec: spec,
                                           lookup: lookup, padding: gridPadding)
                    }
                }
                .frame(height: contentHeight)
            }
            VStack(alignment: .leading, spacing: 0) {
                // On the grid's first column, with the tray's first chip.
                pathLine
                    .frame(height: Self.pathLineHeight)
                    .padding(.horizontal, isSide ? 16 : max(16, gridPadding))
                if isSide {
                    HStack(alignment: .top, spacing: 0) {
                        board.frame(width: gridWidth)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }
                                action: { gridFrame = $0 }
                        // Spare width goes to the rail, as wider buttons,
                        // rather than to margins or a gap: an iPad mini's tiles
                        // are bound by its height, and centring its narrower
                        // grid left a band down each edge; a wide gap instead
                        // left one in the middle (Mark 2026-10-27).
                        Spacer(minLength: GridLayoutCalculator.railGap)
                            .frame(maxWidth: GridLayoutCalculator.railGap)
                        controlRail(spec: spec, cellHeight: cellH, vertical: true,
                                    width: max(spec.tileSize,
                                               geo.size.width - 32 - gridWidth - GridLayoutCalculator.railGap))
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) }
                                action: { railFrame = $0 }
                    }
                    .padding(.horizontal, 16)
                } else {
                    board
                        .onGeometryChange(for: CGRect.self) {
                            $0.frame(in: .global).insetBy(dx: gridPadding, dy: 0)
                        } action: { gridFrame = $0 }
                    Spacer(minLength: GridLayoutCalculator.railGap)
                    controlRail(spec: spec, cellHeight: cellH, vertical: false)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 4)
                        // Not on disappear of the side rail: every page change
                        // rebuilds the board, and the old one leaves after the
                        // new one has measured.
                        .onAppear { railFrame = nil }
                }
            }
            .onChange(of: isLandscape) { _, _ in
                currentDisplayPage = 0
            }
            // Find Word: page to the screen holding the found word. A task, not
            // an onChange, so it runs after navigation has reset the grid to
            // its first screen rather than racing it.
            .task(id: findHighlight?.token) {
                guard let target = findHighlight, target.pageKey == page.key,
                      let idx = visible.firstIndex(where: { $0.key == target.key }) else { return }
                let chunk = idx / perScreen
                if currentDisplayPage != chunk {
                    withAnimation { currentDisplayPage = chunk }
                }
            }
            .onChange(of: scriptRunner.tapPulseKey) { _, key in
                // During TileScript playback, page the grid to the display-chunk that
                // holds the just-tapped tile so the tap is visible even when it's off
                // the current page. (The script navigates to the tile's board page
                // first, so the tile is always somewhere on `page`.)
                guard let key,
                      let idx = page.tiles.firstIndex(where: { $0.key == key }) else { return }
                let chunk = idx / perScreen
                if currentDisplayPage != chunk {
                    withAnimation { currentDisplayPage = chunk }
                }
            }
        }
    }

    /// The level the system row shows at: the board's own on BlasterAI 60,
    /// else the dial applied to the core board, as its pages are.
    private func chromeLevel(_ scene: BlasterScene) -> Int? {
        if scene.isDefault { return scene.effectiveRevealLevel }
        return BoardLevels.clamp(BoardLevels(scene: scene, system: systemScene).level,
                                 to: systemScene?.revealLevelCount ?? 0)
    }

    /// Row 1: the system folders. On a grid narrower than the row (Large,
    /// Largest, iPhone) it scrolls sideways rather than wrapping onto the page.
    @ViewBuilder
    private func chromeRow(_ row: [TileEntry], spec: GridLayoutSpec,
                           lookup: [String: TileModel], padding: CGFloat) -> some View {
        let cells = HStack(spacing: spec.horizontalSpacing) {
            ForEach(row, id: \.key) { entry in
                tileCellView(for: entry, labelFontSize: spec.labelFontSize, lookup: lookup)
                    .frame(width: spec.tileSize, height: cellHeight(spec))
            }
        }
        if row.count > spec.cols {
            ScrollView(.horizontal, showsIndicators: false) {
                cells.padding(.horizontal, padding)
            }
            .frame(height: cellHeight(spec))
        } else {
            cells
                .padding(.horizontal, padding)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        }
    }

    private func showCompactOverlay(_ kind: CompactOverlay) {
        withAnimation(.spring(duration: 0.35)) { compactOverlay = kind }
        overlayEpoch &+= 1
    }

    private func dismissCompactOverlay() {
        withAnimation(.easeOut(duration: 0.25)) { compactOverlay = .none }
    }

    /// Where the child is in the hierarchy: `Home › Describe › How much`.
    /// It reads left to right under the tray, aligned with the grid.
    @ViewBuilder
    private var pathLine: some View {
        if let scene = activeScene {
            let key = coordinator.currentPageKey ?? scene.homePageKey
            let trail: [String] = {
                if let systemKey = TileToken.systemPageKey(key), let system = systemScene {
                    let pages = BoardLevels(scene: scene, system: system).systemPages
                    return WordPlaces.trail(to: systemKey, pages: pages, homeKey: system.homePageKey,
                                            row: BoardChrome.rowPages(of: system))
                }
                return WordPlaces.trail(to: key, pages: scene.visiblePages, homeKey: scene.homePageKey,
                                        row: BoardChrome.rowPages(of: scene))
            }()
            Text(trail.joined(separator: "  ›  "))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)
                .allowsHitTesting(false)
                .accessibilityLabel("You are on " + (trail.last ?? "Home"))
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func landscapeTabView(chunks: [[TileEntry]], spec: GridLayoutSpec,
                                  lookup: [String: TileModel], padding: CGFloat) -> some View {
        // Fixed at the computed tile size, not flexible. At Auto the two are the
        // same width; at a row-stepped density the tile is sized by the height,
        // and flexible columns would stretch it back to fill the width — making
        // it taller than the rows it was sized for. The width a whole column
        // cannot use becomes a margin either side. See `GridLayoutCalculator`.
        let columns = Array(repeating: GridItem(.fixed(spec.tileSize), spacing: spec.horizontalSpacing),
                            count: spec.cols)
        TabView(selection: $currentDisplayPage) {
            ForEach(Array(chunks.enumerated()), id: \.offset) { index, tiles in
                LazyVGrid(columns: columns, spacing: spec.verticalSpacing) {
                    ForEach(tiles, id: \.key) { entry in
                        tileCellView(for: entry, labelFontSize: spec.labelFontSize, lookup: lookup)
                    }
                }
                .padding(.horizontal, padding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .tag(index as Int?)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .onChange(of: currentDisplayPage) { _, _ in
            haptic.impactOccurred()
        }
    }

    @ViewBuilder
    private func portraitScrollView(chunks: [[TileEntry]], pageHeight: CGFloat, spec: GridLayoutSpec,
                                    lookup: [String: TileModel], padding: CGFloat) -> some View {
        // Fixed at the computed tile size, not flexible. At Auto the two are the
        // same width; at a row-stepped density the tile is sized by the height,
        // and flexible columns would stretch it back to fill the width — making
        // it taller than the rows it was sized for. The width a whole column
        // cannot use becomes a margin either side. See `GridLayoutCalculator`.
        let columns = Array(repeating: GridItem(.fixed(spec.tileSize), spacing: spec.horizontalSpacing),
                            count: spec.cols)
        ScrollView {
            // VStack (not Lazy) ensures all page frames are committed upfront,
            // giving scrollTargetBehavior(.paging) correct snap offsets and
            // preventing layout artifacts on pages beyond the first.
            VStack(spacing: 0) {
                ForEach(Array(chunks.enumerated()), id: \.offset) { index, tiles in
                    LazyVGrid(columns: columns, spacing: spec.verticalSpacing) {
                        ForEach(tiles, id: \.key) { entry in
                            tileCellView(for: entry, labelFontSize: spec.labelFontSize, lookup: lookup)
                        }
                    }
                    .padding(.horizontal, padding)
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

    // MARK: - Rail

    /// - Parameter width: the side rail's width, when the grid leaves it more
    ///   than a tile.
    private func controlRail(spec: GridLayoutSpec, cellHeight: CGFloat, vertical: Bool,
                             width: CGFloat? = nil) -> some View {
        let slots = railProfile.slots
        var size = vertical
            ? GridLayoutCalculator.sideRailSlot(spec, slots: slots.count, cellHeight: cellHeight)
            : CGSize(width: spec.railSlotWidth, height: spec.railSlot)
        if vertical, let width { size.width = width }
        return ControlRail(slots: slots, slot: size,
                           spacing: vertical ? spec.verticalSpacing : TileLayout.gap,
                           vertical: vertical,
                           isEnabled: isRailEnabled, action: railAction,
                           isMenuOpen: $showCaregiverMenu,
                           menu: { caregiverMenuContent },
                           isEditMenuOpen: $showEditMenu,
                           editMenu: { editMenuContent },
                           level: railLevel)
    }

    private func isRailEnabled(_ item: RailItem) -> Bool {
        switch item {
        case .home: coordinator.navigationPath.count > 1 || currentDisplayPage != 0
        case .back: coordinator.canGoBack
        // Mounting topic scenes comes with the scene editor work.
        case .topics: false
        case .keyboard, .search: activeScene != nil
        case .edit: activeScene != nil
        case .levels, .childMode: true
        }
    }

    private func railAction(_ item: RailItem) {
        switch item {
        case .home:
            guard isRailEnabled(.home) else { return }
            withAnimation(Self.pageChange) { coordinator.navigateToRoot() }
            currentDisplayPage = 0
        case .back:
            withAnimation(Self.pageChange) { coordinator.goBack() }
            currentDisplayPage = 0
            // Recorded as `<back>`, which the runner replays as a Back.
            if recorder.state == .recording {
                recorder.recordNavigate(pageKey: NavigationCoordinator.backPageKey)
            }
        case .keyboard:
            let key = activeScene?.isDefault == true ? Self.keyboardPage
                                                     : TileToken.systemLink(to: Self.keyboardPage)
            withAnimation(Self.pageChange) { coordinator.navigate(to: key, linkKey: Self.keyboardPage) }
            if recorder.state == .recording { recorder.recordNavigate(pageKey: key) }
        case .search:
            showFindWord = true
        case .edit:
            showEditMenu = true
        case .childMode:
            railChildLock = true
        case .topics, .levels:
            break
        }
    }

    private static var keyboardPage: String { BoardChrome.keyboardPage }

    /// The page Edit would open: one of the active scene's own. BlasterAI 60's
    /// pages are the system's and cannot be edited.
    private var editablePageKey: String? {
        guard let scene = activeScene, !scene.isDefault,
              TileToken.systemPageKey(identityPageKey) == nil,
              scene.page(withKey: identityPageKey) != nil else { return nil }
        return identityPageKey
    }

    /// The level dial, inline on the caregiver rail; nil when neither board
    /// has levels.
    private var railLevel: RailLevel? {
        guard let scene = activeScene else { return nil }
        let levels = BoardLevels(scene: scene, system: systemScene)
        guard levels.count > 0, let level = levels.level else { return nil }
        return RailLevel(level: level, count: levels.count) { next in
            levels.setLevel(next)
            try? modelContext.save()
        }
    }

    /// Page a tile is rendered on, used to scope its identity. Falls back the
    /// same way `currentPage` does so the two cannot disagree.
    private var identityPageKey: String {
        coordinator.currentPageKey ?? activeScene?.homePageKey ?? "home"
    }

    /// The hierarchy route to the page showing, as navigation keys, so a
    /// scene's `<system>:describe` matches BlasterAI 60's Describe.
    private func computeWayTrail() -> [String] {
        guard let scene = activeScene else { return [] }
        let key = identityPageKey
        if let systemKey = TileToken.systemPageKey(key) {
            guard let system = systemScene else { return [key] }
            let pages = BoardLevels(scene: scene, system: system).systemPages
            return WordPlaces.trailKeys(to: systemKey, pages: pages, homeKey: system.homePageKey,
                                        row: BoardChrome.rowPages(of: system))
                .map(TileToken.systemLink(to:))
        }
        return WordPlaces.trailKeys(to: key, pages: scene.visiblePages, homeKey: scene.homePageKey,
                                    row: BoardChrome.rowPages(of: scene))
    }

    /// Where a tap on `entry` would go, from the page showing.
    private func destination(of entry: TileEntry) -> String {
        entry.link.isEmpty ? "" : SystemLinks.destination(
            of: entry.link, fromPage: identityPageKey,
            homePageKey: activeScene?.homePageKey ?? "home",
            systemHomePageKey: systemScene?.homePageKey)
    }

    private func wayMark(for entry: TileEntry) -> WayMark? {
        guard !entry.link.isEmpty, !entry.isAudible else { return nil }
        let to = destination(of: entry)
        if to == identityPageKey && wayTrail.last == to { return .here }
        return wayTrail.dropLast().contains(to) ? .onTheWay : nil
    }

    @ViewBuilder
    private func tileCellView(for entry: TileEntry, labelFontSize: CGFloat,
                              lookup: [String: TileModel]) -> some View {
        if entry.isEmptyCell {
            // A concealed word and a spacer look identical to the child, and
            // should: both are "nothing is here". They differ only in what the
            // caregiver sees in the editor and in what the coverage report
            // counts — a concealed word is on the board but unavailable, and a
            // spacer was never a word at all.
            //
            // It keeps its full cell. That is the whole feature: the board does
            // not reflow, so every other word stays exactly where the child
            // learned it.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)
        } else if let tile = lookup[entry.key] {
            TileView(
                tile: tile,
                link: entry.link,
                linkColor: entry.linkColor,
                isAudible: entry.isAudible,
                labelFontSize: labelFontSize,
                scriptPulseKey: scriptRunner.tapPulseKey,
                scriptPulseCount: scriptRunner.tapPulseCount,
                isHighlighted: isFindTarget(entry),
                wayMark: wayMark(for: entry)
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
            .zIndex(lastTappedKey == entry.key || scriptRunner.tapPulseKey == entry.key
                    || isFindTarget(entry) ? 1 : 0)
            // Identity is scoped to the page, not just the tile key.
            //
            // `ForEach(tiles, id: \.key)` alone made a tile the *same view* on
            // every page it appeared on, so its `@State` survived navigation —
            // including a press animation still in flight. Tapping a link then
            // finished the bounce on the destination page, on the tile that
            // happens to share the link's key.
            //
            // That is not a rare coincidence: pages are built by wordClass
            // expansion, and a link tile is keyed for the class it opens, so
            // `people`, `social`, `actions`, `describe`, `drinks`, `places` and
            // `weather` all land on a page containing a tile of their own name.
            // Seven of the home board's links reproduce it.
            .id("\(identityPageKey)/\(entry.key)")
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
    /// On a **patient** device this shows **Admin only**. "Switch modes" is an
    /// unguarded action sitting one long-press away from the child whose device
    /// it is — it changes how their board behaves — and it is not urgent enough
    /// for a caregiver to need outside the gate, since Admin reaches it anyway.
    ///
    /// On a **caregiver** device the quick actions stay: mode, level, Find
    /// Word, scene and tile style. That device is for authoring, demoing and testing, its Admin
    /// is ungated by default, and changing these quickly is the point of having
    /// the shortcut at all. One device setting, Admin › Device › "Caregiver
    /// Menu Quick Actions", turns them all off together (on by default).
    ///
    /// TileScript used to be a third entry and is not any more — see the note at
    /// its former call site below.
    private var caregiverMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Caregiver Menu")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            if showsQuickActions {
                // Only the switch *into* sentences is gated.
                //
                // Leaving sentence mode never needs anything, but entering it on
                // a device with no usable key was a dead button: the tap set the
                // override, `interactionMode` overrode it straight back to
                // single-word, and nothing on screen changed or explained why.
                // Disabled and saying so beats enabled and inert.
                if engine.interactionMode == .singleWord && !engine.canGenerateSentences {
                    caregiverMenuRow("AI Sentences need a key",
                                     systemImage: "key.slash",
                                     enabled: false) { }
                } else {
                    caregiverMenuRow(
                        engine.interactionMode == .singleWord ? "Switch to AI Sentences" : "Switch to Single Words",
                        systemImage: "arrow.left.arrow.right"
                    ) {
                        showCaregiverMenu = false
                        toggleInteractionMode()
                    }
                }
                Divider()
                // The level dial stays open after a step on purpose: the board
                // redraws under the popover, which is how a caregiver finds the
                // level that fits — step, look, step again.
                if let scene = activeScene, BoardLevels(scene: scene, system: systemScene).count > 0 {
                    RevealLevelControl(scene: scene, compact: true)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    Divider()
                }
                if activeScene != nil {
                    caregiverMenuRow("Find Word", systemImage: "magnifyingglass") {
                        findWordAfterMenu = true
                        showCaregiverMenu = false
                    }
                    Divider()
                }
                if allScenes.count > 1 {
                    sceneSwitcher
                    Divider()
                }
                tileStyleSwitcher
                Divider()
            }
            // TileScript is deliberately NOT here. It lives in Admin ->
            // Device -> TileScript, which is one door instead of two and is the
            // path that actually works: reached from this menu the runner is
            // presented outside the hierarchy that owns `TileScriptRunner`, so
            // it trapped on a missing environment object every time.
            //
            // Keeping the broken second route and injecting the environment into
            // it was the other option. One gated door to a developer tool is
            // worth more than two.
            // Child mode on a caregiver device: the way back to the caregiver's
            // rail, behind the same gate as Admin.
            if railChildLock && !isPatientDevice {
                caregiverMenuRow("Caregiver Controls", systemImage: "lock.open.fill") {
                    showCaregiverMenu = false
                    caregiverMenu.requested = .unlockCaregiverRail
                }
                Divider()
            }
            caregiverMenuRow("Admin", systemImage: "lock.fill") {
                showCaregiverMenu = false
                caregiverMenu.requested = .admin
            }
        }
        // Wide enough for a name and its value side by side. The popover sizes
        // to its content, so without a floor it changed width with the tile
        // style's name and squeezed the rows on a phone.
        .frame(minWidth: 320)
        .padding(.bottom, 8)
    }

    /// The quick actions are the caregiver's: not on a patient device, and not
    /// on a caregiver device in Child mode.
    /// The caregiver rail's Edit menu: what changes how this board looks and
    /// behaves, in one place, beside the button.
    private var editMenuContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Edit")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)
            if allScenes.count > 1 {
                sceneSwitcher
                Divider()
            }
            tileStyleSwitcher
            Divider()
            trayModeSwitcher
            Divider()
            caregiverMenuRow("Edit This Page", systemImage: "square.and.pencil",
                             enabled: editablePageKey != nil) {
                showEditMenu = false
                if let key = editablePageKey { caregiverMenu.requested = .editPage(key) }
            }
            Divider()
            caregiverMenuRow("Edit This Scene", systemImage: "square.grid.3x3",
                             enabled: activeScene.map { !$0.isDefault } ?? false) {
                showEditMenu = false
                caregiverMenu.requested = .editScene
            }
            Divider()
            caregiverMenuRow("Settings", systemImage: "gearshape") {
                showEditMenu = false
                caregiverMenu.requested = .admin
            }
        }
        .frame(minWidth: 320)
        .padding(.bottom, 8)
    }

    /// Single words or AI sentences, and whether the tray's chips carry their
    /// pictures, for this device. Pictures follow the child's stage unless a
    /// caregiver picks otherwise (`TrayPictures`).
    private var trayModeSwitcher: some View {
        Menu {
            Button {
                if engine.interactionMode != .singleWord { toggleInteractionMode() }
            } label: {
                if engine.interactionMode == .singleWord {
                    Label("Single Words", systemImage: "checkmark")
                } else {
                    Text("Single Words")
                }
            }
            Button {
                if engine.interactionMode != .sentence { toggleInteractionMode() }
            } label: {
                if engine.interactionMode == .sentence {
                    Label("AI Sentences", systemImage: "checkmark")
                } else {
                    Text(engine.canGenerateSentences ? "AI Sentences" : "AI Sentences (needs a key)")
                }
            }
            .disabled(engine.interactionMode == .singleWord && !engine.canGenerateSentences)
            Section("Tray chips") {
                ForEach(TrayPictures.allCases) { option in
                    Button {
                        engine.trayPictures = option
                    } label: {
                        let title = option == .auto
                            ? "\(option.title) (\(profileResolver.brownsStage.label))" : option.title
                        if engine.trayPictures == option {
                            Label(title, systemImage: "checkmark")
                        } else {
                            Text(title)
                        }
                    }
                }
            }
        } label: {
            menuLabel("Tray", value: engine.interactionMode == .singleWord ? "Single Words" : "AI Sentences",
                      systemImage: "text.bubble")
        }
    }

    private var showsQuickActions: Bool { quickActionsEnabled && railProfile == .caregiver }

    private func isFindTarget(_ entry: TileEntry) -> Bool {
        findHighlight?.key == entry.key && findHighlight?.pageKey == identityPageKey
    }

    /// Open the folders from home to the found word's page, as though tapped,
    /// and mark the word. See `NavigationCoordinator.show(path:homePageKey:)`.
    private func go(to finding: WordFinder.Finding, in scene: BlasterScene) {
        withAnimation(Self.pageChange) {
            coordinator.show(path: finding.path, homePageKey: scene.homePageKey)
        }
        findHighlight = FindHighlight(key: finding.key, pageKey: finding.pageKey)
    }

    /// The scenes, the active one checked. Picking one closes the menu: the
    /// board goes to the new scene's Home, so there is nothing left to compare.
    private var sceneSwitcher: some View {
        Menu {
            ForEach(allScenes) { scene in
                Button {
                    // Shared by the caregiver menu and the Edit menu.
                    showCaregiverMenu = false
                    showEditMenu = false
                    switchScene(to: scene)
                } label: {
                    if scene.isActive {
                        Label(scene.name, systemImage: "checkmark")
                    } else {
                        Text(scene.name)
                    }
                }
            }
        } label: {
            menuLabel("Scene", value: activeScene?.name ?? "None",
                      systemImage: "square.grid.3x3")
        }
    }

    /// Device-local, as in Admin › Device. The menu stays open after a pick,
    /// like the level control: the board redraws underneath, so a caregiver
    /// can try a style and look before choosing another.
    private var tileStyleSwitcher: some View {
        Menu {
            ForEach(ImageSetCatalog.selectable) { set in
                Button {
                    setTileStyle(set.id)
                } label: {
                    let name = set.isShippable ? set.displayName : "\(set.displayName) (incomplete)"
                    if set.id == imageResolver.activeSet {
                        Label(name, systemImage: "checkmark")
                    } else {
                        Text(name)
                    }
                }
            }
        } label: {
            menuLabel("Tile Style", value: ImageSetCatalog.displayName(for: imageResolver.activeSet),
                      systemImage: "paintpalette")
        }
    }

    /// A menu row that names its setting and shows the current value, styled to
    /// match `caregiverMenuRow`.
    private func menuLabel(_ title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            // The setting's name never truncates; a long value does. "Tile
            // St…" beside a full "Playful 3D" was the wrong way round.
            Label(title, systemImage: systemImage)
                .fixedSize()
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.body)
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// The same activation Admin › Scenes uses, and the same messages: a scene
    /// that can't be the board is refused before anything changes.
    private func switchScene(to scene: BlasterScene) {
        guard !scene.isActive else { return }
        do {
            let outcome = try scene.activate(context: modelContext)
            try? modelContext.save()
            if let message = outcome.message {
                sceneNotice = SceneNotice(title: "Scene Activated", message: message)
            }
        } catch {
            sceneNotice = SceneNotice(title: "Can't Use This Scene",
                                      message: error.localizedDescription)
        }
    }

    /// Both halves, as onboarding learned: the stored preference, and the live
    /// resolver, which reads the preference only at launch.
    private func setTileStyle(_ id: ImageSetID) {
        let resolved = ImageSetID.resolved(id.rawValue)
        imageSetRaw = resolved.rawValue
        imageResolver.activeSet = resolved
    }

    private func caregiverMenuRow(_ title: String, systemImage: String,
                                  enabled: Bool = true,
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
        .disabled(!enabled)
        .foregroundStyle(enabled ? Color.primary : Color.secondary)
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
        // A folder on a system page stays in the system scene.
        let resolvedLink = destination(of: entry)
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
                engine.speakTile(tile.displayName, key: tile.key)
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
            withAnimation(Self.pageChange) {
                coordinator.navigate(to: resolvedLink, linkKey: key)
            }
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

extension Array {
    /// Consecutive runs of `size`. The board pages with it, and so do the scene
    /// preview and the page editor, which have to break pages where it does.
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

#Preview {
    TileGridView()
        .previewEnvironment()
}
