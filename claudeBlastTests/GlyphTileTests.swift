// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GlyphTileTests.swift
//  claudeBlastTests
//
//  Letters and numbers, drawn rather than generated.
//

import Testing
import Foundation
import UIKit
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct GlyphTileTests {

    // MARK: - Keys

    @Test("Letters and numbers resolve to their character")
    func glyphKeysResolve() {
        #expect(GlyphTile.character(for: "letter_a") == "A")
        #expect(GlyphTile.character(for: "letter_z") == "Z")
        #expect(GlyphTile.character(for: "number_0") == "0")
        #expect(GlyphTile.character(for: "number_10") == "10")
    }

    /// The reason the keys are namespaced. A bare `a` or `i` would collide with
    /// real vocabulary — `i` is the pronoun — and "the letter A" and "the word a"
    /// are different concepts behind a language-neutral key.
    @Test("A real word is never mistaken for a glyph")
    func wordsAreNotGlyphs() {
        for key in ["a", "i", "eat", "more", "page_farm", "home", "letter", "number"] {
            #expect(!GlyphTile.isGlyphKey(key), "\(key) read as a glyph")
        }
    }

    @Test("A malformed glyph key is not a glyph")
    func malformedKeysRejected() {
        for key in ["letter_", "letter_ab", "letter_1", "number_", "number_x"] {
            #expect(!GlyphTile.isGlyphKey(key), "\(key) read as a glyph")
        }
    }

    @Test("The pack covers 26 letters and 11 numbers")
    func packSizes() {
        #expect(GlyphTile.letterKeys.count == 26)
        #expect(GlyphTile.letterKeys.first == "letter_a")
        #expect(GlyphTile.letterKeys.last == "letter_z")
        // 0 through 10 is eleven, not ten.
        #expect(GlyphTile.numberKeys.count == 11)
        #expect(GlyphTile.numberKeys.last == "number_10")
    }

    // MARK: - Drawing

    @Test("A glyph draws in every shipped set")
    func drawsInEverySet() {
        for set in ImageSetCatalog.all.filter(\.isShippable).map(\.id) {
            #expect(GlyphTile.image(for: "letter_a", in: set) != nil,
                    "letter_a did not draw in \(set.rawValue)")
        }
    }

    @Test("A word draws nothing — it has real art")
    func wordsDrawNothing() {
        #expect(GlyphTile.image(for: "eat", in: ImageSetID.defaultSet) == nil)
    }

    /// High Contrast is white-on-black by design, so a glyph has to invert with
    /// it rather than render black ink on a black board.
    @Test("High Contrast inverts")
    func highContrastInverts() throws {
        let light = try #require(GlyphTile.image(for: "letter_a", in: ImageSetID.classic, size: 64))
        let dark = try #require(GlyphTile.image(for: "letter_a", in: ImageSetID.highContrast, size: 64))
        #expect(corner(of: light) != corner(of: dark),
                "both sets drew the same paper colour")
    }

    /// A glyph has no skin tone, so the three Classic sets share one rendering —
    /// the same way the non-people art is already byte-identical across them.
    @Test("The Classic tones share one rendering")
    func classicTonesAgree() throws {
        let light = try #require(GlyphTile.image(for: "letter_a", in: ImageSetID.classic, size: 64))
        let medium = try #require(GlyphTile.image(for: "letter_a", in: ImageSetID.classicMedium, size: 64))
        #expect(light.pngData() == medium.pngData())
    }

    /// Wide and narrow characters must both fill the cell without clipping,
    /// which a fixed point size cannot do.
    @Test("Glyphs are fitted, not fixed")
    func glyphsAreFitted() throws {
        for text in ["letter_w", "letter_i", "number_1", "number_10"] {
            let image = try #require(GlyphTile.image(for: text, in: ImageSetID.classic, size: 64))
            #expect(image.size == CGSize(width: 64, height: 64))
            #expect(inkFraction(of: image) > 0.01, "\(text) drew (almost) nothing")
        }
    }

    // MARK: - Pack integrity

    @Test("Both packs are registered and their keys are glyphs")
    func packsAreWellFormed() throws {
        for slug in ["letters", "numbers"] {
            let pack = try #require(PackCatalog.all.first { $0.slug == slug },
                                    "\(slug) pack is not registered in packs.json")
            #expect(!pack.words.isEmpty)
            for word in pack.words {
                #expect(GlyphTile.isGlyphKey(word.key), "\(word.key) will not draw")
                #expect(VocabularyClasses.known(word.wordClass) != nil,
                        "\(word.wordClass) is not a known class")
            }
        }
    }

    /// A glyph is never "missing art", in any set — otherwise every letter would
    /// be offered up for AI generation that would cost money and look worse.
    @Test("A glyph never needs generated art")
    func glyphsNeverNeedArt() {
        let resolver = TileImageResolver()
        for set in ImageSetCatalog.all.map(\.id) {
            #expect(resolver.hasArt(for: "letter_a", in: set))
            #expect(resolver.hasArt(for: "number_7", in: set))
        }
    }

    /// The per-set review strip in Tile Settings draws from `image(for:in:)`,
    /// whose nil means "this set has no art" and renders an empty slot inviting
    /// generation. For a glyph that would be a lie in five places at once — the
    /// caregiver concealing the ZERO tile because the class counts from one
    /// should see the same 0 the child sees, not five placeholders suggesting
    /// the tile is unfinished.
    @Test("Every set's review slot draws the glyph")
    func reviewStripDrawsGlyphs() {
        let resolver = TileImageResolver()
        for set in ImageSetCatalog.all.map(\.id) {
            #expect(resolver.image(for: "number_0", in: set) != nil,
                    "number_0 showed as missing art in \(set.rawValue)")
            #expect(resolver.image(for: "letter_q", in: set) != nil,
                    "letter_q showed as missing art in \(set.rawValue)")
        }
    }

    /// And an ordinary word must still report honestly, or the strip stops
    /// being able to show what actually needs generating.
    @Test("A word with no art in a set still reports missing")
    func wordsStillReportMissingArt() {
        let resolver = TileImageResolver()
        #expect(resolver.image(for: "zzz_invented_word", in: ImageSetID.classic) == nil)
    }

    // MARK: - Ordering

    /// A caregiver looking at the Numbers pack listed 0, 1, 10, 2, 3 has no way
    /// to know that is a string compare. `localizedStandardCompare` reads runs
    /// of digits as numbers — the same rule Finder uses — so this holds for any
    /// future numbered pack, not just this one.
    @Test("Numbers sort as numbers, not as strings")
    func numbersSortNaturally() throws {
        let scrambled = GlyphTile.numberKeys.shuffled()
        let sorted = scrambled.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        #expect(sorted == GlyphTile.numberKeys)
        // The failure it replaces, spelled out: a plain sort puts 10 immediately
        // after 1, because it is comparing "1" then "0" against "2".
        let plain = GlyphTile.numberKeys.sorted()
        let ten = try #require(plain.firstIndex(of: "number_10"))
        let two = try #require(plain.firstIndex(of: "number_2"))
        #expect(ten < two, "fixture assumes a plain sort misorders these")
        #expect(sorted != plain)
    }

    @Test("Letters still sort alphabetically")
    func lettersSortAlphabetically() {
        let sorted = GlyphTile.letterKeys.shuffled()
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        #expect(sorted == GlyphTile.letterKeys)
    }

    // MARK: - Helpers

    private func corner(of image: UIImage) -> UInt32 {
        pixel(of: image, at: CGPoint(x: 1, y: 1))
    }

    private func pixel(of image: UIImage, at point: CGPoint) -> UInt32 {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        let offset = Int(point.y) * cg.bytesPerRow + Int(point.x) * 4
        return (UInt32(bytes[offset]) << 16) | (UInt32(bytes[offset + 1]) << 8)
            | UInt32(bytes[offset + 2])
    }

    /// Roughly how much of the tile is ink, used only to prove something drew.
    private func inkFraction(of image: UIImage) -> Double {
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return 0 }
        var dark = 0
        let total = cg.width * cg.height
        for y in 0..<cg.height {
            for x in 0..<cg.width {
                let offset = y * cg.bytesPerRow + x * 4
                if bytes[offset] < 128 { dark += 1 }
            }
        }
        return Double(dark) / Double(total)
    }
}
}
