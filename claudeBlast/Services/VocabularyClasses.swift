// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  VocabularyClasses.swift
//  claudeBlast
//
//  Canonical catalog of word classes — the single source of truth for what
//  classes exist, the part of speech each falls back to, and whether a
//  caregiver may pick one when creating a word. Deriving "what classes exist"
//  from the data is fragile (a typo would become a real, selectable class);
//  this catalog governs the creator picker and the derivation instead.
//
//  NOTE: a tile's `wordClass` string is injected verbatim into the
//  sentence-generation prompt (SentencePromptBuilder) as a hint — e.g.
//  "pony (animal)" vs "pony (food)". So class names are plain semantic words,
//  and keeping a concept in ONE class (e.g. all emotions in `feeling`) matters
//  for generation quality, not just tidiness.
//

import SwiftUI
import Observation

struct VocabularyClass: Identifiable, Hashable {
    /// The `wordClass` string stored on tiles and sent to the AI as a hint.
    let name: String
    /// Part of speech a word of this class gets when nothing better is known —
    /// the third layer of `TileModel.resolvedPartOfSpeech`, below a stored
    /// answer and the bundled table. Nil for structural chrome, which has no
    /// part of speech and takes no word color.
    ///
    /// This replaced a per-class `color`. Color now comes from part of speech,
    /// so a color here would be a second source competing with the first.
    let defaultPartOfSpeech: PartOfSpeech?
    /// Whether the caregiver "New Word" creator offers this class. Structural /
    /// function classes (core, navigation, question) are not caregiver content.
    let isCaregiverSelectable: Bool

    var id: String { name }
    /// Human label for pickers (e.g. "feeling" → "Feeling").
    var label: String { name.capitalized }
}

enum VocabularyClasses {
    /// Canonical word classes in caregiver-facing display order.
    ///
    /// The second column used to be a color. It is now the part of speech a
    /// word of this class falls back to when neither a stored answer nor the
    /// bundled table knows — the derivation layer, measured at **92.3% color
    /// accuracy** across the caregiver-selectable classes.
    ///
    /// Every miss in that measurement is a *bundled* word, which has an exact
    /// table entry and never reaches here: prepositions filed as `describe`,
    /// pronouns filed as `people`. The population this actually serves is
    /// caregiver-added words, which are overwhelmingly concrete nouns a family
    /// invented — "grandma", "Bluey", "trampoline" — so its real accuracy is
    /// well above the measured figure.
    static let all: [VocabularyClass] = [
        VocabularyClass(name: "people", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "animal", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "actions", defaultPartOfSpeech: .verb, isCaregiverSelectable: true),
        VocabularyClass(name: "describe", defaultPartOfSpeech: .adjective, isCaregiverSelectable: true),
        VocabularyClass(name: "feeling", defaultPartOfSpeech: .adjective, isCaregiverSelectable: true),
        VocabularyClass(name: "social", defaultPartOfSpeech: .social, isCaregiverSelectable: true),
        // `food` absorbs the former meals/fruit/veggie/snacks buckets (2026-08).
        // Those sub-splits were arbitrary from the LLM's view (the class string is
        // injected into the sentence prompt) and only ever served scene-builder
        // collection filtering — the wrong customer. The word itself ("carrot",
        // "cookie") already tells the model what it is; the sub-class did not.
        VocabularyClass(name: "food", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "plant", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "drinks", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "places", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "weather", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "colors", defaultPartOfSpeech: .adjective, isCaregiverSelectable: true),
        VocabularyClass(name: "shape", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "body", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "health", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "toy", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "games", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "sports", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "play", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        VocabularyClass(name: "art", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        // Generic concrete objects / tools / equipment / vehicles that don't fit a
        // more specific class (handcuffs, badge, hose, ladder, tractor).
        VocabularyClass(name: "object", defaultPartOfSpeech: .noun, isCaregiverSelectable: true),
        // Letters and numbers. Drawn rather than generated (`GlyphTile`), and
        // caregiver-selectable so a family can add a letter we did not ship —
        // an accented character, a numeral past ten — and have it render.
        //
        // A letter has no part of speech: it is not a word, and on a published
        // letter board it is neutral. A number is a `determiner` — "three
        // cookies" quantifies, which is what the Fitzgerald key colors it for.
        VocabularyClass(name: "letter", defaultPartOfSpeech: nil, isCaregiverSelectable: true),
        VocabularyClass(name: "number", defaultPartOfSpeech: .determiner, isCaregiverSelectable: true),
        // Structural / function classes — not caregiver-creatable content.
        //
        // `core` is the one genuinely mixed class: its bundled words split across
        // prepositions, pronouns and determiners, with preposition the modal
        // answer at 50%. Every one of them is in the table, so this fallback is
        // very nearly unreachable — it exists for a `core` word that arrived by
        // scene import.
        VocabularyClass(name: "core", defaultPartOfSpeech: .preposition, isCaregiverSelectable: false),
        VocabularyClass(name: "navigation", defaultPartOfSpeech: nil, isCaregiverSelectable: false),
        VocabularyClass(name: "question", defaultPartOfSpeech: .question, isCaregiverSelectable: false),
        // Auto-minted per page: a silent link tile (key `page_<pageKey>`) that
        // navigates to a named page collection. Reusable on any board. Not
        // caregiver-creatable — pages mint these themselves.
        VocabularyClass(name: "page_link", defaultPartOfSpeech: nil, isCaregiverSelectable: false),
    ]

    /// Shared, tightened rule for how the AI should pick a `wordClass` for a NEW
    /// word. Centralized here so the scene / page / tile / refiner generators all
    /// speak with one voice and can't drift. `object` is deliberately framed as a
    /// LAST resort: it was over-used as a dumping ground (whole packs of animals
    /// and plants leaked into it), which pollutes the class hint the LLM sees.
    static let classSelectionGuidance =
        "Choose the wordClass by what the thing IS. \"places\" is ONLY a location the child goes to " +
        "(park, barn, store) — never a portable thing. Any living creature — pet, farm animal, sea " +
        "creature, bug, or dinosaur — is \"animal\". A growing thing — tree, flower, seaweed, hay — is " +
        "\"plant\". Anything edible is \"food\"; a beverage is \"drinks\". A person or role is \"people\". " +
        "Use \"object\" ONLY as a last resort, for a man-made tool, vehicle, instrument, or piece of " +
        "equipment (ladder, tractor, car, hose) that fits no more specific class — always prefer " +
        "animal / plant / food / places / people first."

    private static let byName: [String: VocabularyClass] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })

