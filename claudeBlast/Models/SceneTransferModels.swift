// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneTransferModels.swift
//  claudeBlast
//
//  Codable structs for the scene exchange format.
//  Media type: application/vnd.claudeblast.scene+json
//  File extension: .blasterscene
//

import Foundation
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreTransferable

// MARK: - UTType

extension UTType {
    static let blasterScene = UTType(
        exportedAs: "com.claudeblast.scene",
        conformingTo: .json
    )

    static let blasterPack = UTType(
        exportedAs: "com.claudeblast.pack",
        conformingTo: .json
    )
}

// MARK: - Exchange format constants

enum BlasterSceneFormat {
    static let mediaType = "application/vnd.claudeblast.scene+json"
    static let currentVersion = "1.0.0"
    static let fileExtension = "blasterscene"
    /// Max decoded image data size in bytes (600 KB).
    static let maxImageDataSize = 600 * 1024
    /// Max image dimension for export (pixels).
    static let maxImageDimension: CGFloat = 512
}

/// The exchange format for a **pack** — a named word list with its art.
///
/// A pack is not a small scene, and the distinction is about what happens on
/// arrival rather than what is in the file. Importing a scene creates a scene:
/// a board the child can use, laid out as its author arranged it. Importing a
/// pack adds *words* to the recipient's vocabulary and creates nothing — they
/// build a page from it later, whenever they want, via the same pickers that
/// already serve the bundled packs.
///
/// That is why sharing a page produces a pack. A page's layout is meaningful
/// inside its own scene, where its links point at sibling pages; lifted out, the
/// links dangle and the arrangement is just one caregiver's taste. The words and
/// their art are the part worth carrying.
enum BlasterPackFormat {
    static let mediaType = "application/vnd.claudeblast.pack+json"
    static let currentVersion = "1.0.0"
    static let fileExtension = "blasterpack"
}

/// The file formats Blaster opens.
///
/// One list, because there are three places that have to agree — the
/// `CFBundleDocumentTypes` in Info.plist, the `onOpenURL` guard, and the
/// `fileImporter`'s content types — and when the pack format was added the guard
/// was missed. A file then arrived, launched the app, and vanished: no sheet, no
/// error, nothing to explain it. Adding a format means adding it here.
enum BlasterFileFormat {
    static let openableExtensions: Set<String> = [
        BlasterSceneFormat.fileExtension,
        BlasterPackFormat.fileExtension,
    ]

    static func canOpen(_ url: URL) -> Bool {
        openableExtensions.contains(url.pathExtension.lowercased())
    }
}

// MARK: - Codable structs

/// One set's canonical art for a custom word, base64-encoded.
///
/// The bytes are whatever the author stored — HEIC for bundled-style art, PNG
/// for AI-generated — copied **verbatim**. Re-encoding here is what made exports
/// enormous, and there is nothing to gain: both ends are Blaster.
struct ExportableTileArt: Codable {
    /// `ImageSetID.rawValue`. Kept as a raw string, never resolved against the
    /// catalog, so art for a set this build has never heard of survives the round
    /// trip instead of being re-filed under the default set. Same reasoning as
    /// `TileArtVariant.imageSet`.
    let imageSet: String
    let imageData: String
}

struct ExportableTile: Codable {
    let key: String
    let wordClass: String
    let displayName: String
    /// The removable camera-photo override — set-independent, and it sits on top
    /// of every image set. This is what `imageData` has always meant; art for a
    /// *set* goes in `art`, never here.
    var imageData: String?
    /// Canonical per-style art, one entry per set the author holds art for.
    ///
    /// Added after the scalar field, and optional, so the format stays compatible
    /// both directions: an older build reads the photo override and ignores this,
    /// and a file written by an older build simply has no entries.
    var art: [ExportableTileArt]?

    enum CodingKeys: String, CodingKey {
        case key, wordClass, displayName, imageData, art
    }
}

struct ExportablePageTile: Codable {
    let key: String
    let isAudible: Bool
    let link: String
}

struct ExportablePage: Codable {
    let key: String
    let tiles: [ExportablePageTile]
}

