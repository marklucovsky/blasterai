// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileImageExporter.swift
//  claudeBlast
//
//  Export tile art as ordinary image files, for a caregiver who wants the
//  pictures themselves.
//

import Foundation
import UIKit

/// Zip a directory using the system's own archiver.
///
/// `NSFileCoordinator` with `.forUploading` is the only zip writer in the SDK,
/// and it exists because AirDrop and the share sheet need one. Reaching for a
/// third-party library here would add a dependency to produce a file format the
/// OS already produces — and this same writer is what OBZ export will need,
/// since an `.obz` is a zip with a manifest.
enum ZipWriter {

    enum ZipError: LocalizedError {
        case coordinationFailed(String)

        var errorDescription: String? {
            switch self {
            case .coordinationFailed(let detail): return "Could not create archive: \(detail)"
            }
        }
    }

    /// Archive `directory` and return a URL to the resulting `.zip`.
    ///
    /// The coordinator hands its archive to the block and deletes it on return,
    /// so the bytes are copied somewhere durable before that happens — a URL
    /// captured out of the block points at nothing by the time the share sheet
    /// reads it.
    static func zip(_ directory: URL, named filename: String) throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("zip-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(filename)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)

        var coordinatorError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: directory,
                                       options: [.forUploading],
                                       error: &coordinatorError) { archive in
            do { try FileManager.default.copyItem(at: archive, to: destination) }
            catch { copyError = error }
        }
        if let coordinatorError { throw ZipError.coordinationFailed(coordinatorError.localizedDescription) }
        if let copyError { throw copyError }
        return destination
    }
}

/// Which image sets an export renders.
enum ExportSetScope: String, CaseIterable, Identifiable {
    /// Just what the child is looking at right now.
    case activeSet
    /// Every installed set, so the caregiver can pick a style later — or print
    /// one board in High Contrast and another in Playful-3D.
    case allSets

    var id: String { rawValue }

    var label: String {
        switch self {
        case .activeSet: return "Current style only"
        case .allSets: return "All styles"
        }
    }
}

@MainActor
enum TileImageExporter {

    /// Render tiles to PNG files and archive them.
    ///
    /// **This is the one export that produces PNG.** Everything Blaster→Blaster
    /// ships the stored bytes untouched, because both ends are Blaster and HEIC
    /// is smaller. Here the artifact *is* the images, headed for a printer, a
    /// laminator, or some other app's import — so it has to be a format anything
    /// can open.
    ///
    /// - Parameters:
    ///   - keys: tile keys, in the order the caller wants them. Duplicates are
    ///     collapsed; a key with no art anywhere is skipped.
    ///   - scope: one style, or every installed style.
    ///   - basename: names the archive and its root folder.
    static func exportZip(keys: [String],
                          scope: ExportSetScope,
                          resolver: TileImageResolver,
                          basename: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tiles-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(basename, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sets: [ImageSetID] = switch scope {
        case .activeSet: [resolver.activeSet]
        case .allSets: ExportArtResolver.allInstalledSets
        }

        var seen = Set<String>()
        let orderedKeys = keys.filter { seen.insert($0).inserted }

        for set in sets {
            // One style flattens to the archive root; several need a folder each,
            // or the same key would overwrite itself set after set.
            let directory: URL = sets.count == 1
                ? root
                : root.appendingPathComponent(set.rawValue, isDirectory: true)
            if directory != root {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            for key in orderedKeys {
                guard let png = ExportArtResolver.renderedPNG(key, in: set, resolver: resolver) else { continue }
                try png.write(to: directory.appendingPathComponent("\(key).png"))
            }
        }

        return try ZipWriter.zip(root, named: "\(basename)-tiles.zip")
    }
}