    static func known(_ name: String) -> VocabularyClass? { byName[name] }

    /// Classes offered in the caregiver "New Word" creator, in display order.
    static var caregiverSelectable: [VocabularyClass] { all.filter(\.isCaregiverSelectable) }
}

/// Single source of truth for tile color.
///
/// ## Color means part of speech, not category
///
/// It used to mean semantic category — food red, animal brown, places blue — a
/// palette this project invented (`VocabularyClasses` said so outright: "Colors
/// mirror the legacy switch"). No clinical practice uses that axis, so a child
/// moving between this board and their school board got no transfer at all.
///
/// It now means **part of speech**, in the Modified Fitzgerald Key that
/// TouchChat, Snap Core First, LAMP, PODD and CoughDrop all speak and that SLPs
/// teach against: yellow pronouns, green verbs, blue describing words, orange
/// nouns, purple questions, red for no, pink social, neutral function words.
///
/// The cost, accepted deliberately: ~20 colors collapse to 8, food stops being
/// red, and color no longer separates food from places. That is the trade
/// Fitzgerald makes on purpose — fewer colors, but ones a therapist teaches and
/// a child carries elsewhere.
///
/// ## Why a tile, not a wordClass string
///
/// Resolution needs the tile: a stored correction lives on it, and the
/// derivation needs its `wordClass`. See `TileModel.resolvedPartOfSpeech`.
enum TileColorResolver {

    /// Structural chrome — home, page links, next/previous page. Not a word, so
    /// no word color: it reads as furniture, which is what it is.
    static let chrome = Color.gray

    /// A tile that takes the board somewhere.
    ///
    /// **Deep royal blue, because Fitzgerald already owns blue for describing
    /// words.** Navigation used plain `.blue`, which was fine while adjectives
    /// were a hairline tint — and stopped being fine the moment a card was
    /// filled: an adjective sat in a row of page links and could not be told
    /// apart from them. Descriptors keep the lighter, more saturated blue the
    /// key specifies (a therapist teaches *that* one); navigation moves down and
    /// darker, which is also where this app's old `navigation` indigo sat.
    static let navigation = Color(red: 0.16, green: 0.26, blue: 0.68)

    /// Function words (prepositions, determiners, conjunctions) are *white* on a
    /// published Fitzgerald board, which works because the card sits against a
    /// colored surround. Ours sit on the page, so white would be invisible; they
    /// get a near-neutral that still draws an edge.
    static let functionWord = Color(red: 0.62, green: 0.64, blue: 0.67)

