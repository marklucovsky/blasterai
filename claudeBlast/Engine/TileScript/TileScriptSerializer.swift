// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileScriptSerializer.swift
//  claudeBlast
//

import Foundation

/// Converts a TileScript into its YAML string representation.
/// Inverse of TileScriptParser — output is compatible with the parser.
struct TileScriptSerializer {

    static func serialize(_ script: TileScript) -> String {
        var lines: [String] = []

        lines.append("name: \(script.name)")
        if !script.description.isEmpty {
            lines.append("description: \(script.description)")
        }
        lines.append("audio: \(script.audio ? "on" : "off")")
        lines.append("tileWait: \(formatTiming(script.tileWait))")
        lines.append("sentenceWait: \(formatTiming(script.sentenceWait))")
        if let provider = script.provider {
            lines.append("provider: \(provider)")
        }
        if let scene = script.scene {
            lines.append("scene: \(scene)")
        }

        lines.append("")
        lines.append("script:")

        for command in script.commands {
            lines.append(contentsOf: serializeCommand(command))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Command Serialization

    private static func serializeCommand(_ command: TileScriptCommand) -> [String] {
        switch command {
        case .tiles(let rows):
            var lines = ["  - tiles:"]
            for row in rows {
                let tokens = formatRow(row)
                lines.append("    - \(tokens)")
            }
            return lines

        case .bulkTiles(let spec):
            return [
                "  - tiles:",
                "      count: \(spec.count)",
                "      source: \(spec.source.rawValue)",
                "      length: \"\(spec.minLength)-\(spec.maxLength)\""
            ]

        case .clear:
            return ["  - clear:"]

        case .comment(let text):
            return ["  - comment: \(text)"]

        case .screenshot(let name):
            return ["  - screenshot: \(name)"]

        case .wait(let duration):
            let ms = Int(duration.components.seconds * 1000)
                + Int(duration.components.attoseconds / 1_000_000_000_000_000)
            if ms >= 1000 && ms % 1000 == 0 {
                return ["  - wait: \(ms / 1000)s"]
            }
            return ["  - wait: \(ms)ms"]

        case .setAudio(let enabled):
            return ["  - audio: \(enabled ? "on" : "off")"]

        case .setTileWait(let value):
            return ["  - tileWait: \(formatTiming(value))"]

        case .setSentenceWait(let value):
            return ["  - sentenceWait: \(formatTiming(value))"]

        case .setProvider(let name):
            return ["  - provider: \(name)"]

        case .setScene(let name):
            return ["  - scene: \(name)"]

        case .setTileSet(let imageSet):
            return ["  - tileSet: \(imageSet.rawValue)"]
        }
    }

    // MARK: - Formatting

    private static func formatRow(_ row: TileRow) -> String {
        row.actions.map { action in
            switch action {
            case .navigate(let key): return "<\(key)>"
            case .tap(let key): return key
            case .audibleNavigate(let key): return "<\(key) isAudible=t/>"
            case .replay: return "<tilescript:replay>"
            case .noclose: return "<tilescript:noclose>"
            }
        }.joined(separator: ", ")
    }

    private static func formatTiming(_ value: TimingValue) -> String {
        switch value {
        case .human: return ".human"
        case .fast: return ".fast"
        case .instant: return ".instant"
        case .explicit(let ms): return "\(ms)ms"
        }
    }
}
