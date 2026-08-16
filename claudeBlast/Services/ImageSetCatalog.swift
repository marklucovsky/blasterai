// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ImageSetCatalog.swift
//  claudeBlast
//
//  Identity and metadata for tile art sets, modelled on scene identity.
//

import Foundation

/// Stable identity for a tile art set.
///
/// **Was a closed enum.** That worked while there were four hardcoded sets and
/// broke the moment sets became content: a downloadable or caregiver-created set
/// cannot be a case in an enum without an app update, tone variants multiply
/// cases combinatorially, and `ImageSetID(rawValue:) ?? .playful3D` silently
/// rendered the wrong art for any id the build didn't know.
///
/// Now a string wrapper, exactly as `BlasterScene` treats scene identity: the id
/// is data, and the app resolves what it can. `TileArtVariant.imageSetRaw` and
/// the `imageSet` UserDefault already stored these strings, so every existing
/// row keeps working — the slug **is** the persisted identity and must not
/// change (see `ImageSetDescriptor.setID` for the qualified provenance id).
struct ImageSetID: RawRepresentable, Hashable, Codable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    var id: String { rawValue }

    // Built-in sets. Named so call sites keep reading `.classic` rather than a
    // string literal, and so a typo is a compile error rather than a blank tile.
    static let classic = ImageSetID("classic")
    static let playful3D = ImageSetID("playful_3d")
    static let highContrast = ImageSetID("high_contrast")
    static let classicMedium = ImageSetID("classic_medium")
    static let classicMediumDark = ImageSetID("classic_medium_dark")

    /// The set a new install starts on, and what onboarding preselects.
    ///
    /// Classic, because flat pictograms are the visual language the field
    /// already speaks — ARASAAC, CBoard, CoughDrop, and most laminated paper
    /// boards. A child arriving from any of those keeps the vocabulary they
    /// already learned. Flat art also survives being printed at 2 inches, and
    /// abstract words lean on symbol convention rather than realism.
    static let defaultSet: ImageSetID = .classic

    /// Fills a gap when the active set lacks a key, so an incomplete or
    /// in-progress set still renders something correct rather than a placeholder.
    ///
    /// Separate from `defaultSet` even though both are Classic today: they answer
    /// different questions, and the backfill must always be a set with **full
    /// vocabulary coverage**.
    static let universalBackfill: ImageSetID = .classic

    /// A set this build can actually resolve, or `defaultSet`.
    ///
    /// **Always use this when reading a persisted or user-supplied id.**
    /// `init(rawValue:)` accepts any string on purpose — an installed set's id
    /// must be storable by a build that has never heard of it — which means it
    /// cannot also reject junk. `ImageSetID(rawValue: stored) ?? .defaultSet`
    /// *looks* like it handles that and does nothing at all, because the left
    /// side is not optional.
    ///
    /// That exact line shipped: with no stored preference it produced
    /// `ImageSetID("")`, which matched no card in onboarding (nothing appeared
    /// selected), was then written back as an empty string, and left the resolver
    /// on the default while the UI implied otherwise — so a word added on
    /// Medium-Dark was generated in Classic.
    static func resolved(_ raw: String?) -> ImageSetID {
        guard let raw, !raw.isEmpty,
              ImageSetCatalog.descriptor(forSlug: raw) != nil
        else { return .defaultSet }
        return ImageSetID(raw)
    }
}

// MARK: - Metadata accessors
//
// These read through to the catalog so an id keeps behaving like the enum did at
// call sites. Each falls back to the raw slug rather than a placeholder string:
// an unknown set should look unfamiliar, not look like some other set.

extension ImageSetID {
    var descriptor: ImageSetDescriptor? { ImageSetCatalog.descriptor(for: self) }
    var displayName: String { descriptor?.displayName ?? rawValue }
    var shortName: String { descriptor?.shortName ?? rawValue }
    var summary: String { descriptor?.summary ?? "" }
    var isShippable: Bool { descriptor?.isShippable ?? false }
    var isSystemOwned: Bool { descriptor?.isSystemOwned ?? false }

