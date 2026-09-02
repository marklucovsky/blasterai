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

    @Test("Both shipped formats are declared and openable")
    func bothFormatsRegistered() {
        let declared = declaredExtensions
        for ext in [BlasterSceneFormat.fileExtension, BlasterPackFormat.fileExtension] {
            #expect(declared.contains(ext), "Info.plist does not declare .\(ext)")
            #expect(BlasterFileFormat.openableExtensions.contains(ext))
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
