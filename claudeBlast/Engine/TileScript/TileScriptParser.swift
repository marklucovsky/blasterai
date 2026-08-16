// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptParser.swift
//  claudeBlast
//

import Foundation
import Yams

/// Parses YAML text into a TileScript model.
struct TileScriptParser {

    enum ParseError: LocalizedError {
        case invalidYAML(String)
        case missingField(String)
        case invalidCommand(String)

        var errorDescription: String? {
            switch self {
            case .invalidYAML(let msg): return "Invalid YAML: \(msg)"
            case .missingField(let field): return "Missing required field: \(field)"
            case .invalidCommand(let msg): return "Invalid command: \(msg)"
            }
        }
    }

    /// Parse a YAML string into a TileScript.
    static func parse(_ yaml: String) throws -> TileScript {
        // Pre-extract line comments from tile row lines before Yams strips them.
        let lineComments = extractLineComments(from: yaml)

        guard let root = try Yams.load(yaml: yaml) as? [String: Any] else {
            throw ParseError.invalidYAML("Root must be a YAML mapping")
        }

        let name = root["name"] as? String ?? "Untitled"
        let description = root["description"] as? String ?? ""
        let audio = parseAudioValue(root["audio"]) ?? true
        let tileWait = parseTimingValue(root["tileWait"]) ?? .human
        let sentenceWait = parseTimingValue(root["sentenceWait"]) ?? .human
        let provider = root["provider"] as? String
        let scene = root["scene"] as? String
        let mode = parseInteractionMode(root["mode"])

        guard let scriptArray = root["script"] as? [[String: Any]] else {
            throw ParseError.missingField("script")
        }

        let commands = try scriptArray.flatMap { try parseCommand($0, lineComments: lineComments) }

        return TileScript(
            name: name,
            description: description,
            audio: audio,
            tileWait: tileWait,
            sentenceWait: sentenceWait,
            provider: provider,
            scene: scene,
            mode: mode,
            commands: commands
        )
    }

