// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky

import SwiftUI

/// What is sent to OpenAI, and what is not — the text a caregiver accepts.
///
/// **This is version `AIConsent.currentVersion` of the disclosure.** Changing
/// what it says means raising that version and appending to its history, so
/// every device is asked again. Editing the words in place would leave devices
/// holding permission for a disclosure nobody showed them.
///
/// The content alone, without buttons, so onboarding can put it on a step and
/// drive the answer from its own navigation bar. Everywhere else uses
/// `AIDisclosureSheet`.
struct AIDisclosureContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Enable AI Features")
                .font(.title.bold())
            Text("BlasterAI can use OpenAI to provide optional AI features:")
                .font(.body)
            VStack(alignment: .leading, spacing: 12) {
                feature("text.bubble.fill", .blue,
                        "Sentence Generation",
                        "selected vocabulary words are sent to OpenAI to create a natural sentence.")
                feature("photo.fill", .orange,
                        "Vocabulary Images",
                        "a vocabulary word or description is sent to OpenAI to generate an image.")
                feature("square.grid.3x3.fill", .green,
                        "Scene Generation",
                        "a description of a situation, such as “field trip to a farm,” is sent to OpenAI to suggest relevant vocabulary.")
            }
            Label {
                Text("BlasterAI does not send your name, device identifiers, or other identifying information to OpenAI.")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "lock.shield.fill").foregroundStyle(.green)
            }
            Text("Without AI features, BlasterAI is a complete word board: each tile speaks its word. You can change this any time in Admin → Device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func feature(_ symbol: String, _ tint: Color,
                         _ title: String, _ detail: String) -> some View {
        Label {
            Text("\(Text(title).bold()) — \(detail)")
                .font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(tint)
        }
    }
}

/// The disclosure with its two answers, for every place that is not onboarding:
/// Admin → Device, opening a key file, and the one-time ask when a device holds
/// a key it has no permission to use.
///
/// Reports the answer and records nothing itself — the caller owns what an
/// answer means there (usually `SentenceEngine.grantAIConsent`).
struct AIDisclosureSheet: View {
    @Environment(\.dismiss) private var dismiss
    /// False when this is the *content* of a sheet rather than the sheet — as in
    /// `APIKeyEntrySheet`, where Enable must lead on to key entry instead of
    /// closing everything.
    var dismissesOnAnswer = true
    let onAnswer: (_ accepted: Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                AIDisclosureContent()
                    .padding()
                    .frame(maxWidth: 600, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Not now") { answer(false) }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Enable") { answer(true) }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(.bar)
            }
        }
        // An answer is required; swiping it away would be neither.
        .interactiveDismissDisabled()
    }

    private func answer(_ accepted: Bool) {
        onAnswer(accepted)
        if dismissesOnAnswer { dismiss() }
    }
}

#Preview {
    AIDisclosureSheet { _ in }
}

/// Asks once per disclosure version, on a device holding a key it has no
/// permission to use.
///
/// That is every tester's device the first time a build with `AIConsent` runs:
/// their key predates the disclosure, so it went dormant. Rather than leave
/// them to discover a switched-off toggle, they are shown the disclosure once.
/// "Not now" is an answer and is not asked again until the version changes.
///
/// Applied to the caregiver board and to Admin — never the child's board on a
/// Patient device, where the child would be the one looking at it.
struct AIConsentPrompt: ViewModifier {
    let isEnabled: Bool
    @Environment(SentenceEngine.self) private var sentenceEngine
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .task(id: isEnabled) {
                guard isEnabled,
                      AIConsent.shouldPrompt(hasKey: OpenAIKeyVault.currentKey() != nil)
                else { return }
                isPresented = true
            }
            .sheet(isPresented: $isPresented) {
                AIDisclosureSheet { accepted in
                    AIConsent.markPrompted()
                    if accepted { sentenceEngine.grantAIConsent() }
                }
            }
    }
}
