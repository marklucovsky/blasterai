// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChildProfileFormSheet.swift
//  claudeBlast
//

import SwiftUI
import SwiftData
import AVFoundation

// MARK: - Voice Picker

/// Lists installed English voices grouped by quality tier.
///
/// iOS ships three tiers:
///   Default   — built-in, always available, sounds robotic
///   Enhanced  — ~50–150 MB download per voice, noticeably better
///   Premium   — ~200 MB download, on-device neural model (iOS 17+),
///               sounds natural and is indistinguishable from cloud TTS
///
/// Downloads live in Settings → Accessibility → Spoken Content → Voices.
/// Audio never leaves the device regardless of tier.
// VoicePickerSection and AVSpeechSynthesisVoiceQuality.sortOrder live in
// VoicePickerSection.swift now — shared by Admin, the profile form, and
// onboarding so the picker stays consistent.

// MARK: - Voice section header with help popover

private struct VoiceSectionHeader: View {
    @State private var showHelp = false

    var body: some View {
        HStack {
            Text("Voice")
            Spacer()
            Button {
                showHelp = true
            } label: {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHelp) {
                VoiceHelpPopover()
            }
        }
    }
}

private struct VoiceHelpPopover: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Voice Quality Tiers")
                .font(.headline)
            Text("**Default** — Built-in voices, always available.")
            Text("**Enhanced** — Noticeably better quality. ~50–150 MB download per voice.")
            Text("**Premium** — On-device neural voice, sounds natural. ~200 MB download.")
            Divider()
            Text("To download Enhanced or Premium voices, go to:")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            Text("Settings → Accessibility → Spoken Content → Voices")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding()
        .frame(minWidth: 300, maxWidth: 400)
    }
}

// MARK: - Child profile form sheet

/// Compact create/edit form for a `ChildProfile`. Used by the Admin
/// Profiles section. Captures the child's Brown's Stage, which decides both
/// the interaction mode and the tile cap — see `BrownsStage`. There is no age
/// or birthday field: the app does not store a child's date of birth.
struct ChildProfileFormSheet: View {
    enum Mode {
        case create
        case edit(ChildProfile)
    }

    let mode: Mode
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver

    /// Which row's color palette is open. One piece of state, not a flag plus a
    /// value, so there is no combination that means nothing.
    @State private var editingColorFor: PartOfSpeech?

    @State private var name: String = ""
    @State private var stage: BrownsStage = .one
    @State private var voiceID: String = ""
    @State private var maxTiles: Int = 4
    @State private var ttsRate: Float = 0.5
    @State private var ttsVolume: Float = 1.0
    @State private var makeActive: Bool = false
    /// This child's palette. Edited here because it belongs to the child, like
    /// their stage and their voice — see `TileColorMap`.
    @State private var colorMap = TileColorMap()
    /// The caregiver's saved palettes, loaded from the system profile.
    @State private var savedMaps: [TileColorMap] = []
    /// Name being typed when saving or renaming. Nil when no prompt is open.
    @State private var namePrompt: NamePrompt?
    @State private var draftName = ""

    /// The form as it stood when it opened. Compared against, rather than a
    /// `hasEdited` flag set from every control's `onChange`, because a flag is
    /// one missed control away from being wrong — and the cost of it being wrong
    /// here is a caregiver losing a palette they spent ten minutes on.
    @State private var loaded: Snapshot?
    /// Raised when Cancel is pressed with work outstanding.
    @State private var showDiscardPrompt = false

    private struct Snapshot: Equatable {
        var name: String
        var stage: BrownsStage
        var voiceID: String
        var maxTiles: Int
        var ttsRate: Float
        var ttsVolume: Float
        var colorMap: TileColorMap
    }

    private var current: Snapshot {
        Snapshot(name: name, stage: stage, voiceID: voiceID, maxTiles: maxTiles,
                 ttsRate: ttsRate, ttsVolume: ttsVolume, colorMap: colorMap)
    }

    /// Whether closing now would throw work away. Before `load` runs there is
    /// nothing to lose, so an early tap is not treated as destructive.
    private var hasUnsavedChanges: Bool {
        guard let loaded else { return false }
        return current != loaded
    }

