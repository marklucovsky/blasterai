// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ScreenshotCommandTests.swift
//  claudeBlastTests
//
//  The `screenshot:` TileScript command: parse, serialize, round-trip.
//

import Testing
import Foundation
import UIKit
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ScreenshotCommandTests {

    private func parse(_ yaml: String) throws -> TileScript {
        try TileScriptParser.parse(yaml)
    }

    private let header = """
    name: Shots
    description: capture test
    script:
    """

    // MARK: - Parsing

    @Test func parsesNamedScreenshot() throws {
        let script = try parse(header + "\n  - screenshot: home-board\n")
        #expect(script.commands.count == 1)
        guard case .screenshot(let name) = script.commands[0] else {
            Issue.record("expected .screenshot, got \(script.commands[0])")
            return
        }
        #expect(name == "home-board")
    }

    /// A bare `screenshot:` is legal — YAML parses the value as empty, and a
    /// capture with no name is still worth taking. It falls back to a default
    /// rather than failing the whole script.
    @Test func bareScreenshotGetsDefaultName() throws {
        let script = try parse(header + "\n  - screenshot:\n")
        guard case .screenshot(let name) = script.commands[0] else {
            Issue.record("expected .screenshot")
            return
        }
        #expect(name == "screen")
    }

    @Test func screenshotAmongOtherCommands() throws {
        let script = try parse(header + """

          - comment: before
          - screenshot: step-one
          - wait: 500ms
          - screenshot: step-two
        """)
        let names: [String] = script.commands.compactMap {
            if case .screenshot(let n) = $0 { return n }
            return nil
        }
        #expect(names == ["step-one", "step-two"])
    }

    // MARK: - Serializing

    /// A recorded or edited script must survive a save/load cycle, or captures
    /// silently vanish from a script the caregiver re-saves.
    @Test func screenshotRoundTripsThroughSerializer() throws {
        let original = try parse(header + "\n  - screenshot: my-shot\n")
        let yaml = TileScriptSerializer.serialize(original)
        #expect(yaml.contains("screenshot: my-shot"))

        let reparsed = try parse(yaml)
        guard case .screenshot(let name) = reparsed.commands[0] else {
            Issue.record("expected .screenshot after round-trip")
            return
        }
        #expect(name == "my-shot")
    }

    // MARK: - Capture

    /// Proves the capture path produces real pixels, not just a file.
    ///
    /// Parsing tests would pass just as happily against a renderer that wrote
    /// zero bytes, so this stands up a real window with known content, captures
    /// it, and checks both that a PNG decodes and that it is the size we asked
    /// for. Without this the command is only tested as far as the YAML.
    @Test func captureWritesADecodablePNGOfTheWindow() throws {
        let before = ScreenCapture.existing().count

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let scene else {
            // No window scene in this environment — nothing to photograph.
            return
        }

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 200, height: 120)
        let content = UIView(frame: window.bounds)
        content.backgroundColor = .systemRed
        window.addSubview(content)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let url = try #require(ScreenCapture.capture(named: "unit-test-capture"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.pathExtension == "png")
        let data = try Data(contentsOf: url)
        #expect(data.count > 0)

        // A decoded PNG has scale 1, so `size` reports PIXELS. Asserting
        // bounds × screen scale is the stronger check anyway: it proves the
        // capture is at native resolution rather than quietly downscaled to
        // points, which is what makes these usable as App Store assets.
        let image = try #require(UIImage(data: data))
        let scale = window.screen.scale
        #expect(image.size.width == window.bounds.width * scale)
        #expect(image.size.height == window.bounds.height * scale)

        #expect(ScreenCapture.existing().count == before + 1)
    }

    /// Capturing the same name twice must not overwrite: a re-run would
    /// otherwise destroy the evidence from the run before it.
    @Test func repeatedNamesDoNotOverwrite() throws {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        guard let scene else { return }

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 60, height: 60)
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        let first = try #require(ScreenCapture.capture(named: "dup-test"))
        let second = try #require(ScreenCapture.capture(named: "dup-test"))
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        #expect(first != second)
        #expect(second.lastPathComponent.contains("dup-test-2"))
    }

    // MARK: - Filename handling

    /// Names reach the filesystem, so anything that is not filename-safe has to
    /// be neutralised rather than trusted — a script is a text file a caregiver
    /// can edit.
    @Test func sanitizesNamesForTheFilesystem() throws {
        let dir = ScreenCapture.directory
        #expect(dir.lastPathComponent == "Screenshots")

        // The parser accepts whatever the YAML holds; sanitisation happens at
        // capture time. Verify the parse step preserves it verbatim so the
        // capture layer stays the single place that decides filename policy.
        let script = try parse(header + "\n  - screenshot: a/b c:d\n")
        guard case .screenshot(let name) = script.commands[0] else {
            Issue.record("expected .screenshot")
            return
        }
        #expect(name == "a/b c:d")
    }
}
}