struct ExportableScene: Codable {
    let type: String
    var comment: String? = "This is a Blaster AAC scene file. Tap the share icon and choose \"Blaster\" to import."
    let version: String
    let name: String
    let description: String
    let homePageKey: String
    /// Decentralized scene identity — travels with the file so file-based
    /// sharing needs no registry. Optional for back-compat with pre-identity
    /// exports (import falls back to name).
    var id: String? = nil
    var slug: String? = nil
    /// Scene content version (distinct from the envelope `version` = file format).
    var sceneVersion: String? = nil
    /// The author's self-asserted display name ("by Greta"). May be absent.
    var authorName: String? = nil
    var tiles: [ExportableTile]?
    let pages: [ExportablePage]

    enum CodingKeys: String, CodingKey {
        case type = "@type"
        case comment = "_comment"
        case version, name, description, homePageKey
        case id, slug, sceneVersion, authorName
        case tiles, pages
    }
}

/// A word inside a portable pack. Mirrors `VocabPackWord` (the bundled form)
/// plus the art a bundled pack gets from the app binary instead.
struct ExportablePackWord: Codable {
    let key: String
    let wordClass: String
    let displayName: String
    /// Canonical per-style art. Empty for a system word: the recipient already
    /// ships it, in every set.
    var art: [ExportableTileArt]?
    /// The camera-photo override, if the author set one.
    var imageData: String?
}

struct ExportablePack: Codable {
    let type: String
    var comment: String? = "This is a Blaster AAC vocabulary pack. Tap the share icon and choose \"Blaster\" to add these words."
    let version: String
    /// Namespaced pack id, matching the bundled packs' convention
    /// ("packs.blasterai.app/space" → "greta.example/dinner-words").
    let id: String
    let slug: String
    let displayName: String
    /// Pack content version, distinct from the envelope `version`.
    let packVersion: String
    var authorName: String?
    /// Where this pack came from, for the caregiver's benefit: the scene and
    /// page it was lifted out of. Descriptive only — nothing resolves it.
    var sourceScene: String?
    var sourcePage: String?
    /// Words in the order the author had them on the page. A pack has no layout,
    /// but order is the one part of the arrangement that survives lifting the
    /// words out, and the bundled packs are ordered too.
    let words: [ExportablePackWord]

    enum CodingKeys: String, CodingKey {
        case type = "@type"
        case comment = "_comment"
        case version, id, slug, displayName, packVersion, authorName
        case sourceScene, sourcePage, words
    }
}

// MARK: - Transferable file wrapper for ShareLink

struct BlasterSceneFile: Identifiable, Transferable {
    let id = UUID()
    let data: Data
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .blasterScene) { file in
            let url = file.temporaryFileURL()
            try file.data.write(to: url)
            return SentTransferredFile(url, allowAccessingOriginalFile: true)
        }
    }

    /// Write data to a temp file and return the URL.
    func temporaryFileURL() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try? data.write(to: url)
        return url
    }
}

// MARK: - Import coordinator (shared across view hierarchy)

/// Holds a pending import URL so any active view can handle it.
/// Solves the problem of onOpenURL firing while a fullScreenCover is already presented.
@Observable
@MainActor
final class ImportCoordinator {
    var pendingURL: URL?
}

// MARK: - UIActivityViewController wrapper

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - A finished export, ready for the share sheet

/// One produced artifact on its way to the share sheet.
///
/// Every destination lands here, whatever it is — a `.blasterscene`, a
/// `.blasterpack`, a zip of PNGs, later a PDF. They arrive differently (some as
/// `Data` in memory, some as a file a zip writer already produced on disk), so
/// this holds a **URL** rather than bytes: it is the one form all of them share,
/// and the only form `UIActivityViewController` actually wants.
struct ExportedFile: Identifiable {
    let id = UUID()
    let url: URL
    /// Shown to the caregiver while choosing a destination.
    var displayName: String

    /// Write bytes to a uniquely-named temp directory and wrap the result.
    ///
    /// The per-export subdirectory matters: two shares of the same scene in one
    /// session would otherwise collide on filename, and the share sheet is
    /// asynchronous enough that the second write can land while the first is
    /// still being read.
    static func write(_ data: Data, named filename: String) throws -> ExportedFile {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try data.write(to: url)
        return ExportedFile(url: url, displayName: filename)
    }
}

/// Identifiable wrapper for presenting a URL-based import sheet.
struct ImportSheetURL: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - String helpers

extension String {
    /// Sanitize a string for use as a filename.
    var sanitizedFilename: String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_ "))
        return unicodeScalars
            .filter { allowed.contains($0) }
            .map { String($0) }
            .joined()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
    }
}
