// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ScreenCapture.swift
//  claudeBlast
//
//  Capture the app's own window to a PNG, on demand, from inside the app.
//

import Foundation
import UIKit
import os

/// Writes a PNG of the app's current window to a known directory.
///
/// ## Why capture from inside the app
///
/// `xcrun simctl io … screenshot` can photograph a simulator at any moment, but
/// it cannot know *when* the app has reached the state worth photographing. The
/// interesting states here — a sentence mid-generation, an overlay up, a board
/// scrolled to page 3 — last a few hundred milliseconds and are reached by
/// script. Capturing from inside means the script decides the moment.
///
/// It also works on a **real device**, which matters beyond testing: App Store
/// assets have to come from real hardware, and the same script that verifies a
/// layout can produce the picture of it.
///
/// ## Where the files go
///
/// `Documents/Screenshots/`, which is reachable three ways: on a simulator by
/// path, on a device through the Files app (the target declares
/// `UIFileSharingEnabled`), and in either case through a share sheet.
enum ScreenCapture {

    private static let logger = Logger(subsystem: "com.blaster.app", category: "ScreenCapture")

    /// Directory holding captures. Created on first use.
    static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Screenshots", isDirectory: true)
    }

    /// Capture the key window and write it as a PNG.
    ///
    /// - Parameter name: base filename. Sanitized, and suffixed with a counter
    ///   when a script captures the same name twice, so a re-run never silently
    ///   overwrites the evidence from the run before it.
    /// - Returns: the file URL, or nil if there was no window to capture.
    @MainActor
    @discardableResult
    static func capture(named name: String) -> URL? {
        guard let window = keyWindow else {
            logger.error("capture(\(name, privacy: .public)): no key window")
            return nil
        }

        // drawHierarchy(afterScreenUpdates:) rather than layer.render(in:):
        // the latter misses visual effects — blur, materials, and anything
        // presented in a separate window such as popovers — which is most of
        // what these captures exist to show.
        let format = UIGraphicsImageRendererFormat()
        format.scale = window.screen.scale
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds, format: format)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }

        guard let data = image.pngData() else {
            logger.error("capture(\(name, privacy: .public)): PNG encode failed")
            return nil
        }

        do {
            try FileManager.default.createDirectory(at: directory,
                                                    withIntermediateDirectories: true)
            let url = uniqueURL(for: name)
            try data.write(to: url, options: .atomic)
            logger.info("captured \(url.lastPathComponent, privacy: .public)")
            return url
        } catch {
            logger.error("capture(\(name, privacy: .public)) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Everything currently in the capture directory, newest first.
    static func existing() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return urls.sorted {
            let l = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let r = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return l > r
        }
    }

    /// Delete every capture. Wired to a button in Admin so a screenshot run can
    /// start from a clean directory.
    @discardableResult
    static func deleteAll() -> Int {
        let urls = existing()
        for url in urls { try? FileManager.default.removeItem(at: url) }
        return urls.count
    }

    // MARK: - Helpers

    @MainActor
    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// `name.png`, or `name-2.png`, `name-3.png` … if that is taken.
    private static func uniqueURL(for name: String) -> URL {
        let base = sanitize(name)
        var candidate = directory.appendingPathComponent("\(base).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base)-\(counter).png")
            counter += 1
        }
        return candidate
    }

    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let cleaned = name.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return cleaned.isEmpty ? "screenshot" : cleaned
    }
}
