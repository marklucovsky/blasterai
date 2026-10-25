// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneStructure.swift
//  claudeBlast
//
//  Structure — the pages and core words a caregiver adds to a scene — resolved
//  in one place, for every surface that offers it.
//
//  ## Why this exists
//
//  A generated scene used to arrive pre-wrapped in a core cluster and four
//  category pages, and the only control over that was a "Focused board" toggle
//  that rebuilt the scene from its home-page words — silently dropping every
//  page the caregiver had made. There was no way to ask for a *different*
//  structure, only more or less of ours.
//
//  So structure became a step you walk through rather than a flag you set.
//  Creation produces a flat page of the words the scene is about; pages and core
//  words are chosen afterwards, explicitly, by the person who knows what the
//  child needs. `SceneStructurePlan` is that choice, and `SceneStructure.build`
//  turns it into pages.
//
//  ## Additive by construction
//
//  `build` only ever produces *new* pages and *new* home-page tiles. It reads the
//  scene's existing page keys and home-page tiles so it can skip what is already
//  there and uniquify what isn't, but it never rewrites, reorders or removes
//  anything. That is what makes the step safe to re-enter on a scene someone has
//  spent an afternoon on — the property the old toggle lacked.
//
//  ## Side effects, and why they are acceptable
//
//  Building a pack page installs that pack's words, and every new page mints its
//  `page_link` tile. Both land in the device's vocabulary immediately, before the
//  scene is accepted. That is deliberate: a pack's words are vocabulary the
//  family now has rather than scene content, so backing out of the wizard
//  afterwards leaves extra words available — never a broken scene. It is also
//  what lets the confirm step render the new pages as real tiles instead of
//  placeholders.
//

import Foundation
import SwiftData

/// What the caregiver asked for in the structure step. Pure selection — it holds
/// no tiles and performs no work; `SceneStructure.build` resolves it.
struct SceneStructurePlan: Equatable {
    /// How much of the familiar core board to add to the home page.
    var chrome: SceneNavigation.ChromeBundle = .none
    /// `VocabPack.id`s to add, one page each.
    var packIDs: Set<String> = []
    /// Word-class names to add, one page each.
    var wordClasses: Set<String> = []
    /// Pages to copy from other scenes, as `"<sceneID>|<pageKey>"` — the same
    /// page key can exist in two scenes, so the scene has to be part of the id.
    var donorPages: Set<String> = []

    /// Donor token for a page, matching what `build` expects.
    static func donorToken(sceneID: String, pageKey: String) -> String {
        "\(sceneID)|\(pageKey)"
    }

    /// How many distinct things this plan adds — pages, plus the core strip if
    /// one was chosen. Drives the step's summary line.
    var additionCount: Int {
        packIDs.count + wordClasses.count + donorPages.count + (chrome == .none ? 0 : 1)
    }

    var isEmpty: Bool { additionCount == 0 }
}

/// The pages and home-page tiles a plan resolved to, ready to be appended either
/// to an in-flight `GeneratedScene` (the wizard) or to a saved `BlasterScene`
/// (the editor). Nothing here replaces anything.
struct SceneStructureResult {
    /// New pages, keys already uniquified against the scene.
    var pages: [PageSpec] = []
    /// Tiles to append to the home page: core words first, then the nav links
    /// for the pages above.
    var homeAdditions: [TileEntry] = []
    /// Tiles created along the way — installed pack words and minted page links.
    /// Handed back so a caller holding a stale `@Query` snapshot can still
    /// resolve them (see the note on side effects above).
    var createdTiles: [TileModel] = []

    var isEmpty: Bool { pages.isEmpty && homeAdditions.isEmpty }
}

/// What a plan *would* do, worked out without touching the store.
///
/// `build` installs packs and mints page links, so it can't run on every tap of
/// a toggle — but the structure step is only worth having if you can see what
/// you are choosing. This is the same walk over the same plan, producing only
/// what a preview needs to draw. `SceneStructureTests` holds the two to each
/// other so the picture can't drift from the result.
struct SceneStructureOutline: Equatable {
    struct Page: Equatable {
        var title: String
        var tileCount: Int
    }
    /// Core-word tile keys appended to the home page, in order.
    var homeWords: [String] = []
    /// Titles of the pages the home page gains a link to, in order.
    var homeLinks: [String] = []
    /// The pages themselves.
    var pages: [Page] = []

    var isEmpty: Bool { homeWords.isEmpty && pages.isEmpty }
}

