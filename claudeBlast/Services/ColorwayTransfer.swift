// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ColorwayTransfer.swift
//  claudeBlast
//
//  A therapist's answer for one child's vision, sent to the device that child
//  uses. Media type: application/vnd.claudeblast.colorway+json
//  File extension: .blastercolors
//

import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let blasterColorway = UTType(
        exportedAs: "com.claudeblast.colorway",
        conformingTo: .json
    )
}

enum BlasterColorwayFormat {
    static let mediaType = "application/vnd.claudeblast.colorway+json"
    static let currentVersion = "1.0.0"
    static let fileExtension = "blastercolors"
}

/// The wire form. Deliberately tiny — a name and a sparse map of overrides —
/// because that is genuinely all a colorway is. There is no art, no vocabulary
/// and no child in it.
struct ExportableColorway: Codable {
    let type: String
    var comment: String? = "This is a Blaster color set. Open it in Blaster to use it."
    let version: String
    let name: String
    /// `PartOfSpeech.rawValue` → `#RRGGBB`. Sparse: a part of speech absent here
    /// uses the Fitzgerald default, which is what "no override" means everywhere
    /// else in the app.
    let overrides: [String: String]
    /// Who sent it, when they said. Never inferred.
    var authorName: String? = nil

    enum CodingKeys: String, CodingKey {
        case type = "@type"
        case comment = "_comment"
        case version, name, overrides, authorName
    }
}

enum ColorwayTransferError: LocalizedError, Equatable {
    case invalidType(String)
    case unsupportedVersion(String)
    case decodingFailed(String)
    /// A file that names no colors at all. Applying it would silently reset the
    /// child to the defaults, which is a destructive no-op wearing the costume
    /// of an import.
    case empty

    var errorDescription: String? {
        switch self {
        case .invalidType:
            return "That isn't a Blaster color set."
        case .unsupportedVersion(let version):
            return "This color set was made by a newer version of Blaster (\(version))."
        case .decodingFailed(let detail):
            return "This color set could not be read. \(detail)"
        case .empty:
            return "This color set doesn't change any colors, so there is nothing to apply."
        }
    }
}

enum ColorwayExporter {
    static func export(_ map: TileColorMap, authorName: String = "") -> ExportableColorway {
        ExportableColorway(
            type: BlasterColorwayFormat.mediaType,
            version: BlasterColorwayFormat.currentVersion,
            name: map.name,
            overrides: map.overrides,
            authorName: authorName.isEmpty ? nil : authorName)
    }

    static func data(for map: TileColorMap, authorName: String = "") throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export(map, authorName: authorName))
    }

    /// `Colors — Warm Bias.blastercolors`. Named so a recipient holding three of
    /// them in a mail thread can tell which is which.
    static func suggestedFileName(for map: TileColorMap) -> String {
        let base = map.name.isEmpty ? "Colors" : "Colors — \(map.name)"
        return "\(base).\(BlasterColorwayFormat.fileExtension)"
            .replacingOccurrences(of: "/", with: "-")
    }
}

enum ColorwayImporter {

    struct ImportResult: Equatable {
        /// The colorway that is now in force.
        let applied: TileColorMap
        /// The name the previous colors were filed under, when they had to be
        /// rescued. Nil when there was nothing worth keeping.
        let preservedAs: String?
        /// Whose colors changed. Nil only if there is no active profile at all,
        /// which the resolver's fallback makes very unlikely.
        let appliedTo: String?
    }

    static func preview(_ data: Data) throws -> ExportableColorway {
        let incoming: ExportableColorway
        do {
            incoming = try JSONDecoder().decode(ExportableColorway.self, from: data)
        } catch {
            throw ColorwayTransferError.decodingFailed(error.localizedDescription)
        }
        guard incoming.type == BlasterColorwayFormat.mediaType else {
            throw ColorwayTransferError.invalidType(incoming.type)
        }
        guard incoming.version.hasPrefix("1.") else {
            throw ColorwayTransferError.unsupportedVersion(incoming.version)
        }
        guard !incoming.overrides.isEmpty else {
            throw ColorwayTransferError.empty
        }
        return incoming
    }

