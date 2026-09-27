// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  PageBuildCommandTests.swift
//  claudeBlastTests
//
//  Round-trip tests for the JSON DSL shape — guards against regressions
//  as bundled scene files start to ride on this encoding.
//

import Testing
import Foundation
@testable import claudeBlast

@MainActor
struct PageBuildCommandTests {

    @Test func classSingle_decodesString() throws {
        let json = #"{"class": "actions"}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .classSelector(let classes, let exclude, let limit, let orderBy) = cmd else {
            Issue.record("expected classSelector"); return
        }
        #expect(classes == ["actions"])
        #expect(exclude == [])
        #expect(limit == nil)
        #expect(orderBy == .vocab)
    }

    @Test func classMulti_decodesArray() throws {
        let json = #"{"class": ["food","drinks"], "exclude": ["pizza"], "limit": 8, "orderBy": "name"}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .classSelector(let classes, let exclude, let limit, let orderBy) = cmd else {
            Issue.record("expected classSelector"); return
        }
        #expect(classes == ["food","drinks"])
        #expect(exclude == ["pizza"])
        #expect(limit == 8)
        #expect(orderBy == .name)
    }

    @Test func keys_decodes() throws {
        let json = #"{"keys": ["i","me","you"]}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .keys(let keys) = cmd else { Issue.record("expected keys"); return }
        #expect(keys == ["i","me","you"])
    }

    @Test func link_decodes() throws {
        let json = #"{"link": "people", "to": "people", "audible": false}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .link(let key, let to, let audible, let color) = cmd else {
            Issue.record("expected link"); return
        }
        #expect(key == "people")
        #expect(to == "people")
        #expect(audible == false)
        // A link written before folders could carry a color must still decode,
        // and must not invent one — absent means wayfinding, which is what every
        // link did before.
        #expect(color == nil)
    }

    @Test func link_decodes_a_color() throws {
        let json = #"{"link": "actions", "to": "actions", "audible": false, "linkColor": "verb"}"#
            .data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .link(_, _, _, let color) = cmd else {
            Issue.record("expected link"); return
        }
        #expect(color == "verb")
    }

    /// The color has to survive a round trip, or re-exporting a scene would
    /// quietly strip every folder back to blue.
    @Test func link_color_round_trips() throws {
        let original = PageBuildCommand.link(key: "actions", to: "actions",
                                             audible: false, color: "verb")
        let data = try JSONEncoder().encode(original)
        let back = try JSONDecoder().decode(PageBuildCommand.self, from: data)
        #expect(back == original)
        // Absent rather than null when there is no color, so an untouched scene
        // file does not grow noise.
        let plain = PageBuildCommand.link(key: "eat", to: "food", audible: true, color: nil)
        let text = String(data: try JSONEncoder().encode(plain), encoding: .utf8) ?? ""
        #expect(!text.contains("linkColor"))
    }

    @Test func remove_decodes() throws {
        let json = #"{"remove": "stop"}"#.data(using: .utf8)!
        let cmd = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        guard case .remove(let key) = cmd else { Issue.record("expected remove"); return }
        #expect(key == "stop")
    }

    @Test func unknownCommand_throws() {
        let json = #"{"bogus": "x"}"#.data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(PageBuildCommand.self, from: json)
        }
    }

    @Test func roundTrip_classSingle() throws {
        let original = PageBuildCommand.classSelector(classes: ["actions"], exclude: [], limit: nil, orderBy: .vocab)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageBuildCommand.self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTrip_classMultiWithOptions() throws {
        let original = PageBuildCommand.classSelector(
            classes: ["food","drinks"], exclude: ["pizza"], limit: 8, orderBy: .name)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageBuildCommand.self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTrip_link() throws {
        let original = PageBuildCommand.link(key: "eat", to: "<home>", audible: true, color: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PageBuildCommand.self, from: data)
        #expect(decoded == original)
    }

    @Test func roundTrip_fullPage() throws {
        let page = PageJSON(key: "home", tiles: [
            .link(key: "people", to: "people", audible: false, color: nil),
            .keys(["i","me","you","my","your","it"]),
            .classSelector(classes: ["actions"], exclude: ["eat"], limit: nil, orderBy: .vocab),
            .remove("stop"),
        ])
        let data = try JSONEncoder().encode(page)
        let decoded = try JSONDecoder().decode(PageJSON.self, from: data)
        #expect(decoded.key == "home")
        #expect(decoded.tiles.count == 4)
        #expect(decoded.tiles == page.tiles)
    }
}