    /// What the name prompt is for. Deliberately an enum rather than two flags:
    /// two booleans admit a state where both are true.
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

    private var titleText: String {
        switch mode {
        case .create: return "New Child Profile"
        case .edit:   return "Edit Child Profile"
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Personalize the voice preview when the child's name is filled in:
    /// "Hi Aubrey, I'll be your voice." Otherwise a generic line so the
    /// preview still works while the form is being filled out.
    private var previewPhrase: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty
            ? "Hi, I'll be your voice."
            : "Hi \(trimmed), I'll be your voice."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }

                Section("Voice") {
                    VoicePickerSection(
                        voiceIdentifier: $voiceID,
                        previewPhrase: previewPhrase
                    )
                }

                Section("Stage") {
                    Picker("Stage", selection: $stage) {
                        ForEach(BrownsStage.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    // Was a hand-written sentence that said roughly what
                    // `BrownsStage.appBehavior` says, differently, and omitted
                    // the key requirement entirely.
                    StageIntro(stage: stage,
                               keyHint: "Add one in Admin → Device.",
                               namesTheScale: false)
                    StageGuide()
                }
                .onChange(of: stage) { _, newStage in
                    maxTiles = min(newStage.tileCapRange.upperBound,
                                   max(newStage.tileCapRange.lowerBound, maxTiles))
                }

                Section("Tiles + Audio") {
                    // Only Stage IV+ leaves a number to choose — earlier stages
                    // pin the count, because the count is part of the stage.
                    if stage.allowsTileCapChoice {
                        Stepper(value: $maxTiles, in: stage.tileCapRange) {
                            HStack {
                                Text("Tiles per sentence")
                                Spacer()
                                Text("\(maxTiles)").foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        LabeledContent("Tiles per sentence",
                                       value: "\(stage.tileCapRange.lowerBound) (set by \(stage.label))")
                    }
                    VStack(alignment: .leading) {
                        Text("Speech rate \(String(format: "%.2f", ttsRate))")
                            .font(.caption)
                        Slider(value: $ttsRate, in: 0.3...0.7)
                    }
                    VStack(alignment: .leading) {
                        Text("Volume \(String(format: "%.2f", ttsVolume))")
                            .font(.caption)
                        Slider(value: $ttsVolume, in: 0.0...1.0)
                    }
                }

                colorSection

                if case .create = mode {
                    Section {
                        Toggle("Make this profile active", isOn: $makeActive)
                    }
                }
            }
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        // Deliberate exit with work outstanding asks; the
                        // accidental one (below) is refused without a dialog,
                        // because a dialog raised by a stray touch is its own
                        // kind of noise.
                        if hasUnsavedChanges { showDiscardPrompt = true } else { onDismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
            // An iPad form sheet dismisses on a tap outside it — the same
            // gesture as scrolling the list behind it — and this form holds work
            // that cannot be recovered. A colorway is eleven deliberate
            // decisions about one child's vision, and they were going in the bin
            // on a misplaced touch.
            //
            // Only while there is something to lose, so opening a profile just
            // to look at it still closes the easy way. SwiftUI gives no callback
            // when it swallows the gesture, so the way out is the Cancel button
            // that is already in the toolbar — which does ask.
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog("Discard changes?",
                                isPresented: $showDiscardPrompt,
                                titleVisibility: .visible) {
                Button("Discard", role: .destructive, action: onDismiss)
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("This profile has changes that have not been saved.")
            }
            .onAppear(perform: load)
            .alert(namePromptTitle, isPresented: Binding(
                get: { namePrompt != nil },
                set: { if !$0 { namePrompt = nil } })) {
                TextField("Name", text: $draftName)
                Button("Cancel", role: .cancel) { namePrompt = nil }
                Button("Save") { commitName() }
            } message: {
                Text("Saved colors are yours, not this child's — they show up for "
                     + "every child you set up on this device and anywhere else you "
                     + "are signed in.")
            }
        }
    }

    /// Color, for a child who does not see the default palette.
    ///
    /// Lives in the profile form rather than a global setting because it is a
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
            ForEach(PartOfSpeech.display) { pos in
                HStack(spacing: 10) {
                    Text(pos.label)
                    if colorMap.color(for: pos) != nil {
                        Text("changed")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                    }
                    Spacer()
                    colorWell(for: pos)
                }
                .contextMenu {
                    if colorMap.color(for: pos) != nil {
                        Button(role: .destructive) {
                            colorMap.set(nil, for: pos)
                        } label: {
                            Label("Use the Default", systemImage: "arrow.uturn.backward")
                        }
                    }
                }
            }

            if !colorMap.isEmpty {
                Button(role: .destructive) {
                    colorMap = TileColorMap()
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
                 + "child sees differently — with CVI, several of the default colors "
                 + "can look alike. Anything left alone keeps the default.")
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
    private func colorWell(for pos: PartOfSpeech) -> some View {
        Button {
            editingColorFor = pos
        } label: {
            Circle()
                .fill(colorMap.color(for: pos) ?? TileColorResolver.fitzgerald(pos))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 0.5))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(pos.label) color")
        // Bound to this row rather than to the Section. A `.popover` on the
        // Section is torn down whenever the Form re-renders — which is every
        // keystroke elsewhere in the sheet — and that is exactly how the first
        // version of this dismissed itself the moment it opened.
        .popover(isPresented: Binding(
            get: { editingColorFor == pos },
            set: { if !$0 { editingColorFor = nil } }
        )) {
            colorPalette(for: pos)
                .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder
    private func colorPalette(for pos: PartOfSpeech) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(pos.label).font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 10),
                                     count: 4), spacing: 10) {
                ForEach(TileColorMap.palette, id: \.self) { hex in
                    let color = Color(hex: hex) ?? .gray
                    Button {
                        colorMap.set(color, for: pos)
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

            if colorMap.color(for: pos) != nil {
                Button {
                    colorMap.set(nil, for: pos)
                    editingColorFor = nil
                } label: {
                    Label("Use the Default", systemImage: "arrow.uturn.backward")
                }
            }

            // The escape hatch, reached on purpose. On Mac this is still the
            // detached system panel — that is the platform's picker and we do
            // not get to change it — but nobody meets it by accident now.
            ColorPicker(selection: binding(for: pos), supportsOpacity: false) {
                Label("Custom…", systemImage: "eyedropper")
            }
        }
        .padding()
        .frame(minWidth: 240)
    }

    /// Writes through to the sparse map: setting a color records an override,
    /// and there is no way to record "the default" as an override, because the
    /// default is the absence of one.
    private func binding(for partOfSpeech: PartOfSpeech) -> Binding<Color> {
        Binding(
            get: { colorMap.color(for: partOfSpeech)
                    ?? TileColorResolver.fitzgerald(partOfSpeech) },
            set: { colorMap.set($0, for: partOfSpeech) }
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

    private func load() {
        savedMaps = ColorMapLibrary.load(from: modelContext)
        if case let .edit(profile) = mode {
            name = profile.displayName
            stage = profile.brownsStage
            voiceID = profile.voiceIdentifier
            maxTiles = profile.effectiveTileCap
            ttsRate = profile.ttsRate
            ttsVolume = profile.ttsVolume
            colorMap = TileColorMap.decode(profile.colorMapData)
        }
        // After the fields are populated, so an untouched form compares equal.
        loaded = current
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch mode {
        case .create:
            let profile = ChildProfile(
                displayName: trimmed,
                brownsStage: stage,
                voiceIdentifier: voiceID,
                maxSelectedTiles: maxTiles,
                isActive: false
            )
            profile.ttsRate = ttsRate
            profile.ttsVolume = ttsVolume
            profile.colorMapData = colorMap.encoded
            modelContext.insert(profile)
            if makeActive {
                profileResolver.setActive(id: profile.id)
            }
        case .edit(let profile):
            profile.displayName = trimmed
            profile.brownsStage = stage
            profile.voiceIdentifier = voiceID
            profile.setTileCap(maxTiles)
            profile.ttsRate = ttsRate
            profile.ttsVolume = ttsVolume
            profile.colorMapData = colorMap.encoded
            profile.modifiedAt = .now
            // `refresh()` re-reads the active profile AND its palette, so the
            // board picks up a color change on dismiss rather than at next
            // launch. See the defer in ChildProfileResolver.refresh().
            profileResolver.refresh()
        }
        onDismiss()
    }
}
