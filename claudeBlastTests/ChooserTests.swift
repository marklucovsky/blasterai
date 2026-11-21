// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ChooserTests.swift
//  claudeBlastTests
//
//  The shared word and page choosers: what they offer and what they call it.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct ChooserTests {

    // MARK: - Words

    /// A word hidden from the child, a page folder and an excluded word are
    /// never offered; folders only when asked for.
    @Test func wordCandidatesLeaveOutHiddenFoldersAndExcluded() {
        let apple = TileModel(key: "apple", value: "apple", wordClass: "food")
        let gone = TileModel(key: "gone", value: "gone", wordClass: "food")
        gone.isRetired = true
        let folder = TileModel(key: "page_animals", value: "animals", wordClass: PageLink.wordClass)
        let mine = TileModel(key: "eat", value: "eat", wordClass: "actions")
        let all = [apple, gone, folder, mine]

        let offered = WordChoice.candidates(all, rules: .init(excluding: ["eat"]))
        #expect(offered.map(\.key) == ["apple"])

        let withFolders = WordChoice.candidates(all, rules: .init(includesPageLinks: true))
        #expect(Set(withFolders.map(\.key)) == ["apple", "page_animals", "eat"])
    }

    /// Chips follow `word_classes.json`'s order, an unknown class last.
    @Test func classChipsFollowTheClassFile() {
        let tiles = [TileModel(key: "apple", value: "apple", wordClass: "food"),
                     TileModel(key: "zorb", value: "zorb", wordClass: "zzz_custom"),
                     TileModel(key: "eat", value: "eat", wordClass: "actions"),
                     TileModel(key: "pear", value: "pear", wordClass: "food")]
        let order = VocabularyClasses.all.map(\.name)
        #expect(order.firstIndex(of: "actions")! < order.firstIndex(of: "food")!)
        #expect(WordChoice.classes(of: tiles) == ["actions", "food", "zzz_custom"])
        #expect(WordChoice.label(ofClass: "actions") == "Actions")
        #expect(WordChoice.label(ofClass: PageLink.wordClass) == "Page Links")
    }

    /// A search ranks whole-word matches first; a class narrows; no search
    /// is alphabetical.
    @Test func wordFilterRanksAndNarrows() {
        let tiles = [TileModel(key: "ice_cream", value: "ice cream", wordClass: "food"),
                     TileModel(key: "cream", value: "cream", wordClass: "food"),
                     TileModel(key: "scream", value: "scream", wordClass: "actions"),
                     TileModel(key: "apple", value: "apple", wordClass: "food")]

        #expect(WordChoice.filter(tiles, query: "cream", wordClass: nil).map(\.key)
                == ["cream", "ice_cream", "scream"])
        #expect(WordChoice.filter(tiles, query: "cream", wordClass: "actions").map(\.key) == ["scream"])
        #expect(WordChoice.filter(tiles, query: "", wordClass: "food").map(\.key)
                == ["apple", "cream", "ice_cream"])
        #expect(WordChoice.filter(tiles, query: "CRÈME", wordClass: nil).isEmpty)
    }

    // MARK: - Pages

    private func board() -> [PageSpec] {
        [PageSpec(key: "home", tiles: [TileEntry(key: "groups", link: "groups", isAudible: false)]),
         PageSpec(key: "groups", tiles: [TileEntry(key: "animals", link: "animals", isAudible: false)]),
         PageSpec(key: "animals", tiles: [TileEntry(key: "cat")]),
         PageSpec(key: "orphan", tiles: [])]
    }

    /// Each page is named by its folder route from home, and listed home
    /// first, then beneath the folder it is in.
    @Test func pagesAreNamedByRoute() {
        let group = PageChoice.group(board: "Board", pages: board(), homeKey: "home")
        #expect(group.options.map(\.value) == ["home", "groups", "animals", "orphan"])
        let animals = group.options.first { $0.value == "animals" }!
        #expect(animals.route == ["Groups", "Animals"])
        #expect(animals.path == "Groups › Animals")
        #expect(animals.parents == "Groups ›")
        #expect(group.options.first { $0.value == "groups" }!.parents == "")
        #expect(group.options.first { $0.value == "home" }!.path == "Home")
        #expect(group.options.first { $0.value == "orphan" }!.path == "Orphan")
        #expect(PageChoice.fullPath(of: "animals", in: [group]) == "Board › Groups › Animals")
    }

    /// A search matches any step of the route, so "groups" finds the pages
    /// inside it; a board left empty drops out.
    @Test func pageSearchMatchesAnyStep() {
        let groups = [PageChoice.group(board: "Board", pages: board(), homeKey: "home", includeHome: false,
                                       value: { TileToken.systemLink(to: $0) }),
                      PageChoice.group(board: "Other", pages: [PageSpec(key: "home", tiles: [])],
                                       homeKey: "home")]
        let found = PageChoice.filter(groups, query: "group")
        #expect(found.map(\.board) == ["Board"])
        #expect(found[0].options.map(\.value)
                == [TileToken.systemLink(to: "groups"), TileToken.systemLink(to: "animals")])
        #expect(PageChoice.filter(groups, query: "").count == 2)
    }

    /// Browsing is a tree: a page sits under the folder that opens it, and
    /// a re-keyed group keeps the tree.
    @Test func pagesBrowseAsATree() {
        let group = PageChoice.group(board: "Board", pages: board(), homeKey: "home")
        let tree = group.tree
        #expect(tree.map(\.id) == ["home", "groups", "orphan"])
        #expect(tree[0].children == nil)
        #expect(tree[1].children?.map(\.id) == ["animals"])
        #expect(tree[1].allValues == ["groups", "animals"])

        let keyed = group.mapValues { "x/" + $0 }
        #expect(keyed.tree[1].children?.map(\.id) == ["x/animals"])
    }

    /// A search for a word that names no page finds the page holding it, and
    /// says which word; a page found by name comes first and says nothing.
    @Test func pageSearchFindsTheWordsOnIt() {
        var pages = board()
        pages[1].tiles.append(TileEntry(key: "cat_food"))
        let groups = [PageChoice.group(board: "Board", pages: pages, homeKey: "home")]
        let found = PageChoice.filter(groups, query: "cat")
        #expect(found[0].options.map(\.value) == ["groups", "animals"])
        let animals = found[0].options.first { $0.value == "animals" }!
        #expect(PageChoice.matchedWord(in: animals, query: "Cat") == "cat")
        let groupsPage = found[0].options.first { $0.value == "groups" }!
        #expect(PageChoice.matchedWord(in: groupsPage, query: "food") == "cat food")
        #expect(PageChoice.matchedWord(in: animals, query: "anim") == nil)
        #expect(PageChoice.filter(groups, query: "animals")[0].options.map(\.value) == ["animals"])
    }

    /// In the sheet editor, browsing is offered with nothing typed after
    /// `>`, `sys:` or `template:`, and a page chosen writes the text a
    /// caregiver would have typed.
    @Test func linkBrowsingInTheSheetEditor() {
        #expect(CellSuggestion.browseScope(for: "cow > ") == .all)
        #expect(CellSuggestion.browseScope(for: ">") == .all)
        #expect(CellSuggestion.browseScope(for: "cow > SYS:") == .system)
        #expect(CellSuggestion.browseScope(for: "> template:") == .template)
        #expect(CellSuggestion.browseScope(for: "cow > pl") == nil)
        #expect(CellSuggestion.browseScope(for: "cow") == nil)
        #expect(CellSuggestion.browse(.all).applied(to: "cow > ") == "cow > ")

        #expect(CellSuggestion.cellText(forLink: "lions") == "lions")
        #expect(CellSuggestion.cellText(forLink: TileToken.systemLink(to: "animals")) == "sys:animals")
        #expect(CellSuggestion.cellText(forLink: TileToken.templateLink(to: "bible")) == "template:bible")

        let system = BlasterScene(name: "BlasterAI 60", homePageKey: "home", isDefault: true)
        system.pages = board()
        let scene = BlasterScene(name: "Zoo", homePageKey: "home")
        scene.pages = [PageSpec(key: "home", tiles: [])]
        let groups = PageChoice.linkTargets(scene: scene,
                                            chain: TemplateChain(scene: scene, templates: [], system: system))
        #expect(groups.filter(CellSuggestion.BrowseScope.system.includes).map(\.board) == ["BlasterAI 60"])
        #expect(groups.filter(CellSuggestion.BrowseScope.all.includes).count == 2)
        #expect(groups.filter(CellSuggestion.BrowseScope.template.includes).isEmpty)
    }

    /// Me page contexts by route: homes and the Me page left out, a copy of a
    /// BlasterAI 60 page chosen as that page, a shared name marked.
    @Test func contextTargetsMatchContextChoices() {
        let ctx = TestStore.freshContainer().mainContext
        let system = BlasterScene(name: "BlasterAI 60", homePageKey: "home", isDefault: true)
        system.pages = [PageSpec(key: "home", tiles: []), PageSpec(key: "places", tiles: [])]
        let church = BlasterScene(name: "Sunday School", homePageKey: "home")
        church.designedFor = "ipad-10x6"
        var copy = PageSpec(key: "my_places", tiles: [])
        copy.shadows = "places"
        church.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "bible", link: "bible", isAudible: false)]),
                        copy, PageSpec(key: "bible", tiles: [])]
        let me = MeScene.ensure(profileID: "p1", context: ctx)
        ctx.insert(system); ctx.insert(church)

        let groups = PageChoice.contextTargets(system: system, scenes: [church, me])
        #expect(groups.map(\.board) == ["BlasterAI 60", "Sunday School"])
        #expect(groups.map { Set($0.options.map(\.value)) } == [["places"], ["places", "bible"]])
        #expect(PageChoice.sharedValues(groups) == ["places"])
        #expect(groups[1].options.first { $0.value == "bible" }!.route == ["Bible"])
        #expect(PageChoice.contextTargets(system: system, scenes: [church], excludingScene: church.sceneID)
                    .map(\.board) == ["BlasterAI 60"])
    }

    /// Every keyboard is offered as a page to link to: a navigation bar can
    /// anchor `sys:keyboard`, `sys:keyboard_abc`, `sys:numbers` and
    /// `sys:calculator` (session 20, PR G).
    @Test func theKeyboardsAreLinkTargets() {
        let ctx = TestStore.freshContainer().mainContext
        let system = BootstrapLoader.loadDefaultVocabulary(context: ctx).scene
        let scene = BlasterScene(name: "Zoo", homePageKey: "home")
        scene.pages = [PageSpec(key: "home", tiles: [])]
        let groups = PageChoice.linkTargets(scene: scene,
                                            chain: TemplateChain(scene: scene, templates: [], system: system))
        let offered = Dictionary(groups.flatMap(\.options).map { ($0.value, $0.title) },
                                 uniquingKeysWith: { a, _ in a })
        for layout in KeyboardLayout.allCases {
            let link = TileToken.systemLink(to: layout.pageKey)
            #expect(offered[link] != nil, "\(link) is not offered")
            #expect(KeyboardLayout.forPage(link) == layout, "\(link) opens its keyboard")
        }
        #expect(offered[TileToken.systemLink(to: "calculator")] == "Calculator")
    }

    /// Link targets: the scene's own pages by key, then BlasterAI 60's as
    /// system links.
    @Test func linkTargetsAreOwnThenSystem() {
        let system = BlasterScene(name: "BlasterAI 60", homePageKey: "home", isDefault: true)
        system.pages = board()
        let scene = BlasterScene(name: "Zoo", homePageKey: "home")
        scene.pages = [PageSpec(key: "home", tiles: []), PageSpec(key: "lions", tiles: [])]
        let chain = TemplateChain(scene: scene, templates: [], system: system)

        let groups = PageChoice.linkTargets(scene: scene, chain: chain)
        #expect(groups.map(\.board) == ["Zoo", "BlasterAI 60"])
        #expect(groups[0].options.map(\.value) == ["home", "lions"])
        #expect(groups[1].options.first { $0.title == "Animals" }?.value == TileToken.systemLink(to: "animals"))
        #expect(PageChoice.fullPath(of: TileToken.systemLink(to: "animals"), in: groups)
                == "BlasterAI 60 › Groups › Animals")
        #expect(PageChoice.linkTargets(scene: system, chain: nil).count == 1)
    }
}
}
