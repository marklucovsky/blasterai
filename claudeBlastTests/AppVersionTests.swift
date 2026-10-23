// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AppVersionTests.swift
//  claudeBlastTests
//
//  About & Stats shows the version the way TestFlight does: "0.9.0 (9)".
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct AppVersionTests {

    @Test func displayMatchesTestFlightsForm() {
        let info: [String: Any] = ["CFBundleShortVersionString": "0.9.0", "CFBundleVersion": "9"]
        #expect(AppVersion.display(info: info) == "0.9.0 (9)")
    }

    @Test func missingKeysShowAQuestionMarkNotABlank() {
        #expect(AppVersion.display(info: [:]) == "? (?)")
    }

    /// The bundle really carries both keys — a blank would mean the generated
    /// Info.plist lost them, and testers would report "? (?)".
    @Test func theAppBundleCarriesBothNumbers() {
        #expect(!AppVersion.display.contains("?"))
    }
}
}
