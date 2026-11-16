// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ProfilePages.swift
//  claudeBlast
//
//  The pages under Settings › Profile. Session 19 replaced the profile form
//  sheet — every field at once behind Save and Cancel, with a discard prompt —
//  with short pages that apply as you change them, like iOS Settings, and a
//  three-step Add Profile.
//

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Name and avatar

/// A profile name, which may carry a picture: `[sys:<tile key>,]<name>`.
///
/// - `Aubrey` — a plain name.
/// - `sys:unicorn,Aubrey` — the *unicorn* tile, drawn in the current tile
///   style, beside "Aubrey".
/// - `sys:me,me` — the tile and its own word. The caregiver's profile starts
///   here; the short `sys:me` reads the same.
///
/// One stored string, so the picture syncs with the name and needs no schema
/// change. Typed into the name field like any other name.
struct ProfileName: Equatable {
    static let avatarPrefix = "sys:"

    /// The tile to draw, or nil for a plain name.
    let avatarKey: String?
    /// The name as text: what the UI shows and a screen reader says.
    let text: String
    /// Whether `text` is a name of its own, rather than the tile's word
    /// (`sys:me` or `sys:me,me`). Only a name of its own is spoken.
    let isWrittenOut: Bool

    /// The stored form: always written out in full, `sys:<key>,<name>`, or
    /// the plain name when there is no picture. An empty name takes the
    /// tile's word, so a picture alone still has something to say.
    static func stored(avatarKey: String?, name: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard let key = avatarKey?.trimmingCharacters(in: .whitespaces).lowercased(),
              !key.isEmpty else { return name }
        let word = key.replacingOccurrences(of: "_", with: " ")
        return "\(avatarPrefix)\(key),\(name.isEmpty ? word : name)"
    }

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix(Self.avatarPrefix) else {
            (avatarKey, text, isWrittenOut) = (nil, trimmed, true)
            return
        }
        let rest = trimmed.dropFirst(Self.avatarPrefix.count)
        let parts = rest.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        let name = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
        if key.isEmpty {
            (avatarKey, text, isWrittenOut) = (nil, name.isEmpty ? trimmed : name, true)
        } else if name.isEmpty {
            (avatarKey, text, isWrittenOut) = (key, key.replacingOccurrences(of: "_", with: " "), false)
        } else {
            let word = key.replacingOccurrences(of: "_", with: " ")
            (avatarKey, text, isWrittenOut) = (key, name, name.lowercased() != word)
        }
    }
}

extension ChildProfile {
    var parsedName: ProfileName { ProfileName(displayName) }
    /// The tile a `sys:` name draws, or nil for a plain name.
    var avatarTileKey: String? { parsedName.avatarKey }
    /// The name as text, without the `sys:` part. Use this wherever a name is
    /// shown or sorted; `displayName` is the stored form.
    var visibleName: String { parsedName.text }
}

/// A profile's picture alone, on a small rounded card. Draws nothing for a
/// key with no art in any style.
struct ProfileAvatarImage: View {
    let key: String
    var size: CGFloat = 44
    @Environment(TileImageResolver.self) private var imageResolver

    var body: some View {
        if imageResolver.hasResolvedArt(for: key), let image = imageResolver.image(for: key) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(size * 0.06)
                .frame(width: size, height: size)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: size * 0.22))
                .accessibilityHidden(true)
        }
    }
}

/// A profile's name as people see it: its picture and name side by side, read
/// as the name alone; or the name as text.
struct ProfileNameLabel: View {
    let profile: ChildProfile
    var size: CGFloat = 32
    var font: Font = .body

    @Environment(TileImageResolver.self) private var imageResolver

    var body: some View {
        if let key = profile.avatarTileKey, imageResolver.hasResolvedArt(for: key) {
            HStack(spacing: size * 0.3) {
                ProfileAvatarImage(key: key, size: size)
                Text(profile.visibleName).font(font)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text(profile.visibleName).font(font)
        }
    }
}

/// The picture, as a button: tap to choose one from every word's art, the
/// same picker the tile editor uses. With none chosen it shows an empty slot.
struct ProfileAvatarButton: View {
    @Binding var avatarKey: String?
    var size: CGFloat = 56

