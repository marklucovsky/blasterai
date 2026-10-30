// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardHaptics.swift
//  claudeBlast
//
//  What the board feels like under a finger.
//

import CoreHaptics
import UIKit

/// The board's haptics: a few, each meaning one thing, so a child can feel
/// where they are going as well as see it (Mark 2026-10-30: "the phone should
/// stand out as a very good device").
///
/// - A **tick** for each system-row folder that slides past, like a picker
///   wheel, so the row can be counted: *places* is so many ticks along.
/// - A **bump** going into a page, from a folder or a doorway.
/// - A **light tap** for Back, one level out.
/// - **Back's tap, held longer** for Home, all the way out — kin to Back,
///   because both go out, and longer, because Home goes all the way.
/// - A **soft rigid tap** when a screen of a long page settles.
///
/// Word taps get nothing: speech is their feedback, and a buzz on every word
/// tires fast. iPads have no haptic engine, so every call is a no-op there;
/// this is the phone's. Off with Settings → Device → Haptics, for a child who
/// finds it too much.
@MainActor
enum BoardHaptics {
    enum Event {
        case folderPassed, openPage, back, home, screenSettled
    }

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: AppSettingsKey.hapticsEnabled) as? Bool ?? true
    }

    private static let tick = UISelectionFeedbackGenerator()
    private static let bump = UIImpactFeedbackGenerator(style: .medium)
    private static let tap = UIImpactFeedbackGenerator(style: .light)
    private static let settle = UIImpactFeedbackGenerator(style: .rigid)

    /// Wake the engine before the first touch, so the first one isn't late.
    static func prepare() {
        guard isEnabled else { return }
        tick.prepare()
        bump.prepare()
        tap.prepare()
    }

    static func play(_ event: Event) {
        guard isEnabled else { return }
        switch event {
        case .folderPassed:
            tick.selectionChanged()
        case .openPage:
            bump.impactOccurred()
        case .back:
            tap.impactOccurred()
        case .home:
            // Back's tap, held longer. Two impacts 90ms apart read as a hard
            // double tap half a beat late (Mark 2026-10-30), so Home is one
            // pattern instead: Back's tap and a short tail that fades.
            if !playHomePattern() { tap.impactOccurred() }
        case .screenSettled:
            settle.impactOccurred(intensity: 0.6)
        }
    }

    private static var engine: CHHapticEngine?

    /// Home as a Core Haptics pattern: a transient like Back's tap, then a
    /// continuous tail of about a fifth of a second, fading out. False when
    /// the device can't play it (an iPad, or the engine fails to start).
    private static func playHomePattern() -> Bool {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        do {
            if engine == nil {
                let made = try CHHapticEngine()
                made.isAutoShutdownEnabled = true
                // Restart on next use if the system stops it (backgrounding).
                made.resetHandler = { Task { @MainActor in engine = nil } }
                made.stoppedHandler = { _ in Task { @MainActor in engine = nil } }
                engine = made
            }
            guard let engine else { return false }
            try engine.start()
            let tap = CHHapticEvent(eventType: .hapticTransient, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
            ], relativeTime: 0)
            let tail = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
            ], relativeTime: 0, duration: 0.2)
            let fade = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
                .init(relativeTime: 0, value: 1),
                .init(relativeTime: 0.2, value: 0),
            ], relativeTime: 0)
            let pattern = try CHHapticPattern(events: [tap, tail], parameterCurves: [fade])
            try engine.makePlayer(with: pattern).start(atTime: CHHapticTimeImmediate)
            return true
        } catch {
            engine = nil
            return false
        }
    }
}
