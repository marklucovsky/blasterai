// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  StageHelp.swift
//  claudeBlast
//
//  The help that sits under a Brown's Stage picker, in one place.
//
//  There are three stage pickers — onboarding, Admin → Now, and the child
//  profile editor — and each had grown its own explanation. One named the
//  scale, one didn't; one described what the app does in a hand-written
//  sentence that disagreed with `BrownsStage.appBehavior`; none of them
//  mentioned that two of the three stages need an OpenAI key. A caregiver who
//  meets the same control twice should not be told two different things about
//  it.
//

import SwiftUI

/// Help shown directly beneath a stage picker.
///
/// Three lines, in the order a reader needs them: what the scale is, where the
/// child is, and what the app will therefore do. The key note appears only when
/// it applies — the chosen stage needs a key and none is stored.
struct StageIntro: View {
    let stage: BrownsStage

    /// Where this reader would go to supply a key, phrased for the surface
    /// they are on. `nil` omits the note entirely.
    var keyHint: String?

    /// The scale's name. Shown once per screen — a picker that already sits
    /// under a "Stage" section header does not need it repeated.
    var namesTheScale: Bool = true

    private var needsKeyNote: Bool {
        stage.requiresAPIKey && keyHint != nil && OpenAIKeyVault.currentKey() == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if namesTheScale {
                Text("Brown's Stages, the standard scale for early language.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(stage.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            // What the choice switches on, kept visually apart from the
            // description of the child so the two are not read as one sentence.
            Label {
                Text(stage.appBehavior)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: stage.requiresAPIKey ? "sparkles" : "speaker.wave.2.fill")
                    .foregroundStyle(.blue)
            }

            if needsKeyNote, let hint = keyHint {
                Label {
                    Text("Sentences are built by AI. \(hint) Without a key they come back as placeholder text.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The full three-stage comparison, collapsed.
///
/// Belongs where someone is deciding rather than adjusting: onboarding and the
/// profile editor. Admin → Now is a switch someone flips who has already made
/// this decision, so it carries the intro alone.
struct StageGuide: View {
    var body: some View {
        DisclosureGroup("Not sure which to pick?") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(BrownsStage.allCases) { stage in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.label)
                            .font(.caption.weight(.semibold))
                        Text(stage.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(stage.appBehavior)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                Text("If you are unsure, start at Stage I. It is the simplest to use, works without a key, and moving up later takes one tap.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        }
        .font(.caption)
    }
}

#Preview("Stage I") {
    Form {
        Section("Stage") {
            StageIntro(stage: .one, keyHint: "You'll add one next.")
            StageGuide()
        }
    }
}

#Preview("Stage II-III") {
    Form {
        Section("Stage") {
            StageIntro(stage: .twoThree, keyHint: "Add one in Admin → Device.")
            StageGuide()
        }
    }
}
