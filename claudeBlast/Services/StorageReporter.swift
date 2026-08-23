// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  StorageReporter.swift
//  claudeBlast
//
//  What this install actually occupies on disk, measured rather than estimated.
//

import Foundation
import SQLite3
import SwiftData
import os

/// One measured component of the app's footprint.
struct StorageComponent: Identifiable, Sendable {
    let id: String
    let label: String
    let bytes: Int64
    /// True when this data is mirrored to the family's CloudKit database, so it
    /// costs the user iCloud quota as well as local disk.
    let isSynced: Bool
}

/// Everything this install occupies, split by what a caregiver would recognise.
///
/// ## Measured, never estimated
///
/// Every number here comes from `FileManager` reading real files. That matters
/// most for `deviceLocalBytes`, which is what `MetricCompactor` budgets against:
/// a per-row size estimate would put the compactor's trigger at the mercy of an
/// assumption about SwiftData's on-disk layout, and the whole point of the budget
/// is that it reacts to what is actually there.
struct StorageReport: Sendable {
    /// The `DeviceLocal` store — `DeviceProfile`, `MetricEvent`, `APIUsageEvent`.
    let deviceLocalBytes: Int64
    /// The synced store's own file, with generated-art blob bytes taken out so
    /// they are reported as art rather than as words.
    let syncedStoreBytes: Int64
    /// Generated art and caregiver photos, wherever SwiftData decided to put
    /// them — see `artBytes(forStoreAt:)`, which is why this is not simply a
    /// directory size.
    let generatedArtBytes: Int64
    /// Tile art shipped in the binary, **wherever it happens to live**.
    let bundledArtBytes: Int64
    /// The rest of the shipped app — binary, frameworks, non-art resources.
    let appBytes: Int64

    /// What this app occupies on this device.
    var onDeviceBytes: Int64 {
        deviceLocalBytes + syncedStoreBytes + generatedArtBytes + bundledArtBytes + appBytes
    }

    /// What is mirrored to iCloud — the family's quota, not just this disk.
    /// Bundled art ships in the binary and the device-local store never leaves,
    /// so neither counts.
    var syncedBytes: Int64 { syncedStoreBytes + generatedArtBytes }

    var components: [StorageComponent] {
        [
            StorageComponent(id: "app", label: "App",
                             bytes: appBytes, isSynced: false),
            StorageComponent(id: "tileart", label: "Tile art",
                             bytes: bundledArtBytes, isSynced: false),
            StorageComponent(id: "art", label: "Generated art & photos",
                             bytes: generatedArtBytes, isSynced: true),
            StorageComponent(id: "synced", label: "Words, boards & sentences",
                             bytes: syncedStoreBytes, isSynced: true),
            StorageComponent(id: "local", label: "Usage history",
                             bytes: deviceLocalBytes, isSynced: false),
        ]
    }
}

enum StorageReporter {
    private static let log = Logger(subsystem: "app.blasterai", category: "storage")

    /// Name of the device-local configuration, as passed in `AppSettings`.
    /// Matching on the name rather than assuming an ordering keeps this correct
    /// if the configuration array is ever reordered.
    static let deviceLocalConfigurationName = "DeviceLocal"

    /// Measure the whole install.
    ///
    /// Not cheap — it stats a directory tree — so call it when the storage panel
    /// appears or once per launch for the compaction check, never per render.
    static func report(container: ModelContainer,
                       bundle: Bundle = .main) -> StorageReport {
        let configurations = container.configurations
        let local = configurations.first { $0.name == deviceLocalConfigurationName }
        // Anything that is not the device-local store is the synced one. Falling
        // back to "the other configuration" rather than a second name match keeps
        // this working with the app's local-only fallback container, where the
        // synced config takes SwiftData's default name.
        let synced = configurations.first { $0.name != deviceLocalConfigurationName }

        let shipped = bundleBreakdown(bundle: bundle)
        let art = synced.map { artBytes(forStoreAt: $0.url) } ?? (inline: 0, external: 0)
        return StorageReport(
            deviceLocalBytes: local.map { storeBytes(at: $0.url) } ?? 0,
            // Inline art is physically part of the store file, so it has to come
            // back out of that number or the two lines double-count and the
            // total overshoots what Settings reports.
            syncedStoreBytes: synced.map { max(0, storeBytes(at: $0.url) - art.inline) } ?? 0,
            generatedArtBytes: art.inline + art.external,
            bundledArtBytes: shipped.tileArt,
            appBytes: shipped.app)
    }

    /// Just the number the compactor budgets against. Skips the directory walks
    /// the full report does, so the "are we over budget" guard stays cheap enough
    /// to run on every launch.
    static func deviceLocalBytes(container: ModelContainer) -> Int64 {
        guard let local = container.configurations
            .first(where: { $0.name == deviceLocalConfigurationName }) else { return 0 }
        return storeBytes(at: local.url)
    }

    // MARK: - Measuring

    /// A SQLite store plus its write-ahead log and shared-memory sidecars.
    ///
    /// The `-wal` file is the reason this is not a single `fileSize` call: between
    /// checkpoints it holds committed data that has not yet landed in the main
    /// file, and after a burst of metric writes it can be a large fraction of the
    /// total. Measuring only the `.store` file would under-report exactly when
    /// the compactor most needs an accurate number.
    static func storeBytes(at url: URL) -> Int64 {
        let base = url.path
        return [base, base + "-wal", base + "-shm"]
            .reduce(0) { $0 + fileBytes(atPath: $1) }
    }

