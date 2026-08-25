// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BulkCacheGenerator.swift
//  claudeBlast
//

import SwiftData
import Foundation

/// Generates bulk cache traffic by creating random tile combinations and
/// exercising the SentenceCacheManager lookup/store path. Repeated combos
/// naturally produce cache hits, giving realistic hit/miss metrics.
///
/// ## Development tool, not a shipping path
///
/// Nothing a caregiver does reaches this class. It exists so the storage and
/// compaction work can be exercised against stores far larger than ordinary use
/// produces, and it is reachable only from the DEBUG-only load scripts in the
/// TileScript picker.
///
/// ## Memory: bounded by `spec.count`, not by the batch size
///
/// Rows are saved every `batchSize` iterations, but the `ModelContext` is never
/// pruned — SwiftData keeps every inserted object registered for the lifetime of
/// the run. So resident memory scales with the **total** row count, not with the
/// batch, and a save is not a release.
///
/// The practical limit that follows:
///
/// - ~10k utterances (~40k rows) — fine anywhere, including a device.
/// - ~25k utterances (~100k rows) — fine; this is what `load_compaction` uses.
/// - ~400k utterances (~1.6M rows) — **simulator only.** Plausibly 300–700 MB
///   resident on top of the store. A Mac absorbs it; an iPad is jetsammed
///   partway through and the run is lost with no usable result.
///
/// This is a deliberate limitation rather than an oversight. Recycling the
/// context per batch would cap memory flat and make any size safe on any target,
/// and is the fix if a load script ever needs to run on device. Until then the
/// constraint is cheaper than the code, and `load_natural.yaml` carries the same
/// warning at the point of use.
@MainActor
final class BulkCacheGenerator {
    private let modelContext: ModelContext

    /// Progress callback: (completed, duplicates, total)
    var onProgress: ((Int, Int, Int) -> Void)?

    /// Final stats after generation completes.
    private(set) var insertedCount: Int = 0
    private(set) var duplicateCount: Int = 0

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Generate `spec.count` lookups using random tile combinations.
    /// Each combo goes through SentenceCacheManager: miss → store, hit → count.
    /// MetricEvents are logged so cache stats reflect real usage.
    func generate(spec: BulkTileSpec) async {
        let descriptor = FetchDescriptor<TileModel>()
        guard let allTiles = try? modelContext.fetch(descriptor), !allTiles.isEmpty else { return }

        var rng = SeededRNG(seed: spec.seed &+ 1)

        let pool: [TileModel]
        switch spec.source {
        case .mostCommon:
            pool = mostCommonTiles(allTiles, using: &rng)
        case .random, .allCombos:
            pool = allTiles
        }

        let cacheManager = SentenceCacheManager(modelContext: modelContext)
        let stage = ChildProfileResolver.fallbackStage

        insertedCount = 0
        duplicateCount = 0
        let batchSize = 1000
        var batchCount = 0

        // Seeded so a run replays identically, and backdated so the rows can
        // land in months the compactor is willing to touch. With the defaults
        // (`spanDays == 0`) every date is now, exactly as before.
        var clock = SimulatedClock(spanDays: spec.spanDays, count: spec.count, seed: spec.seed)

        for i in 0..<spec.count {
            guard !Task.isCancelled else { break }

            let at = clock.next()
            let length = Int.random(in: spec.minLength...spec.maxLength, using: &rng)
            let combo = randomCombo(from: pool, length: length, using: &rng)
            let selections = combo.map { TileSelection(from: $0) }
            let key = SentenceCacheManager.cacheKey(for: selections, stage: stage)

            // One `tile`/`.selected` row per tile, exactly as SentenceEngine:252
            // writes on every tap. Without these the synthetic mix is nothing
            // like production: tile rows are ~4 of every 5 metric rows written,
            // and they are the ones with LOW key cardinality, so a fold measured
            // without them would flatter itself enormously.
            for selection in selections {
                cacheManager.logEvent(subjectType: "tile", subjectKey: selection.key,
                                      eventType: .selected, at: at)
            }

            // Metrics-only skips the cache entirely — including the lookup, since
            // with nothing ever stored every lookup would miss and the run would
            // report a 0% hit rate that says nothing about the cache.
            if spec.metricsOnly {
                cacheManager.logEvent(subjectType: "sentence", subjectKey: key,
                                      eventType: .used, at: at)
                insertedCount += 1
            }
            // Exercise the cache: lookup first, store on miss. Synthetic traffic
            // has no child profile, so all combos share the fallback grade — keeps
            // the combinatorial space small enough for combos to collide naturally.
            else if cacheManager.lookup(tiles: selections, stage: stage, at: at) != nil {
                // Cache hit — lookup already incremented hitCount
                cacheManager.logEvent(subjectType: "cache", subjectKey: key,
                                      eventType: .hit, at: at)
                duplicateCount += 1
            } else {
                // Cache miss — generate mock sentence and store
                let sentence = buildMockSentence(from: combo)
                cacheManager.store(tiles: selections, stage: stage, sentence: sentence, at: at)
                cacheManager.logEvent(subjectType: "sentence", subjectKey: key,
                                      eventType: .used, at: at)
                insertedCount += 1
            }

            batchCount += 1
            if batchCount >= batchSize {
                try? modelContext.save()
                onProgress?(i + 1, duplicateCount, spec.count)
                batchCount = 0
                await Task.yield()
            }
        }

        // Final save
        if batchCount > 0 {
            try? modelContext.save()
        }
        onProgress?(spec.count, duplicateCount, spec.count)
    }

    // MARK: - Helpers

    /// Return only high-frequency tiles for "most-common" source.
    /// A small pool (~30-50 tiles) ensures combos repeat naturally,
    /// producing realistic cache hit rates.
    private func mostCommonTiles(_ tiles: [TileModel],
                                 using rng: inout SeededRNG) -> [TileModel] {
        let highFrequency: Set<String> = ["actions", "people", "food", "social", "describe"]
        let pool = tiles.filter { highFrequency.contains($0.wordClass) }
        // Cap at ~40 tiles so the combinatorial space stays small
        return Array(pool.shuffled(using: &rng).prefix(40))
    }

    private func randomCombo(from tiles: [TileModel], length: Int,
                             using rng: inout SeededRNG) -> [TileModel] {
        var selected: [TileModel] = []
        var usedKeys: Set<String> = []
        var retries = length * 3
        while selected.count < length && retries > 0 {
            retries -= 1
            guard let tile = tiles.randomElement(using: &rng),
                  usedKeys.insert(tile.key).inserted else {
                continue
            }
            selected.append(tile)
        }
        return selected
    }

    private func buildMockSentence(from tiles: [TileModel]) -> String {
        let values = tiles.map(\.value)
        switch values.count {
        case 1: return "I want \(values[0])."
        case 2: return "I want \(values[0]) and \(values[1])."
        default:
            let allButLast = values.dropLast().joined(separator: ", ")
            return "I want \(allButLast), and \(values.last!)."
        }
    }
}
