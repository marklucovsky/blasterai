// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptView.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// Tab for browsing curated demo scripts and configuring test generation runs.
struct TileScriptView: View {
    @Environment(TileScriptRunner.self) private var runner
    @Environment(TileScriptRecorder.self) private var recorder
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \RecordedScript.created, order: .reverse)
    private var recordings: [RecordedScript]

    @Query(filter: #Predicate<BlasterScene> { $0.isActive })
    private var activeScenes: [BlasterScene]

    @State private var selectedCount: Int = 1000
    @State private var selectedSource: BulkTileSpec.BulkSource = .mostCommon
    @State private var selectedMinLength: Int = 2
    @State private var selectedMaxLength: Int = 4
    @State private var errorMessage: String?
    @AppStorage(AppSettingsKey.demoMode) private var demoMode = false

    // Save modal state
    @State private var showSaveSheet = false
    @State private var saveName = ""
    @State private var saveYaml = ""

    // Demo run logs (JSONL, written by the runner in Demo Mode)
    @State private var runLogs: [URL] = []

    private let countOptions = [100, 1_000, 10_000, 200_000, 1_000_000]

    private var activeScene: BlasterScene? { activeScenes.first }

    var body: some View {
        NavigationStack {
            List {
                demoModeSection
                if demoMode || !runLogs.isEmpty {
                    runLogsSection
                }
                recordSection
                if !recordings.isEmpty {
                    recordingsSection
                }
                curatedSection
                testGeneratorSection

                if runner.state != .idle {
                    nowPlayingSection
                }
            }
            .navigationTitle("TileScript")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .alert("This demo can't run yet",
               isPresented: Binding(get: { runner.validationError != nil },
                                    set: { if !$0 { runner.clearValidationError() } })) {
            Button("OK", role: .cancel) { runner.clearValidationError() }
        } message: {
            Text(validationMessage(runner.validationError))
        }
        .onAppear {
            // When stopRecording fires from the TileGrid tab and switches to TileScript, this
            // view is freshly constructed with `recorder.lastRecordedScript` already non-nil.
            // Populate the modal state on appear so the Save button enables on first show.
            if let script = recorder.lastRecordedScript {
                populateSaveModal(for: script)
            }
            refreshRunLogs()
        }
        .onChange(of: runner.state) { _, newState in
            // A finished/stopped run has just written its log — surface it.
            if newState == .finished || newState == .idle {
                refreshRunLogs()
            }
        }
        .onChange(of: recorder.lastRecordedScript != nil) { _, hasScript in
            // Covers subsequent recordings while the view stays mounted.
            if hasScript, let script = recorder.lastRecordedScript {
                populateSaveModal(for: script)
            }
        }
        .sheet(isPresented: $showSaveSheet, onDismiss: {
            recorder.lastRecordedScript = nil
        }) {
            saveModal
        }
    }

    private var isRunningOrRecording: Bool {
        runner.state == .running || runner.state == .paused || recorder.state == .recording
    }

    // MARK: - Demo Mode

    private var demoModeSection: some View {
        Section {
            Toggle(isOn: $demoMode) {
                Label("Demo Mode", systemImage: "sparkles")
            }
        } footer: {
            Text("For screen recording: hides the playback pill on Run, shows the “Generating…” beat even on cached results, and saves a timestamped run log (below) for aligning the capture.")
        }
    }

    // MARK: - Run Logs

    private var runLogsSection: some View {
        Section {
            if runLogs.isEmpty {
                Text("No run logs yet. With Demo Mode on, Run a demo — a timestamped event log (taps, sentences, escalations) is saved here to export.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(runLogs, id: \.self) { url in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(url.deletingPathExtension().lastPathComponent)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(TileScriptRunLogger.modDate(url), format: .dateTime.month().day().hour().minute().second())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .controlSize(.small)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        try? FileManager.default.removeItem(at: runLogs[index])
                    }
                    refreshRunLogs()
                }
            }
        } header: {
            Text("Run Logs")
        } footer: {
            Text("JSONL, one event per line, timed from run start. Share to your Mac (AirDrop / Messages / Save to Files) to align a screen recording.")
        }
    }

    private func refreshRunLogs() {
        runLogs = TileScriptRunLogger.existingLogs()
    }

    // MARK: - Record Section

    private var recordSection: some View {
        Section {
            Button {
                // Bind the recording to the scene's stable id (not its mutable
                // name), so a shared script resolves to the intended scene.
                recorder.startRecording(sceneName: activeScene?.scriptReference ?? "")
            } label: {
                HStack {
                    Circle()
                        .fill(.red)
                        .frame(width: 10, height: 10)
                    Text("Record Demo")
                        .font(.body.weight(.medium))
                    Spacer()
                    Text("Navigates to Home")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(isRunningOrRecording)
        } footer: {
            Text("Tap tiles naturally. When you stop, you'll return here to name and save the recording.")
        }
    }

    // MARK: - My Recordings

    private var recordingsSection: some View {
        Section("My Recordings") {
            ForEach(recordings) { recording in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.name)
                            .font(.body.weight(.medium))
                        Text(recording.created, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Step") {
                        playRecording(recording, paused: true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunningOrRecording)
                    Button("Run") {
                        playRecording(recording, paused: false)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isRunningOrRecording)
                    ShareLink(item: recording.yamlContent) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .controlSize(.small)
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    modelContext.delete(recordings[index])
                }
            }
        }
    }

    private func playRecording(_ recording: RecordedScript, paused: Bool) {
        errorMessage = nil
        do {
            let script = try TileScriptParser.parse(recording.yamlContent)
            if paused {
                runner.playPaused(script: script)
            } else {
                runner.play(script: script)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Turn a scene reference (a qualified `sceneID`, a slug, or a bare name)
    /// into something human for a miss message: e.g. `…/potty-training` → "Potty Training".
    private static func humanizeSceneRef(_ ref: String) -> String {
        let slug = ref.split(separator: "/").last.map(String.init) ?? ref
        let words = slug.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return words.isEmpty ? ref : words.joined(separator: " ")
    }

    private func validationMessage(_ result: TileScriptValidator.Result?) -> String {
        guard let result else { return "" }
        if let scene = result.missingScene {
            // Explicit + actionable instead of silently running against whatever
            // scene is active: the script binds by stable id, so a miss means the
            // exact scene it was recorded against isn't loaded here.
            return "This demo needs the \u{201C}\(Self.humanizeSceneRef(scene))\u{201D} scene, which isn't loaded on this device. Import that scene (the sender can share it), then try again."
        }
        var parts: [String] = []
        if !result.missingTiles.isEmpty {
            parts.append("tiles \u{2014} \(result.missingTiles.joined(separator: ", "))")
        }
        if !result.missingPages.isEmpty {
            parts.append("pages \u{2014} \(result.missingPages.joined(separator: ", "))")
        }
        return "This demo references items not in its target scene (\(parts.joined(separator: "; "))). Edit the script or pick a matching scene."
    }

    // MARK: - Save Modal

    private var saveModal: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Recording name", text: $saveName)
                }
                Section("YAML") {
                    TextEditor(text: $saveYaml)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("Save Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard") {
                        recorder.lastRecordedScript = nil
                        showSaveSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRecording()
                        showSaveSheet = false
                    }
                    .disabled(saveName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func populateSaveModal(for script: TileScript) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        saveName = "Recording \(formatter.string(from: .now))"
        saveYaml = TileScriptSerializer.serialize(script)
        // Defer sheet presentation to next run loop so saveName state is committed before
        // the sheet reads it.
        DispatchQueue.main.async {
            showSaveSheet = true
        }
    }

    private func saveRecording() {
        let name = saveName.trimmingCharacters(in: .whitespaces)
        // Re-serialize with updated name in the YAML header
        let updatedYaml: String
        if let range = saveYaml.range(of: "name: .*", options: .regularExpression) {
            var yaml = saveYaml
            yaml.replaceSubrange(range, with: "name: \(name)")
            updatedYaml = yaml
        } else {
            updatedYaml = saveYaml
        }
        let recorded = RecordedScript(
            name: name,
            yamlContent: updatedYaml,
            sceneName: recorder.lastRecordedScript?.scene ?? ""
        )
        modelContext.insert(recorded)
        recorder.lastRecordedScript = nil
    }

    // MARK: - Curated Demos

    private var curatedSection: some View {
        Section("Curated Demos") {
            ForEach(curatedScripts, id: \.name) { info in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.name)
                            .font(.body.weight(.medium))
                        Text(info.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Step") {
                        loadAndStep(resourceName: info.resourceName)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunningOrRecording)
                    Button("Run") {
                        loadAndRun(resourceName: info.resourceName)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isRunningOrRecording)
                }
            }
        }
    }

    // MARK: - Test Generator

    private var testGeneratorSection: some View {
        Section("Test Generator") {
            Picker("Entry Count", selection: $selectedCount) {
                ForEach(countOptions, id: \.self) { count in
                    Text(formatCount(count)).tag(count)
                }
            }

            Picker("Source", selection: $selectedSource) {
                Text("Most Common").tag(BulkTileSpec.BulkSource.mostCommon)
                Text("Random").tag(BulkTileSpec.BulkSource.random)
                Text("All Combos").tag(BulkTileSpec.BulkSource.allCombos)
            }

            HStack {
                Text("Tile Length")
                Spacer()
                Stepper("\(selectedMinLength)–\(selectedMaxLength)", value: $selectedMinLength, in: 1...selectedMaxLength)
                Stepper("", value: $selectedMaxLength, in: selectedMinLength...4)
                    .labelsHidden()
            }

            Button("Generate & Run") {
                runBulkGeneration()
            }
            .disabled(isRunningOrRecording)

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Now Playing

    private var nowPlayingSection: some View {
        Section("Now Playing") {
            if let script = runner.currentScript {
                Text(script.name)
                    .font(.body.weight(.medium))
            }

            HStack {
                Text("Status")
                Spacer()
                Text(runner.state == .running ? "Running" : runner.state == .paused ? "Paused" : "Finished")
                    .foregroundStyle(.secondary)
            }

            if let progress = runner.bulkProgress {
                ProgressView(value: Double(progress.completed), total: Double(progress.total)) {
                    HStack {
                        Text("\(progress.completed) / \(progress.total)")
                            .font(.caption)
                        if runner.bulkDuplicates > 0 {
                            Text("(\(runner.bulkDuplicates) duplicates skipped)")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }

            Text("Command \(runner.commandIndex + 1) / \(runner.totalCommands)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Stop", role: .destructive) {
                runner.stop()
            }
        }
    }

    // MARK: - Actions

    private func loadAndRun(resourceName: String) {
        loadScript(resourceName: resourceName, paused: false)
    }

    private func loadAndStep(resourceName: String) {
        loadScript(resourceName: resourceName, paused: true)
    }

    private func loadScript(resourceName: String, paused: Bool) {
        errorMessage = nil
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "yaml"),
              let yaml = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "Could not load script: \(resourceName)"
            return
        }

        do {
            let script = try TileScriptParser.parse(yaml)
            if paused {
                runner.playPaused(script: script)
            } else {
                runner.play(script: script)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runBulkGeneration() {
        errorMessage = nil
        let spec = BulkTileSpec(
            count: selectedCount,
            source: selectedSource,
            minLength: selectedMinLength,
            maxLength: selectedMaxLength
        )
        let script = TileScript(
            name: "Bulk Generation (\(formatCount(selectedCount)))",
            description: "Generating \(formatCount(selectedCount)) cache entries",
            audio: false,
            tileWait: .instant,
            sentenceWait: .instant,
            provider: "mock",
            scene: nil,
            mode: nil,
            commands: [.bulkTiles(spec: spec)]
        )
        runner.play(script: script)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1_000_000 { return "\(n / 1_000_000)M" }
        if n >= 1_000 { return "\(n / 1_000)K" }
        return "\(n)"
    }

    // MARK: - Curated Script Info

    private struct ScriptInfo {
        let name: String
        let description: String
        let resourceName: String
    }

    private var curatedScripts: [ScriptInfo] {
        [
            ScriptInfo(name: "First Look", description: "Child, Grandpa, Mom, and a Playground", resourceName: "demo_basic"),
            ScriptInfo(name: "Single Word Mode", description: "Single Word Mode -- Visit to the Tidepool", resourceName: "demo_wordmode"),
            ScriptInfo(name: "Classic Tiles Showcase", description: "order food, then flip the whole board to the Classic tile set", resourceName: "demo_food"),
            ScriptInfo(name: "At Home — Chocolate", description: "\"Mom, I want chocolate\" — repetition escalates the want (iPad)", resourceName: "demo_home"),
            ScriptInfo(name: "On the Go — Bathroom", description: "\"Mom, I have a stomachache. Can I go to the bathroom?\" (iPhone)", resourceName: "demo_onthego"),
        ]
    }
}

#Preview {
    TileScriptView()
        .previewEnvironment()
}
