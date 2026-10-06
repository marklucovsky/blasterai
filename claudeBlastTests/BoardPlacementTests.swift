// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardPlacementTests.swift
//  claudeBlastTests
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {

/// Which words the bundled board puts on which pages. Nothing pinned page
/// contents before; these pin the session-8 placement audit
/// (`tools/audit_page_placement.py`), so a later edit to a class selector
/// cannot quietly take a word back off a page it was placed on by hand.
@MainActor
@Suite(.serialized)
struct BoardPlacementTests {

    private func load() -> BootstrapLoader.LoadResult {
        BootstrapLoader.loadDefaultVocabulary(context: TestStore.freshContainer().mainContext)
    }

    private func board() -> [String: [TileEntry]] {
        Dictionary(uniqueKeysWithValues: load().scene.pages.map { ($0.key, $0.tiles) })
    }

    private func keys(_ tiles: [TileEntry]?) -> [String] { (tiles ?? []).map(\.key) }

    /// Words a child reaches for from more than one place.
    @Test func secondHomes() {
        let b = board()
        for (page, words) in [
            ("body_health", ["sick", "hurt", "tired", "feel", "uncomfortable", "doctor", "bathroom", "toilet"]),
            ("feelings", ["sick", "lonely", "surprised", "okay_", "hurt", "feel"]),
            ("places", ["bus", "bathroom"]),
        ] {
            for word in words {
                #expect(keys(b[page]).contains(word), "\(word) on \(page)")
            }
        }
    }

    /// No folder from Food to Drinks or back. The silent Drinks folder inside a
    /// page reached by the audible "eat" made <eat> <drinks> <chocolate milk>
    /// read "eat chocolate milk".
    @Test func foodAndDrinksHaveNoInteriorFolders() {
        let b = board()
        #expect(b["food"]?.contains { !$0.link.isEmpty } == false)
        #expect(b["drinks"]?.contains { !$0.link.isEmpty } == false)
    }

    /// Food still fits one 12×5 page with Home in cell 0 — which is why
    /// `meals`, a category word, left it.
    @Test func foodFitsOnePage() {
        let b = board()
        let food = keys(b["food"])
        #expect(Array(food.prefix(2)) == ["hungry", "more"])
        #expect(!food.contains("meals"))
        #expect(food.count <= 12 * 5 - 1, "Food is \(food.count) words")
        #expect(Array(keys(b["drinks"]).prefix(2)) == ["thirsty", "more"])
    }

    /// Answer rows, at the same reach on every page that has one.
    ///
    /// Home answers yes / all done / no at the start of its bottom row (cell
    /// 48). Food, being full, answers yummy / all done / yucky in the same
    /// cells. The shorter pages put theirs at the start of the row after their
    /// words (cell 24) — on Drinks right under the drinks, so a phone does not
    /// have to page past empty rows to reach it. Describe stacks three such rows
    /// on its first page, the top one on that same cell 24 and the bottom one
    /// under Home's answers. Cell 0 is Home, so cell N is the page's word N−1.
    @Test func answerRowsSitAtTheSameReach() {
        let b = board()
        func cells(_ page: String, _ cell: Int) -> [String] {
            let words = keys(b[page])
            return Array(words[(cell - 1)..<min(cell + 2, words.count)])
        }
        #expect(cells("home", 48) == ["yes", "all_done", "no"])
        #expect(cells("food", 48) == ["yummy", "all_done", "yucky"])
        #expect(cells("drinks", 24) == ["yummy", "all_done", "yucky"])
        #expect(cells("social", 24) == ["yes", "i_dont_know", "no"])
        #expect(cells("time_when", 24) == ["always", "sometimes", "never"])
        #expect(cells("describe", 24) == ["true", "maybe", "false"])
        #expect(cells("describe", 36) == ["always", "sometimes", "never"])
        #expect(cells("describe", 48) == ["right", "okay_", "wrong"])
    }

    /// Words beside each other that mean opposite things in one dimension take
    /// one part of speech, and so one colour. The two "right"s had each other's,
    /// so the direction "right" was coloured unlike the `left` beside it. And
    /// `back` the body part is a noun; `back_` (go back) is not.
    @Test func partsOfSpeechMatchTheirNeighbours() {
        let pos = PartOfSpeechIndex.bundledPartOfSpeech(for:)
        #expect(pos("right_") == pos("left"))
        #expect(pos("right") == pos("wrong"))
        #expect(pos("back") == .noun)
        #expect(pos("back_") != .noun)
        // `hurt` sits with sick / tired on Feelings and Body & Health, where it
        // means "I'm hurt", not "to hurt someone". `feel` stays the carrier verb.
        #expect(pos("hurt") == pos("sick"))
        #expect(pos("hurt") == .adjective)
        #expect(pos("feel") == .verb)
    }

    /// The duplicate senses are gone from the vocabulary; the kept ones remain.
    @Test func duplicateSensesAreGone() {
        let all = Set(load().tiles.map(\.key))
        for gone in ["hard_", "light_", "old_"] { #expect(!all.contains(gone), "\(gone)") }
        for kept in ["hard", "light", "old", "right", "right_"] { #expect(all.contains(kept), "\(kept)") }
    }

    /// Describe is laid out by hand: opposites side by side, in the same column
    /// pairs on every row of page 1, and themed rows on page 2. A class
    /// selector put them in alphabetical order, which scattered every pair.
    @Test func describeKeepsItsClusters() {
        let describe = keys(board()["describe"])
        let index = { (k: String) in describe.firstIndex(of: k) ?? -100 }
        for run in [["big", "little"], ["hot_", "cold__"], ["fast", "slow"], ["wet", "dry_"],
                    ["fat", "thin"], ["clean_", "dirty"], ["full", "empty"], ["young", "old"],
                    ["first", "next", "last"], ["better", "best", "worse", "worst"],
                    ["top", "bottom", "front", "behind"]] {
            let start = index(run[0])
            #expect(run.indices.allSatisfy { index(run[$0]) == start + $0 }, "\(run)")
        }
        // The everyday pairs are on the first screen (cells 1–59).
        for word in ["big", "good", "hot_", "wet", "full", "yummy", "same", "smart"] {
            #expect(index(word) < 59, "\(word) on page 1")
        }
    }

    /// A verb that is on Home keeps its Home cell on Actions — eat, drink and
    /// play in cells 3–5, come / go in 15–16, want in 28 — so the reach learned
    /// on Home works on Actions. The page's clusters form around those points.
    @Test func actionsKeepsHomesVerbsInTheirHomeCells() {
        let b = board()
        let home = keys(b["home"]), actions = keys(b["actions"])
        let firstScreen = Array(actions.prefix(59))
        let shared = home.enumerated().filter { firstScreen.contains($0.element) }
        #expect(shared.count >= 18, "\(shared.count) of Home's words on Actions page 1")
        for (cell, word) in shared {
            #expect(firstScreen.firstIndex(of: word) == cell, "\(word)")
        }
    }

    @Test func actionsKeepsItsClusters() {
        let actions = keys(board()["actions"])
        let index = { (k: String) in actions.firstIndex(of: k) ?? -100 }
        for run in [["catch", "throw", "kick"], ["walk", "run", "swim"], ["come", "go"],
                    ["give", "take"], ["find", "lose"], ["sit", "stand"], ["close", "open"],
                    ["talk", "say", "ask", "answer", "speak"], ["write", "draw", "color", "paint"],
                    ["know", "think", "remember", "forget"], ["wash", "wash_hands", "wash_hair"]] {
            let start = index(run[0])
            #expect(run.indices.allSatisfy { index(run[$0]) == start + $0 }, "\(run)")
        }
    }

    /// Groups opens four noun folders added in session 8, each page holding its
    /// words, and the everyday vehicles also sit on Places with `home_`.
    @Test func groupsOpensTheNounFolders() {
        let b = board()
        let links = (b["groups"] ?? []).map(\.link)
        for (page, words) in [
            ("animals", ["dog", "cat", "bird", "fish", "horse", "cow", "pig", "duck", "chicken", "sheep"]),
            ("clothes", ["shoes", "socks", "shirt", "pants", "coat", "hat", "pajamas"]),
            ("things", ["bed", "blanket", "book", "phone", "tv", "music", "toothbrush", "cup", "plate", "spoon", "fork"]),
            ("vehicles", ["car", "bus", "truck", "train", "bicycle", "airplane", "boat", "helicopter",
                          "fire_truck", "ambulance", "police_car"]),
        ] {
            #expect(links.contains(page), "groups → \(page)")
            #expect(keys(b[page]) == words, "\(page)")
        }
        for word in ["home_", "car", "train", "bicycle", "airplane", "boat"] {
            #expect(keys(b["places"]).contains(word), "\(word) on places")
        }
    }

    /// Body & Health is laid out by hand: head to toe on row 1, then the
    /// toileting words together, then how it feels, then who helps.
    @Test func bodyHealthKeepsItsClusters() {
        let body = keys(board()["body_health"])
        let index = { (k: String) in body.firstIndex(of: k) ?? -100 }
        #expect(Array(body.prefix(11)) == ["head", "hair", "face", "eye", "ear", "nose",
                                           "mouth", "tooth", "arm", "hand", "finger"])
        for run in [["leg", "knee", "foot"], ["potty", "pee", "poop", "bathroom", "toilet"],
                    ["sick", "hurt", "tired"], ["medicine", "bandaid", "doctor"]] {
            let start = index(run[0])
            #expect(run.indices.allSatisfy { index(run[$0]) == start + $0 }, "\(run)")
        }
    }

    /// Session 8's new verbs join the Actions clusters on page 2, and the core
    /// connecting words (`or because but`, `will`, `one`) sit on Describe — not
    /// on a page of their own.
    @Test func newWordsJoinTheirClusters() {
        let b = board()
        let actions = keys(b["actions"]), describe = keys(b["describe"])
        func isRun(_ words: [String], _ run: [String]) -> Bool {
            guard let start = words.firstIndex(of: run[0]) else { return false }
            return run.indices.allSatisfy { start + $0 < words.count && words[start + $0] == run[$0] }
        }
        for run in [["jump", "climb"], ["build", "hide", "share", "hug"], ["chew", "bite"], ["cook", "line_up", "lets"]] {
            #expect(isRun(actions, run), "actions \(run)")
            #expect(actions.firstIndex(of: run[0]).map { $0 >= 59 } == true, "\(run) on page 2")
        }
        for run in [["or", "because", "but"], ["soon", "will"], ["few", "one"], ["sticky", "sharp", "closed"]] {
            #expect(isRun(describe, run), "describe \(run)")
        }
        #expect(!describe.contains("not"))
    }

    /// The two "right"s sit with their opposites on Describe: the direction
    /// next to `left`, the correct one in a row with `wrong`.
    @Test func eachRightSitsBesideItsOpposite() {
        let describe = keys(board()["describe"])
        let index = { (k: String) in describe.firstIndex(of: k) ?? -100 }
        #expect(index("right_") == index("left") + 1)
        // The correct sense is in Describe's answer stack: right · okay · wrong.
        #expect(index("right") + 2 == index("wrong"))
    }
}
}
