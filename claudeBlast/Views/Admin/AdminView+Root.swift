// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+Root.swift
//  claudeBlast
//
//  Settings' first screen: eight plain rows, in the order a caregiver thinks
//  about the app — who is talking, which board, what the message box does, how
//  it looks and sounds, then the things they manage, then AI and Advanced.
//  Session 19, round 3 (Mark's mock, after Avaz): short pages, values on the
//  right, small choices inline, no icons, no paragraphs under rows. On iPad the
//  list sits beside the page it opens, which starts on the current profile and
//  a few quick settings; on iPhone the quick settings sit above the list.
//

import SwiftUI
import SwiftData

/// A page in Settings. The first ten are the rows of the first screen; the
/// rest are reached from one of them.
enum AdminPage: Hashable {
    case profile, currentBoard, messageBox, lookSoundFeel
    case boardsAndVocabulary, activity, ai, advanced, help, about
    case profiles, vocabulary, lockRole, aboutDetails, tileScript
    /// A profile's page, and the pages under it, by profile id: the current
    /// profile is `.profile`, any other is reached from All Profiles.
    case profileDetail(String), stage(String), profileAI(String), voice(String), colors(String), meTopics(String)

    /// The profile a page is about, if it is about one.
    var profileID: String? {
        switch self {
        case .profileDetail(let id), .stage(let id), .profileAI(let id), .voice(let id),
             .colors(let id), .meTopics(let id): return id
        default: return nil
        }
    }
}

extension AdminView {

    // MARK: - Layout

