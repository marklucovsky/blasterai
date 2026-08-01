// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BulkWordSheet.swift
//  claudeBlast
//
//  Paste/type a CSV list of words to create many tiles at once and drop them on
//  the current page. One word per line:
//      key, wordClass                 (displayName defaults to the key)
//      key, wordClass, Display Name   (explicit display name)
//  Blank lines and lines starting with '#' are ignored. The created words start
//  artless, so they flow into the existing "Generate art for N words" pass.
//

import SwiftUI
import SwiftData

/// Shared parser for the `key, class[, Display Name]` CSV format used by both the
/// bulk-word sheet and the tile picker's editable selection list. One word per
/// line; blank / '#' lines ignored; a word needs ≥2 non-empty columns
/// (key, class), an optional 3rd column overrides the display name.
enum BulkWordParser {
    struct Word: Hashable {
        let key: String         // column 0 (raw; caller normalizes)
        let wordClass: String   // column 1, lowercased
        let displayName: String // column 2, else the key
    }

    /// Recognized caregiver classes — an unknown class still parses (creation
    /// falls back); this only drives the "unknown class" hint.
    static let knownClasses: Set<String> = Set(VocabularyClasses.caregiverSelectable.map(\.name))

    static func parse(_ text: String) -> (words: [Word], skipped: [String]) {
        var words: [Word] = []
        var skipped: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let cols = line.split(separator: ",", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard cols.count >= 2, !cols[0].isEmpty, !cols[1].isEmpty else {
                skipped.append(line)
                continue
            }
            let key = cols[0]
            let wordClass = cols[1].lowercased()
            let displayName = (cols.count >= 3 && !cols[2].isEmpty) ? cols[2] : key
            words.append(Word(key: key, wordClass: wordClass, displayName: displayName))
        }
        return (words, skipped)
    }
}

struct BulkWordSheet: View {
    let existingTiles: [TileModel]
    /// Called with the created (or reused) tiles to place on the page.
    let onCommit: ([TileModel]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var text = ""

    private var knownClasses: Set<String> { BulkWordParser.knownClasses }
    private var parseResult: (words: [BulkWordParser.Word], skipped: [String]) {
        BulkWordParser.parse(text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(VocabularyClasses.caregiverSelectable, id: \.name) { cls in
                                Button { insertClass(cls.name) } label: {
                                    Text(cls.name)
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 9).padding(.vertical, 4)
                                        .background(Capsule().fill(cls.color.opacity(0.28)))
                                        .foregroundStyle(.primary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } header: {
                    Text("Available classes")
                } footer: {
                    Text("The valid values for the second column — tap one to insert it. Unknown classes still work but render with a neutral color (flagged below).")
                        .font(.caption)
                }

                Section {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Paste words")
                } footer: {
                    Text("One per line: `word, wordClass` (optional third column = display name).\nExample:\n  rocket, object\n  astronaut, people\n  earth, place, Planet Earth")
                        .font(.caption)
                }

                let result = parseResult
                if !result.words.isEmpty {
                    Section("\(result.words.count) word\(result.words.count == 1 ? "" : "s")") {
                        ForEach(Array(result.words.enumerated()), id: \.offset) { _, w in
                            HStack {
                                Text(w.displayName)
                                Spacer()
                                Text(w.wordClass)
                                    .font(.caption)
                                    .foregroundStyle(knownClasses.contains(w.wordClass) ? Color.secondary : Color.orange)
                            }
                        }
                    }
                }
                if !result.skipped.isEmpty {
                    Section {
                        ForEach(result.skipped, id: \.self) { line in
                            Text("Skipped (needs word + class): \(line)")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .navigationTitle("Paste Word List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(parseResult.words.count)") { addWords() }
                        .disabled(parseResult.words.isEmpty)
                }
            }
        }
    }

    /// Append a class to the editor, mending the separator so tapping after a
    /// bare word ("rocket") yields "rocket, object".
    private func insertClass(_ name: String) {
        if text.isEmpty || text.hasSuffix("\n") || text.hasSuffix(", ") {
            text += name
        } else if text.hasSuffix(",") {
            text += " \(name)"
        } else {
            text += ", \(name)"
        }
    }

    private func addWords() {
        var keys = Set(existingTiles.map(\.key))
        var created: [TileModel] = []
        for w in parseResult.words {
            let base = TileModel.normalizeKey(w.key)
            guard !base.isEmpty else { continue }
            // Same key + same class already exists → reuse it (place, don't dup).
            if let existing = existingTiles.first(where: { $0.key == base && $0.wordClass == w.wordClass }) {
                created.append(existing)
                continue
            }
            // Key taken by another class (or an earlier row) → homograph key.
            var finalKey = base
            if keys.contains(base) {
                finalKey = "\(base)_\(w.wordClass)"
                var n = 2
                while keys.contains(finalKey) { finalKey = "\(base)_\(w.wordClass)_\(n)"; n += 1 }
            }
            keys.insert(finalKey)
            let tile = TileModel(key: finalKey, value: w.displayName, wordClass: w.wordClass)
            tile.isSystem = false
            modelContext.insert(tile)
            created.append(tile)
        }
        try? modelContext.save()
        onCommit(created)
        dismiss()
    }
}
