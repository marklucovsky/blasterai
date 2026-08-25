// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  VoicePickerSection.swift
//  claudeBlast
//
//  Shared voice picker used by Onboarding, Admin → Now, and the child
//  profile form. Lists installed English voices with premium / enhanced
//  voices first so users land on a natural-sounding default rather than
//  having to dig through the system roster.
//

import SwiftUI
import AVFoundation
#if canImport(UIKit)
import UIKit
#endif

/// Compact voice picker with auto-preview on selection change. Audio plays
/// regardless of the silent switch (we set the audio session to .playback /
/// .spokenAudio with .duckOthers) so the preview matches how speech
/// actually sounds in normal app use.
struct VoicePickerSection: View {
    @Binding var voiceIdentifier: String

    /// Spoken when the user picks a voice. Callers can personalize this
    /// ("Hi Aubrey, I'll be your voice") — onboarding and the profile form
    /// pass the child's name in; generic Admin contexts use the default.
    var previewPhrase: String = "Welcome to Blaster"

    @State private var previewSynthesizer = AVSpeechSynthesizer()

    /// English voices, sorted Premium → Enhanced → Default, alphabetical
    /// within tier. Premium / Enhanced are downloaded by the user via
    /// Settings → Accessibility → Spoken Content → Voices and sound
    /// dramatically more natural than the bundled default voice.
    private var englishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted {
                if $0.quality != $1.quality {
                    return $0.quality.sortOrder > $1.quality.sortOrder
                }
                return $0.name < $1.name
            }
    }

    private var hasHighQualityVoice: Bool {
        englishVoices.contains { $0.quality == .enhanced || $0.quality == .premium }
    }

    var body: some View {
        Picker("Voice", selection: $voiceIdentifier) {
            Text("System Default").tag("")
            ForEach(englishVoices, id: \.identifier) { voice in
                Text(label(for: voice)).tag(voice.identifier)
            }
        }
        .onChange(of: voiceIdentifier) { _, newValue in
            previewVoice(identifier: newValue)
        }

        if !hasHighQualityVoice {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enhanced and Premium voices sound much more natural.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // The path differs by machine, and a wrong path is worse than
                // none — the caregiver follows it, finds nothing, and concludes
                // the app is broken.
                Text(RuntimePlatform.spokenContentSettingsPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // openSettingsURLString deep-links to *this app's* settings
                // pane, which does not exist on Mac (Designed for iPad). Rather
                // than offer a button that silently does nothing, the Mac gets
                // the path in words and opens System Settings itself.
                if !RuntimePlatform.isMac {
                    Button("Open Settings") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                    .font(.caption)
                }
            }
            .padding(.vertical, 2)
        }
    }

    /// Tags the voice display with a quality badge so Premium / Enhanced
    /// voices are visually distinguishable in the menu picker (where the
    /// per-row sort isn't otherwise obvious).
    private func label(for voice: AVSpeechSynthesisVoice) -> String {
        switch voice.quality {
        case .premium:   return "★ \(voice.name)"
        case .enhanced:  return "◆ \(voice.name)"
        default:         return voice.name
        }
    }

    private func previewVoice(identifier: String) {
        previewSynthesizer.stopSpeaking(at: .immediate)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: previewPhrase)
        if !identifier.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        }
        previewSynthesizer.speak(utterance)
    }
}

extension AVSpeechSynthesisVoiceQuality {
    /// Premium > Enhanced > Default. Used by the sort comparator so
    /// downloaded high-quality voices float to the top of the picker.
    var sortOrder: Int {
        switch self {
        case .premium:  return 2
        case .enhanced: return 1
        default:        return 0
        }
    }
}
