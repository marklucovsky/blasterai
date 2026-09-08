// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ColorwayImportSheet.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

/// Colors arriving from a therapist.
///
/// Unlike the scene and pack sheets, this one has no preview step and no
/// confirm button: the colorway is applied as the sheet opens. The person at the
/// other end is frequently a parent who cannot easily work the color editor, and
/// a confirmation is a way for the fix to not arrive. What makes that safe is
/// that the previous colors are filed into the library first — see
/// `ColorwayImporter.apply`.
struct ColorwayImportSheet: View {
    let url: URL
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(ChildProfileResolver.self) private var profileResolver

    @State private var result: ColorwayImporter.ImportResult?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if let error {
                    ContentUnavailableView("Couldn't Use These Colors",
                                           systemImage: "exclamationmark.triangle",
                                           description: Text(error))
                } else if let result {
                    applied(result)
                } else {
                    ProgressView("Applying colors…")
                }
            }
            .navigationTitle("Colors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .task { apply() }
    }

    @ViewBuilder
    private func applied(_ result: ColorwayImporter.ImportResult) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("\(result.applied.name.isEmpty ? "These colors" : result.applied.name) is now in use",
                          systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.headline)
                    if let who = result.appliedTo {
                        Text("Applied to \(who). The board is already using it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                ForEach(PartOfSpeech.display) { pos in
                    if let color = result.applied.color(for: pos) {
                        HStack {
                            Text(pos.label)
                            Spacer()
                            Circle()
                                .fill(color)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(0.18),
                                                               lineWidth: 0.5))
                                .frame(width: 24, height: 24)
                        }
                    }
                }
            } header: {
                Text("What changed")
            } footer: {
                Text("Anything not listed keeps its usual color.")
            }

            // The undo, stated plainly and by name. "Your old colors are safe"
            // is only reassuring if it says where they are.
            if let preserved = result.preservedAs {
                Section {
                    Text("The colors that were in use have been saved as “\(preserved)”.")
                        .font(.callout)
                } footer: {
                    Text("Admin → Profiles → edit the profile → Colors → Start From… to go back to them, or to any other set you have saved.")
                }
            }
        }
    }

    private func apply() {
        guard result == nil, error == nil else { return }
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            result = try ColorwayImporter.apply(data,
                                                context: modelContext,
                                                resolver: profileResolver)
        } catch {
            self.error = error.localizedDescription
        }
    }
}