    /// The list beside its page. Collapses to one column on iPhone, where a
    /// row pushes its page as usual.
    var settingsSplit: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            rootList
                .toolbar { adminDoneToolbar }
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 400)
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if let selection {
                        page(selection)
                    } else {
                        overviewPage
                    }
                }
                .navigationDestination(for: AdminPage.self) { page($0) }
                // Where a board opens after it is made or chosen for editing.
                .navigationDestination(item: $navigateToNewScene) { scene in
                    SceneEditorView(scene: scene)
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// Choosing a row starts its page fresh.
    var selectionBinding: Binding<AdminPage?> {
        Binding(get: { selection }, set: { selection = $0; path = [] })
    }

    // MARK: - First screen

    var rootList: some View {
        List(selection: selectionBinding) {
            Section {
                statusHeader
            }
            // No Quick Settings on a phone: the board's Tools menu already
            // has them, and a narrow screen cannot fit them on a row.
            Section {
                // No names here: the overview beside the list already says
                // whose profile and which board, and a board name only fits
                // truncated.
                rootRow(.profile, "Profile")
                rootRow(.currentBoard, "Current Board")
                rootRow(.messageBox, "Message Box")
                rootRow(.lookSoundFeel, "Look, Sound, Feel")
                rootRow(.boardsAndVocabulary, "Boards and Vocabulary")
                rootRow(.activity, "Activity")
                rootRow(.ai, "AI", value: sentenceEngine.hasAIConsent ? "On" : "Off")
                rootRow(.help, "Help")
                rootRow(.about, "About")
                rootRow(.advanced, "Advanced")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Settings")
    }

    /// One line, always: a long value (a board's name) truncates rather than
    /// wrapping under its label.
    func rootRow(_ page: AdminPage, _ title: String, value: String? = nil) -> some View {
        NavigationLink(value: page) {
            HStack(spacing: 12) {
                Text(title).layoutPriority(1)
                Spacer(minLength: 0)
                if let value {
                    Text(value)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Status header

    /// The version and the facts a caregiver (or we, on a support call) want
    /// without digging. AI and Lock open their pages; anywhere else on it goes
    /// back to the overview, since a row once chosen stays chosen.
    var statusHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("BlasterAI").font(.subheadline.weight(.semibold))
                Text(AppVersion.display)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text(vocabularySummary)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                statusChip("AI", on: sentenceEngine.hasAIConsent) { show([.ai]) }
                statusChip("Lock", on: deviceProfiles.first?.requireFaceIDForAdmin ?? false) {
                    show([.advanced, .lockRole])
                }
                statusChip("iCloud", on: iCloudSyncOn, action: nil)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { selectionBinding.wrappedValue = nil }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows the current profile and quick settings")
        .listRowBackground(Color.clear)
    }

    var vocabularySummary: String {
        let words = allTiles.filter { !$0.isStructuralChrome }.count
        let boards = switchableScenes.count
        let profiles = childProfiles.count
        return "\(words.formatted()) words · \(boards) board\(boards == 1 ? "" : "s") · "
            + "\(profiles) profile\(profiles == 1 ? "" : "s")"
    }

    /// The setting the store was opened with at launch (on by default in
    /// Release; DEBUG has a switch, which takes effect on the next launch).
    var iCloudSyncOn: Bool {
        UserDefaults.standard.bool(forKey: AppSettingsKey.icloudEnabled)
    }

    @ViewBuilder
    func statusChip(_ name: String, on: Bool, action: (() -> Void)?) -> some View {
        let chip = Text("\(name) \(on ? "on" : "off")")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(on ? Color.green : Color.secondary)
            .overlay(Capsule().strokeBorder(on ? Color.green.opacity(0.6) : Color.secondary.opacity(0.4)))
        if let action {
            Button(action: action) { chip }.buttonStyle(.plain)
        } else {
            chip
        }
    }

    /// Open a page as though its row, then its sub-rows, had been tapped.
    func show(_ pages: [AdminPage]) {
        selection = pages.first
        path = Array(pages.dropFirst())
    }

    // MARK: - Overview (iPad, nothing chosen yet)

    var overviewPage: some View {
        List {
            if let active = currentProfile {
                Section {
                    Button { selectionBinding.wrappedValue = .profile } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            ProfileNameLabel(profile: active, size: 44, font: .title2.weight(.semibold))
                            Text("\(active.brownsStage.label) · \(voiceDisplayName(for: active.voiceIdentifier))")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Current Profile")
                }
            }
            quickSettingsSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// What the board is doing right now on this device — the controls the
    /// board's Tools menu offers, also on their own pages. None of these
    /// belong to the profile: switching profiles leaves them as they are.
    var quickSettingsSection: some View {
        Section("Quick Settings") {
            Picker("Board", selection: Binding(
                get: { activeScene?.sceneID ?? "" },
                set: { id in
                    if let scene = switchableScenes.first(where: { $0.sceneID == id }) {
                        activateScene(scene)
                    }
                })) {
                ForEach(switchableScenes) { scene in
                    Text(scene.name).tag(scene.sceneID)
                }
            }
            if activeSceneHasLevels, let active = activeScene {
                LabeledContent("Level") {
                    RevealLevelControl(scene: active, compact: true)
                }
            }
            Picker("Tile Style", selection: $imageSetRaw) {
                ForEach(ImageSetCatalog.selectable) { set in
                    Text(set.displayName).tag(set.id.rawValue)
                }
            }
            messageModeRow
            picturesRow
            Toggle("Sound", isOn: $audioEnabled)
        }
    }

    // MARK: - Pages

    @ViewBuilder
    func page(_ page: AdminPage) -> some View {
        switch page {
        case .profile:
            if let active = currentProfile { profilePage(active, showsRoster: true) }
        case .profileDetail(let id):
            if let p = profile(id) { profilePage(p, showsRoster: false) }
        case .stage(let id):
            if let p = profile(id) { ProfileStagePage(profile: p) }
        case .profileAI(let id):
            if let p = profile(id) { ProfileAIPage(profile: p) { show([.ai]) } }
        case .voice(let id):
            if let p = profile(id) { ProfileVoicePage(profile: p) }
        case .colors(let id):
            if let p = profile(id) { ProfileColorsPage(profile: p) }
        case .meTopics(let id):
            if let p = profile(id) { ProfileMePage(profile: p) }
        case .currentBoard:        currentBoardPage
        case .messageBox:          messageBoxPage
        case .lookSoundFeel:       lookSoundFeelPage
        case .boardsAndVocabulary: boardsPage
        case .activity:            activityPage
        case .ai:                  aiKeyPage
        case .advanced:            advancedPage
        case .profiles:            talkersPage
        case .vocabulary:          VocabManagerView()
        case .lockRole:            lockRolePage
        case .help:                HelpView()
        case .about:               aboutPage
        case .aboutDetails:        AboutStatsView()
        case .tileScript:          TileScriptView(embedded: true)
        }
    }

    // MARK: Message Box

    var messageBoxPage: some View {
        List {
            Section {
                messageModeRow
                picturesRow
                Toggle("Speak Each Word", isOn: $tileSpeechEnabled)
                if let active = currentProfile, active.aiMode == .sentences {
                    NavigationLink(value: AdminPage.profileAI(active.id)) {
                        LabeledContent("Words per Message", value: "\(active.wordsPerMessage)")
                    }
                }
            }
            Section {
                Picker("Auto-Clear", selection: $autoDoneMs) {
                    ForEach(Self.choices([0, 30_000, 60_000, 120_000], including: autoDoneMs), id: \.self) { ms in
                        Text(ms == 0 ? "Off" : Self.seconds(ms)).tag(ms)
                    }
                }
                Picker("Pause Before Sentence", selection: $idleDebounceMs) {
                    ForEach(Self.choices([1_000, 1_500, 2_500, 4_000], including: idleDebounceMs), id: \.self) { ms in
                        Text(Self.seconds(ms)).tag(ms)
                    }
                }
            }
        }
        .navigationTitle("Message Box")
    }

    /// Single words or AI sentences — the board's Tray menu, here too.
    @ViewBuilder
    var messageModeRow: some View {
        if sentenceEngine.canGenerateSentences || sentenceEngine.interactionMode == .sentence {
            LabeledContent("Message") {
            Picker("Message", selection: Binding(
                get: { sentenceEngine.interactionMode },
                set: { mode in
                    guard mode != sentenceEngine.interactionMode else { return }
                    profileResolver.requestMode(mode)
                    sentenceEngine.clearSelection()
                    sentenceEngine.clearStrip()
                })) {
                Text("Single Words").tag(InteractionMode.singleWord)
                Text("AI Sentences").tag(InteractionMode.sentence)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 260)
            }
        } else {
            Button { show([.ai]) } label: {
                LabeledContent("Message", value: sentenceEngine.hasAIConsent
                               ? "Single Words · Add a Key" : "Single Words · Turn On AI")
            }
            .foregroundStyle(.primary)
        }
    }

    var picturesRow: some View {
        LabeledContent("Pictures") {
        Picker("Pictures", selection: Binding(
            get: { sentenceEngine.trayPictures },
            set: { sentenceEngine.trayPictures = $0 })) {
            Text("Stage").tag(TrayPictures.auto)
            Text("On").tag(TrayPictures.pictures)
            Text("Off").tag(TrayPictures.words)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 260)
        }
    }

    /// The listed values, plus the stored one when an earlier build left
    /// something in between — a picker with no matching tag shows blank.
    static func choices(_ values: [Int], including current: Int) -> [Int] {
        values.contains(current) ? values : (values + [current]).sorted()
    }

    static func seconds(_ ms: Int) -> String {
        ms % 60_000 == 0 && ms >= 60_000 ? "\(ms / 60_000) min"
            : ms % 1000 == 0 ? "\(ms / 1000) s" : String(format: "%.1f s", Double(ms) / 1000)
    }

    // MARK: Look, Sound, Feel

    var lookSoundFeelPage: some View {
        List {
            Section("Look") {
                Picker("Image Set", selection: $imageSetRaw) {
                    ForEach(ImageSetCatalog.selectable) { set in
                        Text(set.isShippable ? set.displayName : "\(set.displayName) (incomplete)")
                            .tag(set.id.rawValue)
                    }
                }
                .pickerStyle(.navigationLink)
                // A layout is a grid, the same on every device of a kind — so
                // the choice shows the grids, not a size. See `BoardLayout`.
                Picker("Board Layout", selection: $boardLayoutRaw) {
                    ForEach(BoardLayout.allCases) { layout in
                        VStack(alignment: .leading) {
                            Text(layout.title)
                            Text(layout.gridsDescription)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .tag(layout.rawValue)
                    }
                }
                .pickerStyle(.navigationLink)
                Toggle("Use Each Board's Layout", isOn: $honorSceneLayouts)
            }
            Section("Sound and Feel") {
                Toggle("Sound", isOn: $audioEnabled)
                // Only a phone has a haptic engine; on an iPad the switch would
                // do nothing. See `BoardHaptics`.
                if UIDevice.current.userInterfaceIdiom == .phone {
                    Toggle("Haptics", isOn: $hapticsEnabled)
                }
            }
        }
        .navigationTitle("Look, Sound, Feel")
    }

    // MARK: Advanced

    var advancedPage: some View {
        List {
            Section {
                NavigationLink("Lock and Role", value: AdminPage.lockRole)
                NavigationLink("TileScript", value: AdminPage.tileScript)
                NavigationLink("Authoring") { authoringPage }
                #if DEBUG
                NavigationLink("Developer") { developerPage }
                #endif
            }
            Section("Message Box") {
                Stepper("Keeps \(trayBufferSize) messages", value: $trayBufferSize, in: 50...500, step: 50)
                Button("Reset Session", role: .destructive) { sentenceEngine.resetSession() }
            }
        }
        .navigationTitle("Advanced")
    }

    var authoringPage: some View {
        List {
            Section { AuthorNameField() }
            carriedTemplatesSection
        }
        .textSelection(.enabled)
        .navigationTitle("Authoring")
    }

    #if DEBUG
    var developerPage: some View {
        List {
            storageSection
            developerSection
        }
        .navigationTitle("Developer")
    }
    #endif

    // MARK: - Script routes

    /// Where each script route lands: the row, then any pages under it. The
    /// names predate this layout — they were tabs — and are kept because
    /// recorded scripts use them.
    static func path(for request: AdminRouteCoordinator.Request) -> [AdminPage] {
        if let detail = request.detail {
            switch detail {
            case .vocabulary: return [.boardsAndVocabulary, .vocabulary]
            case .about:      return [.about]
            case .tileScript: return [.advanced, .tileScript]
            }
        }
        switch request.route {
        case .now:      return []
        case .profiles: return [.profile, .profiles]
        case .scenes:   return [.boardsAndVocabulary]
        case .device:   return [.ai]
        case .activity: return [.activity]
        }
    }

    func consumeRouteRequest() {
        guard let request = adminRoute.consume() else { return }
        show(Self.path(for: request))
    }

    // MARK: - Lifecycle

    /// Reactions to settings that change from more than one page. On the
    /// split view, which outlives every page, so none of them is skipped
    /// because the page that held the control had been popped.
    func settingsLifecycle(_ content: some View) -> some View {
        content
            .onAppear {
                // Self-heal a stored image set that no longer resolves —
                // including the empty string an earlier build could persist.
                // Without this the picker has no matching tag and shows nothing.
                let resolved = ImageSetID.resolved(imageSetRaw)
                if resolved.rawValue != imageSetRaw { imageSetRaw = resolved.rawValue }
                sentenceEngine.audioEnabled = audioEnabled
                consumeRouteRequest()
            }
            .onChange(of: adminRoute.pending) { _, _ in consumeRouteRequest() }
            .onChange(of: imageSetRaw) {
                // Resolved, not raw: a stored id this build cannot resolve must
                // fall back rather than point the resolver at a set with no art.
                imageResolver.activeSet = ImageSetID.resolved(imageSetRaw)
            }
            .onChange(of: audioEnabled) { sentenceEngine.audioEnabled = audioEnabled }
            .onChange(of: providerChoice) { applyProvider() }
            .onChange(of: apiKey) {
                OpenAIKeyVault.setKey(apiKey)
                // A record outliving its key would label somebody else's key
                // with the evaluator's name, which is worse than showing
                // nothing. The install path writes the record *after* the key,
                // so it survives this; every other route through here is a
                // caregiver typing, and that is exactly when the gift is over.
                if let gift = giftedKey,
                   GiftedKeyObfuscation.lastFour(of: apiKey) != gift.lastFour {
                    GiftedKeyRecord.clear()
                    giftedKey = nil
                }
                // A different key has not been rejected — it has not been
                // tried. The flag is about one credential, so it must not
                // outlive it, or a caregiver who fixes the problem stays in
                // single-word mode with no way to tell why.
                sentenceEngine.clearKeyRejection()
                applyProvider()
            }
    }
}
