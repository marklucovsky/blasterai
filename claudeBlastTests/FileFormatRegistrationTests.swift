// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  FileFormatRegistrationTests.swift
//  claudeBlastTests
//
//  A file Blaster claims in Info.plist must actually open.
//

import Testing
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct FileFormatRegistrationTests {

    /// Extensions the app bundle tells the system it can open, read back out of
    /// the built Info.plist rather than retyped here.
    private var declaredExtensions: Set<String> {
        let types = Bundle.main.object(forInfoDictionaryKey: "UTExportedTypeDeclarations") as? [[String: Any]] ?? []
        var found = Set<String>()
        for type in types {
            let tags = type["UTTypeTagSpecification"] as? [String: Any] ?? [:]
            if let exts = tags["public.filename-extension"] as? [String] {
                found.formUnion(exts.map { $0.lowercased() })
            }
        }
        return found
    }

    /// The bug this suite exists for.
    ///
    /// The pack format was declared in Info.plist and handled by the import
    /// sheet, but `onOpenURL` still tested for the scene extension alone. A
    /// `.blasterpack` sent through Messages launched the app and then vanished —
    /// no sheet, no error, nothing to tell the caregiver why. Three places have
    /// to agree, and nothing made them.
    @Test("Every declared file type is one the app will actually open")
    func declaredTypesAreOpenable() {
        let declared = declaredExtensions
        #expect(!declared.isEmpty, "Info.plist declares no exported types")

        for ext in declared {
            let url = URL(fileURLWithPath: "/tmp/example.\(ext)")
            #expect(BlasterFileFormat.canOpen(url),
                    "Info.plist claims .\(ext) but onOpenURL would drop it")
        }
    }

    /// Named "both" when there were two. Every format the app opens belongs
    /// here, so a new one that reaches `openableExtensions` without an
    /// Info.plist declaration is caught from the other direction than
    /// `declaredTypesAreOpenable` checks.
    @Test("Every shipped format is declared and openable")
    func bothFormatsRegistered() {
        let declared = declaredExtensions
        for ext in [BlasterSceneFormat.fileExtension, BlasterSceneFormat.legacyFileExtension,
                    BlasterPackFormat.fileExtension,
                    BlasterColorwayFormat.fileExtension, BlasterKeyFormat.fileExtension] {
            #expect(declared.contains(ext), "Info.plist does not declare .\(ext)")
            #expect(BlasterFileFormat.openableExtensions.contains(ext))
        }
    }

    /// The fourth place, and the one with no other guard on it.
    ///
    /// `ImportRouteSheet`'s switch falls through to the scene importer, so a
    /// format declared in Info.plist and accepted by `canOpen` but missing a
    /// case here does not vanish — it opens with the wrong decoder and reports a
    /// parse error about a file that is perfectly fine. That is harder to
    /// diagnose than the disappearing-file bug this suite was written for,
    /// because something *does* happen and the message is plausible.
    @Test("Every openable format routes to its own importer")
    func everyFormatRoutes() {
        let expected: [String: ImportRouteSheet.Route] = [
            BlasterSceneFormat.fileExtension: .scene,
            BlasterSceneFormat.legacyFileExtension: .scene,
            BlasterPackFormat.fileExtension: .pack,
            BlasterColorwayFormat.fileExtension: .colorway,
            BlasterKeyFormat.fileExtension: .giftedKey,
        ]
        for ext in BlasterFileFormat.openableExtensions {
            let route = ImportRouteSheet.route(for: URL(fileURLWithPath: "/tmp/example.\(ext)"))
            #expect(route == expected[ext],
                    ".\(ext) is openable but ImportRouteSheet sends it to \(route)")
        }
    }

    /// The fallthrough still has to work: an unknown extension that somehow
    /// reaches the sheet gets the scene importer and its error, rather than
    /// nothing at all.
    @Test("An unknown extension still lands somewhere")
    func unknownExtensionFallsThrough() {
        #expect(ImportRouteSheet.route(for: URL(fileURLWithPath: "/tmp/x.whatever")) == .scene)
    }

    /// Board files became `.blasterboard` in build 11; everything shared
    /// before that is `.blasterscene` and has to keep opening.
    @Test("A board file from before build 11 still opens")
    func oldBoardFilesStillOpen() {
        #expect(BlasterSceneFormat.fileExtension == "blasterboard")
        for name in ["/tmp/Aubrey.blasterscene", "/tmp/Aubrey.blasterboard"] {
            let url = URL(fileURLWithPath: name)
            #expect(BlasterFileFormat.canOpen(url))
            #expect(ImportRouteSheet.route(for: url) == .scene)
        }
    }

    @Test("An unrelated file is left alone")
    func foreignFilesAreIgnored() {
        #expect(!BlasterFileFormat.canOpen(URL(fileURLWithPath: "/tmp/notes.txt")))
        #expect(!BlasterFileFormat.canOpen(URL(fileURLWithPath: "/tmp/board.pdf")))
    }

    /// Case arrives however the sender's filesystem stored it.
    @Test("Extension matching ignores case")
    func extensionMatchIsCaseInsensitive() {
        #expect(BlasterFileFormat.canOpen(URL(fileURLWithPath: "/tmp/A.BLASTERPACK")))
        #expect(BlasterFileFormat.canOpen(URL(fileURLWithPath: "/tmp/A.BlasterScene")))
    }
}
}
