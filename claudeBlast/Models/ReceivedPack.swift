// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ReceivedPack.swift
//  claudeBlast
//
//  A vocabulary pack that arrived from outside the app bundle.
//

import Foundation
import SwiftData

/// A pack someone shared with this family, stored so it keeps its identity.
///
/// The bundled packs are discovered by reading `packs.json` out of the app
/// binary (`PackCatalog.all`), which works precisely because they ship with the
/// build. A received pack has no bundle entry, so without a row here its words
/// would land in the vocabulary as loose tiles and the pack itself would vanish:
/// nothing would be named "Dinner Words" anywhere, and the recipient could never
/// build a page *from* it — which is the entire point of receiving one.
///
/// **Synced, not device-local.** A pack the family receives on the iPad should
/// be there on the iPhone, exactly as scenes already are. That makes this bound
/// by the additive-only rules in `SchemaVersions.swift` once V1 is promoted:
/// non-optional defaulted properties, no `@Attribute(.unique)`, dedup in code.
@Model
final class ReceivedPack {
    var id: String = UUID().uuidString
    /// Namespaced pack id, e.g. "greta.example/dinner-words". The dedup key —
    /// receiving the same pack twice updates this row rather than adding one.
    var packID: String = ""
    var slug: String = ""
    var displayName: String = ""
    /// The pack's own content version, distinct from the file format version.
    var packVersion: String = ""
    var authorName: String = ""
    var received: Date = Date.now

    // No `sourceScene` / `sourcePage` here, though the *file* carries both.
    //
    // They are the sender's own filing — "Home Board / dinner" — which the
    // import sheet shows once, read straight off the decoded file, and which
    // means little to the recipient afterwards. Storing them would have put two
    // never-read fields into the synced schema, and at S6 promotion that schema
    // becomes additive-only forever: a field can be added later but never
    // removed. Since adding is the reversible direction, anything without a
    // reader stays out.

    /// The word list as inline JSON, the same way `BlasterScene` stores its
    /// pages. Words are identity only (key, class, display name) — the *art*
    /// lands in `TileArtVariant` at import, where every other custom word's art
    /// lives, so a received pack word is indistinguishable from one the
    /// caregiver authored here.
    @Attribute(.externalStorage) var wordsData: Data = Data()

    var words: [VocabPackWord] {
        get { (try? JSONDecoder().decode([VocabPackWord].self, from: wordsData)) ?? [] }
        set { wordsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(packID: String, slug: String, displayName: String,
         packVersion: String = "", authorName: String = "",
         words: [VocabPackWord] = []) {
        self.packID = packID
        self.slug = slug
        self.displayName = displayName
        self.packVersion = packVersion
        self.authorName = authorName
        self.received = .now
        self.words = words
    }

    /// The bundled-pack view of this row, so received and bundled packs are the
    /// same type everywhere downstream — `CollectionSource.pack`, the tile
    /// picker, "New Scene from Collections".
    ///
    /// `icon` is empty: a bundled pack aliases a thematic cover shipped in the
    /// binary (`packcover_<slug>`), which a received pack has no equivalent of.
    /// `CollectionSource` already handles a coverless pack.
    var asVocabPack: VocabPack {
        VocabPack(id: packID, slug: slug, displayName: displayName,
                  version: packVersion, icon: "", words: words,
                  authorName: authorName.isEmpty ? nil : authorName)
    }
}

extension ReceivedPack {
    /// Insert or update the row for `packID`. Idempotent — re-receiving a pack
    /// refreshes it in place rather than accumulating duplicates, which matters
    /// because there is no `.unique` attribute to lean on.
    @discardableResult
    static func upsert(_ pack: ExportablePack, context: ModelContext) -> ReceivedPack {
        let packID = pack.id
        let descriptor = FetchDescriptor<ReceivedPack>(
            predicate: #Predicate { $0.packID == packID }
        )
        let words = pack.words.map {
            VocabPackWord(key: $0.key, wordClass: $0.wordClass, displayName: $0.displayName)
        }
        if let existing = try? context.fetch(descriptor).first {
            existing.slug = pack.slug
            existing.displayName = pack.displayName
            existing.packVersion = pack.packVersion
            existing.authorName = pack.authorName ?? existing.authorName
            existing.received = .now
            existing.words = words
            return existing
        }
        let row = ReceivedPack(packID: pack.id, slug: pack.slug,
                               displayName: pack.displayName,
                               packVersion: pack.packVersion,
                               authorName: pack.authorName ?? "",
                               words: words)
        context.insert(row)
        return row
    }

    /// Every received pack, newest first.
    static func all(in context: ModelContext) -> [ReceivedPack] {
        let descriptor = FetchDescriptor<ReceivedPack>(
            sortBy: [SortDescriptor(\.received, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
