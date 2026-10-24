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
    /// A folder's colour slot, when it was chosen rather than worked out — a
    /// link into BlasterAI 60 keeps the colour that board gives it. Not part of
    /// the model's JSON.
    var linkColor: String? = nil

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
    /// What to call the page, when the key's title-cased form isn't good enough
    /// ("Body & Health" for `body_health`). Empty means "derive from the key",
    /// matching `PageSpec.displayName`. The model never sets this — the
    /// structure step does, for the pages it builds.
    var displayName: String = ""

    init(key: String, tiles: [GeneratedTile], displayName: String = "") {
        self.key = key
        self.tiles = tiles
        self.displayName = displayName
    }
}

extension GeneratedPage {
    private enum CodingKeys: String, CodingKey { case key, tiles, displayName }

    /// Hand-written for the same reason `PageSpec`'s is: Swift's synthesized
    /// decoder throws on a missing non-optional rather than using the property's
    /// default, so model JSON — which has no `displayName` — would fail to decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(key: try c.decode(String.self, forKey: .key),
                  tiles: try c.decodeIfPresent([GeneratedTile].self, forKey: .tiles) ?? [],
                  displayName: try c.decodeIfPresent(String.self, forKey: .displayName) ?? "")
    }
}

/// A full scene suggested by AI.
struct GeneratedScene: Codable {
    let name: String
    let description: String
    /// Must match the key of one of the pages below.
    /// `var` so the structure step can re-point it when a scene arrives with no
    /// usable home page.
    var homePageKey: String
    /// `var` so the structure step can append pages before the scene is built.
    var pages: [GeneratedPage]
    /// New words declared by the AI (decoded from the raw response). nil on the
    /// sanitized scene returned to callers — by then the metadata lives on the
    /// individual tiles.
    var newWords: [GeneratedNewWord]? = nil
    /// Total tokens billed for this generation, attached by SceneGeneratorService
    /// after parsing the response. Optional → absent in model JSON decodes to nil.
    var tokenUsage: Int? = nil
    /// The raw model JSON this scene was parsed from. Retained so the preview
    /// can re-apply a different chrome bundle to the same content with no extra
    /// API call. nil on cached-starter scenes.
    var rawContent: String? = nil
    /// Set when the home page is a ranked word list for the page scheme
    /// (`PagePlacer`), laid out when it is shown and when it is built. Nil is
    /// a flat page, placed in list order — cached starters, older flows.
    var template: PageTemplate.Kind? = nil
}

extension GeneratedScene {
    /// The pages as they will be built. A templated home page is laid into the
    /// scheme: the system row and core frame from `systemHome` (BlasterAI 60's
    /// home), its words in bands, its links in the link slots. Every other
    /// page is its tiles in order.
    ///
    /// Pure, and run on every render of the preview as well as at build: the
    /// list is what the caregiver edits (remove a word, refine), and placing
    /// once up front would leave holes or shift cells when they did.
    func placedPages(systemHome: PageSpec?, lookup: [String: TileModel]) -> [PageSpec] {
        pages.map { page in
            guard let template, page.key == homePageKey else {
                return PageSpec(key: page.key, displayName: page.displayName,
                                tiles: page.tiles.map {
                                    TileEntry(key: $0.key, link: $0.link, isAudible: $0.isAudible)
                                })
            }
            let frame = PageFrame(systemHome: systemHome, kind: template)
            let taken = frame.keys
            let words = page.tiles.filter { $0.link.isEmpty && !taken.contains($0.key) }
            let links = page.tiles.filter { !$0.link.isEmpty }
            return PageSpec(key: page.key, displayName: page.displayName,
                            tiles: PagePlacer.place(words: words, links: links, kind: template,
                                                    frame: frame, lookup: lookup))
        }
    }
}

extension GeneratedScene {
    /// Decode a model's JSON content into a sanitized, scaffolded scene. Shared
    /// by SceneGeneratorService and SceneRefinerService: strips surrounding prose,
    /// drops hallucinated tile keys, and admits declared new words. Throws
    /// OpenAIError.decodingError on unusable output.
    ///
    /// **Nothing is added by default.** `chrome` is `.none` unless a caller asks
    /// otherwise, so what comes back is the scene the model actually produced.
    /// Core words and category pages are a separate, explicit choice made in the
    /// structure step — see `SceneNavigation.ChromeBundle`.
    ///
    /// `extraNewWords` carries new words that already exist on the scene being
    /// refined but aren't in base vocabulary yet (an un-accepted preview's
    /// proposed words). Merging them keeps those tiles from being dropped when
    /// the model references them by key without re-declaring them.
    static func parse(content: String, allTiles: [TileModel],
                      extraNewWords: [GeneratedNewWord] = [],
                      chrome: SceneNavigation.ChromeBundle = .none) throws -> GeneratedScene {
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
        var result = SceneNavigation.scaffold(scene, allTiles: allTiles, validKeys: validKeys, chrome: chrome)
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
