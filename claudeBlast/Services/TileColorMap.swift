// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TileColorMap.swift
//  claudeBlast
//
//  What the colors mean, when Fitzgerald is not what this child can see.
//

import SwiftUI
import SwiftData

/// A named part-of-speech → color palette.
///
/// ## Why this is editable at all
///
/// The Modified Fitzgerald key assumes eight distinguishable hues. A child with
/// cortical visual impairment often has one reliably-perceived color — commonly
/// red or yellow — and reduced discrimination generally, so several of those
/// eight collapse into each other. A board whose color system the child cannot
/// see teaches nothing while looking like it does, which makes this clinical
/// rather than a preference.
///
/// Adjacent readers the same lever serves: a district standardising on a
/// different key, a family color-blind in a specific band, and the Goossens'
/// variants that differ from Fitzgerald on prepositions.
///
/// ## Sparse on purpose
///
/// `overrides` holds only what someone changed. Everything absent resolves to
/// the Fitzgerald default in `TileColorResolver`, so the default palette stays
/// in code and can be improved later without rewriting anyone's stored data.
///
/// ## An artifact, not a settings bag
///
/// It carries a `name` because a therapist builds one, keeps it, and means to
/// send it to the right family — the same move scenes and vocabulary packs
/// already made. It is also the smallest shareable thing in the app: eleven
/// name→color pairs, small enough that text is a plausible transport. That
/// sharing is deliberately not built yet; the type is shaped for it.
struct TileColorMap: Codable, Hashable {
    var name: String
    /// `PartOfSpeech.rawValue` → hex, e.g. `"verb": "#4CB859"`. Sparse.
    var overrides: [String: String]

    init(name: String = "", overrides: [String: String] = [:]) {
        self.name = name
        self.overrides = overrides
    }

    var isEmpty: Bool { overrides.isEmpty }

    func color(for partOfSpeech: PartOfSpeech) -> Color? {
        overrides[partOfSpeech.rawValue].flatMap(Color.init(hex:))
    }

    mutating func set(_ color: Color?, for partOfSpeech: PartOfSpeech) {
        if let color {
            overrides[partOfSpeech.rawValue] = color.hexString
        } else {
            overrides.removeValue(forKey: partOfSpeech.rawValue)
        }
    }

    // MARK: - Storage

    /// Decode from `ChildProfile.colorMapData`. A blank or unreadable value is
    /// an empty map, never an error: a board that will not draw because its
    /// palette failed to parse is far worse than one drawn in the defaults.
    static func decode(_ raw: String) -> TileColorMap {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let map = try? JSONDecoder().decode(TileColorMap.self, from: data)
        else { return TileColorMap() }
        return map
    }

    /// Encode for storage. An empty map stores as "" so the common case adds
    /// nothing and reads as "this child uses the defaults".
    var encoded: String {
        guard !isEmpty else { return "" }
        guard let data = try? JSONEncoder().encode(self),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }

    // MARK: - Presets

    /// Starting points, because a therapist should not have to invent a
    /// high-contrast palette from first principles — and a named preset is how
    /// the app says it knows what this is for.
    /// The colors offered inline when a therapist taps a swatch.
    ///
    /// A fixed grid rather than a color wheel, for two reasons. The practical
    /// one: `ColorPicker` hands off to a system picker, and on Mac that is a
    /// free-floating panel this binary cannot reach — Designed-for-iPad is
    /// UIKit-only, so there is no way to close it, place it, or stop it taking
    /// key window away from the sheet underneath. The Save button went dead.
    ///
    /// The better one: for the case this feature exists for, an arbitrary hue is
    /// not what is wanted. CVI work is about a small number of saturated,
    /// reliably-discriminated colors, and a wheel invites picking two that a
    /// child cannot tell apart. `Custom…` is still there for a therapist
    /// matching a specific hue they already know a child perceives.
    ///
    /// Saturated hues first, neutrals last — the order a therapist scans.
    static let palette: [String] = [
        "#E53935", "#F4511E", "#FDD835", "#7CB342",
        "#00897B", "#00ACC1", "#1E88E5", "#3949AB",
        "#8E24AA", "#D81B60", "#F06292", "#6D4C41",
        "#000000", "#616161", "#BDBDBD", "#FFFFFF",
    ]

    static let presets: [TileColorMap] = [highContrastCVI, warmLowDiscrimination]

