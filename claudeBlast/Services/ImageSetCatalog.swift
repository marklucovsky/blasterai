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

    /// The skin tone this set was built to land on, nil when it has none.
    var toneTarget: ToneTarget? { descriptor?.toneTarget }
}

/// The skin tone a set's figures were built to land on.
///
/// Carried as **channel values, not a label**, because a label does not work:
/// the first offline pilot asked for "medium skin tone (Fitzpatrick IV)" and got
/// back rgb(176,80,24) — terracotta, and darker than the *dark* reference. The
/// model needs the target colour. Blue is the channel that decides whether a
/// brown reads as skin or as rust, so the prompt states it as a ratio too.
///
/// These are the same values `tools/build_tone_variants.py` built the shipped
/// sets with, sampled from the Apple Color Emoji tone modifiers
/// (`tools/measure_skin_tone.py`). Runtime word-adds must walk the same scale
/// with the same numbers or a new word lands off-palette from the set it joins.
struct ToneTarget: Hashable, Sendable {
    let label: String        // caregiver-facing: "Medium"
    let fitzpatrick: String  // construction reference: "Fitzpatrick IV"
    let emoji: String        // the emoji modifier the value was sampled from
    let summary: String      // "moderate Mediterranean or East Asian brown"
    let red: Int
    let green: Int
    let blue: Int

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    /// Blue and green as a percentage of red — how the prompt pins the hue.
    var bluePercent: Int { Int((Double(blue) / Double(red) * 100).rounded()) }
    var greenPercent: Int { Int((Double(green) / Double(red) * 100).rounded()) }
    /// "medium skin (#BF8F68)" — how a step names where it is coming FROM.
    var origin: String { "\(label.lowercased()) skin (\(hex))" }
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
    /// additions render in the wrong style. It also groups sets into styles —
    /// see `TileStyle`.
    let stylePromptKey: String

    /// The style's human name — "Classic", not "Classic — Light".
    ///
    /// Repeated across a style's variants rather than derived by splitting
    /// `displayName` on its separator. That split is exactly the kind of string
    /// surgery that already broke once here, when an em-dash was missing from a
    /// list of separators and "Classic — Medium-Dark" parsed as a set nobody had
    /// heard of. `styleNamesAgreeWithinAStyle` keeps the copies honest.
    let styleName: String

    /// The skin tone this set's figures sit at, nil for sets where skin tone is
    /// not a property of the art (High Contrast is white-on-black silhouettes).
    ///
    /// Present on the tone *base* as well as its variants, because a step along
    /// the scale has to name where it is coming from as well as where it is
    /// going — see `ToneTarget`.
    let toneTarget: ToneTarget?

    /// Position in this set's style: **0 is the base**, and each higher index is
    /// one transform further along.
    ///
    /// This is how a style stays a family. New art is generated ONCE, for the
    /// base, and every other variant is a transform of the variant before it —
    /// the same build order `tools/build_tone_variants.py --chain` used for the
    /// shipped sets. Without it, each set generated independently and "swimmer"
    /// came out as three different swimmers in different swimsuits, one wearing a
    /// cap. In AAC the figure is the referent, so a child switching tone would
    /// have met a different person.
    ///
    /// **It is a chain, not a star.** Dark is index 2 and is transformed from
    /// Medium, not from Classic. Asking for the dark end in one jump is what the
    /// offline build tried first and abandoned: results ranged luma 46–201 across
    /// six tiles, sometimes coming back *lighter* than the step above them,
    /// because the model has no idea the tones form an ordered scale when each
    /// call sees one target alone.
    let variantIndex: Int

    var isSystemOwned: Bool { !systemSetKey.isEmpty }
    var slug: String { id.rawValue }
    var acceptsNewWords: Bool { isGenerationTarget && !stylePromptKey.isEmpty }
    var isStyleBase: Bool { variantIndex == 0 }
}

/// A family of sets drawn the same way, differing only by variant transform.
///
/// **A style is the unit art is generated in, and a set is what a caregiver
/// looks at.** Classic is a style whose variants are Light, Medium and Dark;
/// Playful 3D and High Contrast are styles with one variant each. Adding a word
/// generates the style's base and then one transform per remaining variant, so
/// the style as a whole supports the new word and switching tone never turns up
/// a missing or off-palette tile.
///
/// A style with one variant is not a special case — it is N transforms where N
/// is zero. If Playful 3D ever gains tones it slots into the same machinery with
/// no new code path.
///
/// Derived from the descriptors rather than listed separately: a set names its
/// style with `stylePromptKey` and its place in it with `variantIndex`, so an
/// installed set joins the right family without a second table to keep in sync.
struct TileStyle: Identifiable, Hashable, Sendable {
    /// The `stylePromptKey` its variants share — the key into `image_styles.json`.
    let id: String
    /// Base first, then each transform in the order it must be applied.
    let variants: [ImageSetDescriptor]