enum SceneStructure {
    /// Resolve `plan` into pages and home-page tiles.
    ///
    /// - Parameters:
    ///   - existingPageKeys: page keys already on the scene. New keys are
    ///     uniquified against these, and a chrome category page whose key is
    ///     taken is skipped rather than duplicated.
    ///   - homeTileKeys: keys already on the home page, so a core word the scene
    ///     already carries isn't added twice.
    ///   - packs / donorScenes: the catalogs the plan's ids refer to. Passed in
    ///     rather than fetched here so the caller's filtering — received packs,
    ///     eligible donor scenes — is the one that applies.
    static func build(_ plan: SceneStructurePlan,
                      existingPageKeys: Set<String>,
                      homeTileKeys: Set<String>,
                      into context: ModelContext,
                      allTiles: [TileModel],
                      packs: [VocabPack],
                      donorScenes: [BlasterScene]) -> SceneStructureResult {
        var result = SceneStructureResult()
        var lookup = Dictionary(allTiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        var takenPageKeys = existingPageKeys
        // Nav links are collected apart from the pages so they can sort *after*
        // the core strip on the home page — the order the old scaffolder used.
        var navLinks: [TileEntry] = []

        /// Build one collection into a page and remember its nav link. Returns
        /// the key the page actually got, or nil if the source yielded nothing.
        @discardableResult
        func add(_ source: CollectionSource) -> String? {
            guard let built = CollectionSource.build(source, into: context,
                                                     allTiles: allTiles, existing: lookup)
            else { return nil }
            // MUST re-read: installing a pack INSERTS tiles, and `allTiles` is a
            // @Query snapshot that does not refresh mid-call. A later addition —
            // or the core strip — has to be able to see those words.
            for (key, tile) in refresh(context, fallback: allTiles) where lookup[key] == nil {
                lookup[key] = tile
                result.createdTiles.append(tile)
            }

            let pageKey = unique(TileModel.normalizeKey(built.baseKey), taken: &takenPageKeys)
            result.pages.append(PageSpec(key: pageKey, displayName: built.displayName,
                                         tiles: built.tiles))

            let link: TileModel
            switch built.cover {
            case .data(let data):
                link = PageLink.mint(pageKey: pageKey, displayName: built.displayName,
                                     image: data, context: context, existing: lookup)
            case .key(let imageKey):
                link = PageLink.mint(pageKey: pageKey, displayName: built.displayName,
                                     imageKey: imageKey, context: context, existing: lookup)
            }
            // Always carried, minted or reused: the caller's `allTiles` snapshot
            // may predate an earlier run of this step, and a page-link tile the
            // caller cannot resolve renders as a gap where the nav tile should be.
            if lookup[link.key] == nil { lookup[link.key] = link }
            result.createdTiles.append(link)
            navLinks.append(TileEntry(key: link.key, link: pageKey, isAudible: false))
            return pageKey
        }

        // 1. Packs, in catalog order.
        for pack in packs where plan.packIDs.contains(pack.id) { add(.pack(pack)) }

        // 2. Word classes, in canonical class order.
        for cls in VocabularyClasses.caregiverSelectable where plan.wordClasses.contains(cls.name) {
            add(.wordClass(classes: [cls.name]))
        }

        // 3. Pages from other scenes: BlasterAI 60's are linked, everyone
        //    else's copied. A link opens the core board's own page, so it stays
        //    current as that board changes; another scene can be edited or
        //    deleted under us, so its page is copied.
        for donor in donorScenes {
            for page in donor.pages
            where plan.donorPages.contains(SceneStructurePlan.donorToken(sceneID: donor.sceneID,
                                                                         pageKey: page.key)) {
                if donor.isDefault, let folder = systemFolder(for: page.key, in: donor) {
                    navLinks.append(folder)
                } else {
                    add(.copyPage(page))
                }
            }
        }

        // 4. The chosen word strip.
        //
        // Words only. A bundle used to bring category pages with it, which meant
        // one control quietly made two decisions; pages are ticked above, each
        // with its own link. See `SceneNavigation.ChromeBundle`.
        var present = homeTileKeys
        var core: [TileEntry] = []
        for key in plan.chrome.clusterKeys where lookup[key] != nil && !present.contains(key) {
            core.append(TileEntry(key: key, link: "", isAudible: true))
            present.insert(key)
        }

        result.homeAdditions = core + navLinks
        return result
    }

    /// Work out what `plan` would add, without adding it. Pure — no inserts, no
    /// minting, safe to call on every toggle. Walks the plan in the same order
    /// `build` does; keep the two in step.
    static func outline(_ plan: SceneStructurePlan,
                        existingPageKeys: Set<String>,
                        homeTileKeys: Set<String>,
                        allTiles: [TileModel],
                        packs: [VocabPack],
                        donorScenes: [BlasterScene]) -> SceneStructureOutline {
        var outline = SceneStructureOutline()
        var takenPageKeys = existingPageKeys
        let vocabulary = Set(allTiles.map(\.key))
        /// Keys a pack will have installed by the time the core strip is built —
        /// `build` re-reads the store after each addition, and this stands in.
        var reachable = vocabulary

        func add(title: String, baseKey: String, tileCount: Int) {
            guard tileCount > 0 else { return }
            _ = unique(TileModel.normalizeKey(baseKey), taken: &takenPageKeys)
            outline.pages.append(.init(title: title, tileCount: tileCount))
            outline.homeLinks.append(title)
        }

        func classCount(_ classes: [String]) -> Int {
            let set = Set(classes)
            return allTiles.count { set.contains($0.wordClass) && !$0.isRetired }
        }

        for pack in packs where plan.packIDs.contains(pack.id) {
            reachable.formUnion(pack.words.map(\.key))
            add(title: pack.displayName, baseKey: pack.slug, tileCount: pack.words.count)
        }

        for cls in VocabularyClasses.caregiverSelectable where plan.wordClasses.contains(cls.name) {
            add(title: cls.label, baseKey: cls.name, tileCount: classCount([cls.name]))
        }

        for donor in donorScenes {
            for page in donor.pages
            where plan.donorPages.contains(SceneStructurePlan.donorToken(sceneID: donor.sceneID,
                                                                         pageKey: page.key)) {
                let count = page.tiles.count { entry in
                    guard let tile = allTiles.first(where: { $0.key == entry.key }) else { return false }
                    return !tile.isRetired && !tile.isStructuralChrome
                }
                if donor.isDefault, systemFolder(for: page.key, in: donor) != nil {
                    outline.homeLinks.append(SystemLinks.displayName(of: TileToken.systemLink(to: page.key)))
                    continue
                }
                // Not `page.title` — a copy is named from its key, the way
                // `CollectionSource.copyPage` names it.
                add(title: page.key.replacingOccurrences(of: "_", with: " ").capitalized,
                    baseKey: page.key, tileCount: count)
            }
        }

        var present = homeTileKeys
        for key in plan.chrome.clusterKeys where reachable.contains(key) && !present.contains(key) {
            outline.homeWords.append(key)
            present.insert(key)
        }
        return outline
    }

    /// A folder that opens `pageKey` on the system scene: the tile and colour
    /// that board itself uses to reach it. Nil for its home, which is Home,
    /// and for a page nothing on that board opens.
    static func systemFolder(for pageKey: String, in system: BlasterScene) -> TileEntry? {
        guard pageKey != system.homePageKey else { return nil }
        let opener = system.pages.lazy.flatMap(\.tiles).first { $0.link == pageKey && !$0.isSpacer }
        return opener.map {
            TileEntry(key: $0.key, link: TileToken.systemLink(to: pageKey), isAudible: false,
                      linkColor: $0.linkColor, linkColorIsAuto: $0.linkColor == nil)
        }
    }

    // MARK: - Private

    private static func unique(_ base: String, taken: inout Set<String>) -> String {
        let seed = base.isEmpty ? "page" : base
        var key = seed
        var n = 2
        while taken.contains(key) { key = "\(seed)_\(n)"; n += 1 }
        taken.insert(key)
        return key
    }

    private static func refresh(_ context: ModelContext, fallback: [TileModel]) -> [String: TileModel] {
        let tiles = (try? context.fetch(FetchDescriptor<TileModel>())) ?? fallback
        return Dictionary(tiles.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - Applying a result

extension BlasterScene {
    /// Append a structure result to this saved scene. Used by the scene editor,
    /// and by the wizard's cached-starter path — which imports the bundle first,
    /// to keep the bundled art, and then adds the structure on top.
    func applyStructure(_ result: SceneStructureResult) {
        guard !result.isEmpty else { return }
        var updated = pages
        updated.append(contentsOf: result.pages)
        if homePageKey.isEmpty, let first = updated.first { homePageKey = first.key }
        if let homeIndex = updated.firstIndex(where: { $0.key == homePageKey }) {
            updated[homeIndex].tiles.append(contentsOf: result.homeAdditions)
        }
        pages = updated
        lastModified = .now
    }
}

extension GeneratedScene {
    /// Fold a structure result into this in-flight scene so the confirm step can
    /// show the whole board before anything is saved. The pages and tiles are the
    /// exact ones `SceneBuilder` will materialize — nothing is re-derived later.
    func adding(_ result: SceneStructureResult) -> GeneratedScene {
        guard !result.isEmpty else { return self }
        var updated = pages
        let home = pages.contains(where: { $0.key == homePageKey })
            ? homePageKey
            : (pages.first?.key ?? "")
        if let homeIndex = updated.firstIndex(where: { $0.key == home }) {
            updated[homeIndex].tiles += result.homeAdditions.map {
                GeneratedTile(key: $0.key, isAudible: $0.isAudible, link: $0.link,
                              linkColor: $0.linkColorIsAuto ? nil : $0.linkColor)
            }
        }
        updated += result.pages.map { page in
            GeneratedPage(key: page.key,
                          tiles: page.tiles.map {
                              GeneratedTile(key: $0.key, isAudible: $0.isAudible, link: $0.link)
                          },
                          displayName: page.displayName)
        }
        var next = self
        next.pages = updated
        next.homePageKey = home.isEmpty ? (updated.first?.key ?? "") : home
        return next
    }
}