    /// For a child who reliably perceives few hues.
    ///
    /// Collapses the eight Fitzgerald buckets toward a smaller set with wide
    /// luminance separation, keeping the distinctions that carry the most
    /// meaning on a core board — people, doing words, describing words — and
    /// letting the rest share. **Deliberately fewer real colors than
    /// Fitzgerald**, because for this child eight was never eight.
    ///
    /// A starting point for a therapist to adjust against the child in front of
    /// them, not a clinical recommendation.
    static let highContrastCVI = TileColorMap(name: "High Contrast (CVI)", overrides: [
        PartOfSpeech.pronoun.rawValue: "#FFD400",       // saturated yellow
        PartOfSpeech.verb.rawValue: "#00A040",          // saturated green
        PartOfSpeech.adjective.rawValue: "#0066CC",     // deep blue
        PartOfSpeech.noun.rawValue: "#FF6A00",          // saturated orange
        PartOfSpeech.question.rawValue: "#FFD400",      // folded into yellow
        PartOfSpeech.negation.rawValue: "#E00000",      // saturated red
        PartOfSpeech.social.rawValue: "#FF6A00",        // folded into orange
        PartOfSpeech.interjection.rawValue: "#FF6A00",
        PartOfSpeech.preposition.rawValue: "#FFFFFF",   // white, maximum contrast
        PartOfSpeech.determiner.rawValue: "#FFFFFF",
        PartOfSpeech.conjunction.rawValue: "#FFFFFF",
    ])

    /// Warm-biased, for a child who discriminates the red–yellow band better
    /// than the blue–green one. Keeps every Fitzgerald bucket distinct but
    /// moves the cool colors warmer and lighter so they separate by luminance
    /// as well as by hue.
    static let warmLowDiscrimination = TileColorMap(name: "Warm Bias", overrides: [
        PartOfSpeech.verb.rawValue: "#8FBF3F",
        PartOfSpeech.adjective.rawValue: "#7FA8D8",
        PartOfSpeech.conjunction.rawValue: "#C9B9A0",
        PartOfSpeech.preposition.rawValue: "#C9B9A0",
        PartOfSpeech.determiner.rawValue: "#C9B9A0",
    ])
}

// MARK: - Hex

extension Color {
    /// `#RRGGBB`. Nil for anything else, so a malformed stored value falls back
    /// to the default rather than drawing something arbitrary.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255)
    }

    /// `#RRGGBB`, for storage. Round-trips with `init(hex:)`.
    var hexString: String {
        let components = UIColor(self).cgColor.components ?? [0, 0, 0, 1]
        func channel(_ index: Int) -> Int {
            guard components.count > index else { return 0 }
            return Int((components[index] * 255).rounded())
        }
        // A grayscale CGColor has two components (white, alpha), not four.
        let (r, g, b) = components.count < 3
            ? (channel(0), channel(0), channel(0))
            : (channel(0), channel(1), channel(2))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}


// MARK: - The caregiver's library

/// Named palettes a caregiver has saved, for reuse across children.
///
/// Stored on the **system profile** — the caregiver's own record, auto-seeded on
/// every device with a stable shared id. A library belongs to the person
/// building palettes rather than to any one child, and the point is reuse: the
/// person who can build a good CVI palette is rarely the person holding the
/// device it needs to be on.
enum ColorMapLibrary {

    /// The caregiver's record. Nil before bootstrap has run.
    @MainActor
    static func owner(in context: ModelContext) -> ChildProfile? {
        let descriptor = FetchDescriptor<ChildProfile>(predicate: #Predicate { $0.isSystem })
        return (try? context.fetch(descriptor))?.first
    }

    @MainActor
    static func load(from context: ModelContext) -> [TileColorMap] {
        decode(owner(in: context)?.colorMapLibrary ?? "")
    }

    @MainActor
    static func save(_ maps: [TileColorMap], to context: ModelContext) {
        guard let owner = owner(in: context) else { return }
        owner.colorMapLibrary = encode(maps)
        try? context.save()
    }

    /// Add or replace by name, so saving twice under one name updates rather
    /// than accumulating near-duplicates a caregiver then has to tell apart.
    @MainActor
    static func store(_ map: TileColorMap, in context: ModelContext) {
        var maps = load(from: context)
        if let index = maps.firstIndex(where: { $0.name == map.name }) {
            maps[index] = map
        } else {
            maps.append(map)
        }
        save(maps, to: context)
    }

    @MainActor
    static func remove(named name: String, from context: ModelContext) {
        save(load(from: context).filter { $0.name != name }, to: context)
    }

    @MainActor
    static func rename(_ old: String, to new: String, in context: ModelContext) {
        var maps = load(from: context)
        guard let index = maps.firstIndex(where: { $0.name == old }) else { return }
        maps[index].name = new
        save(maps, to: context)
    }

    // MARK: - Coding

    /// Unreadable storage is an empty library, never an error — the same rule
    /// `TileColorMap.decode` follows, and for the same reason: a caregiver
    /// locked out of the editor because one saved palette failed to parse is
    /// worse than one who has to save it again.
    static func decode(_ raw: String) -> [TileColorMap] {
        guard !raw.isEmpty, let data = raw.data(using: .utf8),
              let maps = try? JSONDecoder().decode([TileColorMap].self, from: data)
        else { return [] }
        return maps
    }

    static func encode(_ maps: [TileColorMap]) -> String {
        guard !maps.isEmpty else { return "" }
        guard let data = try? JSONEncoder().encode(maps),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}