    /// Take the colors, and do not ask.
    ///
    /// A colorway arrives applied rather than filed away for later. That is the
    /// opposite of the pack rule — a pack adds words and creates nothing,
    /// because what to do with them is the caregiver's call — and the difference
    /// is who is holding the device. A therapist sending colors to a child's
    /// iPad is answering a question about that child's vision, and the person at
    /// the other end is often the one who cannot easily work the color editor.
    /// A prompt there is a way for the fix to not arrive.
    ///
    /// **What makes that safe is that nothing is lost.** The colors in force are
    /// filed into the library first if they are not already in it, so the answer
    /// to "put it back how it was" is always one tap in the profile editor
    /// rather than an apology.
    @MainActor
    @discardableResult
    static func apply(_ data: Data,
                      context: ModelContext,
                      resolver: ChildProfileResolver) throws -> ImportResult {
        let incoming = try preview(data)
        let map = TileColorMap(name: incoming.name, overrides: incoming.overrides)

        let target = resolver.active
        let current = TileColorMap.decode(target?.colorMapData ?? "")
        let preservedAs = preserveIfUnsaved(current, in: context)

        // File the incoming one too, so it can be re-applied after the caregiver
        // tries something else. Received colors that exist only on one child are
        // colors that vanish the moment someone experiments.
        ColorMapLibrary.store(uniquelyNamed(map, in: context), in: context)

        target?.colorMapData = map.encoded
        target?.modifiedAt = .now
        try? context.save()
        // Repaints the board now rather than at next launch — the resolver's
        // refresh re-reads the active profile's palette. See its `defer`.
        resolver.refresh()

        return ImportResult(applied: map,
                            preservedAs: preservedAs,
                            appliedTo: target?.displayName)
    }

    /// Rescue the colors in force, unless they are already safe.
    ///
    /// "Unsaved" means the overrides match no entry in the library — compared by
    /// *content*, not by name, because a caregiver who tweaked two colors and
    /// never pressed Save has a map whose name still matches the preset it came
    /// from while its contents no longer do. Comparing names would file it as
    /// safe and then overwrite it.
    @MainActor
    private static func preserveIfUnsaved(_ current: TileColorMap,
                                          in context: ModelContext) -> String? {
        guard !current.overrides.isEmpty else { return nil }
        let library = ColorMapLibrary.load(from: context)
        guard !library.contains(where: { $0.overrides == current.overrides }) else { return nil }

        let stamp = Date.now.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
        let base = current.name.isEmpty ? "Previous colors" : "\(current.name) (before \(stamp))"
        let rescued = uniquelyNamed(TileColorMap(name: base, overrides: current.overrides),
                                    in: context)
        ColorMapLibrary.store(rescued, in: context)
        return rescued.name
    }

    /// `ColorMapLibrary.store` replaces by name, so an incoming colorway that
    /// happens to share a name with something the caregiver already has would
    /// silently overwrite it. Suffix instead.
    @MainActor
    private static func uniquelyNamed(_ map: TileColorMap,
                                      in context: ModelContext) -> TileColorMap {
        let library = ColorMapLibrary.load(from: context)
        // An identical map under the same name is not a collision, it is the
        // same thing arriving twice.
        if library.contains(where: { $0.name == map.name && $0.overrides == map.overrides }) {
            return map
        }
        guard library.contains(where: { $0.name == map.name }) else { return map }
        var candidate = map
        var suffix = 2
        while library.contains(where: { $0.name == "\(map.name) \(suffix)" }) {
            suffix += 1
        }
        candidate.name = "\(map.name) \(suffix)"
        return candidate
    }
}