    var base: ImageSetDescriptor { variants[0] }
    var setIDs: [ImageSetID] { variants.map(\.id) }
    /// "Classic" — what a caregiver calls the family, not any one variant.
    var displayName: String { base.styleName }

    /// The variants to produce when `set` is the one a caregiver actually uses,
    /// or every variant when `set` belongs to some other style (or is nil).
    ///
    /// **Always a prefix, never a subset.** Each variant is transformed from the
    /// one before it, so Dark cannot exist without Medium — "generate Light and
    /// Dark but skip Medium" is not a request that can be honoured, and a UI
    /// offering it would be lying. The only real choice is where to stop.
    ///
    /// Stopping at the active variant is the default because most caregivers
    /// identify with exactly one: someone on Medium needs Medium and the Light
    /// base it derives from, and nothing else. Dark is a call they never asked
    /// for. The variants above the stop are kept anyway — they already exist in
    /// memory, so the cost was the API call, not the row.
    func variants(upTo set: ImageSetID?) -> [ImageSetDescriptor] {
        guard let set, let stop = variants.firstIndex(where: { $0.id == set })
        else { return variants }
        return Array(variants.prefix(through: stop))
    }
    /// Whether a caregiver adding a word gets art in this style. A property of
    /// the style, not the set: the variants are one piece of art plus transforms,
    /// so generating "some of them" is not a meaningful request.
    var acceptsNewWords: Bool { base.acceptsNewWords }
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
    ///
    /// ## Display names deliberately do not match the slugs
    ///
    /// The slugs (`classic`, `classic_medium`, `classic_medium_dark`) name the
    /// Fitzpatrick/emoji steps the sets were *built* from, and are frozen because
    /// they are persisted in `TileArtVariant.imageSetRaw` and the `imageSet`
    /// default.
    ///
    /// The labels are **Light / Medium / Dark**, relative to these three sets and
    /// nothing else. Fitzpatrick is our construction reference, not a caregiver's
    /// vocabulary — "Medium-Dark" only means something to someone who knows the
    /// scale it came from. And the labels tell the truth about *this* palette:
    /// the darkest set really is our dark end, because the black facial features
    /// stop reading below it (see the note on cutting Fitzpatrick VI), so calling
    /// it "Medium-Dark" would imply a darker option that deliberately does not
    /// exist.
    ///
    /// So `classic_medium_dark` is labelled "Classic — Dark", and the base set —
    /// which measures at the emoji Medium-Light swatch — is labelled
    /// "Classic — Light". Both are correct in their own frame.
    static let system: [ImageSetDescriptor] = [
        ImageSetDescriptor(
            id: .classic,
            setID: firstPartyID("classic"),
            displayName: "Classic — Light",
            shortName: "Light",
            summary: "Flat pictograms, like most school boards and other AAC apps.",
            bundlePrefix: "cls",
            version: "1.0.0",
            systemSetKey: "classic",
            isShippable: true,
            isGenerationTarget: true,
            stylePromptKey: "classic",
            styleName: "Classic",
            // Measured from the shipped art rather than taken from the emoji
            // scale: Classic's figures sit at roughly #F0B482, warmer than the
            // Light modifier. A step has to start from where the art actually
            // is, not from where the label suggests it should be.
            toneTarget: ToneTarget(label: "Light", fitzpatrick: "Fitzpatrick II–III",
                                   emoji: "🏻", summary: "light, warm",
                                   red: 240, green: 180, blue: 130),
            variantIndex: 0),
        ImageSetDescriptor(
            id: .classicMedium,
            setID: firstPartyID("classic_medium"),
            displayName: "Classic — Medium",
            shortName: "Medium",
            summary: "The same pictograms with a medium skin tone.",
            bundlePrefix: "clsm",
            version: "1.0.0",
            systemSetKey: "classic_medium",
            isShippable: true,
            isGenerationTarget: true,
            stylePromptKey: "classic",
            styleName: "Classic",
            toneTarget: ToneTarget(label: "Medium", fitzpatrick: "Fitzpatrick IV",
                                   emoji: "🏽",
                                   summary: "moderate Mediterranean or East Asian brown",
                                   red: 191, green: 143, blue: 104),
            variantIndex: 1),
        ImageSetDescriptor(
            id: .classicMediumDark,
            setID: firstPartyID("classic_medium_dark"),
            displayName: "Classic — Dark",
            shortName: "Dark",
            summary: "The same pictograms with a darker skin tone.",
            bundlePrefix: "clsmd",
            version: "1.0.0",
            systemSetKey: "classic_medium_dark",
            isShippable: true,
            isGenerationTarget: true,
            stylePromptKey: "classic",
            styleName: "Classic",
            toneTarget: ToneTarget(label: "Dark", fitzpatrick: "Fitzpatrick V",
                                   emoji: "🏾",
                                   summary: "dark brown, South Asian or Middle Eastern",
                                   red: 155, green: 100, blue: 61),
            // Transformed from Medium, not Classic — see `variantIndex`.
            variantIndex: 2),
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
            styleName: "Playful 3D",
            toneTarget: nil,
            variantIndex: 0),
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
            isGenerationTarget: true,
            stylePromptKey: "high_contrast_v2",
            styleName: "High Contrast",
            toneTarget: nil,
            variantIndex: 0),
    ]

    /// Sets installed from outside the bundle. Empty until installable sets land;
    /// the lookups below already read it so that work is additive rather than a
    /// second code path.
    static var installed: [ImageSetDescriptor] = []

    static var all: [ImageSetDescriptor] { system + installed }

    /// Resolution ladder, mirroring `TileScriptValidator.resolveScene`:
    /// **slug → qualified setID → displayName**. A reference authored before
    /// this model existed is a bare slug and still resolves.
    ///
    /// Every rung is case-insensitive. Lookup is not storage: `"Classic"` from a
    /// hand-written script or an import should find the set whose slug is
    /// `classic`. That used to work by accident — it fell through to the
    /// displayName rung, which was literally "Classic" — and broke the moment the
    /// label became "Classic — Light". Matching identity case-insensitively is
    /// what was actually meant.
    static func descriptor(for id: ImageSetID) -> ImageSetDescriptor? {
        let raw = id.rawValue
        func same(_ a: String, _ b: String) -> Bool {
            a.caseInsensitiveCompare(b) == .orderedSame
        }
        if let bySlug = all.first(where: { same($0.id.rawValue, raw) }) { return bySlug }
        if let byQualified = all.first(where: { same($0.setID, raw) }) { return byQualified }
        return all.first { same($0.displayName, raw) }
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

    // MARK: - Styles

    /// Every style this install knows about, in catalog order, each with its
    /// variants ordered base-first.
    ///
    /// Grouped out of the descriptors rather than listed separately so there is
    /// nothing to keep in sync — a set declares its style and its place in it,
    /// and an installed set joins the right family by saying so.
    static var styles: [TileStyle] {
        var order: [String] = []
        var grouped: [String: [ImageSetDescriptor]] = [:]
        for set in all where !set.stylePromptKey.isEmpty {
            if grouped[set.stylePromptKey] == nil { order.append(set.stylePromptKey) }
            grouped[set.stylePromptKey, default: []].append(set)
        }
        return order.compactMap { key in
            // Sorted by index, then slug so the order is total — two sets
            // claiming the same index would otherwise make the base, and
            // therefore every transform below it, depend on dictionary order.
            let variants = grouped[key]!.sorted {
                ($0.variantIndex, $0.slug) < ($1.variantIndex, $1.slug)
            }
            // A style whose first variant is not a base has no art to transform
            // FROM, so there is nothing coherent to generate. Dropping it keeps
            // the invariant `variants[0].isStyleBase` that `TileStyle.base`
            // relies on; `stylesCoverEverySet` fails loudly if it ever happens.
            guard variants.first?.isStyleBase == true else { return nil }
            return TileStyle(id: key, variants: variants)
        }
    }

    /// The style a set belongs to, nil for a set that names no style.
    static func style(for set: ImageSetID) -> TileStyle? {
        guard let key = descriptor(for: set)?.stylePromptKey, !key.isEmpty else { return nil }
        return styles.first { $0.id == key }
    }

    /// Styles art is generated in when a caregiver adds a word, the active set's
    /// style first so their own board fills in before the others.
    static var generationTargets: [TileStyle] {
        styles.filter(\.acceptsNewWords)
    }

    static func generationTargets(preferring preferred: ImageSetID) -> [TileStyle] {
        let targets = generationTargets
        guard let active = style(for: preferred), targets.contains(active) else { return targets }
        return [active] + targets.filter { $0 != active }
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
