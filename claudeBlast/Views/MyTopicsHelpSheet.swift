// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MyTopicsHelpSheet.swift
//  claudeBlast
//
//  What an empty My Topics folder opens in Setup mode.
//

import SwiftUI

/// My Topics is on every Me page, in the same cell, whether or not it holds
/// anything (`MeScene.topicsCell`). Empty, it is dimmed; in Setup mode a tap
/// says what it is for and how to fill it, instead of opening an empty page
/// (Mark, 2026-11-16). In Talk mode it does nothing.
struct MyTopicsHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("My Topics holds boards the user opens from the Me page without changing the main board: a Thanksgiving dinner board, a zoo trip, a Sunday School board.")
                    Text("It has no topics yet, so the folder is dimmed. In Talk mode it does nothing.")
                        .foregroundStyle(.secondary)
                }
                Section("Add a topic") {
                    Label("In the board editor, tap the heart in the toolbar.", systemImage: "heart")
                    Label("Or Settings › Profile › Me Page › Add a Topic.", systemImage: "gearshape")
                    Label("No board to add yet? Make one in Settings › Boards and Vocabulary, with +.",
                          systemImage: "plus.circle")
                }
                Section {
                    Text("A topic can also come forward on its own: tap it under My Topics in Me Page and choose the pages it shows for. Pressing the heart from Food can then bring up the Thanksgiving board.")
                }
            }
            .navigationTitle("My Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
