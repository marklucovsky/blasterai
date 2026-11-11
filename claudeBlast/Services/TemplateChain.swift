// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TemplateChain.swift
//  claudeBlast
//
//  The templates a scene is built on, and the pages they give it.
//

import Foundation
import SwiftData

/// The scenes a scene is built on: its template, that template's template,
/// and so on, ending at BlasterAI 60.
///
/// BlasterAI 60 is the template that ships with the app; a caregiver's scene
/// marked `isTemplate` is a peer of it. A scene built on a template reaches
/// its pages with `<template>:` links (`template:random` typed) as every
/// scene reaches BlasterAI 60's with `<system>:` (`sys:random`). The two are
/// separate: `sys:people` is always BlasterAI 60's People, `template:people`
/// always the template's — its own page or its copy of BlasterAI 60's —
/// and never falls through to BlasterAI 60. With templates on templates,
/// `template:` looks nearest first.
///
/// Templates are found by `sceneID`. One that is gone — deleted, not yet
/// synced, never received — ends the chain there, so the scene falls back to
/// BlasterAI 60 rather than to nothing. A loop, or a chain deeper than
/// `maxDepth`, is cut off the same way.
struct TemplateChain {
    /// Nearest first; BlasterAI 60 is not in it.
    let templates: [BlasterScene]
    /// BlasterAI 60.
    let system: BlasterScene?
    /// The scene named a template the chain could not find.
    let isMissingTemplate: Bool

    static let maxDepth = 4

    /// - Parameter templates: every scene marked `isTemplate` this device has.
    init(scene: BlasterScene, templates candidates: [BlasterScene], system: BlasterScene?) {
        self.init(templateID: scene.templateID, sceneID: scene.sceneID, templates: candidates, system: system)
    }

    /// The chain a scene with `templateID` would have — for one not made yet
    /// (an import naming its template).
    init(templateID: String, sceneID: String = "", templates candidates: [BlasterScene],
         system: BlasterScene?) {
        self.system = system
        var chain: [BlasterScene] = []
        var seen: Set<String> = sceneID.isEmpty ? [] : [sceneID]
        var next = templateID
        var missing = false
        while !next.isEmpty, chain.count < Self.maxDepth {
            guard !seen.contains(next),
                  let template = candidates.first(where: { $0.isTemplate && $0.sceneID == next })
            else {
                missing = chain.isEmpty
                break
            }
            seen.insert(next)
            chain.append(template)
            next = template.templateID
        }
        templates = chain
        isMissingTemplate = missing
    }

    /// The scene the chain starts at: its template, else BlasterAI 60.
    var nearest: BlasterScene? { templates.first ?? system }

    /// What the scene editor calls the scene it is built on.
    var name: String {
        BlasterScene.copyRoot(of: nearest?.name ?? "BlasterAI 60")
    }

    /// The home page key `<system>:` links treat as Home: BlasterAI 60's. A
    /// template's links to its own home are made `<home>` (`absolute`).
    var homePageKey: String? { system?.homePageKey }

    /// Most levels anything in the chain declares.
    var revealLevelCount: Int {
        (templates.map(\.revealLevelCount) + [system?.revealLevelCount ?? 0]).max() ?? 0
    }

    /// The pages links out of the scene name, at `level`: BlasterAI 60's
    /// under their own keys, then the templates' under template keys
    /// (`template:random`), nearest winning. A template's copy of a BlasterAI
    /// 60 page is its page of that name; its home is left out, as its links
    /// home are Home. Template pages' links are made `absolute`, so they
    /// mean from the scene what they meant in the template.
    func pages(atLevel level: Int?) -> [PageSpec] {
        let core = system?.pages(atLevel: BoardLevels.clamp(level, to: system?.revealLevelCount ?? 0)) ?? []
        // Built on BlasterAI 60 alone: its pages as they are, from the cache.
        if templates.isEmpty { return core }
        var order: [String] = []
        var byKey: [String: PageSpec] = [:]
        for template in templates.reversed() {
            let pages = template.pages(atLevel: BoardLevels.clamp(level, to: template.revealLevelCount))
            for page in pages where page.key != template.homePageKey {
                let key = Self.templateKey(of: page)
                var out = page
                out.key = key
                out.shadows = ""
                // Its cover as the template draws it: found from its own
                // pages' folders, which name it by its key there.
                out.cover = PageCover.key(of: page, in: pages)
                out.tiles = page.tiles.map { Self.absolute($0, in: template, pages: pages) }
                if byKey[key] == nil { order.append(key) }
                byKey[key] = out
            }
        }
        return core + order.compactMap { byKey[$0] }
    }

    /// The template key a template's page stands under: `template:` and its
    /// name, or the name of the page it is a copy of.
    static func templateKey(of page: PageSpec) -> String {
        guard page.isShadow else { return TileToken.templateKeyPrefix + page.key }
        return TileToken.isTemplateKey(page.shadows) ? page.shadows : TileToken.templateKeyPrefix + page.shadows
    }

