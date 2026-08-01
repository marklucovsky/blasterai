// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BulkWordParserTests.swift
//  claudeBlastTests
//
//  The shared `key, class[, Display Name]` CSV parser (bulk-word sheet + the
//  tile picker's editable selection list). Pure logic — no container.
//

import Testing
@testable import claudeBlast

struct BulkWordParserTests {
    @Test func twoTupleDefaultsDisplayNameToKey() {
        let r = BulkWordParser.parse("potty, body")
        #expect(r.words.count == 1)
        #expect(r.words[0].key == "potty")
        #expect(r.words[0].wordClass == "body")
        #expect(r.words[0].displayName == "potty")
        #expect(r.skipped.isEmpty)
    }

    @Test func threeTupleKeepsExplicitDisplayName() {
        let r = BulkWordParser.parse("earth, place, Planet Earth")
        #expect(r.words[0].key == "earth")
        #expect(r.words[0].wordClass == "place")
        #expect(r.words[0].displayName == "Planet Earth")
    }

    @Test func lowercasesClassAndSkipsUnderColumnLines() {
        let r = BulkWordParser.parse("""
        rocket, OBJECT
        # a comment

        justoneword
        astronaut, people
        """)
        #expect(r.words.map(\.key) == ["rocket", "astronaut"])
        #expect(r.words[0].wordClass == "object")          // lowercased
        #expect(r.skipped == ["justoneword"])              // needs ≥2 columns
    }

    @Test func blankAndHashLinesIgnoredNotSkipped() {
        let r = BulkWordParser.parse("\n#hi\n   \n")
        #expect(r.words.isEmpty)
        #expect(r.skipped.isEmpty)
    }
}
