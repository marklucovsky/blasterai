// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AIGeneratedModels.swift
//  claudeBlast
//
//  Shared Codable structs used by SceneGeneratorService and PageGeneratorService.
//

import Foundation

/// A single tile suggested by AI.
struct GeneratedTile: Codable {
    /// For existing tiles, an existing TileModel.key. For a proposed NEW word,
    /// the normalized key derived from `displayName` (see the service parsers).
    let key: String
    /// Whether tapping adds the tile to the sentence tray.
    let isAudible: Bool
    /// If non-empty, tapping navigates to the page with this key.
    let link: String
    /// Present only for a proposed NEW word (not yet in vocabulary). Together
    /// with `wordClass`, this is what lets the word be materialized on Accept.
    var displayName: String? = nil
    /// Word class for a proposed NEW word (one of VocabularyClasses).
    var wordClass: String? = nil

    /// A proposed new word carries both `displayName` and `wordClass`.
    var isProposedNew: Bool { displayName != nil && wordClass != nil }
}

extension GeneratedTile {
    private enum CodingKeys: String, CodingKey { case key, isAudible, link, displayName, wordClass }

    /// Decode tolerantly: the model usually emits tile objects, but occasionally
    /// emits a bare key string (e.g. "fish"). Accept both so one stray string
    /// doesn't fail the whole scene. (Custom init lives in an extension so the
    /// memberwise initializer is preserved for call sites that build tiles.)
    init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let key = try? single.decode(String.self) {
            self.init(key: key, isAudible: true, link: "")
            return
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            key: try c.decode(String.self, forKey: .key),
            isAudible: (try? c.decode(Bool.self, forKey: .isAudible)) ?? true,
            link: (try? c.decode(String.self, forKey: .link)) ?? "",
            displayName: try? c.decodeIfPresent(String.self, forKey: .displayName),
            wordClass: try? c.decodeIfPresent(String.self, forKey: .wordClass)
        )
    }
}

/// A new vocabulary word the AI declares ONCE in the response's `newWords`
/// array (rather than inlining metadata per tile — gpt-4o-mini does that
/// unreliably). Page tiles reference it by `key`.
struct GeneratedNewWord: Codable {
    let key: String
    let displayName: String
    let wordClass: String
}

extension GeneratedNewWord {
    /// Build a normalized-key → new word map. The map key is normalized so page
    /// tiles resolve regardless of the model's casing/spacing.
    ///
    /// We keep words whose wordClass isn't a known VocabularyClass rather than
    /// dropping them: the model occasionally reaches for a sensible-but-untaxon­
    /// omized class (e.g. "plant" for seaweed, "tools" for a bucket), and a tile
    /// with a neutral tint plus a good image-gen sense hint beats a silently
    /// missing word. Only entries with an empty key or class are skipped.
    static func lookup(from words: [GeneratedNewWord]?) -> [String: GeneratedNewWord] {
        var map: [String: GeneratedNewWord] = [:]
        for word in words ?? [] {
            guard !word.wordClass.isEmpty else { continue }
            let source = word.displayName.isEmpty ? word.key : word.displayName
            let key = TileModel.normalizeKey(source)
            guard !key.isEmpty else { continue }
            map[key] = word
        }
        return map
    }
}

extension GeneratedTile {
    /// Resolve a raw AI page tile against the existing vocabulary and the
    /// declared `newWords`. Shared by the scene and page generators.
    /// - key already in vocab → existing reference.
    /// - key declared in `newWords` → new word (carries displayName + wordClass).
    /// - else (hallucinated key, not declared) → nil (dropped).
    static func sanitize(_ tile: GeneratedTile,
                         validKeys: Set<String>,
                         newWords: [String: GeneratedNewWord]) -> GeneratedTile? {
        if validKeys.contains(tile.key) {
            return GeneratedTile(key: tile.key, isAudible: tile.isAudible, link: tile.link)
        }
        let key = TileModel.normalizeKey(tile.key)
        if validKeys.contains(key) {
            return GeneratedTile(key: key, isAudible: tile.isAudible, link: tile.link)
        }
        if let word = newWords[key] {
            let displayName = word.displayName.isEmpty
                ? key.replacingOccurrences(of: "_", with: " ")
                : word.displayName
            return GeneratedTile(key: key, isAudible: tile.isAudible, link: tile.link,
                                 displayName: displayName, wordClass: word.wordClass)
        }
        return nil
    }
}

