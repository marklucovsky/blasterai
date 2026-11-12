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

    // MARK: - Sharing

    private func lookup(in ctx: ModelContext) -> [String: TileModel] {
        var lookup: [String: TileModel] = [:]
        for key in ["pray", "jesus", "home", "park", "church", "bible", "actions"] {
            let t = TileModel(key: key, value: key, wordClass: "object")
            ctx.insert(t); lookup[key] = t
        }
        return lookup
    }

    /// One file brings the scene and the template it is built on; the
    /// template arrives read-only.
    @Test func aSceneFileCarriesItsTemplate() throws {
        let ctx = TestStore.freshContext()
        let lookup = lookup(in: ctx)
        let template = makeTemplate(), scene = makeScene(on: "brandi/core")
        ctx.insert(template); ctx.insert(scene)

        let file = SceneExporter.export(scene, tileLookup: lookup, templates: [template])
        #expect(file.templateID == "brandi/core")
        #expect(file.templates?.first?.isTemplate == true)
        #expect(file.templates?.first?.id == "brandi/core")

        ctx.delete(scene); ctx.delete(template)
        try ctx.save()
        let result = try SceneImporter.importJSON(JSONEncoder().encode(file), context: ctx)

        let scenes = try ctx.fetch(FetchDescriptor<BlasterScene>())
        let arrived = try #require(scenes.first { $0.sceneID == "brandi/core" })
        #expect(arrived.isTemplate && arrived.isImported && arrived.isLockedTemplate)
        // Brought by the scene, not sent on its own: carried, not listed.
        #expect(arrived.isCarriedTemplate)
        #expect(!result.scene.isCarriedTemplate)
        #expect(arrived.ownRow?.tiles.count == 2)
        #expect(result.scene.templateID == "brandi/core")
        #expect(!result.scene.isTemplate)
        let chain = TemplateChain(scene: result.scene, templates: scenes.filter(\.isTemplate), system: makeSystem())
        #expect(chain.templates.first?.sceneID == "brandi/core")
    }

    /// `template` as a file whose Home says church; the scene keeps its own.
    private func exportWithChurchHome(_ template: BlasterScene, lookup: [String: TileModel]) -> ExportableScene {
        let original = template.pages
        template.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "church")])]
            + original.filter { $0.key != "home" }
        let file = SceneExporter.export(template, tileLookup: lookup)
        template.pages = original
        return file
    }

    /// The template's own file, opened on purpose, makes a carried template
    /// one of the receiver's scenes.
    @Test func itsOwnFileListsACarriedTemplate() throws {
        let ctx = TestStore.freshContext()
        let lookup = lookup(in: ctx)
        let template = makeTemplate(), scene = makeScene(on: "brandi/core")
        ctx.insert(template); ctx.insert(scene)
        let sceneFile = SceneExporter.export(scene, tileLookup: lookup, templates: [template])
        let templateFile = SceneExporter.export(template, tileLookup: lookup)
        ctx.delete(scene); ctx.delete(template)
        try ctx.save()

        _ = try SceneImporter.importJSON(JSONEncoder().encode(sceneFile), context: ctx)
        let arrived = try #require(try ctx.fetch(FetchDescriptor<BlasterScene>()).first { $0.sceneID == "brandi/core" })
        #expect(arrived.isCarriedTemplate)
        _ = try SceneImporter.importJSON(JSONEncoder().encode(templateFile), context: ctx)
        #expect(!arrived.isCarriedTemplate)
        // A later scene file bringing it again leaves it listed.
        _ = try SceneImporter.importJSON(JSONEncoder().encode(sceneFile), context: ctx)
        #expect(!arrived.isCarriedTemplate)
    }

    /// A carried template stays while a scene uses it, directly or through
    /// another template, and is unused once none does.
    @Test func aCarriedTemplateGoesWithItsLastScene() {
        let base = makeTemplate(id: "brandi/core")
        base.isCarriedTemplate = true
        let middle = makeTemplate(id: "pastor/bible")
        middle.templateID = "brandi/core"
        middle.isCarriedTemplate = true
        let scene = makeScene(on: "pastor/bible")

        #expect(TemplateRemoval.unusedCarried(in: [base, middle, scene]).isEmpty)
        #expect(Set(TemplateRemoval.unusedCarried(in: [base, middle]).map(\.sceneID))
                == ["brandi/core", "pastor/bible"])
        // A carried template is not offered to build on.
        #expect(TemplateChain.choices(for: scene, templates: [base, middle]).isEmpty)
    }

    /// A template inside an old scene file never replaces a newer copy, and
    /// a newer one replaces it quietly.
    @Test func aCarriedTemplateNeverRollsBack() throws {
        let ctx = TestStore.freshContext()
        let lookup = lookup(in: ctx)
        let installed = makeTemplate()
        installed.isImported = true
        ctx.insert(installed)
        var carried = exportWithChurchHome(installed, lookup: lookup)

        carried.modified = installed.lastModified.addingTimeInterval(-60)
        try SceneImporter.installCarried(carried, context: ctx)
        #expect(installed.page(withKey: "home")?.tiles.first?.key == "pray")

        carried.modified = installed.lastModified.addingTimeInterval(60)
        try SceneImporter.installCarried(carried, context: ctx)
        #expect(installed.page(withKey: "home")?.tiles.first?.key == "church")
        #expect(installed.lastModified == carried.modified)
    }

    /// The author's own template (not imported) is never replaced by a file.
    @Test func aCarriedTemplateLeavesTheAuthorsOwn() throws {
        let ctx = TestStore.freshContext()
        let lookup = lookup(in: ctx)
        let own = makeTemplate()
        ctx.insert(own)
        var carried = exportWithChurchHome(own, lookup: lookup)
        carried.modified = own.lastModified.addingTimeInterval(60)
        try SceneImporter.installCarried(carried, context: ctx)
        #expect(own.page(withKey: "home")?.tiles.first?.key == "pray")
        #expect(!own.isLockedTemplate)
    }

    /// A copy of a template is a scene built on it, as a copy of BlasterAI
    /// 60 is: its Home alone, linking into the template, drawing its bar.
    @Test func aCopyOfATemplateIsBuiltOnIt() {
        let ctx = TestStore.freshContext()
        let template = makeTemplate()
        template.pages = [PageSpec(key: "home", tiles: [TileEntry(key: "bible", link: "bible", isAudible: false)])]
            + template.pages.filter { $0.key != "home" }
        ctx.insert(template)

        let copy = BlasterScene.duplicate(of: template, in: ctx, authorID: "a", authorName: "")
        #expect(copy.templateID == template.sceneID)
        #expect(!copy.isTemplate)
        #expect(copy.ownRow == nil)
        #expect(copy.pages.map(\.key) == ["home"])
        #expect(copy.pages[0].tiles[0].link == "<template>:bible")

        let editing = BlasterScene.cloneForEditing(template, in: ctx, authorID: "a", authorName: "",
                                                   alsoShadowing: "bible")
        #expect(editing.shadowPage(for: "template:bible")?.key == "bible")
        #expect(editing.shadowPage(for: "template:bible")?.tiles[1].link == TileToken.home)
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

    /// `Built On:` names the template a sheet's scene uses; `Uses
    /// Template:` and the old `Template:` mean the same.
    @Test func builtOnNamesTheTemplate() {
        func builtOn(_ cell: String) -> String? {
            let tabs = [SpreadsheetTab(name: "home", rows: [[cell], [], ["yes", "more"]])]
            return BoardWorkbook.builtOn(
                BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: [:], systemPages: []).details)
        }
        #expect(builtOn("Built On: Brandi Board") == "Brandi Board")
        #expect(builtOn("Uses Template: Brandi Board") == "Brandi Board")
        #expect(builtOn("Template: Brandi Board") == "Brandi Board")
        #expect(builtOn("Is Template: yes") == nil)
        #expect(BoardWorkbook.sameName("brandi board", "Brandi Board (2)"))
        #expect(!BoardWorkbook.sameName("Brandi Board", "Bible Board"))
        #expect(!BoardWorkbook.sameName("", ""))
    }

    @Test func aMissingTemplateHasAReadableName() {
        #expect(TemplateChain.missingName("599ea158-44e6/brandi-board") == "brandi-board")
        #expect(TemplateChain.missingName("solo") == "solo")
    }

    // MARK: - Placement

    /// A bar at the top stores nothing, so no page stored before placement
    /// existed changes its bytes (or its scene's content hash).
    @Test func aTopBarStoresNothing() throws {
        let top = PageSpec(key: BlasterScene.rowPageKey, tiles: [TileEntry(key: "bible")])
        let json = String(decoding: try JSONEncoder().encode(top), as: UTF8.self)
        #expect(!json.contains("barPlacement"))
        var bottom = top
        bottom.barPlacement = NavBarPlacement.bottom.stored
        let back = try JSONDecoder().decode(PageSpec.self, from: JSONEncoder().encode(bottom))
        #expect(back.barPlacement == "bottom")
        #expect(NavBarPlacement("sideways") == .top)
    }

    /// The bar's owner decides: the scene's own bar, else its template's,
    /// else BlasterAI 60's top.
    @Test func aBarSitsWhereItsOwnerPutsIt() {
        let system = makeSystem(), template = makeTemplate()
        template.updatePage(BlasterScene.rowPageKey) { $0.barPlacement = "bottom" }
        let scene = makeScene(on: template.sceneID)
        let chain = TemplateChain(scene: scene, templates: [template], system: system)
        #expect(chain.navBarPlacement == .bottom)
        #expect(BoardChrome.placement(for: scene, inherited: chain.navBarPlacement) == .bottom)
        #expect(BoardChrome.placement(for: template) == .bottom)

        // Made its own, the bar keeps the template's place until changed.
        scene.ownRow = BoardChrome.ownRowStart(from: chain.navBar, placement: .bottom)
        #expect(BoardChrome.placement(for: scene, inherited: nil) == .bottom)
        scene.updatePage(BlasterScene.rowPageKey) { $0.barPlacement = nil }
        #expect(BoardChrome.placement(for: scene, inherited: chain.navBarPlacement) == .top)

        let plain = makeScene(on: "")
        #expect(BoardChrome.placement(for: plain, inherited: nil) == .top)
        #expect(BoardChrome.placement(for: system, inherited: .bottom) == .top)
    }

    /// A bar at the bottom closes a screen padded out to its capacity; at the
    /// top it opens the screen, and the content is left as it is.
    @Test func arrangePutsTheBarFirstOrLast() {
        let bar = [TileEntry(key: "a"), TileEntry(key: "b")]
        let words = [TileEntry(key: "x"), TileEntry(key: "y"), TileEntry(key: "z")]
        let top = BoardChrome.arrange(content: words, chrome: bar, placement: .top, perScreen: 6)
        let topKeys = top.map { $0.key }
        #expect(topKeys == ["a", "b", "x", "y", "z"])
        let bottom = BoardChrome.arrange(content: words, chrome: bar, placement: .bottom, perScreen: 6)
        let keys = bottom.map { $0.key }
        let gaps = bottom[3..<6].allSatisfy { $0.isSpacer }
        #expect(bottom.count == 8)
        #expect(Array(keys.prefix(3)) == ["x", "y", "z"])
        #expect(gaps)
        #expect(Array(keys.suffix(2)) == ["a", "b"])
        #expect(Set(keys).count == keys.count)
        #expect(BoardChrome.arrange(content: words, chrome: [], placement: .bottom, perScreen: 6).count == 3)
    }

    /// A template's placement travels with it inside a scene's file.
    @Test func aSceneFileCarriesItsBarPlacement() throws {
        let ctx = TestStore.freshContext()
        let lookup = lookup(in: ctx)
        let template = makeTemplate(), scene = makeScene(on: "brandi/core")
        template.updatePage(BlasterScene.rowPageKey) { $0.barPlacement = "bottom" }
        ctx.insert(template); ctx.insert(scene)
        let file = SceneExporter.export(scene, tileLookup: lookup, templates: [template])
        ctx.delete(scene); ctx.delete(template)
        try ctx.save()
        _ = try SceneImporter.importJSON(JSONEncoder().encode(file), context: ctx)

        let arrived = try #require(try ctx.fetch(FetchDescriptor<BlasterScene>()).first { $0.sceneID == "brandi/core" })
        #expect(arrived.ownRow?.barPlacement == "bottom")
    }

    /// `Bar Placement: bottom`, in one cell or two, on any tab; and a
    /// bottom bar is written back over the Navigation Bar tab.
    @Test func aSheetSaysWhereTheBarGoes() {
        func placement(_ rows: [[String]]) -> NavBarPlacement? {
            let tabs = [SpreadsheetTab(name: "home", rows: rows + [[], ["yes", "more"]])]
            return BoardWorkbook.barPlacement(
                BoardWorkbook.preview(tabs, cols: 10, scenePages: [], lookup: [:], systemPages: []).details)
        }
        #expect(placement([["Bar Placement: bottom"]]) == .bottom)
        #expect(placement([["Bar Placement:", "Bottom"]]) == .bottom)
        #expect(placement([["Bar Placement:", "top"]]) == .top)
        #expect(placement([["Name: Tide Pools"]]) == nil)

        let row = PageSpec(key: BlasterScene.rowPageKey, tiles: [TileEntry(key: "yes")], barPlacement: "bottom")
        let tabs = BoardWorkbook.tabs(for: [PageSpec(key: "home", tiles: [])], homeKey: "home", cols: 10, row: row)
        let bar = tabs.first { $0.name == BoardWorkbook.rowTab }
        #expect(bar?.rows.first == ["Bar Placement:", "bottom"])
        #expect(BoardWorkbook.barPlacement(BoardWorkbook.details(of: bar!)) == .bottom)
    }

    /// An exported scene says what it is over Home — a template stays a
    /// template, a scene keeps its template — and `#board` marks exactly
    /// where the board starts, even when its first cell is a gap.
    @Test func anExportedSheetSaysWhatTheSceneIs() {
        let details = BoardWorkbook.details(name: "Brandi Board", description: "Core board",
                                            isTemplate: true, builtOn: "School Core")
        let home = PageSpec(key: "home", tiles: [TileEntry(key: "<spacer>#a"), TileEntry(key: "yes")])
        let tabs = BoardWorkbook.tabs(for: [home], homeKey: "home", cols: 10, details: details)
        let homeTab = tabs.first { $0.name == "home" }!
        let read = BoardWorkbook.details(of: homeTab)
        #expect(read["name"] == "Brandi Board")
        #expect(read["description"] == "Core board")
        #expect(read["is template"] == "yes")
        #expect(BoardWorkbook.builtOn(read) == "School Core")
        let origin = BoardWorkbook.detectOrigin(homeTab, cols: 10) { !$0.isEmpty }
        let boardRow = homeTab.rows[origin.row]
        #expect(boardRow.count >= 2)
        #expect(boardRow.first == "")
        #expect(boardRow.dropFirst().first == "yes")

        let plain = BoardWorkbook.details(name: "Zoo", description: " ", isTemplate: false, builtOn: nil)
        #expect(plain.map(\.0) == ["Name"])
    }
}
}
