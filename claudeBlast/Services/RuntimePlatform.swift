// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  RuntimePlatform.swift
//  claudeBlast
//
//  Where this build is actually running, as opposed to what it was compiled for.
//

import Foundation

/// Which machine the app is running on right now.
///
/// ## Why a runtime check, not `#if`
///
/// The app supports **Mac (Designed for iPad)**, which is the *same iOS binary*
/// running on Apple Silicon. Compile-time platform checks cannot see the
/// difference — `#if os(iOS)` is true on the Mac too — so anything that must
/// differ there has to be decided at runtime.
///
/// The cases that matter are ones where the app tells the user to go somewhere:
/// a Settings path, a gesture, a piece of hardware. Those instructions are
/// wrong on a Mac, and wrong instructions are worse than none, because the
/// caregiver follows them and concludes the app is broken when they don't work.
enum RuntimePlatform {

    /// True when this iOS build is running on a Mac (Designed for iPad).
    ///
    /// `isiOSAppOnMac` is the supported way to ask; it is false in the iOS
    /// Simulator running on a Mac, which is correct — the simulator behaves
    /// like the device it simulates.
    static var isMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }

    /// Where the user changes system voices, phrased for the machine they are
    /// actually on. Both paths lead to the same iOS/macOS speech-voice store.
    static var spokenContentSettingsPath: String {
        isMac
            ? "System Settings → Accessibility → Spoken Content → System Voice"
            : "Settings → Accessibility → Spoken Content → Voices"
    }
}
