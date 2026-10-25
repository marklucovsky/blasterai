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
///
/// Session 14 rebuilt BlasterAI 60 from `tools/board_spec/blasterai60.json`
/// (`tools/build_core_board.py`): a system row on every page, folders in
/// columns 11–12, and a word on a page and its folder in the same cell. The
/// session-8 decisions survive it. Opposites still sit side by side, answer
/// rows still line up, and Home's verbs keep their Home cells, now across the
/// folders a page was split into rather than across one long page.
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

    /// Row 1, the same eleven folders on every page.
    private static let rowLength = PageTemplate.cols - 1

    /// A page's words and folders below the system row, gaps left out.
    private func body(_ tiles: [TileEntry]?) -> [String] {
        (tiles ?? []).dropFirst(Self.rowLength).filter { !$0.isSpacer }.map(\.key)
    }

    /// The pages a category was split into, the category first.
    private func family(_ b: [String: [TileEntry]], _ category: String) -> [[String]] {
        let pages = [category] + b.keys.filter { $0.hasPrefix(category + "_") }.sorted()
        return pages.map { keys(b[$0]) }
    }

    /// True when `run` sits side by side, in order, on some page of `pages`.
    private func isRun(_ run: [String], in pages: [[String]]) -> Bool {
        pages.contains { words in
            guard let start = words.firstIndex(of: run[0]) else { return false }
            return run.indices.allSatisfy { start + $0 < words.count && words[start + $0] == run[$0] }
        }
    }

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
    /// read "eat chocolate milk". The system row is not such a folder: it holds
    /// neither page.
    @Test func foodAndDrinksHaveNoInteriorFolders() {
        let b = board()
        #expect(b["food"]?.contains { $0.link == "drinks" && !$0.isAudible } == false)
        #expect(b["drinks"]?.contains { $0.link == "food" && !$0.isAudible } == false)
        #expect(b["food"]?.contains { !$0.link.isEmpty && !$0.isAudible } == false)
    }

    /// Food still fits one 12×5 page with Home in cell 0 — which is why
    /// `meals`, a category word, left it. It is also why Food has no system row
    /// yet (`systemRowExempt`): the row would push it onto a second screen.
    @Test func foodFitsOnePage() {
        let b = board()
        let food = keys(b["food"])
        #expect(Array(food.prefix(2)) == ["hungry", "more"])
        #expect(!food.contains("meals"))
        #expect(food.count <= 12 * 5 - 1, "Food is \(food.count) words")
        #expect(Array(body(b["drinks"]).prefix(2)) == ["thirsty", "more"])
    }

    /// Answer rows, at the same reach on every page that has one.
    ///
    /// Home answers yes / all done / no at the start of its bottom row (cell
    /// 48), and Describe puts right / okay / wrong in the same cells. Food,
    /// being full, answers yummy / all done / yucky there too. The shorter pages
    /// put theirs at the start of the row after their words: cell 36 since the
    /// system row moved those pages down one row (cell 24 before). Cell 0 is
    /// Home, so cell N is the page's tile N−1.
    @Test func answerRowsSitAtTheSameReach() {
        let b = board()
        func cells(_ page: String, _ cell: Int) -> [String] {
            let words = keys(b[page])
            return Array(words[(cell - 1)..<min(cell + 2, words.count)])
        }
        #expect(cells("home", 48) == ["yes", "all_done", "no"])
        #expect(cells("describe", 48) == ["right", "okay_", "wrong"])
        #expect(cells("food", 48) == ["yummy", "all_done", "yucky"])
        #expect(cells("drinks", 36) == ["yummy", "all_done", "yucky"])
        #expect(cells("social", 36) == ["yes", "i_dont_know", "no"])
        #expect(cells("time_when", 36) == ["always", "sometimes", "never"])
        // true · maybe · false moved to What it's like, still a row.
        #expect(isRun(["true", "maybe", "false"], in: [keys(b["describe_what_its_like"])]))
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
    /// pairs on every row, and the rest in its folders. A class selector put them
    /// in alphabetical order, which scattered every pair.
    @Test func describeKeepsItsClusters() {
        let b = board()
        let pages = family(b, "describe")
        for run in [["big", "little"], ["hot_", "cold__"], ["fast", "slow"], ["wet", "dry_"],
                    ["fat", "thin"], ["clean_", "dirty"], ["full", "empty"], ["new", "old"],
                    ["old", "young"], ["better", "best", "worse", "worst"],
                    ["top", "bottom", "front", "behind"]] {
            #expect(isRun(run, in: pages), "\(run)")
        }
        // The everyday pairs are on Describe itself, one screen.
        let describe = keys(b["describe"])
        for word in ["big", "good", "hot_", "wet", "full", "yummy", "same", "smart"] {
            #expect(describe.contains(word), "\(word) on Describe")
        }
        #expect(describe.count <= 12 * 5 - 1)
    }

    /// A verb that is on Home keeps its Home cell on Actions — eat and drink in
    /// cells 17–18, come / go in 15–16, want in 28 — so the reach learned on
    /// Home works on Actions. A Home word in columns 11–12 (`stop`) is the
    /// exception: there those columns hold Actions' folders.
    @Test func actionsKeepsHomesVerbsInTheirHomeCells() {
        let b = board()
        let home = keys(b["home"]), actions = keys(b["actions"])
        let cols = PageTemplate.cols
        let shared = home.enumerated().filter { index, word in
            index >= Self.rowLength && (index + 1) % cols < cols - 2 && actions.contains(word)
        }
        #expect(shared.count >= 12, "\(shared.count) of Home's words on Actions")
        for (index, word) in shared {
            #expect(actions.firstIndex(of: word) == index, "\(word)")
        }
    }

    /// The same rule one level down: a word on Actions and on one of its folders
    /// sits in the same cell on both (Avaz; *teacher* on People and School people).
    @Test func aFolderKeepsItsParentsCells() {
        let b = board()
        let actions = keys(b["actions"])
        var checked = 0
        for (folder, tiles) in b where folder.hasPrefix("actions_") {
            for (index, tile) in tiles.enumerated() where index >= Self.rowLength && tile.link.isEmpty {
                guard let cell = actions.firstIndex(of: tile.key) else { continue }
                #expect(cell == index, "\(folder)/\(tile.key)")
                checked += 1
            }
        }
        #expect(checked >= 20, "only \(checked) shared words checked")
    }

    @Test func actionsKeepsItsClusters() {
        let pages = family(board(), "actions")
        for run in [["catch", "throw", "kick"], ["walk", "run", "jump"], ["come", "go"],
                    ["give", "take"], ["find", "lose"], ["sit", "stand"], ["close", "open"],
                    ["talk", "say", "ask", "answer", "speak"], ["draw", "color", "paint"],
                    ["know", "think", "remember", "forget"], ["wash", "wash_hands", "wash_hair"],
                    ["am", "are", "was"], ["bite", "chew"]] {
            #expect(isRun(run, in: pages), "\(run)")
        }
    }

    /// Things (the `groups` hub) opens the noun folders added in session 8, each
    /// page holding its words, and the everyday vehicles also sit on Places with
    /// `home_`. Door and window joined House things from Places in session 14.
    @Test func groupsOpensTheNounFolders() {
        let b = board()
        let links = (b["groups"] ?? []).map(\.link)
        for (page, words) in [
            ("animals", ["dog", "cat", "bird", "fish", "horse", "cow", "pig", "duck", "chicken", "sheep"]),
            ("clothes", ["shoes", "socks", "shirt", "pants", "coat", "hat", "pajamas"]),
            ("things", ["bed", "blanket", "book", "phone", "tv", "music", "toothbrush", "cup", "plate", "spoon",
                        "fork", "door", "window"]),
            ("vehicles", ["car", "bus", "truck", "train", "bicycle", "airplane", "boat", "helicopter",
                          "fire_truck", "ambulance", "police_car"]),
        ] {
            #expect(links.contains(page), "groups → \(page)")
            #expect(body(b[page]) == words, "\(page)")
        }
        for word in ["home_", "car", "train", "bicycle", "airplane", "boat"] {
            #expect(keys(b["places"]).contains(word), "\(word) on places")
        }
    }

    /// Body & Health is laid out by hand: head to toe on row 1, then the
    /// toileting words together, then how it feels, then who helps. The system
    /// row moved it down a row intact.
    @Test func bodyHealthKeepsItsClusters() {
        let body = self.body(board()["body_health"])
        #expect(Array(body.prefix(11)) == ["head", "hair", "face", "eye", "ear", "nose",
                                           "mouth", "tooth", "arm", "hand", "finger"])
        for run in [["leg", "knee", "foot"], ["potty", "pee", "poop", "bathroom", "toilet"],
                    ["sick", "hurt", "tired"], ["medicine", "bandaid", "doctor"]] {
            #expect(isRun(run, in: [body]), "\(run)")
        }
    }

    /// The connecting words (`or because but`) and `will` came off Describe,
    /// where session 8 had put them for want of a page, onto Small words, one tap
    /// from every page. `will` is on the I page too.
    @Test func smallWordsHoldTheConnectingWords() {
        let b = board()
        let small = keys(b["small_words"]), describe = keys(b["describe"])
        for word in ["or", "because", "but", "will", "a", "the", "to", "and"] {
            #expect(small.contains(word), "\(word) on Small words")
        }
        for word in ["or", "because", "but", "not"] {
            #expect(!describe.contains(word), "\(word) on Describe")
        }
        #expect(keys(b["i_page"]).contains("will"))
    }

    /// The two "right"s sit with their opposites: the direction next to `left`
    /// on Where, the correct one in a row with `wrong` on Describe.
    @Test func eachRightSitsBesideItsOpposite() {
        let b = board()
        #expect(isRun(["left", "right_"], in: [keys(b["describe_where"])]))
        #expect(isRun(["right", "okay_", "wrong"], in: [keys(b["describe"])]))
    }
}
}