    /// Parse a `tileSet:` value (`classic` / `playful` / `high-contrast`).
    ///
    /// A script naming `arasaac` now returns nil, as any unknown set does. That
    /// set was removed and no compatibility mapping is provided — pre-pilot,
    /// a stale reference is a delete-and-reinstall, not a shim to carry forward.
    static func parseImageSet(_ value: Any?) -> ImageSetID? {
        guard let raw = (value as? String)?
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespaces) else { return nil }
        switch raw {
        case "classic": return .classic
        case "playful3d", "playful", "p3d", "3d": return .playful3D
        case "highcontrast", "hc": return .highContrast
        default: return ImageSetID(rawValue: raw)
        }
    }

    /// Parse a `mode:` header value (`sentence` / `single-word` / `singleWord`).
    static func parseInteractionMode(_ value: Any?) -> InteractionMode? {
        guard let raw = (value as? String)?
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespaces) else { return nil }
        switch raw {
        case "sentence": return .sentence
        case "singleword", "word", "classic": return .singleWord
        default: return nil
        }
    }

    // MARK: - Line Comment Extraction

    /// Scan raw YAML lines for trailing `# comment` on tile row entries.
    /// Returns a dictionary mapping the stripped tile content → comment text.
    /// e.g. "<home>, mom, <food>, pizza" → "requesting pizza from mom"
    private static func extractLineComments(from yaml: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Match YAML list items: "- <content>  # comment"
            guard trimmed.hasPrefix("- ") else { continue }
            let afterDash = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            // Skip structured entries (tiles:, comment:, etc.)
            if afterDash.contains(":") && !afterDash.hasPrefix("<") { continue }

            // Find trailing comment: look for ` #` or `  #` (space before hash)
            // but not inside angle brackets
            if let commentRange = findTrailingComment(in: afterDash) {
                let content = String(afterDash[afterDash.startIndex..<commentRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                let comment = String(afterDash[commentRange.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
                if !content.isEmpty && !comment.isEmpty {
                    result[content] = comment
                }
            }
        }
        return result
    }

    /// Find the range of ` #` that starts a trailing comment (not inside the value).
    private static func findTrailingComment(in str: String) -> Range<String.Index>? {
        // Search for " #" pattern — the space before # distinguishes comment from content
        var searchStart = str.startIndex
        while let range = str.range(of: " #", range: searchStart..<str.endIndex) {
            // Make sure this isn't inside angle brackets
            let prefix = str[str.startIndex..<range.lowerBound]
            let openCount = prefix.filter({ $0 == "<" }).count
            let closeCount = prefix.filter({ $0 == ">" }).count
            if openCount == closeCount {
                return range
            }
            searchStart = range.upperBound
        }
        return nil
    }

    // MARK: - Command Parsing

    private static func parseCommand(_ dict: [String: Any], lineComments: [String: String]) throws -> [TileScriptCommand] {
        if let tilesValue = dict["tiles"] {
            return try [parseTilesCommand(tilesValue, lineComments: lineComments)]
        }
        if let comment = dict["comment"] as? String {
            return [.comment(text: comment)]
        }
        if let waitValue = dict["wait"] {
            let duration = parseDurationString(waitValue)
            return [.wait(duration: duration)]
        }
        if dict["clear"] != nil {
            return [.clear]
        }
        if let audioValue = dict["audio"] {
            if let enabled = parseAudioValue(audioValue) {
                return [.setAudio(enabled: enabled)]
            }
        }
        if let twValue = dict["tileWait"] {
            if let tv = parseTimingValue(twValue) {
                return [.setTileWait(value: tv)]
            }
        }
        if let swValue = dict["sentenceWait"] {
            if let tv = parseTimingValue(swValue) {
                return [.setSentenceWait(value: tv)]
            }
        }
        if let providerName = dict["provider"] as? String {
            return [.setProvider(name: providerName)]
        }
        if let sceneName = dict["scene"] as? String {
            return [.setScene(name: sceneName)]
        }
        if let tileSetValue = dict["tileSet"] ?? dict["tileset"], let set = parseImageSet(tileSetValue) {
            return [.setTileSet(imageSet: set)]
        }

        throw ParseError.invalidCommand("Unrecognized command: \(dict.keys.joined(separator: ", "))")
    }

    private static func parseTilesCommand(_ value: Any, lineComments: [String: String]) throws -> TileScriptCommand {
        // Bulk spec: {count: N, source: ..., length: "2-4"}
        if let dict = value as? [String: Any], dict["count"] != nil {
            let count = dict["count"] as? Int ?? 100
            let sourceStr = dict["source"] as? String ?? "random"
            let source = BulkTileSpec.BulkSource(rawValue: sourceStr) ?? .random
            let lengthStr = dict["length"] as? String ?? "2-4"
            let (minLen, maxLen) = parseLengthRange(lengthStr)
            return .bulkTiles(spec: BulkTileSpec(count: count, source: source, minLength: minLen, maxLength: maxLen))
        }

        // Row array: list of strings
        if let rows = value as? [String] {
            let tileRows = rows.map { parseTileRow($0, lineComments: lineComments) }
            return .tiles(rows: tileRows)
        }

        // Single string
        if let single = value as? String {
            return .tiles(rows: [parseTileRow(single, lineComments: lineComments)])
        }

        throw ParseError.invalidCommand("tiles value must be a list of strings or a bulk spec")
    }

    /// Parse a single tile row string.
    ///
    /// Supported token forms:
    /// - `tile_key`                    → `.tap(tileKey:)`
    /// - `<page_key>`                  → `.navigate(pageKey:)`
    /// - `<page_key isAudible=t/>`     → `.audibleNavigate(pageKey:)` (tile-add + nav in one)
    /// - `<tilescript:replay>`         → `.replay` (standalone control row)
    /// - `<tilescript:noclose>`        → `.noclose` (suppresses auto-Done at row end)
    static func parseTileRow(_ row: String, lineComments: [String: String] = [:]) -> TileRow {
        let rawText = row.trimmingCharacters(in: .whitespaces)
        let comment = lineComments[rawText]

        // A trailing "+" is shorthand for <tilescript:noclose>: Play the row but
        // don't Done it, so the next row extends the same tray (single-word: keep
        // the strip). Look up the comment on the full text first, then strip it.
        var body = rawText
        var noclose = false
        if body.hasSuffix("+") {
            noclose = true
            body = String(body.dropLast()).trimmingCharacters(in: .whitespaces)
            if body.hasSuffix(",") { body = String(body.dropLast()).trimmingCharacters(in: .whitespaces) }
        }

        let parts = body.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var actions: [TileAction] = parts.compactMap { part in
            guard !part.isEmpty else { return nil }
            if part.hasPrefix("<") && part.hasSuffix(">") {
                return parseAngleToken(part)
            }
            return .tap(tileKey: part)
        }
        if noclose { actions.append(.noclose) }
        return TileRow(actions: actions, rawText: rawText, comment: comment)
    }

    /// Parse a `<...>` token. Inner content may include attributes (e.g. `<drinks isAudible=t/>`).
    /// Trailing `/` is treated as a self-closing marker and stripped.
    private static func parseAngleToken(_ token: String) -> TileAction? {
        var inner = String(token.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        if inner.hasSuffix("/") {
            inner = String(inner.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        guard !inner.isEmpty else { return nil }

        // Control tokens (no attributes).
        if inner == "tilescript:replay" { return .replay }
        if inner == "tilescript:noclose" { return .noclose }

        // Otherwise: page key plus optional attributes.
        let pieces = inner.split(separator: " ", omittingEmptySubsequences: true).map { String($0) }
        guard let pageKey = pieces.first else { return nil }

        var isAudible = false
        for attr in pieces.dropFirst() {
            if let value = attributeValue(attr, name: "isaudible"), isTrueValue(value) {
                isAudible = true
            }
        }
        return isAudible ? .audibleNavigate(pageKey: pageKey) : .navigate(pageKey: pageKey)
    }

    /// Pull `value` out of `name=value` (case-insensitive on the name). Strips surrounding
    /// single or double quotes from the value.
    private static func attributeValue(_ token: String, name: String) -> String? {
        guard let eqIndex = token.firstIndex(of: "=") else { return nil }
        let key = token[..<eqIndex].lowercased()
        guard key == name else { return nil }
        var value = String(token[token.index(after: eqIndex)...])
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")),
            value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func isTrueValue(_ value: String) -> Bool {
        switch value.lowercased() {
        case "t", "true", "yes", "1", "on": return true
        default: return false
        }
    }

    // MARK: - Value Parsing

    private static func parseAudioValue(_ value: Any?) -> Bool? {
        if let str = value as? String {
            return str.lowercased() == "on" || str.lowercased() == "true"
        }
        if let bool = value as? Bool { return bool }
        return nil
    }

    static func parseTimingValue(_ value: Any?) -> TimingValue? {
        guard let str = value as? String else { return nil }
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        switch trimmed {
        case ".human", "human": return .human
        case ".fast", "fast": return .fast
        case ".instant", "instant": return .instant
        default:
            if let ms = parseDurationToMs(trimmed) {
                return .explicit(milliseconds: ms)
            }
            return nil
        }
    }

    private static func parseDurationToMs(_ str: String) -> Int? {
        if str.hasSuffix("ms"), let val = Int(str.dropLast(2)) {
            return val
        }
        if str.hasSuffix("s"), let val = Double(str.dropLast(1)) {
            return Int(val * 1000)
        }
        return nil
    }

    private static func parseDurationString(_ value: Any) -> Duration {
        if let str = value as? String {
            if let ms = parseDurationToMs(str) {
                return .milliseconds(ms)
            }
        }
        if let secs = value as? Int {
            return .seconds(secs)
        }
        if let secs = value as? Double {
            return .milliseconds(Int(secs * 1000))
        }
        return .seconds(1)
    }

    private static func parseLengthRange(_ str: String) -> (Int, Int) {
        let parts = str.split(separator: "-")
        if parts.count == 2, let lo = Int(parts[0]), let hi = Int(parts[1]) {
            return (lo, hi)
        }
        if let single = Int(str) {
            return (single, single)
        }
        return (2, 4)
    }
}