    /// The active child's palette, when they have one.
    ///
    /// Held in memory rather than fetched per call: color is asked for once per
    /// tile per render, on a board that can hold a hundred, so this must not
    /// touch the store. `refreshActiveMap(from:)` reloads it, the same shape as
    /// `PartOfSpeechIndex.stored`.
    ///
    /// **Empty is the overwhelmingly common case** and costs one dictionary
    /// lookup that misses.
    static var activeMap: TileColorMap { Palette.shared.map }

    /// Load the active child's palette. Call at launch and whenever the active
    /// child or their map changes.
    @MainActor
    static func refreshActiveMap(from profile: ChildProfile?) {
        Palette.shared.map = TileColorMap.decode(profile?.colorMapData ?? "")
    }

    /// Why the palette lives on an `@Observable` box rather than in a `static
    /// var`.
    ///
    /// It was a plain static, and changing a color did not redraw anything — the
    /// board only picked it up on the next navigation, because something else
    /// happened to force a re-render. SwiftUI cannot invalidate a view over a
    /// value it was never told the view depends on, and a static read inside a
    /// body is invisible to it.
    ///
    /// Observation fixes that without touching a single call site: every
    /// `TileColorResolver.color(for:)` evaluated during a view body reads
    /// `Palette.shared.map` through this box, which registers the dependency —
    /// so assigning a new palette invalidates exactly the views that drew with
    /// the old one.
    @Observable
    final class Palette {
        @MainActor static let shared = Palette()
        var map = TileColorMap()
        private init() {}
    }

    /// The Modified Fitzgerald Key, unless this child sees differently.
    static func color(for partOfSpeech: PartOfSpeech?) -> Color {
        guard let partOfSpeech else { return chrome }
        // The child's own map wins. Sparse, so anything they did not change
        // falls through to the default below — which means the default palette
        // can still be improved without rewriting anyone's stored overrides.
        if let override = activeMap.color(for: partOfSpeech) { return override }
        return fitzgerald(partOfSpeech)
    }

    /// The unmodified key, ignoring any child's overrides.
    ///
    /// The editor needs this: a color well showing the *current* color would
    /// echo the override back, and a therapist could then neither see what they
    /// were changing nor what resetting would restore — the same trap
    /// "Automatic" fell into in the word-type picker.
    static func fitzgerald(_ partOfSpeech: PartOfSpeech) -> Color {
        switch partOfSpeech {
        case .pronoun:     return Color(red: 0.98, green: 0.80, blue: 0.20)   // yellow
        case .verb:        return Color(red: 0.30, green: 0.72, blue: 0.35)   // green
        case .adjective:   return Color(red: 0.36, green: 0.70, blue: 0.96)   // light blue
        case .noun:        return Color(red: 0.96, green: 0.60, blue: 0.16)   // orange
        case .question:    return Color(red: 0.62, green: 0.40, blue: 0.82)   // purple
        case .negation:    return Color(red: 0.90, green: 0.29, blue: 0.27)   // red
        case .social,
             .interjection: return Color(red: 0.95, green: 0.55, blue: 0.72)  // pink
        case .preposition,
             .determiner,
             .conjunction: return functionWord
        }
    }

    /// Color for a tile — the entry point every surface should use.
    ///
    /// Optional because several surfaces render a placement whose word may not
    /// resolve (a page built from a scene whose vocabulary did not travel). A
    /// missing tile is chrome: no word, no word color.
    static func color(for tile: TileModel?) -> Color {
        guard let tile else { return chrome }
        return color(for: tile.resolvedPartOfSpeech)
    }

    /// Color for a tray chip. The selection carries the part of speech it was
    /// created with, so a chip always matches the tile it came from.
    static func color(for selection: TileSelection) -> Color {
        color(for: selection.partOfSpeech)
    }

    /// Degraded path for the few surfaces that hold a `wordClass` string and no
    /// tile — a scene-import preview, a class swatch in a picker.
    ///
    /// **Prefer `color(for tile:)` wherever a tile exists.** Without a key there
    /// is no stored answer and no table lookup, so this can only ask the
    /// derivation, which is the weakest of the four layers. It is right for a
    /// swatch that stands for a whole class; it is wrong for a word.
    static func color(forWordClass wordClass: String) -> Color {
        color(for: VocabularyClasses.known(wordClass)?.defaultPartOfSpeech)
    }
}