    /// `entry` of a template's page as it reads from a scene built on it: a
    /// link to one of its pages is `<template>:`, to its home is Home, and to
    /// a BlasterAI 60 page it has its own copy of is that copy.
    static func absolute(_ entry: TileEntry, in template: BlasterScene, pages: [PageSpec]) -> TileEntry {
        let link = entry.link
        guard !link.isEmpty, link != TileToken.home, TileToken.scenePageKey(link) == nil else { return entry }
        var out = entry
        if let key = TileToken.systemPageKey(link) {
            guard !TileToken.isTemplateKey(key), pages.contains(where: { $0.shadows == key }) else { return entry }
            out.link = TileToken.templateLink(to: key)
        } else if link == template.homePageKey {
            out.link = TileToken.home
        } else {
            let page = pages.first { $0.key == link }
            out.link = TileToken.systemLink(to: page.map(templateKey(of:)) ?? TileToken.templateKeyPrefix + link)
        }
        return out
    }

    /// The navigation bar the chain gives a scene without its own: the
    /// nearest template's own bar, its links made `absolute`; nil when no
    /// template has one, and BlasterAI 60's is drawn.
    var navBar: [TileEntry]? {
        for template in templates {
            guard let row = template.ownRow else { continue }
            return row.tiles.map { Self.absolute($0, in: template, pages: template.pages) }
        }
        return nil
    }

    /// The template whose page `systemKey` is, nearest first; nil for a
    /// BlasterAI 60 page.
    func owner(ofSystemPage systemKey: String) -> BlasterScene? {
        guard TileToken.isTemplateKey(systemKey) else { return nil }
        return templates.first { template in
            template.pages.contains { $0.key != template.homePageKey && Self.templateKey(of: $0) == systemKey }
        }
    }

    /// The template's own page behind `systemKey`, by its key in the
    /// template, for editing it there.
    func pageInOwner(_ systemKey: String) -> (template: BlasterScene, pageKey: String)? {
        guard let owner = owner(ofSystemPage: systemKey),
              let page = owner.pages.first(where: { Self.templateKey(of: $0) == systemKey }) else { return nil }
        return (owner, page.key)
    }

    /// The template a spreadsheet's `Template:` line names: by name (the
    /// name without a copy number, any case), slug or `sceneID`.
    static func named(_ text: String, in templates: [BlasterScene]) -> BlasterScene? {
        let wanted = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { return nil }
        return templates.first { $0.isTemplate && !$0.sceneID.isEmpty
            && ($0.sceneID.lowercased() == wanted || $0.slug.lowercased() == wanted
                || $0.name.lowercased() == wanted || BlasterScene.copyRoot(of: $0.name).lowercased() == wanted) }
    }

    /// A readable name for a template id this device cannot find: its slug,
    /// the part after the author (`…/brandi-board` → `brandi-board`).
    static func missingName(_ templateID: String) -> String {
        templateID.split(separator: "/").last.map(String.init) ?? templateID
    }

    /// Templates `scene` may be built on: not itself, and none whose own
    /// chain already runs through it.
    static func choices(for scene: BlasterScene, templates: [BlasterScene]) -> [BlasterScene] {
        templates.filter { candidate in
            // A carried template is not one of the caregiver's boards to
            // choose; adding it to their scenes first makes it one.
            guard candidate.isTemplate, !candidate.isCarriedTemplate,
                  candidate.persistentModelID != scene.persistentModelID,
                  !candidate.sceneID.isEmpty else { return false }
            let chain = TemplateChain(scene: candidate, templates: templates, system: nil)
            return !chain.templates.contains { $0.persistentModelID == scene.persistentModelID }
        }
    }
}

/// Deleting a template other scenes are built on.
///
/// Left alone, those scenes would fall back to BlasterAI 60: its bar for the
/// template's, its pages for the template's, and a link to a page only the
/// template had — Bible, on a scene built on Brandi Core — would open
/// nothing. So each keeps its look: the template's bar and the pages it
/// reaches are copied into it, and it is built on what the template was.
enum TemplateRemoval {
    struct Dependent {
        let scene: BlasterScene
    }

    /// Every scene built on `template`, directly or through another template.
    static func dependents(of template: BlasterScene, scenes: [BlasterScene],
                           system: BlasterScene?) -> [Dependent] {
        let templates = scenes.filter(\.isTemplate)
        return scenes.compactMap { scene in
            guard scene.persistentModelID != template.persistentModelID, !scene.isDefault else { return nil }
            let chain = TemplateChain(scene: scene, templates: templates, system: system)
            guard chain.templates.contains(where: { $0.persistentModelID == template.persistentModelID })
            else { return nil }
            return Dependent(scene: scene)
        }
    }

