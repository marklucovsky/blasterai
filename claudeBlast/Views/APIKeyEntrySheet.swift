// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftUI

/// Lightweight in-flow sheet for installing an OpenAI API key (paste + live
/// validation via the shared OpenAIKeyEntrySection). The key is written to the
/// device Keychain as it changes; on dismiss the presenting view re-reads
/// OpenAIKeyVault and flips from the "add a key" nudge to the normal
/// generate-art action.
struct APIKeyEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    /// Optional for the same reason as `GiftedKeyImportSheet`'s: sheets here do
    /// not rely on inheriting the environment.
    @Environment(SentenceEngine.self) private var sentenceEngine: SentenceEngine?
    @State private var apiKey: String = OpenAIKeyVault.currentKey() ?? ""
    /// A key is only entered with permission to use it (`AIConsent`), so the
    /// disclosure comes first on a device that has not given it.
    @State private var hasConsent = AIConsent.isGranted()

    var body: some View {
        if hasConsent {
            keyEntry
        } else {
            AIDisclosureSheet(dismissesOnAnswer: false) { accepted in
                if accepted {
                    if let sentenceEngine { sentenceEngine.grantAIConsent() } else { AIConsent.accept() }
                    hasConsent = true
                } else {
                    AIConsent.markPrompted()
                    dismiss()
                }
            }
        }
    }

    private var keyEntry: some View {
        NavigationStack {
            Form {
                Section {
                    OpenAIKeyEntrySection(apiKey: $apiKey)
                } footer: {
                    Text("Stored only on this device (Keychain). New-word art generation uses it directly — typical cost is well under a cent per image.")
                }
            }
            .navigationTitle("Add an AI Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: apiKey) { OpenAIKeyVault.setKey(apiKey) }
        }
    }
}