    @Environment(TileImageResolver.self) private var imageResolver
    @State private var isPicking = false

    var body: some View {
        Button { isPicking = true } label: {
            if let key = avatarKey, imageResolver.hasResolvedArt(for: key) {
                ProfileAvatarImage(key: key, size: size)
            } else {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(.tint)
                    .frame(width: size, height: size)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: size * 0.22))
            }
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(avatarKey == nil ? "Choose a picture" : "Change picture")
        .sheet(isPresented: $isPicking) {
            ExistingArtPicker(
                title: "Choose a Picture",
                onClear: avatarKey == nil ? nil : { avatarKey = nil; isPicking = false }
            ) { tile in
                avatarKey = tile.key
                isPicking = false
            }
        }
    }
}

/// The top of a profile's page: picture and name, each changed where it is
/// shown. The name commits on Return, on losing focus, or on leaving; an
/// emptied name puts the old one back. Both are stored as one string
/// (`ProfileName.stored`), so the picture syncs with the name.
struct ProfileNameField: View {
    let profile: ChildProfile

    @Environment(ChildProfileResolver.self) private var profileResolver
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 16) {
            ProfileAvatarButton(avatarKey: Binding(
                get: { profile.avatarTileKey },
                set: { save(avatarKey: $0, name: profile.visibleName) }))
            TextField("Name", text: $draft)
                .font(.title2.weight(.semibold))
                .focused($focused)
                .submitLabel(.done)
                .onAppear { draft = profile.visibleName }
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .onDisappear(perform: commit)
        }
        .padding(.vertical, 4)
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { draft = profile.visibleName; return }
        // A name typed with its own `sys:` part is taken as written.
        if ProfileName(trimmed).avatarKey != nil {
            save(raw: trimmed)
            draft = profile.visibleName
        } else {
            save(avatarKey: profile.avatarTileKey, name: trimmed)
        }
    }

    private func save(avatarKey: String?, name: String) {
        save(raw: ProfileName.stored(avatarKey: avatarKey, name: name))
    }

    private func save(raw: String) {
        guard raw != profile.displayName else { return }
        profile.displayName = raw
        profile.modifiedAt = .now
        profileResolver.refresh()
    }
}

// MARK: - Stage

struct ProfileStagePage: View {
    let profile: ChildProfile

    @Environment(SentenceEngine.self) private var sentenceEngine
    @Environment(ChildProfileResolver.self) private var profileResolver
    /// The stage just picked, while its defaults are offered.
    @State private var offeredStage: BrownsStage?