    /// A tile from this set whose skin tone new art should match, empty when the
    /// set has no tone to match. This is what a runtime word-add passes as a
    /// colour reference — describing a tone in words does not reproduce it.
    var toneExemplarKey: String { descriptor?.toneExemplarKey ?? "" }
}

/// Everything the app needs to know about one set.
///
/// Mirrors the scene model deliberately (`docs/scene-identity.md`): a qualified
/// `setID` for provenance, a `slug` for references and filenames, a `version`
/// for upgrade/dedupe, and a system key that decides mutability.
struct ImageSetDescriptor: Identifiable, Hashable, Sendable {
    let id: ImageSetID

    /// Qualified provenance id — `imagesets.blasterai.app/<slug>` for
    /// first-party sets, `<authorID>/<slug>` for anything a caregiver makes or
    /// installs. The same phone-number/contact-name split scenes use: the id is
    /// machine identity and always present; `displayName` is the human label and
    /// may collide.
    let setID: String

    let displayName: String
    let shortName: String
    let summary: String

    /// Filename prefix in `TileImageSets/` — `{prefix}_{key}.heic`.
    let bundlePrefix: String

    /// For import dedupe and upgrade, as `BlasterScene.sceneVersion`.
    let version: String

    /// Non-empty means **system supplied and immutable**, gated exactly as
    /// `BlasterScene.isSystemOwned` is gated on `systemSceneKey` — never on
    /// "is it first-party", because a bundled set a caregiver may edit is still
    /// theirs to edit. Edits to a system set must produce a clone.
    let systemSetKey: String

    /// Complete, reviewed, and offered to end users. Controls the *picker*, not
    /// the bundle: keeping art out of the binary is a build-phase question.
    let isShippable: Bool

    /// AI art is generated for this set when a caregiver adds a word.
    let isGenerationTarget: Bool

    /// Key in `Resources/image_styles.json` describing how this set is drawn.
    /// A set that can accept new words **must** carry one, or on-device
    /// additions render in the wrong style.
    let stylePromptKey: String

    /// A tile from this set whose skin tone a new word should be matched to.
    ///
    /// This is what makes runtime word-adds work on a tone variant: describing a
    /// tone in words does not reproduce it, but passing an existing correct tile
    /// as a colour swatch does. Empty for sets with no tone to match.
    let toneExemplarKey: String

    var isSystemOwned: Bool { !systemSetKey.isEmpty }
    var slug: String { id.rawValue }
    var acceptsNewWords: Bool { isGenerationTarget && !stylePromptKey.isEmpty }
}

/// The sets this install knows about.
enum ImageSetCatalog {
    /// Authority for first-party sets, matching `SceneIdentity.firstPartyAuthority`.
    static let firstPartyAuthority = "imagesets.blasterai.app"

    static func firstPartyID(_ slug: String) -> String { "\(firstPartyAuthority)/\(slug)" }