    /// Every byte of generated art and caregiver photos in this store, split by
    /// where SwiftData happened to put it.
    ///
    /// ## `.externalStorage` is a threshold, not a promise
    ///
    /// `TileArtVariant.imageData` is `@Attribute(.externalStorage)`, and the
    /// obvious reading — "art is files beside the store" — is wrong. Core Data
    /// spills a blob to a file only above a size threshold of roughly a megabyte;
    /// below it the bytes stay in the row. Our tiles are ~512px HEIC, tens of KB,
    /// so **most generated art lives inside the store file**. On a real device
    /// with 55 variants, 44 were inline and 11 had spilled.
    ///
    /// Counting only the directory therefore reported art as near-zero while its
    /// bytes sat inside the "Words, boards & sentences" line — art filed as words.
    ///
    /// So `inline` is read from the rows and `external` from the directory, and
    /// the caller subtracts `inline` from the store's file size.
    static func artBytes(forStoreAt url: URL) -> (inline: Int64, external: Int64) {
        (inline: inlineBlobBytes(forStoreAt: url),
         external: directoryBytes(at: supportDirectory(forStoreAt: url)))
    }

    /// The sidecar directory holding spilled blobs.
    ///
    /// The name is Core Data's: a leading dot, the store's name **without its
    /// extension**, then `_SUPPORT` — so `default.store` is served by
    /// `.default_SUPPORT`, not `default.store_SUPPORT`. Getting either detail
    /// wrong just yields a path that never exists, which reads as "no art" rather
    /// than as an error.
    static func supportDirectory(forStoreAt url: URL) -> URL {
        let stem = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent(".\(stem)_SUPPORT")
    }

    /// Blob bytes held directly in rows, summed by SQLite so the images are never
    /// loaded. A `ModelContext` fetch would materialise every variant — a fully
    /// generated library is thousands of them — to measure something the database
    /// can add up without reading.
    ///
    /// Table and column names are Core Data's `Z`-prefixed convention. If that
    /// ever changes the statement simply fails to prepare and this returns zero,
    /// which under-reports art rather than crashing a stats screen.
    private static func inlineBlobBytes(forStoreAt url: URL) -> Int64 {
        var db: OpaquePointer?
        // Read-only: this runs while SwiftData holds the same store open, and
        // WAL mode permits concurrent readers.
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return 0
        }
        defer { sqlite3_close(db) }

        // Rows that did spill hold a short filename here instead of the image, so
        // they contribute a few dozen bytes — which is what they genuinely
        // occupy in the store.
        let sql = """
            SELECT (SELECT COALESCE(SUM(LENGTH(ZIMAGEDATA)), 0) FROM ZTILEARTVARIANT)
                 + (SELECT COALESCE(SUM(LENGTH(ZUSERIMAGEDATA)), 0) FROM ZTILEMODEL)
            """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            log.debug("inline blob query did not prepare; reporting 0")
            return 0
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return max(0, sqlite3_column_int64(statement, 0))
    }

    /// Split the shipped bundle into tile art and everything else.
    ///
    /// ## Classified by name, not by location
    ///
    /// **Tile art is tile art wherever it sits.** `TileImageSets/` is a
    /// `PBXFileSystemSynchronizedRootGroup`, and how its contents land in the
    /// built product is the build system's business — today it flattens all 2,743
    /// files into the `.app` root, with no folder to point at. An earlier version
    /// resolved one known file and measured its parent directory, which happened
    /// to give the right total only because of that flattening: preserve the
    /// folder and it would report tile art alone; flatten it and it reports the
    /// whole app. Same code, two different meanings, depending on a build detail.
    ///
    /// So a file is tile art when its name carries a known set's bundle prefix,
    /// full stop. Prefixes come from `ImageSetCatalog`, so a new or installed set
    /// is counted without touching this, and pack covers (`cls_packcover_*`) fall
    /// in naturally.
    ///
    /// `app` is then everything else that ships — binary, frameworks, non-art
    /// resources — by subtraction, so the two always sum to the real bundle.
    static func bundleBreakdown(bundle: Bundle = .main) -> (tileArt: Int64, app: Int64) {
        // `_` included so `cls_` cannot swallow `clsm_` / `clsmd_`.
        let prefixes = ImageSetCatalog.all.map { $0.bundlePrefix + "_" }
        var tileArt: Int64 = 0
        var total: Int64 = 0

        forEachFile(in: bundle.bundleURL) { name, bytes in
            total += bytes
            if prefixes.contains(where: name.hasPrefix) { tileArt += bytes }
        }
        return (tileArt, max(0, total - tileArt))
    }

    private static func fileBytes(atPath path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Recursive size of a directory, skipping anything unreadable.
    private static func directoryBytes(at url: URL) -> Int64 {
        var total: Int64 = 0
        forEachFile(in: url) { _, bytes in total += bytes }
        return total
    }

    /// Visit every regular file under `url` with its name and size on disk.
    ///
    /// Allocated size where available, not logical size: it is what the disk
    /// actually gives up and what iOS Settings shows. The difference is not
    /// academic here — 2,743 tile files averaging ~14 KB against a 4 KB block
    /// round up to roughly 15% more than their content.
    ///
    /// `.skipsPackageDescendants` is deliberately NOT set: the app bundle is
    /// itself a package, and so are nested ones, so skipping descendants would
    /// walk into nothing.
    private static func forEachFile(in url: URL, body: (String, Int64) -> Void) {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return }

        guard let walker = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else { return }

        for case let child as URL in walker {
            let values = try? child.resourceValues(
                forKeys: [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileSizeKey])
            guard values?.isRegularFile == true else { continue }
            body(child.lastPathComponent,
                 Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0))
        }
    }

    /// Human-readable bytes, using the same formatter iOS Settings does so the
    /// panel's numbers can be compared with Settings → iPhone Storage directly.
    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