    var body: some View {
        List {
            Section {
                Picker("Stage", selection: Binding(get: { profile.brownsStage }, set: setStage)) {
                    ForEach(BrownsStage.allCases) { stage in
                        Text(stage.label).tag(stage)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                StageIntro(stage: profile.brownsStage, keyHint: "Add one in Settings → AI.")
                StageGuide()
            }
        }
        .navigationTitle("Stage")
        .confirmationDialog(
            "Use \(offeredStage?.label ?? "the stage")'s starting settings?",
            isPresented: Binding(get: { offeredStage != nil }, set: { if !$0 { offeredStage = nil } }),
            titleVisibility: .visible
        ) {
            Button("Use Them") {
                profile.applyStageDefaults()
                settled()
            }
            Button("Keep Current Settings", role: .cancel) {}
        } message: {
            if let stage = offeredStage {
                Text(ProfileAIPage.stageDefaultsLine(stage))
            }
        }
    }

    /// The stage is an input to the defaults, not a rule over them: picking
    /// one offers its starting settings and changes nothing else on its own.
    private func setStage(_ stage: BrownsStage) {
        guard stage != profile.brownsStage else { return }
        profile.brownsStage = stage
        if profile.wordsPerMessage != stage.defaultWordsPerMessage || profile.trayPictures != .auto {
            offeredStage = stage
        }
        settled()
    }

    private func settled() {
        // The board is speaking for this profile: start the new settings clean.
        if profileResolver.active?.id == profile.id {
            sentenceEngine.clearSelection()
            sentenceEngine.clearStrip()
        }
        profileResolver.refresh()
    }
}

// MARK: - AI

/// A profile's AI: whether this profile uses AI, and whether its words become
/// a sentence and from how many. The message box's pictures are a profile
/// setting too, but they live on Settings › Message Box, the one place that
/// controls the message box. The stage only sets where these start; Reset
/// puts them back.
struct ProfileAIPage: View {
    let profile: ChildProfile
    /// Opens Settings › AI, where the device's AI is turned on.
    let openDeviceAI: () -> Void

    @Environment(SentenceEngine.self) private var sentenceEngine
    @Environment(ChildProfileResolver.self) private var profileResolver

    /// One line for the profile page's AI row.
    static func summary(of p: ChildProfile) -> String {
        switch p.aiMode {
        case .off: "Off"
        case .on: "On"
        case .sentences: "Sentences · \(p.wordsPerMessage) words"
        }
    }

    /// What a stage starts with, for the stage prompt and the Reset footer.
    static func stageDefaultsLine(_ stage: BrownsStage) -> String {
        let pictures = stage.showsPicturesInTray ? "pictures in the message box" : "words only in the message box"
        return "\(stage.label) starts with \(stage.defaultWordsPerMessage) words per message and \(pictures)."
    }

    private var deviceAIOn: Bool { sentenceEngine.hasAIConsent }

    var body: some View {
        List {
            Section {
                Toggle("AI", isOn: Binding(
                    get: { profile.aiMode != .off },
                    set: { on in change { profile.aiMode = on ? .on : .off } }))
                    .disabled(!deviceAIOn)
                if profile.aiMode != .off {
                    Toggle("Sentences", isOn: Binding(
                        get: { profile.aiMode == .sentences },
                        set: { on in change { profile.aiMode = on ? .sentences : .on } }))
                        .disabled(!deviceAIOn)
                    if profile.aiMode == .sentences {
                        Stepper(value: Binding(
                            get: { profile.wordsPerMessage },
                            set: { n in change { profile.wordsPerMessage = n } }),
                                in: ChildProfile.wordsPerMessageRange) {
                            LabeledContent("Words per Message", value: "\(profile.wordsPerMessage)")
                        }
                    }
                }
            } footer: {
                if !deviceAIOn {
                    Button("AI is off on this device. Turn it on in Settings › AI.", action: openDeviceAI)
                        .font(.footnote)
                } else if profile.aiMode == .sentences {
                    Text("The words in the message box become a sentence.")
                } else {
                    Text("Each word speaks as it is tapped. The message box holds any number and clears at once.")
                }
            }
            Section {
                Button("Reset to Stage Defaults") { change { profile.resetToStageDefaults() } }
                    .disabled(profile.matchesStageDefaults)
            } footer: {
                Text(Self.stageDefaultsLine(profile.brownsStage) + " AI on, sentences off.")
            }
        }
        .navigationTitle("AI")
    }

    private func change(_ apply: () -> Void) {
        let wasMode = profile.interactionMode
        apply()
        if profileResolver.active?.id == profile.id, wasMode != profile.interactionMode {
            sentenceEngine.clearSelection()
            sentenceEngine.clearStrip()
        }
        profileResolver.refresh()
    }
}

// MARK: - Voice

struct ProfileVoicePage: View {
    let profile: ChildProfile

    /// The preview line, without emoji or the picture: a voice reads 😎 as
    /// "smiling face with sunglasses", and the `sys:` part is not a word to say.
    /// `sys:unicorn,Aubrey` greets Aubrey; `sys:me,me` greets nobody.
    static func greeting(for name: String) -> String {
        let parsed = ProfileName(name)
        guard parsed.isWrittenOut else { return "Hi, I'll be your voice." }
        let spoken = String(parsed.text.unicodeScalars.filter {
            !($0.properties.isEmojiPresentation || $0.properties.isEmojiModifier
              || $0.value == 0xFE0F || $0.value == 0x200D
              || ($0.properties.isEmoji && $0.value > 0xFF))
        }).trimmingCharacters(in: .whitespaces)
        return spoken.isEmpty ? "Hi, I'll be your voice." : "Hi \(spoken), I'll be your voice."
    }

    var body: some View {
        Form {
            VoicePickerSection(
                voiceIdentifier: Binding(
                    get: { profile.voiceIdentifier },
                    set: { profile.voiceIdentifier = $0; profile.modifiedAt = .now }),
                previewPhrase: Self.greeting(for: profile.displayName))
            Section {
                LabeledContent("Rate") {
                    Slider(value: Binding(
                        get: { profile.ttsRate },
                        set: { profile.ttsRate = $0; profile.modifiedAt = .now }
                    ), in: 0.3...0.7)
                    .frame(maxWidth: 240)
                }
                LabeledContent("Volume") {
                    Slider(value: Binding(
                        get: { profile.ttsVolume },
                        set: { profile.ttsVolume = $0; profile.modifiedAt = .now }
                    ), in: 0.0...1.0)
                    .frame(maxWidth: 240)
                }
            }
        }
        .navigationTitle("Voice")
    }
}

// MARK: - Me page

/// A profile's Me page: the page itself, its rules (Always, Pinned, and by
/// page in the section below), the Me pages it includes, its topics, and
/// sharing it. See `MeScene` for how the rules are applied.
///
/// An SLP builds one per student, plus one for a group ("Room 4") that each
/// student's includes; a family adds a received Me page to their child's
/// with Includes. Nothing here replaces anyone's own page.
struct ProfileMePage: View {
    let profile: ChildProfile

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BlasterScene.name) private var scenes: [BlasterScene]
    @Query private var profiles: [ChildProfile]
    @Query(filter: #Predicate<BlasterScene> { $0.isDefault }) private var systemScenes: [BlasterScene]
    @State private var editing: String?
    @State private var isSharing = false
    @State private var isPreviewing = false

    private var me: BlasterScene? {
        scenes.first { $0.sceneID == MeScene.sceneID(forProfileID: profile.id) }
    }
    private func find(_ id: String) -> BlasterScene? { scenes.first { $0.sceneID == id } }

    /// An included page's name: its profile's on this device, else its own,
    /// with who sent it.
    private func includeName(_ scene: BlasterScene) -> String {
        if let owner = profiles.first(where: { MeScene.sceneID(forProfileID: $0.id) == scene.sceneID }) {
            return owner.visibleName
        }
        let from = scene.authorDisplay
        return from.isEmpty ? scene.name : "\(scene.name) \u{00B7} from \(from)"
    }

    var body: some View {
        Form {
            if let me, let system = systemScenes.first {
                Section {
                    Button("Edit \(profile.visibleName)\u{2019}s Page") { editing = MeScene.homePageKey }
                    NavigationLink("Preview") { MePreviewView(profile: profile) }
                    NavigationLink {
                        ContextPageView(me: me, system: system, systemKey: MeScene.alwaysKey)
                    } label: {
                        LabeledContent("Always", value: count(MeScene.alwaysPageKey, in: me))
                    }
                    Button { editing = MeScene.pinnedPageKey } label: {
                        LabeledContent("Pinned", value: count(MeScene.pinnedPageKey, in: me))
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Always adds its words and folders every time the Me page opens. Pinned puts tiles in cells you choose. Neither covers anything on the page itself.")
                }
                includesSection(me)
            }
            MeTopicsSection(profileID: profile.id)
            if me != nil {
                Section {
                    Button { isSharing = true } label: {
                        Label("Share \(profile.visibleName)\u{2019}s Me Page", systemImage: "square.and.arrow.up")
                    }
                } footer: {
                    Text("Sends this Me page and the pages it includes. Whoever opens it can add it to the Me page of a profile there; sending it again updates it there.")
                }
            }
        }
        .navigationTitle("Me Page")
        .onAppear(perform: prepare)
        .fullScreenCover(item: Binding(get: { editing.map(EditTarget.init) },
                                       set: { editing = $0?.pageKey })) { target in
            if let me {
                NavigationStack {
                    PageEditorView(scene: me, pageKey: target.pageKey)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Done") { editing = nil }
                            }
                            // What the page will look like with its rules,
                            // while placing tiles on it.
                            ToolbarItem(placement: .topBarLeading) {
                                Button { isPreviewing = true } label: {
                                    Label("Preview", systemImage: "eye")
                                }
                            }
                        }
                        .sheet(isPresented: $isPreviewing) {
                            NavigationStack {
                                MePreviewView(profile: profile)
                                    .toolbar {
                                        ToolbarItem(placement: .confirmationAction) {
                                            Button("Done") { isPreviewing = false }
                                        }
                                    }
                            }
                        }
                }
            }
        }
        .sheet(isPresented: $isSharing) {
            if let me { ShareBoardSheet(subject: .scene(me)) }
        }
    }

    private struct EditTarget: Identifiable {
        let pageKey: String
        var id: String { pageKey }
    }

    private func count(_ pageKey: String, in me: BlasterScene) -> String {
        let n = (me.page(withKey: pageKey)?.tiles ?? []).filter { !$0.isEmptyCell }.count
        return n == 0 ? "None" : n == 1 ? "1 item" : "\(n) items"
    }

    private func includesSection(_ me: BlasterScene) -> some View {
        let entries = MeScene.includeEntries(in: me)
        let choices = MeScene.includeChoices(for: me, scenes: scenes, profiles: profiles)
        return Section {
            ForEach(entries, id: \.link) { entry in
                if let id = MeScene.includedID(entry), let included = find(id) {
                    Toggle(includeName(included), isOn: Binding(
                        get: { !entry.isConcealed },
                        set: { on in
                            MeScene.setInclude(on, sceneID: id, in: me)
                            try? modelContext.save()
                        }))
                } else {
                    Label("\(entry.label ?? "A Me page") (not on this device)",
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete { offsets in
                for entry in offsets.map({ entries[$0] }) {
                    if let id = MeScene.includedID(entry) { MeScene.removeInclude(sceneID: id, from: me) }
                }
                try? modelContext.save()
            }
            if !choices.onDevice.isEmpty || !choices.received.isEmpty {
                Menu {
                    if !choices.onDevice.isEmpty {
                        Section("On This Device") {
                            ForEach(choices.onDevice, id: \.scene.sceneID) { choice in
                                Button(choice.name) { include(choice.scene, in: me) }
                            }
                        }
                    }
                    if !choices.received.isEmpty {
                        Section("Received") {
                            ForEach(choices.received) { scene in
                                Button(includeName(scene)) { include(scene, in: me) }
                            }
                        }
                    }
                } label: {
                    Label("Include a Me Page", systemImage: "plus.circle")
                }
            }
        } header: {
            Text("Includes")
        } footer: {
            Text("An included Me page adds its words, folders and pinned tiles after this page\u{2019}s own, without covering them.")
        }
    }

    private func include(_ other: BlasterScene, in me: BlasterScene) {
        MeScene.addInclude(other, to: me, find: find)
        try? modelContext.save()
    }

    /// Made here, not while the view is built: the Me scene and its Pinned
    /// page exist before anything opens them, and the scene carries the
    /// profile's name, so a shared copy says whose it is.
    private func prepare() {
        let me = MeScene.ensure(profileID: profile.id, context: modelContext)
        MeScene.ensurePinned(in: me)
        if me.name != profile.visibleName { me.name = profile.visibleName }
        try? modelContext.save()
    }
}

// MARK: - Colors

/// Colour, for a child who does not see the default palette. Changes apply as
/// they are made, so the board behind Settings already shows them.
struct ProfileColorsPage: View {
    let profile: ChildProfile

    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver

    @State private var editingColorFor: TileColorSlot?
    @State private var colorMap = TileColorMap()
    @State private var linkColorMode = LinkColorMode.standard
    @State private var savedMaps: [TileColorMap] = []
    @State private var namePrompt: NamePrompt?
    @State private var draftName = ""
    @State private var loaded = false

    private enum NamePrompt: Identifiable {
        case saveCurrent
        case rename(String)
        var id: String {
            switch self {
            case .saveCurrent: return "save"
            case .rename(let name): return "rename:\(name)"
            }
        }
    }

    var body: some View {
        Form { colorSection }
            .navigationTitle("Colors")
            .onAppear {
                savedMaps = ColorMapLibrary.load(from: modelContext)
                colorMap = TileColorMap.decode(profile.colorMapData)
                linkColorMode = profile.linkColorMode
                loaded = true
            }
            .onChange(of: colorMap) { _, map in
                guard loaded, map.encoded != profile.colorMapData else { return }
                profile.colorMapData = map.encoded
                profile.modifiedAt = .now
                profileResolver.refresh()
            }
            .onChange(of: linkColorMode) { _, mode in
                guard loaded, mode != profile.linkColorMode else { return }
                profile.linkColorMode = mode
                profile.modifiedAt = .now
                profileResolver.refresh()
            }
            .alert(namePromptTitle, isPresented: Binding(
                get: { namePrompt != nil },
                set: { if !$0 { namePrompt = nil } })) {
                TextField("Name", text: $draftName)
                Button("Cancel", role: .cancel) { namePrompt = nil }
                Button("Save") { commitName() }
            } message: {
                Text("Saved colors are yours, not this profile's — they show up for "
                     + "every profile you set up on this device and anywhere else you "
                     + "are signed in.")
            }
    }

    /// Color, for a child who does not see the default palette.
    ///
    /// Lives on the profile rather than in a global setting because it is a
    /// fact about this child — see `ChildProfile.colorMapData` for why that
    /// differs from the image set, which is per device.
    @ViewBuilder
    private var colorSection: some View {
        Section {
            // A plain filled circle, not a `ColorPicker`. Eleven rainbow rings
            // read as decoration competing with the colors themselves, which
            // are the actual content here — and the footer says what to tap, so
            // the affordance does not need drawing eleven times. See
            // `colorWell(for:)` for why this is our own control rather than a
            // system one wearing a disguise.
            ForEach(TileColorSlot.display) { slot in
                HStack(spacing: 10) {
                    Text(slot.label)
                    if colorMap.color(for: slot) != nil {
                        Text("changed")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    Spacer()
                    colorWell(for: slot)
                }
                .contextMenu {
                    if colorMap.color(for: slot) != nil {
                        Button(role: .destructive) {
                            colorMap.set(nil, for: slot)
                        } label: {
                            Label("Use the Default", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }

            // One switch over every folder in every scene, so a caregiver who
            // needs links to stand out does not have to edit them one at a time
            // — including in a scene somebody else authored and sent them.
            Picker("Folder Color", selection: $linkColorMode) {
                ForEach(LinkColorMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            Text(linkColorMode.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if !colorMap.isEmpty || linkColorMode != .standard {
                Button(role: .destructive) {
                    colorMap = TileColorMap()
                    linkColorMode = .standard
                } label: {
                    Label("Reset to Default Colors", systemImage: "arrow.uturn.backward")
                }
            }

            // Saving is only meaningful once something has been changed, and a
            // palette identical to the default is not worth a name.
            if !colorMap.isEmpty {
                Button {
                    draftName = colorMap.name
                    namePrompt = .saveCurrent
                } label: {
                    Label("Save These Colors…", systemImage: "square.and.arrow.down")
                }
            }

            // Send it to the device that needs it.
            //
            // A colorway is worked out by a therapist and needed on a child's
            // iPad, and those are almost never the same device — the therapist
            // will not be on the family's iCloud, so the library syncing across
            // *her* devices does not help this child at all. Same reasoning as
            // the usage report: the real recipient is on the other side of a
            // text message.
            if !colorMap.isEmpty, let file = colorwayFile {
                ShareLink(item: file, preview: SharePreview(colorMap.name.isEmpty
                                                            ? "Blaster colors"
                                                            : colorMap.name)) {
                    Label("Send These Colors…", systemImage: "square.and.arrow.up")
                }
            }

            // A therapist should not have to invent a high-contrast palette from
            // first principles, and a named preset is also how we say we know
            // what this is for. Their own saved palettes sit alongside, because
            // after the first child the ones they built are the better start.
            Menu {
                if !savedMaps.isEmpty {
                    Section("Saved") {
                        ForEach(savedMaps, id: \.name) { saved in
                            // A nested menu rather than a plain Apply, so manage
                            // lives where the palette does and needs no separate
                            // screen.
                            Menu(saved.name) {
                                Button { colorMap = saved } label: {
                                    Label("Use These Colors", systemImage: "checkmark.circle")
                                }
                                Button {
                                    draftName = saved.name
                                    namePrompt = .rename(saved.name)
                                } label: {
                                    Label("Rename…", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    ColorMapLibrary.remove(named: saved.name, from: modelContext)
                                    savedMaps = ColorMapLibrary.load(from: modelContext)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                Section("Presets") {
                    ForEach(TileColorMap.presets, id: \.name) { preset in
                        Button(preset.name) { colorMap = preset }
                    }
                }
            } label: {
                Label(savedMaps.isEmpty ? "Start From a Preset" : "Start From…",
                      systemImage: "swatchpalette")
            }
        } header: {
            Text("Colors")
        } footer: {
            Text("Tap a color to change it.\n\nTile color normally shows the type "
                 + "of word, using the key most AAC boards share. Change it when this "
                 + "user sees differently — with CVI, several of the default colors "
                 + "can look alike. Anything left alone keeps the default.\n\n"
                 + "Page Links are the tiles that open another page. They are not a "
                 + "kind of word, so they get their own color — change it if this "
                 + "user cannot tell a link from the describing words beside it, or "
                 + "to match a device they already use.")
        }
    }

    /// A swatch that opens a palette, inline.
    ///
    /// This replaces a `ColorPicker` with our own circle laid over its rainbow
    /// ring. That trick worked on iOS and fell apart on Mac twice over: the
    /// circle did not match the shape of Mac's color well, so eleven rows drew
    /// as misaligned blobs; and the picker underneath opened the shared system
    /// color panel, a window this binary cannot reach — Designed-for-iPad is
    /// UIKit-only, so nothing here can close it or stop it taking key window,
    /// which left the sheet's own Save button dead under it.
    ///
    /// Masking a system control was the mistake. This does not mask anything:
    /// the swatch is ours, the palette is ours, and the system picker is reached
    /// deliberately through `Custom…` rather than by every tap.
    @ViewBuilder
    private func colorWell(for slot: TileColorSlot) -> some View {
        Button {
            editingColorFor = slot
        } label: {
            Circle()
                .fill(colorMap.color(for: slot) ?? TileColorResolver.defaultColor(for: slot))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.label) color")
        // Bound to this row rather than to the Section. A `.popover` on the
        // Section is torn down whenever the Form re-renders — which is every
        // keystroke elsewhere in the sheet — and that is exactly how the first
        // version of this dismissed itself the moment it opened.
        .popover(isPresented: Binding(
            get: { editingColorFor == slot },
            set: { if !$0 { editingColorFor = nil } }
        )) {
            colorPalette(for: slot)
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func colorPalette(for slot: TileColorSlot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(slot.label).font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10),
                                     count: 4), spacing: 10) {
                ForEach(TileColorMap.palette, id: \.self) { hex in
                    let color = Color(hex: hex) ?? .gray
                    Button {
                        colorMap.set(color, for: slot)
                        editingColorFor = nil
                    } label: {
                        Circle()
                            .fill(color)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.25),
                                                           lineWidth: 0.5))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(hex)
                }
            }

            Divider()

            if colorMap.color(for: slot) != nil {
                Button {
                    colorMap.set(nil, for: slot)
                    editingColorFor = nil
                } label: {
                    Label("Use the Default", systemImage: "arrow.uturn.backward")
                }
            }

            // The escape hatch, reached on purpose. On Mac this is still the
            // detached system panel — that is the platform's picker and we do
            // not get to change it — but nobody meets it by accident now.
            ColorPicker(selection: binding(for: slot), supportsOpacity: false) {
                Label("Custom…", systemImage: "eyedropper")
            }
        }
        .padding()
        .frame(minWidth: 240)
    }

    /// Writes through to the sparse map: setting a color records an override,
    /// and there is no way to record "the default" as an override, because the
    /// default is the absence of one.
    private func binding(for slot: TileColorSlot) -> Binding<Color> {
        Binding(
            get: { colorMap.color(for: slot)
                    ?? TileColorResolver.defaultColor(for: slot) },
            set: { colorMap.set($0, for: slot) }
        )
    }

    private var namePromptTitle: String {
        if case .rename = namePrompt { return "Rename Palette" }
        return "Save These Colors"
    }

    /// Apply the typed name. Saving under an existing name replaces it, so a
    /// caregiver refining a palette does not end up with three near-identical
    /// entries they then have to tell apart.
    private func commitName() {
        let trimmed = draftName.trimmingCharacters(in: .whitespaces)
        defer { namePrompt = nil }
        guard !trimmed.isEmpty else { return }

        switch namePrompt {
        case .saveCurrent:
            var toSave = colorMap
            toSave.name = trimmed
            colorMap.name = trimmed
            ColorMapLibrary.store(toSave, in: modelContext)
        case .rename(let old):
            ColorMapLibrary.rename(old, to: trimmed, in: modelContext)
            if colorMap.name == old { colorMap.name = trimmed }
        case nil:
            return
        }
        savedMaps = ColorMapLibrary.load(from: modelContext)
    }

    /// The colorway as a file on disk, for `ShareLink`.
    ///
    /// Written to a temp URL rather than shared as raw `Data` because the file
    /// *name* is the only thing the recipient sees before they tap it, and
    /// "Colors — Warm Bias.blastercolors" tells them what it is where an
    /// untitled attachment does not.
    private var colorwayFile: URL? {
        guard let data = try? ColorwayExporter.data(for: colorMap) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(ColorwayExporter.suggestedFileName(for: colorMap))
        guard (try? data.write(to: url, options: .atomic)) != nil else { return nil }
        return url
    }

}

// MARK: - Add Profile

/// Three short steps — name, stage, voice — and nothing is made until the
/// last one. Everything else is on the profile's page afterwards.
struct AddProfileFlow: View {
    let onDone: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver

    @State private var name = ""
    @State private var avatarKey: String?
    @State private var stage: BrownsStage = .one
    @State private var voiceID = ""
    @State private var path: [Step] = []

    private enum Step: Hashable { case stage, voice }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    HStack(spacing: 16) {
                        ProfileAvatarButton(avatarKey: $avatarKey)
                        TextField("Name", text: $name)
                            .font(.title3)
                            .submitLabel(.next)
                            .onSubmit { if !trimmedName.isEmpty { path.append(.stage) } }
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Who will be talking with this board? The picture is optional.")
                }
            }
            .navigationTitle("New Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: onDone) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { path.append(.stage) }.disabled(trimmedName.isEmpty)
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .stage: stageStep
                case .voice: voiceStep
                }
            }
        }
    }

    private var stageStep: some View {
        List {
            Section {
                Picker("Stage", selection: $stage) {
                    ForEach(BrownsStage.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                StageIntro(stage: stage, keyHint: "Add one in Settings → AI.")
                StageGuide()
            }
        }
        .navigationTitle("Stage")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Next") { path.append(.voice) }
            }
        }
    }

    private var voiceStep: some View {
        Form {
            VoicePickerSection(voiceIdentifier: $voiceID,
                               previewPhrase: "Hi \(trimmedName), I'll be your voice.")
            Section {
                Button("Add and Switch to \(trimmedName)") { create(switchTo: true) }
                Button("Add") { create(switchTo: false) }
            }
        }
        .navigationTitle("Voice")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func create(switchTo: Bool) {
        let profile = ChildProfile(displayName: ProfileName.stored(avatarKey: avatarKey, name: trimmedName),
                                   brownsStage: stage,
                                   voiceIdentifier: voiceID, isActive: false)
        modelContext.insert(profile)
        try? modelContext.save()
        if switchTo { profileResolver.setActive(id: profile.id) }
        onDone()
    }
}
