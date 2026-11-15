// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  HelpManifestTests.swift
//  claudeBlastTests
//
//  Which set of guides a build reads, from the site's help/index.json.
//

import Testing
import Foundation
@testable import claudeBlast

struct HelpManifestTests {
    private func manifest(_ json: String) throws -> HelpManifest {
        try JSONDecoder().decode(HelpManifest.self, from: Data(json.utf8))
    }

    /// An old build keeps the frozen guides that match its screens while the
    /// main guides move on; the newest build reads the main ones.
    @Test func eachBuildReadsTheSetThatHoldsIt() throws {
        let m = try manifest("""
        {"version":1,"sets":[
          {"fromBuild":15,"index":"/guides/index.json"},
          {"fromBuild":11,"toBuild":14,"index":"/guides/b14/index.json"},
          {"fromBuild":1,"toBuild":10,"index":"/guides/b10/index.json"}]}
        """)
        #expect(m.set(for: 17)?.index == "/guides/index.json")
        #expect(m.set(for: 14)?.index == "/guides/b14/index.json")
        #expect(m.set(for: 11)?.index == "/guides/b14/index.json")
        #expect(m.set(for: 3)?.index == "/guides/b10/index.json")
        #expect(m.set(for: 0) == nil)
    }

    /// The manifest the site ships today: one set for every build. Unknown
    /// keys (the `about` note) are ignored rather than failing the decode.
    @Test func todaysManifestCoversEveryBuild() throws {
        let m = try manifest("""
        {"version":1,"about":"…","sets":[{"fromBuild":1,"index":"/guides/index.json"}]}
        """)
        #expect(m.set(for: 11)?.index == "/guides/index.json")
        #expect(HelpSite.url("/guides/board-layout/").absoluteString
                == "https://blasterai.app/guides/board-layout/")
    }
}
