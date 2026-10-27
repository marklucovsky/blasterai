// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SpeechSynthesizer.swift
//  claudeBlast
//
//  Local TTS via AVSpeechSynthesizer.
//  iOS ships with built-in voices. Enhanced and Premium voices can be
//  downloaded in Settings → Accessibility → Spoken Content → Voices
//  for significantly more natural-sounding speech. Premium voices
//  (iOS 17+) use an on-device neural model and are indistinguishable
//  from cloud TTS; Enhanced voices are a step up from the default.
//  Audio never leaves the device regardless of voice tier.
//

import AVFoundation

@Observable
@MainActor
final class SpeechSynthesizer: NSObject {
    private(set) var isSpeaking: Bool = false
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// What a word spoken on its own is read as, by tile key.
    ///
    /// A lone "I" is read as a letter: the *I* tile said "capital I", which is
    /// the first thing a demo hears (Mark, 2026-10-20 and again 2026-10-27).
    /// "i." says the word. Mark chose it by ear over the IPA "aɪ", which came
    /// out abrupt, and over "eye", which sounds the same but reads as cheating.
    ///
    /// Keyed by tile **key**, never by the text, because the letters pack's own
    /// `letter_i` tile is also "I" and its letter name is exactly right there.
    /// In a sentence the voice reads *I* correctly, so only a word spoken
    /// alone needs it.
    static let loneSpeech: [String: String] = ["i": "i."]

    /// Speak `text`. All voice attributes are optional — pass `nil` to use the
    /// `AVSpeechUtterance` defaults. The engine routes the active child's
    /// `voiceIdentifier`, `ttsRate`, and `ttsVolume` through here on every
    /// utterance so per-child prefs are honored without the synthesizer
    /// needing to know about the resolver.
    ///
    /// - Parameter key: the tile key when `text` is one tile spoken alone, so
    ///   `loneSpeech` can say it as a word.
    func speak(_ text: String,
               key: String? = nil,
               voiceIdentifier: String?,
               rate: Float? = nil,
               volume: Float? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        // .playback + .spokenAudio ensures speech is audible regardless of
        // the ringer/silent switch — critical for an AAC communication app.
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(
            .playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        let utterance = AVSpeechUtterance(string: key.flatMap { Self.loneSpeech[$0] } ?? text)
        if let id = voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }
        if let rate {
            // Clamp to the framework's documented bounds. Out-of-range
            // values throw a runtime assertion in some AVFoundation builds.
            utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate,
                                 max(AVSpeechUtteranceMinimumSpeechRate, rate))
        }
        if let volume {
            utterance.volume = min(1.0, max(0.0, volume))
        }
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

extension SpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