    /// Give `scene` what it draws from `template` as its own, so deleting the
    /// template changes nothing it shows: the template's navigation bar when
    /// the scene draws it, and every page of the template the scene reaches,
    /// as ordinary pages of the scene — no longer copies of anything — with
    /// its `<template>:` links to them made plain links. A copy the scene had
    /// already made of one of them becomes that page. Call `rebind` after
    /// every dependent has kept its look: a scene built on the template
    /// through another reads its pages through that one until then.
    static func keepLook(of scene: BlasterScene, without template: BlasterScene,
                         templates: [BlasterScene], system: BlasterScene?) {
        let chain = TemplateChain(scene: scene, templates: templates, system: system)
        if scene.ownRow == nil,
           chain.templates.first(where: { $0.ownRow != nil })?.persistentModelID == template.persistentModelID,
           let bar = chain.navBar {
            scene.ownRow = PageSpec(key: BlasterScene.rowPageKey, displayName: "Navigation Bar", tiles: bar)
        }
        let pages = chain.pages(atLevel: nil)
        let from = scene.pages + (scene.ownRow.map { [$0] } ?? [])
        let reachable = BoardLevels.reachableSystemKeys(
            from: from, systemPages: pages, homePageKey: chain.homePageKey,
            inheritsRow: BoardChrome.inherits(scene),
            rowKeys: BoardChrome.systemPageKeys(of: scene, inherited: chain.navBar))
        let theirs = reachable.filter {
            chain.owner(ofSystemPage: $0)?.persistentModelID == template.persistentModelID
        }
        guard !theirs.isEmpty else { return }

        var own = scene.pages
        var keyFor: [String: String] = [:]
        var taken = Set(own.map(\.key))
        for key in theirs.sorted() {
            if let i = own.firstIndex(where: { $0.shadows == key }) {
                own[i].shadows = ""
                keyFor[key] = own[i].key
            } else if var page = pages.first(where: { $0.key == key }) {
                let base = TileToken.bareKey(key)
                var name = base
                var n = 2
                while taken.contains(name) { name = "\(base)_\(n)"; n += 1 }
                taken.insert(name)
                if page.displayName.isEmpty, name != base { page.displayName = PageNaming.displayName(base) }
                page.key = name
                own.append(page)
                keyFor[key] = name
            }
        }
        func plain(_ tiles: [TileEntry]) -> [TileEntry] {
            tiles.map { entry in
                guard let key = TileToken.systemPageKey(entry.link), let name = keyFor[key] else { return entry }
                var out = entry
                out.link = name
                return out
            }
        }
        scene.pages = own.map { page in
            var page = page
            page.tiles = plain(page.tiles)
            return page
        }
        if var row = scene.ownRow {
            row.tiles = plain(row.tiles)
            scene.ownRow = row
        }
    }

    /// The scenes built directly on `template` are then built on what it was
    /// built on; those built on it through another template keep that one.
    static func rebind(_ dependents: [Dependent], without template: BlasterScene) {
        for dependent in dependents where dependent.scene.templateID == template.sceneID {
            dependent.scene.templateID = template.templateID
        }
    }

    /// Take `scene` off every template, keeping the template pages it links
    /// to as its own (`keepLook`), so no `template:` link opens nothing. The
    /// template's bar stays as the scene's own only when `keepingBar`.
    static func leave(_ scene: BlasterScene, keepingBar: Bool,
                      templates: [BlasterScene], system: BlasterScene?) {
        let chain = TemplateChain(scene: scene, templates: templates, system: system)
        let hadOwnBar = scene.ownRow != nil
        for template in chain.templates {
            keepLook(of: scene, without: template, templates: templates, system: system)
        }
        if !keepingBar, !hadOwnBar { scene.ownRow = nil }
        scene.templateID = ""
    }

    /// Carried templates (`BlasterScene.isCarriedTemplate`) no scene uses
    /// any more, directly or through another template: theirs to delete.
    static func unusedCarried(in scenes: [BlasterScene]) -> [BlasterScene] {
        let templates = scenes.filter(\.isTemplate)
        var used = Set<String>()
        for scene in scenes where !scene.isCarriedTemplate {
            let chain = TemplateChain(scene: scene, templates: templates, system: nil)
            used.formUnion(chain.templates.map(\.sceneID))
        }
        return scenes.filter { $0.isCarriedTemplate && !used.contains($0.sceneID) }
    }

    /// Keep every dependent's look, then let the template go.
    static func keepLookOfAll(_ dependents: [Dependent], without template: BlasterScene,
                              templates: [BlasterScene], system: BlasterScene?) {
        for dependent in dependents {
            keepLook(of: dependent.scene, without: template, templates: templates, system: system)
        }
        rebind(dependents, without: template)
    }
}
