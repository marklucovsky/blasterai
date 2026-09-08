// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ColorwayTransferTests.swift
//  claudeBlastTests
//
//  Applying without asking is only safe if nothing is lost.
//

import Testing
import SwiftData
import Foundation
import SwiftUI
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ColorwayTransferTests {

    private func makeResolver(_ context: ModelContext) -> ChildProfileResolver {
        ProfileMigration.ensureProfilesAfterBootstrap(context: context)
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: context)
        return resolver
    }

    private func colorwayData(name: String,
                              overrides: [String: String],
                              type: String = BlasterColorwayFormat.mediaType,
                              version: String = "1.0.0") -> Data {
        let body: [String: Any] = [
            "@type": type,
            "version": version,
            "name": name,
            "overrides": overrides,
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    // MARK: - Round trip

    @Test("A colorway survives export and import")
    func roundTrip() throws {
        let map = TileColorMap(name: "Warm", overrides: ["verb": "#FF0000"])
        let data = try ColorwayExporter.data(for: map)
        let back = try ColorwayImporter.preview(data)

        #expect(back.name == "Warm")
        #expect(back.overrides == ["verb": "#FF0000"])
        #expect(back.type == BlasterColorwayFormat.mediaType)
    }

    /// The file name is the only thing a recipient sees before they tap it.
    @Test("The file name carries the colorway's name")
    func fileNameCarriesTheName() {
        let map = TileColorMap(name: "Warm Bias", overrides: ["verb": "#FF0000"])
        let name = ColorwayExporter.suggestedFileName(for: map)
        #expect(name.contains("Warm Bias"))
        #expect(name.hasSuffix(".blastercolors"))
    }

    // MARK: - Refusals

    @Test("A file of the wrong type is refused")
    func wrongTypeIsRefused() {
        let data = colorwayData(name: "X", overrides: ["verb": "#FF0000"],
                                type: "application/vnd.claudeblast.scene+json")
        #expect(throws: (any Error).self) { try ColorwayImporter.preview(data) }
    }

    /// A colorway that changes nothing would silently reset the child to the
    /// defaults — destructive, wearing the costume of an import.
    @Test("A colorway that changes nothing is refused")
    func emptyColorwayIsRefused() {
        #expect(throws: ColorwayTransferError.empty) {
            try ColorwayImporter.preview(colorwayData(name: "Nothing", overrides: [:]))
        }
    }

    // MARK: - Applied on arrival

    @Test("A colorway applies to the active profile without asking")
    func appliesOnArrival() throws {
        let context = TestStore.freshContainer().mainContext
        let resolver = makeResolver(context)

        let data = colorwayData(name: "Warm", overrides: ["verb": "#FF0000"])
        let result = try ColorwayImporter.apply(data, context: context, resolver: resolver)

        #expect(result.applied.name == "Warm")
        let active = try #require(resolver.active)
        #expect(TileColorMap.decode(active.colorMapData).overrides == ["verb": "#FF0000"])
    }

    /// The received set is filed too. Colors that exist only on one child are
    /// colors that vanish the moment someone experiments.
    @Test("The received colorway joins the library")
    func receivedColorwayIsFiled() throws {
        let context = TestStore.freshContainer().mainContext
        let resolver = makeResolver(context)

        let data = colorwayData(name: "Warm", overrides: ["verb": "#FF0000"])
        _ = try ColorwayImporter.apply(data, context: context, resolver: resolver)

        #expect(ColorMapLibrary.load(from: context).contains { $0.name == "Warm" })
    }

    // MARK: - Nothing is lost

    /// The property the whole design rests on. Applying without a prompt is only
    /// defensible because the colors being replaced are rescued first.
    @Test("Unsaved colors in use are preserved before being replaced")
    func unsavedColorsArePreserved() throws {
        let context = TestStore.freshContainer().mainContext
        let resolver = makeResolver(context)

        let active = try #require(resolver.active)
        active.colorMapData = TileColorMap(name: "Mine", overrides: ["noun": "#00FF00"]).encoded

        let data = colorwayData(name: "Warm", overrides: ["verb": "#FF0000"])
        let result = try ColorwayImporter.apply(data, context: context, resolver: resolver)

        let preserved = try #require(result.preservedAs)
        let library = ColorMapLibrary.load(from: context)
        let rescued = try #require(library.first { $0.name == preserved })
        #expect(rescued.overrides == ["noun": "#00FF00"])
    }

    /// Compared by content, not by name. A caregiver who started from a preset
    /// and tweaked two colors has a map whose *name* still matches the library
    /// entry while its contents no longer do — matching on name would call that
    /// safe and overwrite it.
    @Test("A tweaked-but-unsaved map is preserved even though its name is in the library")
    func tweakedMapWithAFamiliarNameIsPreserved() throws {
        let context = TestStore.freshContainer().mainContext
        let resolver = makeResolver(context)

        ColorMapLibrary.store(TileColorMap(name: "Mine", overrides: ["noun": "#00FF00"]),
                              in: context)
        let active = try #require(resolver.active)
        // Same name, different contents — the unsaved tweak.
        active.colorMapData = TileColorMap(name: "Mine",
                                           overrides: ["noun": "#00FF00",
                                                       "verb": "#0000FF"]).encoded

        let data = colorwayData(name: "Warm", overrides: ["verb": "#FF0000"])
        let result = try ColorwayImporter.apply(data, context: context, resolver: resolver)

        let preserved = try #require(result.preservedAs)
        let rescued = try #require(ColorMapLibrary.load(from: context).first { $0.name == preserved })
        #expect(rescued.overrides == ["noun": "#00FF00", "verb": "#0000FF"])
    }

    /// Colors already filed need no rescue, and a duplicate entry every time a
    /// colorway arrives would bury the library.
    @Test("Colors already in the library are not duplicated")
    func savedColorsAreNotRescuedAgain() throws {
        let context = TestStore.freshContainer().mainContext
        let resolver = makeResolver(context)

        let mine = TileColorMap(name: "Mine", overrides: ["noun": "#00FF00"])
        ColorMapLibrary.store(mine, in: context)
        let active = try #require(resolver.active)
        active.colorMapData = mine.encoded

        let data = colorwayData(name: "Warm", overrides: ["verb": "#FF0000"])
        let result = try ColorwayImporter.apply(data, context: context, resolver: resolver)

        #expect(result.preservedAs == nil)
        #expect(ColorMapLibrary.load(from: context).count == 2) // Mine + Warm
    }

    /// A child on the defaults has nothing worth keeping, and an entry called
    /// "Previous colors" holding no overrides is noise.
    @Test("Default colors are not rescued")
    func defaultColorsAreNotRescued() throws {
        let context = TestStore.freshContainer().mainContext
        let resolver = makeResolver(context)

        let data = colorwayData(name: "Warm", overrides: ["verb": "#FF0000"])
        let result = try ColorwayImporter.apply(data, context: context, resolver: resolver)

        #expect(result.preservedAs == nil)
    }

    /// `ColorMapLibrary.store` replaces by name, so an incoming set sharing a
    /// name with one the caregiver built would silently destroy theirs.
    @Test("An incoming name collision does not overwrite the caregiver's own set")
    func nameCollisionDoesNotOverwrite() throws {
        let context = TestStore.freshContainer().mainContext
        let resolver = makeResolver(context)

        ColorMapLibrary.store(TileColorMap(name: "Warm", overrides: ["noun": "#00FF00"]),
                              in: context)

        let data = colorwayData(name: "Warm", overrides: ["verb": "#FF0000"])
        _ = try ColorwayImporter.apply(data, context: context, resolver: resolver)

        let library = ColorMapLibrary.load(from: context)
        let original = try #require(library.first { $0.name == "Warm" })
        #expect(original.overrides == ["noun": "#00FF00"], "the caregiver's own set was replaced")
        #expect(library.contains { $0.overrides == ["verb": "#FF0000"] })
    }

    /// The same file arriving twice is one colorway, not two.
    @Test("Re-importing the same colorway does not pile up entries")
    func reimportIsIdempotent() throws {
        let context = TestStore.freshContainer().mainContext
        let resolver = makeResolver(context)

        let data = colorwayData(name: "Warm", overrides: ["verb": "#FF0000"])
        _ = try ColorwayImporter.apply(data, context: context, resolver: resolver)
        _ = try ColorwayImporter.apply(data, context: context, resolver: resolver)

        #expect(ColorMapLibrary.load(from: context).filter { $0.name == "Warm" }.count == 1)
    }

    // MARK: - Registration

    /// `BlasterFileFormat` carries the warning: when the pack format was added
    /// this guard was missed, and files arrived, launched the app, and vanished.
    @Test("A colorway file is openable")
    func colorwayFileIsOpenable() {
        let url = URL(fileURLWithPath: "/tmp/Colors — Warm.blastercolors")
        #expect(BlasterFileFormat.canOpen(url))
    }
}
}
