// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  LinkColorResolverTests.swift
//  claudeBlastTests
//
//  What color a folder should be, and the guard against two implementations
//  of that question drifting apart.
//

import Testing
import SwiftData
import SwiftUI
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct LinkColorResolverTests {

    /// The bundled board, materialized exactly as the app does at launch —
    /// rather than a fixture that could describe a board we do not ship.
    private func bundledBoard() throws
        -> (pages: [String: PageSpec], all: [PageSpec], vocabulary: [String]) {
        let container = TestStore.freshContainer()
        let result = BootstrapLoader.loadDefaultVocabulary(context: container.mainContext)
        let byKey = Dictionary(uniqueKeysWithValues: result.pages.map { ($0.key, $0) })
        return (byKey, result.pages, result.tiles.map(\.key))
    }

    // MARK: - Helpers

    /// A fixed toy vocabulary, so the arithmetic in these tests is checkable by
    /// hand and does not move when the bundled vocabulary grows.
    ///
    /// **Shaped like a real AAC vocabulary rather than balanced**, which is the
    /// whole premise: nouns are the bulk of it and pronouns are a handful. A
    /// first draft gave pronouns 18% of the vocabulary where the bundled one has
    /// 3%, and at that density the pronoun and noun lifts tie exactly — so the
    /// test measured the tie-break rather than the rule it was written for.
    private static let parts: [String: PartOfSpeech] = {
        var table: [String: PartOfSpeech] = [
            "he": .pronoun, "she": .pronoun, "they": .pronoun, "we": .pronoun,
            "run": .verb, "jump": .verb, "eat": .verb, "sleep": .verb,
            "big": .adjective, "small": .adjective, "hot": .adjective, "cold": .adjective,
            "what": .question, "why": .question,
        ]
        for name in ["mom", "dad", "sister", "brother",
                     "baby", "teacher", "doctor", "friend"] {
            table[name] = .noun
        }
        // The long tail of fringe nouns every AAC vocabulary carries. Named
        // rather than numbered so a failure message stays readable.
        for i in 0..<60 { table["thing\(i)"] = .noun }
        return table
    }()

    private static func part(_ key: String) -> PartOfSpeech? { parts[key] }

    /// Noun-heavy on purpose: that is the shape of a real AAC vocabulary, and
    /// the whole reason a plain count fails.
    private static var background: [PartOfSpeech: Int] {
        LinkColorResolver.background(for: Array(parts.keys), partOfSpeech: part)
    }

    private static func words(_ keys: [String]) -> [TileEntry] {
        keys.map { TileEntry(key: $0) }
    }

    private static func links(_ count: Int) -> [TileEntry] {
        (0..<count).map { TileEntry(key: "link\($0)", link: "somewhere", isAudible: false) }
    }

    // MARK: - The rule

    /// The case that motivated the whole approach. Eight nouns against four
    /// pronouns: a plain count says noun and every published board says the
    /// People folder is colored for pronouns.
    @Test("Nouns outnumber pronouns on a people page, and pronouns still win")
    func pronounsBeatNounsDespiteBeingFewer() {
        let page = Self.words(["mom", "dad", "sister", "brother",
                               "baby", "teacher", "doctor", "friend",
                               "he", "she", "they", "we"])
        let slot = LinkColorResolver.slot(forDestination: page,
                                          partOfSpeech: Self.part,
                                          background: Self.background)
        #expect(slot == .partOfSpeech(.pronoun))
    }

    /// A page that really is about its nouns still comes out orange — the lift
    /// correction must not overshoot into always preferring the rare thing.
    @Test("An all-noun page is still a noun page")
    func allNounPageIsNoun() {
        let page = Self.words(["mom", "dad", "sister", "brother", "baby", "teacher"])
        #expect(LinkColorResolver.slot(forDestination: page,
                                       partOfSpeech: Self.part,
                                       background: Self.background)
                == .partOfSpeech(.noun))
    }

    /// The Time page bug, in miniature. Undiluted lift let a single question
    /// word out-rank four adjectives, because question words are rare overall.
    /// The share floor is what stops it.
    @Test("One rare word does not outrank the page it sits on")
    func rareWordDoesNotHijackThePage() {
        let page = Self.words(["big", "small", "hot", "cold",
                               "mom", "dad", "what"])
        #expect(LinkColorResolver.slot(forDestination: page,
                                       partOfSpeech: Self.part,
                                       background: Self.background)
                == .partOfSpeech(.adjective))
    }

    /// The `keyboard` placeholder: one tile is not evidence of anything.
    @Test("Too few words falls back to wayfinding")
    func tooFewWordsIsWayfinding() {
        for count in 0..<LinkColorResolver.minimumWords {
            let page = Array(Self.words(["mom", "dad", "sister"]).prefix(count))
            #expect(LinkColorResolver.slot(forDestination: page,
                                           partOfSpeech: Self.part,
                                           background: Self.background)
                    == .wayfinding, "\(count) words should not decide a color")
        }
    }

    /// A folder of folders has no part of speech, which is the original
    /// argument for the blue turning out to be right for a narrow class of page.
    @Test("A page of mostly links is wayfinding")
    func pageOfLinksIsWayfinding() {
        let page = Self.links(5) + Self.words(["mom", "dad"])
        #expect(LinkColorResolver.slot(forDestination: page,
                                       partOfSpeech: Self.part,
                                       background: Self.background)
                == .wayfinding)
    }

    /// Spacers are holes. Counting them would let a layout decision change a
    /// folder's color.
    @Test("Spacers do not dilute the page")
    func spacersAreIgnored() {
        let page = Self.words(["he", "she", "they", "we"])
            + (0..<20).map { _ in TileEntry.spacer() }
        #expect(LinkColorResolver.slot(forDestination: page,
                                       partOfSpeech: Self.part,
                                       background: Self.background)
                == .partOfSpeech(.pronoun))
    }

    /// A word we cannot identify is excluded rather than bucketed: "unknown" is
    /// not a category a color should stand for.
    @Test("Unknown words are excluded, not counted")
    func unknownWordsExcluded() {
        let page = Self.words(["he", "she", "they", "we"])
            + Self.words(["zzz1", "zzz2", "zzz3", "zzz4", "zzz5", "zzz6"])
        #expect(LinkColorResolver.slot(forDestination: page,
                                       partOfSpeech: Self.part,
                                       background: Self.background)
                == .partOfSpeech(.pronoun))
    }

    /// The committed board must not depend on dictionary iteration order.
    @Test("Resolution is deterministic across repeated runs")
    func resolutionIsStable() {
        let page = Self.words(["mom", "dad", "he", "she", "big", "small"])
        let first = LinkColorResolver.slot(forDestination: page,
                                           partOfSpeech: Self.part,
                                           background: Self.background)
        for _ in 0..<50 {
            #expect(LinkColorResolver.slot(forDestination: page,
                                           partOfSpeech: Self.part,
                                           background: Self.background) == first)
        }
    }

    // MARK: - An audible link is a word first

    /// `eat`, `drink` and `play` navigate *and* speak. A tile that says "eat" is
    /// a verb whatever is on the page behind it — and coloring it from the
    /// destination made three verbs orange on the board while the same words
    /// arrived in the tray as green chips. The board and the tray disagreeing
    /// about one word is precisely what a color key exists to prevent.
    @Test("An audible link takes its own word's color, not the destination's")
    func audibleLinkUsesItsOwnWord() {
        let nounPage = Self.words(["mom", "dad", "sister", "brother", "baby"])
        let speaking = TileEntry(key: "eat", link: "food", isAudible: true)
        #expect(LinkColorResolver.slot(for: speaking,
                                       destination: nounPage,
                                       partOfSpeech: Self.part,
                                       background: Self.background)
                == .partOfSpeech(.verb))
    }

    /// The other half: a silent link is never spoken, so it has no part of
    /// speech of its own and borrows meaning from where it goes.
    @Test("A silent link still takes the destination's color")
    func silentLinkUsesTheDestination() {
        let nounPage = Self.words(["mom", "dad", "sister", "brother", "baby"])
        let silent = TileEntry(key: "eat", link: "food", isAudible: false)
        #expect(LinkColorResolver.slot(for: silent,
                                       destination: nounPage,
                                       partOfSpeech: Self.part,
                                       background: Self.background)
                == .partOfSpeech(.noun))
    }

    /// Turning "Add to sentence tray" on changes what the tile *is*, so it
    /// changes color. The editor writes through `scene.pages`, which re-resolves.
    @Test("Making a link audible recolors it")
    func togglingAudibleRecolors() {
        var pages = [
            Self.page("home", [TileEntry(key: "eat", link: "stuff", isAudible: false)]),
            Self.page("stuff", Self.words(["mom", "dad", "sister", "brother", "baby"])),
        ]
        _ = SceneLinkColors.refresh(&pages, vocabulary: Self.vocabulary(),
                                    partOfSpeech: Self.part)
        #expect(pages[0].tiles[0].linkColor == "noun")

        pages[0].tiles[0].isAudible = true
        #expect(SceneLinkColors.refresh(&pages, vocabulary: Self.vocabulary(),
                                        partOfSpeech: Self.part))
        #expect(pages[0].tiles[0].linkColor == "verb")
    }

    /// An audible link whose word we cannot type has nothing of its own to fall
    /// back on, so the destination answers after all.
    @Test("An audible link with no known word type falls back to the destination")
    func audibleWithUnknownWordFallsBack() {
        let verbPage = Self.words(["run", "jump", "eat", "sleep"])
        let odd = TileEntry(key: "zzz", link: "doing", isAudible: true)
        #expect(LinkColorResolver.slot(for: odd,
                                       destination: verbPage,
                                       partOfSpeech: Self.part,
                                       background: Self.background)
                == .partOfSpeech(.verb))
    }

    // MARK: - The two implementations agree

    /// **This is the load-bearing test of the whole feature.**
    ///
    /// The bundled board's colors are resolved offline by
    /// `tools/resolve_link_colors.py` and committed, because a folder must not
    /// change color on its own. That leaves two implementations of one rule —
    /// Swift for in-app authoring, Python for the bundled board — and nothing in
    /// either language makes them agree.
    ///
    /// So neither is trusted alone. The tool's `--check` fails when the
    /// committed JSON disagrees with Python; this fails when it disagrees with
    /// Swift. Both are pinned to the same committed artifact, so a divergence
    /// cannot pass quietly in either direction.
    @Test("Every committed link color is what Swift computes for it")
    func committedColorsMatchSwift() throws {
        let board = try bundledBoard()
        let part: (String) -> PartOfSpeech? = {
            PartOfSpeechIndex.bundledPartOfSpeech(for: $0)
        }
        // The denominator is the **vocabulary**, not the board. Counting board
        // tiles double-counts a word placed on two pages (`slide` and `swing`
        // are on both `places` and `play_activities`) and misses every word on
        // no page at all — which is enough to move a folder's color, and did:
        // `social` came out `interjection` against the tool's `social`.
        let background = LinkColorResolver.background(for: board.vocabulary,
                                                      partOfSpeech: part)

        var checked = 0
        for page in board.all {
            for tile in page.tiles where !tile.link.isEmpty {
                let destination = try #require(board.pages[tile.link],
                                               "\(tile.key) links to a missing page")
                // The audible-aware entry point, which is what the app and the
                // tool both use. Calling `slot(forDestination:)` here would test
                // a rule neither of them follows — it colored `eat` from the
                // food page while the board colors it as the verb it speaks.
                let computed = LinkColorResolver.slot(for: tile,
                                                      destination: destination.tiles,
                                                      partOfSpeech: part,
                                                      background: background)
                let committed = tile.linkColor ?? "nothing"
                #expect(tile.linkColor == computed.rawValue,
                        "\(page.key)/\(tile.key) -> \(tile.link): committed \(committed), Swift says \(computed.rawValue)")
                checked += 1
            }
        }
        // A silent zero here would make the assertion above vacuous, which is
        // the same trap as a test filter that matches nothing.
        #expect(checked >= 12, "only \(checked) links checked")
    }

    /// `"auto"` is an authoring instruction for the offline tool, never a stored
    /// value. One surviving into a shipped scene would draw as wayfinding and
    /// look deliberate.
    @Test("No shipped link is left on auto")
    func noShippedLinkIsAuto() throws {
        let board = try bundledBoard()
        for page in board.all {
            for tile in page.tiles where !tile.link.isEmpty {
                #expect(tile.linkColor != "auto", "\(page.key)/\(tile.key) is still auto")
                let raw = try #require(tile.linkColor,
                                       "\(page.key)/\(tile.key) has no color")
                #expect(TileColorSlot(rawValue: raw) != nil,
                        "\(raw) is not a slot")
            }
        }
    }

    // MARK: - Automatic vs pinned

    private static func vocabulary() -> [String] { Array(parts.keys) }

    private static func page(_ key: String, _ tiles: [TileEntry]) -> PageSpec {
        PageSpec(key: key, tiles: tiles)
    }

    /// The point of `linkColorIsAuto`: editing a page moves the folders that
    /// describe it, so the board does not start lying about itself.
    @Test("An automatic folder follows the page behind it")
    func automaticFolderFollowsItsPage() {
        var pages = [
            Self.page("home", [TileEntry(key: "menu", link: "stuff", isAudible: false,
                                         linkColor: TileColorSlot.wayfinding.rawValue)]),
            Self.page("stuff", Self.words(["run", "jump", "eat", "sleep"])),
        ]
        var changed = SceneLinkColors.refresh(&pages,
                                              vocabulary: Self.vocabulary(),
                                              partOfSpeech: Self.part)
        #expect(changed)
        #expect(pages[0].tiles[0].linkColor == "verb")

        // Turn it into a page of describing words; the folder follows.
        pages[1] = Self.page("stuff", Self.words(["big", "small", "hot", "cold"]))
        changed = SceneLinkColors.refresh(&pages,
                                          vocabulary: Self.vocabulary(),
                                          partOfSpeech: Self.part)
        #expect(changed)
        #expect(pages[0].tiles[0].linkColor == "adjective")
    }

    /// A folder made by dropping a page link onto a page arrives with no color
    /// at all, and no color draws as wayfinding blue — which is indistinguishable
    /// from a folder somebody decided should be blue. Both link-creation paths
    /// have to resolve, and the one in `PageLinkPlacementSheet` did not.
    @Test("A freshly created link resolves rather than staying blue")
    func newlyCreatedLinkResolves() {
        var pages = [
            Self.page("home", []),
            Self.page("stuff", Self.words(["mom", "dad", "sister", "brother", "baby"])),
        ]
        // Exactly what the placement sheet appends: key, link, nothing else.
        pages[0].tiles.append(TileEntry(key: "menu", link: "stuff", isAudible: false))
        #expect(pages[0].tiles[0].linkColor == nil)

        #expect(SceneLinkColors.refresh(&pages, vocabulary: Self.vocabulary(),
                                        partOfSpeech: Self.part))
        #expect(pages[0].tiles[0].linkColor == "noun")
    }

    /// A page with nothing on it yet cannot say what it is about, so its folder
    /// stays wayfinding — and starts following as soon as it is filled.
    @Test("An empty destination is wayfinding until it has words")
    func emptyDestinationBecomesResolvedWhenFilled() {
        var pages = [
            Self.page("home", [TileEntry(key: "menu", link: "stuff", isAudible: false)]),
            Self.page("stuff", []),
        ]
        _ = SceneLinkColors.refresh(&pages, vocabulary: Self.vocabulary(),
                                    partOfSpeech: Self.part)
        #expect(pages[0].tiles[0].linkColor == TileColorSlot.wayfinding.rawValue)

        pages[1] = Self.page("stuff", Self.words(["run", "jump", "eat", "sleep"]))
        #expect(SceneLinkColors.refresh(&pages, vocabulary: Self.vocabulary(),
                                        partOfSpeech: Self.part))
        #expect(pages[0].tiles[0].linkColor == "verb")
    }

    /// And the other half: a color someone chose is theirs, and no amount of
    /// editing the destination may quietly take it back.
    @Test("A pinned folder ignores the page behind it")
    func pinnedFolderIgnoresItsPage() {
        var pages = [
            Self.page("home", [TileEntry(key: "menu", link: "stuff", isAudible: false,
                                         linkColor: "negation", linkColorIsAuto: false)]),
            Self.page("stuff", Self.words(["run", "jump", "eat", "sleep"])),
        ]
        let changed = SceneLinkColors.refresh(&pages,
                                              vocabulary: Self.vocabulary(),
                                              partOfSpeech: Self.part)
        #expect(!changed)
        #expect(pages[0].tiles[0].linkColor == "negation")
    }

    /// The editor calls `refresh` when a page changes, and `refresh` writes
    /// `scene.pages`, which is itself a change. It has to settle rather than
    /// loop, and it settles by reporting honestly that it did nothing.
    @Test("Refreshing twice changes nothing the second time")
    func refreshIsIdempotent() {
        var pages = [
            Self.page("home", [TileEntry(key: "menu", link: "stuff", isAudible: false)]),
            Self.page("stuff", Self.words(["he", "she", "they", "we"])),
        ]
        #expect(SceneLinkColors.refresh(&pages, vocabulary: Self.vocabulary(),
                                        partOfSpeech: Self.part))
        let settled = pages
        #expect(!SceneLinkColors.refresh(&pages, vocabulary: Self.vocabulary(),
                                         partOfSpeech: Self.part))
        #expect(pages == settled)
    }

    /// `<home>` names no page — it resolves at navigation time — and a Home
    /// button is wayfinding by definition.
    @Test("A link to a page that is not there is wayfinding")
    func unknownDestinationIsWayfinding() {
        var pages = [
            Self.page("home", [TileEntry(key: "back", link: TileToken.home, isAudible: false)]),
        ]
        _ = SceneLinkColors.refresh(&pages, vocabulary: Self.vocabulary(),
                                    partOfSpeech: Self.part)
        #expect(pages[0].tiles[0].linkColor == TileColorSlot.wayfinding.rawValue)
    }

    /// The flag has to cross storage, or a pinned color silently becomes
    /// automatic on the next launch and drifts. `TileEntry` decodes by hand, so
    /// this is not free — see `PageSpec.swift`.
    @Test("Pinned survives a storage round trip")
    func pinnedSurvivesStorage() throws {
        let pinned = TileEntry(key: "menu", link: "stuff", isAudible: false,
                               linkColor: "negation", linkColorIsAuto: false)
        let back = try JSONDecoder().decode(
            TileEntry.self, from: try JSONEncoder().encode(pinned))
        #expect(back.linkColor == "negation")
        #expect(back.linkColorIsAuto == false)

        // A tile written before the flag existed must read as automatic, or it
        // would freeze at whatever color it happened to hold.
        let legacy = #"{"key":"menu","link":"stuff","isAudible":false,"linkColor":"verb"}"#
        let old = try JSONDecoder().decode(TileEntry.self,
                                           from: Data(legacy.utf8))
        #expect(old.linkColorIsAuto)
        #expect(old.linkColor == "verb")
    }

    /// The bundled board is authored by the tool, which resolves every link —
    /// so every one of its links is automatic and will track the vocabulary.
    @Test("Refreshing the bundled board changes nothing")
    func bundledBoardIsAlreadyResolved() throws {
        let board = try bundledBoard()
        var pages = board.all
        let changed = SceneLinkColors.refresh(
            &pages, vocabulary: board.vocabulary,
            partOfSpeech: { PartOfSpeechIndex.bundledPartOfSpeech(for: $0) })
        #expect(!changed, "the committed board disagrees with the in-app resolver")
    }

    // MARK: - Rendering

    /// The mode changes which color is looked up and never what a link stores,
    /// so switching it back restores exactly the board that was there before.
    @Test("Always-wayfinding overrides a stored slot without erasing it")
    func alwaysWayfindingOverridesLookupOnly() {
        let profile = ChildProfile(displayName: "Test")
        profile.linkColorMode = .alwaysWayfinding
        TileColorResolver.refreshActiveMap(from: profile)
        defer { TileColorResolver.refreshActiveMap(from: nil) }

        #expect(TileColorResolver.linkColor(slotRawValue: "verb")
                == TileColorResolver.navigation)

        profile.linkColorMode = .perTile
        TileColorResolver.refreshActiveMap(from: profile)
        #expect(TileColorResolver.linkColor(slotRawValue: "verb")
                == TileColorResolver.fitzgerald(.verb))
    }

    /// A link with no stored color draws as wayfinding — what every link did
    /// before folders could carry one.
    @Test("A colorless link draws as wayfinding")
    func colorlessLinkIsWayfinding() {
        TileColorResolver.refreshActiveMap(from: nil)
        #expect(TileColorResolver.linkColor(slotRawValue: nil)
                == TileColorResolver.navigation)
        #expect(TileColorResolver.linkColor(slotRawValue: "not-a-slot")
                == TileColorResolver.navigation)
    }

    /// The badge is the only thing left saying "this is a folder" once folders
    /// stopped all being blue, so it has to separate from every color a tile can
    /// be — including the ones a caregiver invents.
    @Test("The link marker contrasts with every tile color it can sit on")
    func markerContrastsWithItsTile() {
        func luminance(_ color: Color) -> CGFloat {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            return 0.2126 * r + 0.7152 * g + 0.0722 * b
        }

        var tested = 0
        var colors = PartOfSpeech.allCases.map { TileColorResolver.fitzgerald($0) }
        colors.append(TileColorResolver.navigationDefault)
        colors.append(contentsOf: TileColorMap.palette.compactMap { Color(hex: $0) })

        for tile in colors {
            let badge = TileColorResolver.marker(on: tile)
            let separation = abs(luminance(badge) - luminance(tile))
            #expect(separation > 0.15,
                    "badge \(badge.hexString) is too close to tile \(tile.hexString)")
            tested += 1
        }
        #expect(tested > 20, "only \(tested) colors tested")
    }
}
}
