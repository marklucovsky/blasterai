// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PromptTemplate.swift
//  claudeBlast
//
//  Prompt prose lives in `Resources/Prompts/prompt_<name>.txt`, not in Swift
//  string literals, so the eval harness (`tools/eval/`, Python) sends exactly
//  what the app sends. `PromptFixtureTests` and
//  `tools/eval/check_prompt_parity.py` hold both sides to the same fixtures.
//
//  Format, mirrored by `tools/eval/prompts.py`: the file's text minus one
//  trailing newline, with each `{{name}}` replaced by its value. Values are
//  inserted literally. Single braces (the JSON schemas in the prompts) are
//  ordinary text.

import Foundation
import os

nonisolated enum PromptTemplate {
    private static let logger = Logger(subsystem: "app.blasterai", category: "prompts")

    /// Render `prompt_<name>.txt` with `values`. Every placeholder in the file
    /// must be supplied and every value must be used, so a renamed placeholder
    /// fails `PromptFixtureTests` rather than shipping a literal `{{goal}}`.
    static func render(_ name: String, _ values: [String: String] = [:]) -> String {
        var text = raw(name)
        for (key, value) in values {
            let token = "{{\(key)}}"
            if !text.contains(token) {
                logger.fault("prompt_\(name, privacy: .public): unused value \(key, privacy: .public)")
                assertionFailure("prompt_\(name): unused value \(key)")
            }
            text = text.replacingOccurrences(of: token, with: value)
        }
        // Values were substituted in one pass each, so a leftover token can only
        // be a placeholder nobody supplied (values never contain "{{").
        if text.contains("{{") {
            logger.fault("prompt_\(name, privacy: .public): unfilled placeholder")
            assertionFailure("prompt_\(name): unfilled placeholder")
        }
        return text
    }

    /// The template text, unrendered.
    static func raw(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: "prompt_\(name)", withExtension: "txt"),
              var text = try? String(contentsOf: url, encoding: .utf8)
        else {
            logger.fault("prompt_\(name, privacy: .public).txt missing from the bundle")
            assertionFailure("prompt_\(name).txt missing from the bundle")
            return ""
        }
        if text.hasSuffix("\n") { text.removeLast() }
        return text
    }

    /// Brown's Stage descriptors from `prompt_stages.json`, keyed by the
    /// stage's raw value, with "/escalating" for the insisting variant.
    static let stages: [String: String] = {
        guard let url = Bundle.main.url(forResource: "prompt_stages", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            logger.fault("prompt_stages.json missing or unreadable")
            assertionFailure("prompt_stages.json missing or unreadable")
            return [:]
        }
        return decoded
    }()
}
