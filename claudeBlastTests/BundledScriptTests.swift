// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BundledScriptTests.swift
//  claudeBlastTests
//
//  Every script we ship must parse and validate against the bundled content.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct BundledScriptTests {

    /// Scripts that ship in `Resources/Scripts/` and are expected to run against
    /// the **bundled** Core-First board. Demos that name a hand-built scene are
    /// excluded: they legitimately reference a board a fresh install doesn't have.
    private static let selfContained = [
        "shots_child_surface",
        "shots_admin",
        "shots_full",
        "shots_activity",
        "demo_basic",
        "demo_home",
        "demo_onthego",
    ]

    /// A shipped script that doesn't parse is a button that fails when a user
    /// presses it, which is exactly what happened to the screenshot script: it
    /// named the scene "Core-First" while the bundled board is called
    /// "Core-First - System Supplied".
    ///
    /// Cheap to check and it covers every script at once, so a typo in a demo
    /// can't reach a device again.
    @Test func everyBundledScriptParses() throws {
        for name in Self.selfContained {
            let url = try #require(
                Bundle.main.url(forResource: name, withExtension: "yaml"),
                "\(name).yaml is not in the bundle"
            )
            let yaml = try String(contentsOf: url, encoding: .utf8)
            #expect(throws: Never.self, "\(name).yaml failed to parse") {
                _ = try TileScriptParser.parse(yaml)
            }
        }
    }

    /// Parsing only proves the YAML is well-formed. Validation is what catches a
    /// script naming a scene, page or tile the bundled content doesn't have —
    /// the class of error that makes a script fail *after* the user starts it.
    @Test func everyBundledScriptValidatesAgainstBundledContent() throws {
        let container = TestStore.freshContainer()
        let ctx = container.mainContext
        let result = BootstrapLoader.loadDefaultVocabulary(context: ctx)

        for name in Self.selfContained {
            let url = try #require(Bundle.main.url(forResource: name, withExtension: "yaml"))
            let yaml = try String(contentsOf: url, encoding: .utf8)
            let script = try TileScriptParser.parse(yaml)
            let verdict = TileScriptValidator.validate(script, context: ctx)
            #expect(verdict.isValid,
                    "\(name).yaml does not validate: missing scene \(verdict.missingScene ?? "-"), tiles \(verdict.missingTiles), pages \(verdict.missingPages)")
        }

        withExtendedLifetime(result) {}
    }
}
}