/// A page (possibly a sub-page) suggested by AI.
struct GeneratedPage: Codable {
    /// Unique key for this page (snake_case, lowercase).
    let key: String
    /// `var` so the page preview can prune/reorder before Accept.
    var tiles: [GeneratedTile]
}

/// A full scene suggested by AI.
struct GeneratedScene: Codable {
    let name: String
    let description: String
    /// Must match the key of one of the pages below.
    let homePageKey: String
    let pages: [GeneratedPage]
    /// New words declared by the AI (decoded from the raw response). nil on the
    /// sanitized scene returned to callers — by then the metadata lives on the
    /// individual tiles.
    var newWords: [GeneratedNewWord]? = nil
    /// Total tokens billed for this generation, attached by SceneGeneratorService
    /// after parsing the response. Optional → absent in model JSON decodes to nil.
    var tokenUsage: Int? = nil
    /// The raw model JSON this scene was parsed from. Retained so the preview can
    /// re-scaffold the same content at a different profile (focused ⇄ full) with
    /// no extra API call. nil on cached-starter scenes.
    var rawContent: String? = nil
}

extension GeneratedScene {
    /// Decode a model's JSON content into a sanitized, scaffolded scene. Shared
    /// by SceneGeneratorService and SceneRefinerService: strips surrounding prose,
    /// drops hallucinated tile keys, admits declared new words, then hands off to
    /// SceneNavigation.scaffold to build the familiar core board around the
    /// topical tiles. Throws OpenAIError.decodingError on unusable output.
    ///
    /// `extraNewWords` carries new words that already exist on the scene being
    /// refined but aren't in base vocabulary yet (an un-accepted preview's
    /// proposed words). Merging them keeps those tiles from being dropped when
    /// the model references them by key without re-declaring them.
    static func parse(content: String, allTiles: [TileModel],
                      extraNewWords: [GeneratedNewWord] = [],
                      profile: SceneNavigation.Profile = .full) throws -> GeneratedScene {
        let validKeys = Set(allTiles.map(\.key))

        let jsonText: String
        if let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") {
            jsonText = String(content[start...end])
        } else {
            jsonText = content
        }
        guard let jsonData = jsonText.data(using: .utf8) else {
            throw OpenAIError.decodingError("Response JSON was not valid UTF-8")
        }

        let raw = try JSONDecoder().decode(GeneratedScene.self, from: jsonData)
        var newWords = GeneratedNewWord.lookup(from: raw.newWords)
        // Carried-over words the model may reference without re-declaring; the
        // model's own declarations win on key collision.
        for (key, word) in GeneratedNewWord.lookup(from: extraNewWords) where newWords[key] == nil {
            newWords[key] = word
        }

        let sanitizedPages = raw.pages.map { page in
            let validTiles = page.tiles.compactMap { tile in
                GeneratedTile.sanitize(tile, validKeys: validKeys, newWords: newWords)
            }
            return GeneratedPage(key: page.key, tiles: validTiles)
        }.filter { !$0.tiles.isEmpty }

        guard !sanitizedPages.isEmpty else {
            throw OpenAIError.decodingError("No valid tiles found in generated scene")
        }

        let homeKey = sanitizedPages.contains(where: { $0.key == raw.homePageKey })
            ? raw.homePageKey
            : sanitizedPages[0].key

        let scene = GeneratedScene(
            name: raw.name,
            description: raw.description,
            homePageKey: homeKey,
            pages: sanitizedPages
        )
        var result = SceneNavigation.scaffold(scene, allTiles: allTiles, validKeys: validKeys, profile: profile)
        result.rawContent = content
        return result
    }
}

/// Raw AI response for a page (includes optional sub-pages via `newPages`).
struct GeneratedPageResponse: Codable {
    let key: String
    let tiles: [GeneratedTile]
    let newPages: [GeneratedPage]
    var newWords: [GeneratedNewWord]? = nil
}

/// Result returned by PageGeneratorService — a primary page plus optional sub-pages.
struct GeneratedPageResult {
    /// `var` so the page preview can prune/reorder tiles before Accept.
    var primaryPage: GeneratedPage
    /// Sub-pages referenced by nav tiles in the primary page.
    var subPages: [GeneratedPage]

    /// Tile keys for the primary page (for pre-selecting in TilePickerView Edit path).
    var primaryTileKeys: Set<String> {
        Set(primaryPage.tiles.map(\.key))
    }
}
