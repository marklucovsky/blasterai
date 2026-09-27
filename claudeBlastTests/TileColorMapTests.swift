// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileColorMapTests.swift
//  claudeBlastTests
//
//  What the colors mean, when Fitzgerald is not what this child can see.
//

import Testing
import SwiftData
import SwiftUI
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct TileColorMapTests {

    // MARK: - Hex round trip

    /// Storage is hex, so a color that does not survive the trip would silently
    /// drift every time the profile is saved.
    @Test("A color round-trips through hex")
    func hexRoundTrips() throws {
        for hex in ["#FF6A00", "#000000", "#FFFFFF", "#4CB859"] {
            let color = try #require(Color(hex: hex))
            #expect(color.hexString == hex, "\(hex) did not survive")
        }
    }

    /// A malformed stored value must fall back to the default rather than draw
    /// something arbitrary — a board is not a place to render a guess.
    @Test("Malformed hex is rejected, not approximated")
    func malformedHexRejected() {
        for bad in ["", "#12345", "nonsense", "#GGGGGG", "1234567"] {
            #expect(Color(hex: bad) == nil, "\(bad) parsed")
        }
    }

    // MARK: - The map

    @Test("An empty map stores as nothing at all")
    func emptyMapStoresEmpty() {
        #expect(TileColorMap().encoded.isEmpty)
        #expect(TileColorMap.decode("").isEmpty)
    }

    @Test("A map round-trips through storage")
    func mapRoundTrips() {
        var map = TileColorMap(name: "Test")
        map.set(Color(hex: "#FF6A00"), for: .verb)
        let back = TileColorMap.decode(map.encoded)
        #expect(back.name == "Test")
        #expect(back.color(for: .verb)?.hexString == "#FF6A00")
        #expect(back.color(for: .noun) == nil, "an unset type must stay unset")
    }

    /// Unreadable storage is an empty map, never a throw. A board that will not
    /// draw because its palette failed to parse is far worse than one drawn in
    /// the defaults.
    @Test("Unreadable storage decodes to the defaults")
    func garbageDecodesToEmpty() {
        #expect(TileColorMap.decode("not json at all").isEmpty)
        #expect(TileColorMap.decode("{\"unexpected\": true}").isEmpty)
    }

    /// Setting nil is how a therapist restores one type, and it has to remove
    /// the override rather than store the default as an override — otherwise the
    /// default palette could never be improved for that child again.
    @Test("Clearing one type removes its override")
    func clearingRemovesTheOverride() {
        var map = TileColorMap()
        map.set(Color(hex: "#FF6A00"), for: .verb)
        #expect(!map.isEmpty)
        map.set(nil, for: .verb)
        #expect(map.isEmpty)
    }

    // MARK: - Resolution

    /// The point of the whole feature.
    @Test("A child's override wins over Fitzgerald")
    func overrideWinsOverDefault() {
        let fitzgerald = TileColorResolver.fitzgerald(.verb)
        var map = TileColorMap(name: "CVI")
        map.set(Color(hex: "#E00000"), for: .verb)

        let profile = ChildProfile(displayName: "Test")
        profile.colorMapData = map.encoded
        TileColorResolver.refreshActiveMap(from: profile)
        defer { TileColorResolver.refreshActiveMap(from: nil) }

        #expect(TileColorResolver.color(for: .verb).hexString == "#E00000")
        #expect(TileColorResolver.color(for: .verb) != fitzgerald)
    }

    /// Sparse: anything the therapist did not change still tracks the default,
    /// so the shipped palette can be improved later without rewriting stored
    /// data.
    @Test("An untouched type still follows the default")
    func untouchedTypesFollowTheDefault() {
        var map = TileColorMap()
        map.set(Color(hex: "#E00000"), for: .verb)

        let profile = ChildProfile(displayName: "Test")
        profile.colorMapData = map.encoded
        TileColorResolver.refreshActiveMap(from: profile)
        defer { TileColorResolver.refreshActiveMap(from: nil) }

        #expect(TileColorResolver.color(for: .noun) == TileColorResolver.fitzgerald(.noun))
    }

    /// `fitzgerald` must ignore the active map, or the editor's color well
    /// echoes the override back and a therapist can see neither what they are
    /// changing nor what resetting restores — the trap "Automatic" fell into in
    /// the word-type picker.
    @Test("The default is readable even while an override is active")
    func defaultIsReadableUnderAnOverride() {
        var map = TileColorMap()
        map.set(Color(hex: "#E00000"), for: .verb)
        let profile = ChildProfile(displayName: "Test")
        profile.colorMapData = map.encoded
        TileColorResolver.refreshActiveMap(from: profile)
        defer { TileColorResolver.refreshActiveMap(from: nil) }

        #expect(TileColorResolver.fitzgerald(.verb).hexString != "#E00000")
    }

    // MARK: - Page links are a color slot, not a part of speech

    /// The whole design rests on this: `TileColorSlot`'s raw value for a part of
    /// speech is *exactly* `PartOfSpeech.rawValue`, so every palette already
    /// saved on a device — and every colorway file already sent to a family —
    /// keeps resolving after page links became colorable.
    ///
    /// The other half of that bargain is that no part of speech may ever be
    /// named `wayfinding` or `chrome`. Nothing in the compiler stops someone
    /// adding one; this does.
    @Test("Slot raw values match parts of speech and never collide")
    func slotRawValuesDoNotCollide() {
        for part in PartOfSpeech.allCases {
            #expect(TileColorSlot.partOfSpeech(part).rawValue == part.rawValue)
            #expect(TileColorSlot(rawValue: part.rawValue) == .partOfSpeech(part))
        }
        let reserved = [TileColorSlot.wayfinding.rawValue, TileColorSlot.chrome.rawValue]
        for name in reserved {
            #expect(PartOfSpeech(rawValue: name) == nil,
                    "\(name) is now a part of speech and collides with a color slot")
        }
        #expect(TileColorSlot(rawValue: "wayfinding") == .wayfinding)
        #expect(TileColorSlot(rawValue: "chrome") == .chrome)
        #expect(TileColorSlot(rawValue: "not-a-slot") == nil)
    }

    /// A palette written before page links existed is keyed purely by part of
    /// speech. It must still read through the widened API, or upgrading the app
    /// would silently drop a therapist's work.
    @Test("A palette saved before slots existed still resolves")
    func legacyPaletteStillResolves() {
        // Hand-built the old way: raw part-of-speech keys, no slot involved.
        let legacy = TileColorMap(name: "Old", overrides: ["verb": "#E00000"])
        #expect(legacy.color(for: .partOfSpeech(.verb))?.hexString == "#E00000")
        #expect(legacy.color(for: PartOfSpeech.verb)?.hexString == "#E00000")
        #expect(legacy.color(for: .wayfinding) == nil)

        let profile = ChildProfile(displayName: "Test")
        profile.colorMapData = legacy.encoded
        TileColorResolver.refreshActiveMap(from: profile)
        defer { TileColorResolver.refreshActiveMap(from: nil) }
        #expect(TileColorResolver.color(for: .verb).hexString == "#E00000")
    }

    /// The point of the feature: a caregiver can recolor page links, because the
    /// deep royal blue has to stay distinct from the adjective blue beside it and
    /// whether it does is a fact about one child's vision.
    @Test("A wayfinding override recolors page links")
    func wayfindingOverrideRecolorsLinks() {
        let shipped = TileColorResolver.navigationDefault
        var map = TileColorMap(name: "Loud links")
        map.set(Color(hex: "#FDD835"), for: .wayfinding)

        let profile = ChildProfile(displayName: "Test")
        profile.colorMapData = map.encoded
        TileColorResolver.refreshActiveMap(from: profile)
        defer { TileColorResolver.refreshActiveMap(from: nil) }

        #expect(TileColorResolver.navigation.hexString == "#FDD835")
        #expect(TileColorResolver.navigation != shipped)
        // Recoloring links must not disturb any word color.
        #expect(TileColorResolver.color(for: .adjective) == TileColorResolver.fitzgerald(.adjective))
    }

    /// Untouched, page links keep the shipped blue — the same sparseness rule
    /// every word color follows.
    @Test("Page links follow the shipped blue when untouched")
    func wayfindingFollowsDefaultWhenUntouched() {
        var map = TileColorMap()
        map.set(Color(hex: "#E00000"), for: .verb)
        let profile = ChildProfile(displayName: "Test")
        profile.colorMapData = map.encoded
        TileColorResolver.refreshActiveMap(from: profile)
        defer { TileColorResolver.refreshActiveMap(from: nil) }

        #expect(TileColorResolver.navigation == TileColorResolver.navigationDefault)
        #expect(TileColorResolver.chrome == TileColorResolver.chromeDefault)
    }

    /// `defaultColor(for:)` is what the editor's swatch draws and what "Use the
    /// Default" restores, so like `fitzgerald` it must ignore the active map.
    @Test("The slot default ignores an active override")
    func slotDefaultIgnoresOverride() {
        var map = TileColorMap()
        map.set(Color(hex: "#FDD835"), for: .wayfinding)
        let profile = ChildProfile(displayName: "Test")
        profile.colorMapData = map.encoded
        TileColorResolver.refreshActiveMap(from: profile)
        defer { TileColorResolver.refreshActiveMap(from: nil) }

        #expect(TileColorResolver.defaultColor(for: .wayfinding) == TileColorResolver.navigationDefault)
        #expect(TileColorResolver.defaultColor(for: .chrome) == TileColorResolver.chromeDefault)
        for part in PartOfSpeech.allCases {
            #expect(TileColorResolver.defaultColor(for: .partOfSpeech(part))
                    == TileColorResolver.fitzgerald(part))
        }
    }

    /// Every slot the editor lists must be one a caregiver can act on. `chrome`
    /// is deliberately absent: it is the fallback for a word we could not
    /// identify, so coloring it would say something about our data rather than
    /// about the child.
    @Test("The editor lists every word color plus page links, and not chrome")
    func displayListIsCompleteAndExcludesChrome() {
        #expect(TileColorSlot.display.contains(.wayfinding))
        #expect(!TileColorSlot.display.contains(.chrome))
        for part in PartOfSpeech.display {
            #expect(TileColorSlot.display.contains(.partOfSpeech(part)))
        }
        #expect(TileColorSlot.display.count == PartOfSpeech.display.count + 1)
        // Page links sit last: it answers a different question from the word
        // colors above it.
        #expect(TileColorSlot.display.last == .wayfinding)
        for slot in TileColorSlot.display {
            #expect(!slot.label.isEmpty)
        }
    }

    /// A shared colorway carries raw keys straight through, so a therapist can
    /// send a palette that recolors links without a format change.
    @Test("A wayfinding override survives storage")
    func wayfindingSurvivesStorage() {
        var map = TileColorMap(name: "Loud links")
        map.set(Color(hex: "#FDD835"), for: .wayfinding)
        let restored = TileColorMap.decode(map.encoded)
        #expect(restored.color(for: .wayfinding)?.hexString == "#FDD835")
        #expect(restored.overrides["wayfinding"] == "#FDD835")

        var cleared = restored
        cleared.set(nil, for: .wayfinding)
        #expect(cleared.color(for: .wayfinding) == nil)
        #expect(cleared.isEmpty)
    }

    @Test("No profile means the default palette")
    func noProfileMeansDefaults() {
        TileColorResolver.refreshActiveMap(from: nil)
        for pos in PartOfSpeech.allCases {
            #expect(TileColorResolver.color(for: pos) == TileColorResolver.fitzgerald(pos))
        }
    }

    // MARK: - The caregiver's library

    private func container() -> ModelContainer {
        let container = TestStore.freshContainer()
        // The library lives on the system profile — the caregiver's own record.
        let system = ChildProfile(displayName: "Caregiver")
        system.isSystem = true
        container.mainContext.insert(system)
        return container
    }

    @Test("An empty library stores as nothing")
    func emptyLibraryStoresEmpty() {
        #expect(ColorMapLibrary.encode([]).isEmpty)
        #expect(ColorMapLibrary.decode("").isEmpty)
    }

    @Test("A palette survives save and reload")
    func libraryRoundTrips() {
        let context = container().mainContext
        var map = TileColorMap(name: "Ada's palette")
        map.set(Color(hex: "#E00000"), for: .verb)

        ColorMapLibrary.store(map, in: context)
        let loaded = ColorMapLibrary.load(from: context)

        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "Ada's palette")
        #expect(loaded.first?.color(for: .verb)?.hexString == "#E00000")
    }

    /// Saving twice under one name replaces rather than accumulating, or a
    /// caregiver refining a palette ends up with three near-identical entries
    /// they then have to tell apart.
    @Test("Saving under an existing name replaces it")
    func savingUnderTheSameNameReplaces() {
        let context = container().mainContext
        var first = TileColorMap(name: "CVI")
        first.set(Color(hex: "#E00000"), for: .verb)
        ColorMapLibrary.store(first, in: context)

        var second = TileColorMap(name: "CVI")
        second.set(Color(hex: "#00A040"), for: .verb)
        ColorMapLibrary.store(second, in: context)

        let loaded = ColorMapLibrary.load(from: context)
        #expect(loaded.count == 1, "the library accumulated a duplicate name")
        #expect(loaded.first?.color(for: .verb)?.hexString == "#00A040")
    }

    @Test("Palettes can be renamed and deleted")
    func libraryRenameAndDelete() {
        let context = container().mainContext
        ColorMapLibrary.store(TileColorMap(name: "One", overrides: ["verb": "#E00000"]),
                              in: context)
        ColorMapLibrary.store(TileColorMap(name: "Two", overrides: ["noun": "#0066CC"]),
                              in: context)

        ColorMapLibrary.rename("One", to: "Renamed", in: context)
        var names = ColorMapLibrary.load(from: context).map(\.name)
        #expect(names.contains("Renamed"))
        #expect(!names.contains("One"))

        ColorMapLibrary.remove(named: "Two", from: context)
        names = ColorMapLibrary.load(from: context).map(\.name)
        #expect(names == ["Renamed"])
    }

    /// The library belongs to the caregiver, not to a child — the whole point is
    /// reuse across children.
    @Test("The library lives on the system profile, not the child")
    func libraryLivesOnTheSystemProfile() {
        let container = container()
        let context = container.mainContext
        let child = ChildProfile(displayName: "Ada")
        context.insert(child)

        ColorMapLibrary.store(TileColorMap(name: "Shared", overrides: ["verb": "#E00000"]),
                              in: context)

        #expect(child.colorMapLibrary.isEmpty, "a child's record should not hold the library")
        #expect(ColorMapLibrary.owner(in: context)?.isSystem == true)
        #expect(!ColorMapLibrary.load(from: context).isEmpty)
    }

    /// Same rule as a single map: unreadable storage is an empty library, not a
    /// thrown error. A caregiver locked out of the editor by one bad entry is
    /// worse than one who saves it again.
    @Test("Unreadable library storage decodes to empty")
    func libraryGarbageIsEmpty() {
        #expect(ColorMapLibrary.decode("not json").isEmpty)
    }

    // MARK: - Presets

    /// A therapist should not have to invent a high-contrast palette from first
    /// principles.
    @Test("Presets are usable and well formed")
    func presetsAreWellFormed() {
        #expect(!TileColorMap.presets.isEmpty)
        for preset in TileColorMap.presets {
            #expect(!preset.name.isEmpty)
            #expect(!preset.isEmpty)
            for (raw, hex) in preset.overrides {
                #expect(PartOfSpeech(rawValue: raw) != nil, "\(raw) is not a part of speech")
                #expect(Color(hex: hex) != nil, "\(hex) is not a color")
            }
        }
    }

    /// The CVI preset deliberately uses FEWER distinct colors than Fitzgerald,
    /// because for that child eight was never eight.
    @Test("The CVI preset collapses colors rather than adding them")
    func cviPresetCollapses() {
        let distinct = Set(TileColorMap.highContrastCVI.overrides.values)
        #expect(distinct.count < TileColorMap.highContrastCVI.overrides.count,
                "the CVI preset should share colors across types")
    }
}
}
