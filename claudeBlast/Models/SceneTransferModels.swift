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

// MARK: - Codable structs

struct ExportableTile: Codable {
    let key: String
    let wordClass: String
    let displayName: String
    var imageData: String?  // base64 PNG, optional

    enum CodingKeys: String, CodingKey {
        case key, wordClass, displayName, imageData
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