    /// Built-in sets, in the order they should be offered.
    ///
    /// Classic leads because it is the default. The tone variants follow it
    /// directly — they are Classic, with skin tone changed and nothing else, so
    /// separating them from their base would misrepresent what they are.
    static let system: [ImageSetDescriptor] = [
        ImageSetDescriptor(
            id: .classic,
            setID: firstPartyID("classic"),
            displayName: "Classic",
            shortName: "Classic",
            summary: "Flat pictograms, like most school boards and other AAC apps.",
            bundlePrefix: "cls",
            version: "1.0.0",
            systemSetKey: "classic",
            isShippable: true,
            isGenerationTarget: true,
            stylePromptKey: "classic",
            toneExemplarKey: ""),
        ImageSetDescriptor(
            id: .classicMedium,
            setID: firstPartyID("classic_medium"),
            displayName: "Classic — Medium",
            shortName: "Medium",
            summary: "Classic art with a medium skin tone.",
            bundlePrefix: "clsm",
            version: "1.0.0",
            systemSetKey: "classic_medium",
            isShippable: true,
            isGenerationTarget: true,
            stylePromptKey: "classic",
            // `mom` is a plain front-facing figure with a large, unambiguous area
            // of skin — the clearest colour reference in the set.
            toneExemplarKey: "mom"),
        ImageSetDescriptor(
            id: .classicMediumDark,
            setID: firstPartyID("classic_medium_dark"),
            displayName: "Classic — Medium-Dark",
            shortName: "Med-Dark",
            summary: "Classic art with a medium-dark skin tone.",
            bundlePrefix: "clsmd",
            version: "1.0.0",
            systemSetKey: "classic_medium_dark",
            isShippable: true,
            isGenerationTarget: true,
            stylePromptKey: "classic",
            toneExemplarKey: "mom"),
        ImageSetDescriptor(
            id: .playful3D,
            setID: firstPartyID("playful_3d"),
            displayName: "Playful 3D",
            shortName: "Playful 3D",
            summary: "Soft 3D characters — warmer, less like traditional symbols.",
            bundlePrefix: "p3d",
            version: "1.0.0",
            systemSetKey: "playful_3d",
            isShippable: true,
            isGenerationTarget: true,
            stylePromptKey: "playful_3d",
            toneExemplarKey: ""),
        ImageSetDescriptor(
            id: .highContrast,
            setID: firstPartyID("high_contrast"),
            displayName: "High Contrast",
            shortName: "Contrast",
            summary: "Bold white on black, for low vision and CVI.",
            bundlePrefix: "hc",
            version: "2.0.0",   // v2 — the complete 546-tile set; v1 had 23 gaps
            systemSetKey: "high_contrast",
            isShippable: true,
            isGenerationTarget: false,
            stylePromptKey: "high_contrast_v2",
            toneExemplarKey: ""),
    ]

    /// Sets installed from outside the bundle. Empty until installable sets land;
    /// the lookups below already read it so that work is additive rather than a
    /// second code path.
    static var installed: [ImageSetDescriptor] = []

    static var all: [ImageSetDescriptor] { system + installed }

    /// Resolution ladder, mirroring `TileScriptValidator.resolveScene`:
    /// **slug → qualified setID → displayName**. A reference authored before
    /// this model existed is a bare slug and still resolves.
    static func descriptor(for id: ImageSetID) -> ImageSetDescriptor? {
        let raw = id.rawValue
        if let bySlug = all.first(where: { $0.id.rawValue == raw }) { return bySlug }
        if let byQualified = all.first(where: { $0.setID == raw }) { return byQualified }
        return all.first { $0.displayName.caseInsensitiveCompare(raw) == .orderedSame }
    }

    static func descriptor(forSlug slug: String) -> ImageSetDescriptor? {
        descriptor(for: ImageSetID(slug))
    }

    /// Sets offered to users. Release builds show only complete, reviewed sets;
    /// debug builds expose everything so a set can be developed against the app.
    static var selectable: [ImageSetDescriptor] {
        #if DEBUG
        return all
        #else
        return all.filter(\.isShippable)
        #endif
    }

    /// Styles AI art is generated for when a caregiver adds a word, default
    /// first so the active set's style appears immediately.
    static var generationTargets: [ImageSetID] {
        all.filter(\.acceptsNewWords).map(\.id)
    }

    static func generationTargets(preferring preferred: ImageSetID) -> [ImageSetID] {
        let targets = generationTargets
        guard targets.contains(preferred) else { return targets }
        return [preferred] + targets.filter { $0 != preferred }
    }

    /// Filename prefix for a set, falling back to the slug so an unknown set
    /// looks for `{slug}_{key}` rather than silently resolving to another set's
    /// art — the failure the old `?? .playful3D` produced.
    static func bundlePrefix(for id: ImageSetID) -> String {
        descriptor(for: id)?.bundlePrefix ?? id.rawValue
    }

    static func displayName(for id: ImageSetID) -> String {
        descriptor(for: id)?.displayName ?? id.rawValue
    }
}
