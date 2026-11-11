// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TemplateChainTests.swift
//  claudeBlastTests
//
//  A template is a peer of BlasterAI 60: a scene built on one links to its
//  pages with `<template>:` as to BlasterAI 60's with `<system>:`, and the
//  two never stand for each other.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct TemplateChainTests {

    private func makeSystem() -> BlasterScene {
        let s = BlasterScene(name: "BlasterAI 60", homePageKey: "home", isDefault: true)
        s.systemSceneKey = "core_first"
        s.pages = [
            PageSpec(key: "home", tiles: [TileEntry(key: "actions", link: "actions", isAudible: false)]),
            PageSpec(key: "actions", tiles: [TileEntry(key: "eat")]),
            PageSpec(key: "places", tiles: [TileEntry(key: "park")]),
        ]
        return s
    }

    /// Brandi Core: its own Bible page, its own copy of Places, its own bar.
    private func makeTemplate(id: String = "brandi/core") -> BlasterScene {
        let t = BlasterScene(name: "Brandi Core", homePageKey: "home")
        t.designedFor = "ipad-10x6"
        t.isTemplate = true
        t.sceneID = id
        t.pages = [
            PageSpec(key: "home", tiles: [TileEntry(key: "pray")]),
            PageSpec(key: "bible", tiles: [TileEntry(key: "jesus"),
                                           TileEntry(key: "home", link: "home", isAudible: false),
                                           TileEntry(key: "park", link: "<system>:places", isAudible: false)]),
            PageSpec(key: "places", tiles: [TileEntry(key: "church")], shadows: "places"),
        ]
        t.ownRow = PageSpec(key: BlasterScene.rowPageKey, tiles: [
            TileEntry(key: "bible", link: "bible", isAudible: false),
            TileEntry(key: "actions", link: "<system>:actions", isAudible: false),
        ])
        return t
    }

    private func makeScene(on templateID: String) -> BlasterScene {
        let s = BlasterScene(name: "Sunday School", homePageKey: "home")
        s.designedFor = "ipad-10x6"
        s.sceneID = "brandi/sunday"
        s.templateID = templateID
        s.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "bible", link: "<template>:bible", isAudible: false)])]
        return s
    }

    // MARK: - Pages

    /// `sys:places` is BlasterAI 60's Places and `template:places` the
    /// template's copy of it; `sys:bible` is nothing.
    @Test func sysAndTemplateNameDifferentPages() {
        let system = makeSystem(), template = makeTemplate()
        let chain = TemplateChain(scene: makeScene(on: template.sceneID), templates: [template], system: system)
        let pages = chain.pages(atLevel: nil)

        #expect(chain.templates.count == 1)
        #expect(pages.map(\.key) == ["home", "actions", "places", "template:bible", "template:places"])
        func page(_ link: String) -> PageSpec? {
            SystemLinks.page(forKey: link, scenePages: [], systemPages: pages)
        }
        #expect(page("<system>:places")?.tiles.map(\.key) == ["park"])
        #expect(page("<template>:places")?.tiles.map(\.key) == ["church"])
        #expect(page("<template>:bible")?.tiles.first?.key == "jesus")
        #expect(page("<system>:bible") == nil)
        #expect(page("<template>:actions") == nil)
        #expect(chain.owner(ofSystemPage: "template:places")?.sceneID == template.sceneID)
        #expect(chain.owner(ofSystemPage: "places") == nil)
    }

    /// A template's page means from the scene what it meant in the template:
    /// its Home is Home, and its link to BlasterAI 60's Places — which it has
    /// its own copy of — is that copy.
    @Test func aTemplatePagesLinksKeepTheirMeaning() {
        let template = makeTemplate()
        let chain = TemplateChain(scene: makeScene(on: template.sceneID), templates: [template], system: makeSystem())
        let bible = chain.pages(atLevel: nil).first { $0.key == "template:bible" }
        #expect(bible?.tiles.map(\.link) == ["", TileToken.home, "<template>:places"])
    }

    @Test func aSceneOnBlasterAI60IsAsBefore() {
        let system = makeSystem()
        let chain = TemplateChain(scene: makeScene(on: ""), templates: [makeTemplate()], system: system)
        #expect(chain.templates.isEmpty)
        #expect(chain.pages(atLevel: nil).map(\.key) == system.pages.map(\.key))
        #expect(chain.navBar == nil)
    }

    /// A template this device does not have is BlasterAI 60, said so.
    @Test func aMissingTemplateFallsBackToBlasterAI60() {
        let chain = TemplateChain(scene: makeScene(on: "someone/else"), templates: [makeTemplate()],
                                  system: makeSystem())
        #expect(chain.templates.isEmpty)
        #expect(chain.isMissingTemplate)
        #expect(chain.name == "BlasterAI 60")
    }

    @Test func aLoopIsCutOff() {
        let a = makeTemplate(id: "a"), b = makeTemplate(id: "b")
        a.templateID = "b"; b.templateID = "a"
        let chain = TemplateChain(scene: makeScene(on: "a"), templates: [a, b], system: makeSystem())
        #expect(chain.templates.map(\.sceneID) == ["a", "b"])
        // A template cannot be built on one already built on it.
        #expect(!TemplateChain.choices(for: a, templates: [a, b]).contains { $0.sceneID == "b" })
        #expect(!TemplateChain.choices(for: a, templates: [a, b]).contains { $0.sceneID == "a" })
    }

    @Test func aTemplateIsFoundByName() {
        let template = makeTemplate()
        #expect(TemplateChain.named("brandi core", in: [template])?.sceneID == template.sceneID)
        #expect(TemplateChain.named("brandi/core", in: [template])?.sceneID == template.sceneID)
        #expect(TemplateChain.named("Someone Else", in: [template]) == nil)
    }

    // MARK: - Bar

    /// The template's bar is drawn on the scene, its links to the template's
    /// pages made links into the chain.
    @Test func aSceneDrawsItsTemplatesBar() {
        let template = makeTemplate()
        let scene = makeScene(on: template.sceneID)
        let chain = TemplateChain(scene: scene, templates: [template], system: makeSystem())

        #expect(chain.navBar?.map(\.link) == ["<template>:bible", "<system>:actions"])
        let drawn = BoardChrome.row(for: scene, level: nil, inherited: chain.navBar).filter { !$0.isSpacer }
        #expect(drawn.map(\.key) == ["bible", "actions"])
        #expect(BoardChrome.systemPageKeys(of: scene, inherited: chain.navBar) == ["template:bible", "actions"])

        // A scene's own bar still wins.
        scene.ownRow = PageSpec(key: BlasterScene.rowPageKey, tiles: [TileEntry(key: "yes")])
        let own = BoardChrome.row(for: scene, level: nil, inherited: chain.navBar).filter { !$0.isSpacer }
        #expect(own.map(\.key) == ["yes"])
    }

    // MARK: - Board

    @Test func theBoardReachesTheTemplate() {
        let ctx = TestStore.freshContext()
        let system = makeSystem(), template = makeTemplate()
        let scene = makeScene(on: template.sceneID)
        ctx.insert(system); ctx.insert(template); ctx.insert(scene)

        let levels = BoardLevels(scene: scene, system: system, templates: [template])

        #expect(levels.systemPages.contains { $0.key == "template:bible" })
        #expect(levels.inheritedNavBar?.count == 2)
        // A link from the template's Bible to its Home is the scene's Home.
        let bible = levels.systemPages.first { $0.key == "template:bible" }!
        let home = SystemLinks.destination(of: bible.tiles[1].link, fromPage: "<template>:bible",
                                           homePageKey: "home", systemHomePageKey: levels.systemHomePageKey)
        #expect(home == "home")
        // Its folder to Places stays in the template.
        let places = SystemLinks.destination(of: bible.tiles[2].link, fromPage: "<template>:bible",
                                             homePageKey: "home", systemHomePageKey: levels.systemHomePageKey)
        #expect(places == "<template>:places")
    }

    /// A copy for this scene alone, made from the template's page.
    @Test func aSceneCopiesATemplatePage() {
        let system = makeSystem(), template = makeTemplate()
        let scene = makeScene(on: template.sceneID)
        let chain = TemplateChain(scene: scene, templates: [template], system: system)
        let bible = chain.pages(atLevel: nil).first { $0.key == "template:bible" }!

        let key = scene.shadowSystemPage(bible, systemHomePageKey: chain.homePageKey ?? "home")

        #expect(key == "bible")
        #expect(scene.shadowPage(for: "template:bible")?.key == key)
        #expect(scene.shadowPage(for: "template:bible")?.tiles[1].link == TileToken.home)
        // The scene's `template:bible` opens the copy; the template is untouched.
        #expect(SystemLinks.page(forKey: "<template>:bible", scenePages: scene.pages,
                                 systemPages: chain.pages(atLevel: nil))?.key == "bible")
        #expect(template.page(withKey: "bible")?.tiles.count == 3)
        #expect(SystemLinks.displayName(of: TileToken.systemLink(to: "template:bible"), chain: chain)
                == "Brandi Core › Bible")
    }

    /// Outside the app a scene built on a template carries the template's pages.
    @Test func anExportCarriesTheTemplatesPages() {
        let system = makeSystem(), template = makeTemplate()
        let scene = makeScene(on: template.sceneID)
        let chain = TemplateChain(scene: scene, templates: [template], system: system)

        let whole = ExportPages(scenePages: scene.pages, systemPages: chain.pages(atLevel: nil),
                                systemHomePageKey: chain.homePageKey)

        // Bible, and the template's Places it opens, under their names.
        #expect(whole.pages.map(\.key) == ["home", "bible", "places"])
        #expect(whole.pages[0].tiles[0].link == "bible")
        #expect(whole.pages[1].tiles.map(\.link) == ["", TileToken.home, "places"])
    }

    // MARK: - Deleting a template

    /// Every scene built on the template, and only those.
    @Test func deletingATemplateFindsItsScenes() {
        let system = makeSystem(), template = makeTemplate()
        let linked = makeScene(on: template.sceneID)
        let other = makeScene(on: "")
        other.sceneID = "brandi/other"

        let dependents = TemplateRemoval.dependents(of: template, scenes: [system, template, linked, other],
                                                    system: system)

        #expect(dependents.map(\.scene.sceneID) == [linked.sceneID])
    }

    /// Deleting the template: the bar and the template pages the scene
    /// reaches become ordinary pages of its own, linked plainly, and it is
    /// built on BlasterAI 60 again. BlasterAI 60's Places is still `sys:`.
    @Test func deletingATemplateKeepsTheLook() {
        let system = makeSystem(), template = makeTemplate()
        let scene = makeScene(on: template.sceneID)
        let dependents = TemplateRemoval.dependents(of: template, scenes: [system, template, scene], system: system)

        TemplateRemoval.keepLookOfAll(dependents, without: template, templates: [template], system: system)

        #expect(scene.templateID.isEmpty)
        #expect(scene.ownRow?.tiles.map(\.link) == ["bible", "<system>:actions"])
        #expect(scene.pages.map(\.key) == ["home", "bible", "places"])
        #expect(scene.pages.allSatisfy { !$0.isShadow })
        #expect(scene.pages[0].tiles[0].link == "bible")
        #expect(scene.page(withKey: "bible")?.tiles.map(\.link) == ["", TileToken.home, "places"])
        #expect(scene.page(withKey: "places")?.tiles.map(\.key) == ["church"])
        #expect(!scene.pages.flatMap(\.tiles).contains { $0.link.hasPrefix(TileToken.templatePrefix) })
    }

    /// A copy the scene had already made of a template page becomes that
    /// page, rather than a second one.
    @Test func deletingATemplateKeepsTheScenesOwnCopy() {
        let system = makeSystem(), template = makeTemplate()
        let scene = makeScene(on: template.sceneID)
        let chain = TemplateChain(scene: scene, templates: [template], system: system)
        let bible = chain.pages(atLevel: nil).first { $0.key == "template:bible" }!
        scene.shadowSystemPage(bible, systemHomePageKey: "home")
        scene.updatePage("bible") { $0.tiles[0] = TileEntry(key: "moses") }

        let dependents = TemplateRemoval.dependents(of: template, scenes: [system, template, scene], system: system)
        TemplateRemoval.keepLookOfAll(dependents, without: template, templates: [template], system: system)

        #expect(scene.pages.filter { $0.key.hasPrefix("bible") }.count == 1)
        #expect(scene.page(withKey: "bible")?.isShadow == false)
        #expect(scene.page(withKey: "bible")?.tiles.first?.key == "moses")
    }

    /// A link into the template is named by the template, not BlasterAI.
    @Test func aTemplatePageIsNamedByItsTemplate() {
        let template = makeTemplate()
        let chain = TemplateChain(scene: makeScene(on: template.sceneID), templates: [template], system: makeSystem())
        #expect(SystemLinks.displayName(of: "<template>:bible", chain: chain) == "Brandi Core › Bible")
        #expect(SystemLinks.displayName(of: "<system>:places", chain: chain) == "BlasterAI › Places")
        #expect(SystemLinks.displayName(of: "<template>:places", chain: chain) == "Brandi Core › Places")
        #expect(SystemLinks.displayName(of: "<template>:bible") == "Template › Bible")
    }

    /// Built On None keeps the template's bar and pages as the scene's own;
    /// BlasterAI 60 keeps the pages but draws BlasterAI 60's bar.
    @Test func leavingATemplateKeepsItsPages() {
        let system = makeSystem(), template = makeTemplate()
        let none = makeScene(on: template.sceneID)
        TemplateRemoval.leave(none, keepingBar: true, templates: [template], system: system)
        #expect(none.templateID.isEmpty)
        #expect(none.ownRow?.tiles.map(\.link) == ["bible", "<system>:actions"])
        #expect(none.page(withKey: "bible")?.tiles.first?.key == "jesus")

        let core = makeScene(on: template.sceneID)
        TemplateRemoval.leave(core, keepingBar: false, templates: [template], system: system)
        #expect(core.ownRow == nil)
        #expect(core.pages[0].tiles[0].link == "bible")
        #expect(core.page(withKey: "bible") != nil)
    }

    // MARK: - Typing

    /// `template:` names the template's page, `sys:` BlasterAI 60's, and
    /// each is written back as typed.
    @Test func aCellNamesEitherBoard() {
        let template = makeTemplate()
        let pages = TemplateChain(scene: makeScene(on: template.sceneID), templates: [template],
                                  system: makeSystem()).pages(atLevel: nil)
        let lookup = Dictionary(uniqueKeysWithValues: ["go", "bible", "places"].map {
            ($0, TileModel(key: $0, value: $0, wordClass: "action"))
        })
        func link(_ text: String) -> String? {
            guard case .plan(let plan) = BoardCell.resolve(BoardCell.parse(text), lookup: lookup,
                                                           scenePages: [], systemPages: pages) else { return nil }
            return plan.entry.link
        }
        #expect(link("go > template:places") == "<template>:places")
        #expect(link("go > sys:places") == "<system>:places")
        #expect(link("go > template:Bible") == "<template>:bible")
        #expect(link("go > sys:bible") == nil)
        #expect(link("go > template:actions") == nil)
        #expect(BoardCell.format(TileEntry(key: "go", link: "<template>:places", isAudible: true))
                == "go > template:places")
        #expect(BoardCell.format(TileEntry(key: "go", link: "<system>:places", isAudible: true))
                == "go > sys:places")
    }

    /// `Is Template: yes` is read from whichever tab holds it, not only the
    /// first (often the navigation bar's).
    @Test func detailsAreReadFromAnyTab() {
        let tabs = [SpreadsheetTab(name: "NavBar", rows: [["yes", "no"]]),
                    SpreadsheetTab(name: "home", rows: [["Is Template: yes"], [], ["yes", "more"]])]
        let preview = BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: [:], systemPages: [])
        #expect(preview.details["is template"] == "yes")
    }

    @Test func aMissingTemplateHasAReadableName() {
        #expect(TemplateChain.missingName("599ea158-44e6/brandi-board") == "brandi-board")
        #expect(TemplateChain.missingName("solo") == "solo")
    }
}
}
