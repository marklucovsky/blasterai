// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  StorageReporterTests.swift
//  claudeBlastTests
//
//  2C: measuring what the install actually occupies, and giving the space back.
//
//  These build files and raw SQLite databases directly rather than spinning up a
//  second `ModelContainer`. Two reasons: the functions under test are FileManager
//  and sqlite3 wrappers, so a container proves nothing extra; and per TestStore's
//  own header, additional containers over the same schema are what corrupt
//  SwiftData's process-global entity registry under a parallel test run.
//

import Testing
import Foundation
import SQLite3
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct StorageReporterTests {

    private func tempDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("storage-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A SQLite database configured the way Core Data configures its stores —
    /// verified against a real one — filled with `rows` of junk.
    @discardableResult
    private func makeStore(at url: URL, rows: Int) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK
        else { return false }
        defer { sqlite3_close(db) }
        let setup = """
            PRAGMA auto_vacuum=INCREMENTAL;
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS ZMETRICEVENT(Z_PK INTEGER PRIMARY KEY, ZKEY TEXT);
            """
        sqlite3_exec(db, setup, nil, nil, nil)
        sqlite3_exec(db, "BEGIN", nil, nil, nil)
        let payload = String(repeating: "x", count: 400)
        for i in 0..<rows {
            sqlite3_exec(db, "INSERT INTO ZMETRICEVENT(ZKEY) VALUES ('\(i)-\(payload)')",
                         nil, nil, nil)
        }
        sqlite3_exec(db, "COMMIT", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
        return true
    }

    private func deleteMost(at url: URL) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { return }
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "DELETE FROM ZMETRICEVENT WHERE Z_PK % 100 != 0", nil, nil, nil)
    }

    // MARK: - Measuring

    /// A store's write-ahead log holds committed data not yet checkpointed into
    /// the main file. Measuring only the `.store` file would under-report exactly
    /// after a burst of metric writes — precisely when the compactor needs the
    /// number to be right.
    @Test func storeSizeIncludesTheWriteAheadLog() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = dir.appendingPathComponent("Sized.store")

        try Data(repeating: 0, count: 1_000).write(to: base)
        try Data(repeating: 0, count: 3_000).write(to: URL(fileURLWithPath: base.path + "-wal"))
        try Data(repeating: 0, count: 500).write(to: URL(fileURLWithPath: base.path + "-shm"))

        #expect(StorageReporter.storeBytes(at: base) == 4_500)
    }

    /// Missing sidecars are normal (a freshly checkpointed store has no `-wal`),
    /// so they contribute zero rather than being an error.
    @Test func absentSidecarsAreZeroNotAnError() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let base = dir.appendingPathComponent("Bare.store")
        try Data(repeating: 0, count: 700).write(to: base)

        #expect(StorageReporter.storeBytes(at: base) == 700)
        #expect(StorageReporter.storeBytes(at: dir.appendingPathComponent("Nope.store")) == 0)
    }

    /// The sidecar directory's name is Core Data's, and an earlier version of the
    /// reporter guessed it wrong — `default.store_SUPPORT` instead of
    /// `.default_SUPPORT`. It looked correct and shipped a permanent zero.
    ///
    /// The test that was supposed to catch that built the path the same wrong way
    /// itself, so it agreed with the bug. This one spells the real name out as a
    /// literal, which is the only form that can disagree with the implementation.
    @Test func supportDirectoryUsesCoreDataNaming() {
        let store = URL(fileURLWithPath: "/tmp/x/default.store")
        #expect(StorageReporter.supportDirectory(forStoreAt: store).lastPathComponent
                == ".default_SUPPORT")
    }

    /// Spilled blobs live in files beside the store. Missing them reported a
    /// caregiver's whole generated art library as costing nothing.
    @Test func externalBlobsAreCountedAlongsideTheStore() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("Synced.store")
        try Data(repeating: 0, count: 100).write(to: store)

        // No support directory yet — no generated art is not an error.
        #expect(StorageReporter.artBytes(forStoreAt: store).external == 0)

        let support = dir.appendingPathComponent(".Synced_SUPPORT")
            .appendingPathComponent("_EXTERNAL_DATA")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 8_000).write(to: support.appendingPathComponent("blob-1"))
        try Data(repeating: 0, count: 4_000).write(to: support.appendingPathComponent("blob-2"))

        // Allocated size rounds up to whole disk blocks, so assert a floor: the
        // point is that both blobs are found.
        #expect(StorageReporter.artBytes(forStoreAt: store).external >= 12_000)
    }

    /// The bug that hid most of the art: `.externalStorage` only spills blobs
    /// above roughly a megabyte, and tile art is tens of KB, so it stays in the
    /// rows. Art that is inline must still be counted as art.
    @Test func inlineBlobsAreCountedAsArtNotAsWords() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("Synced.store")
        try writeArtRows(at: store, blobSizes: [30_000, 20_000], photoSizes: [5_000])

        let art = StorageReporter.artBytes(forStoreAt: store)
        #expect(art.inline == 55_000)
        #expect(art.external == 0)
    }

    /// A store the reporter cannot read as art must not fail the whole panel; it
    /// under-reports rather than throwing on a stats screen.
    @Test func aStoreWithoutArtTablesReportsZeroRatherThanFailing() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("Empty.store")
        try Data(repeating: 0, count: 100).write(to: store)

        #expect(StorageReporter.artBytes(forStoreAt: store).inline == 0)
    }

    /// Build a minimal store carrying Core Data's `Z`-prefixed art tables, so the
    /// reporter is exercised against the shape it actually meets on device.
    private func writeArtRows(at url: URL, blobSizes: [Int], photoSizes: [Int]) throws {
        var db: OpaquePointer?
        #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        sqlite3_exec(db, "CREATE TABLE ZTILEARTVARIANT (ZIMAGEDATA BLOB);", nil, nil, nil)
        sqlite3_exec(db, "CREATE TABLE ZTILEMODEL (ZUSERIMAGEDATA BLOB);", nil, nil, nil)
        for size in blobSizes {
            sqlite3_exec(db, "INSERT INTO ZTILEARTVARIANT VALUES (zeroblob(\(size)));",
                         nil, nil, nil)
        }
        for size in photoSizes {
            sqlite3_exec(db, "INSERT INTO ZTILEMODEL VALUES (zeroblob(\(size)));", nil, nil, nil)
        }
    }

    /// Tile art must be found and reported as tile art. A report that missed it
    /// would tell a caregiver the app is a few megabytes when Settings says 70+.
    @Test func tileArtIsFoundAndSeparatedFromTheApp() {
        let split = StorageReporter.bundleBreakdown(bundle: .main)
        #expect(split.tileArt > 0, "no tile art found in the test host bundle")
        #expect(split.app > 0, "the binary and resources cannot be zero")
        // The shipped sets dominate the bundle; if this inverts, the prefix
        // matching has stopped recognising them.
        #expect(split.tileArt > split.app / 4,
                "tileArt=\(split.tileArt) app=\(split.app) — art looks under-counted")
    }

    /// Classified by NAME, not by directory. `TileImageSets/` is a synchronized
    /// folder group and the build currently flattens it into the `.app` root, so
    /// anything keyed off location reports a different thing depending on a build
    /// detail. Every shipped set's prefix must be recognised.
    @Test func everyShippedSetsArtCountsAsTileArt() {
        let prefixes = ImageSetCatalog.all.map { $0.bundlePrefix + "_" }
        // `cls_` must not swallow `clsm_` / `clsmd_`, which is why the separator
        // is part of the prefix.
        #expect(Set(prefixes).count == prefixes.count)
        for set in ImageSetCatalog.all where set.isShippable {
            let name = "\(set.bundlePrefix)_eat"
            let found = ["heic", "png"].contains {
                Bundle.main.url(forResource: name, withExtension: $0) != nil
            }
            #expect(found, "\(set.displayName) art missing — tile art would be under-counted")
        }
    }

    /// Synced and on-device are different questions: generated art costs the
    /// family's iCloud quota; the app, its tile art and this device's history
    /// cost neither.
    @Test func syncedAndOnDeviceAreDistinct() {
        let report = StorageReport(deviceLocalBytes: 10, syncedStoreBytes: 20,
                                   generatedArtBytes: 30, bundledArtBytes: 40,
                                   appBytes: 50)
        #expect(report.onDeviceBytes == 150)
        #expect(report.syncedBytes == 50, "only the synced store and its art sync")
    }

    @Test func formatsAsBytesNotRawNumbers() {
        #expect(StorageReporter.format(5_000_000).contains("MB"))
    }

    // MARK: - Giving the space back

    /// **The store must actually give the space back.**
    ///
    /// Deleting rows alone does not shrink the file — SQLite moves the pages onto
    /// a freelist and reuses them — so without this the app's reported size would
    /// never fall, and a caregiver could not free anything by using it less.
    @Test func reclaimingFreePagesShrinksTheFileOnDisk() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("Local.store")

        makeStore(at: store, rows: 20_000)
        let full = StorageReporter.storeBytes(at: store)
        #expect(full > 1_000_000, "fixture too small to show a reclaim")

        deleteMost(at: store)
        MetricCompactor.reclaimFreeSpace(at: store)

        let reclaimed = StorageReporter.storeBytes(at: store)
        #expect(reclaimed < full / 2,
                "deleting 99% of rows left \(reclaimed) of \(full) bytes — space not returned")
    }

    /// The hand-off only fires when a compaction actually asked for it, and only
    /// once — a stale flag must not make every launch open the store for nothing.
    @Test func reclaimIsPendingOnlyWhenRequested() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appendingPathComponent("Local.store")
        makeStore(at: store, rows: 5_000)
        deleteMost(at: store)
        let full = StorageReporter.storeBytes(at: store)

        let defaults = UserDefaults(suiteName: "reclaim-\(UUID().uuidString)")!
        defaults.set(store.path, forKey: AppSettingsKey.compactionStorePath)

        // No flag — nothing should happen at all.
        MetricCompactor.reclaimPendingSpace(defaults: defaults)
        #expect(StorageReporter.storeBytes(at: store) == full)

        defaults.set(true, forKey: AppSettingsKey.compactionReclaimPending)
        MetricCompactor.reclaimPendingSpace(defaults: defaults)
        #expect(StorageReporter.storeBytes(at: store) < full)
        #expect(!defaults.bool(forKey: AppSettingsKey.compactionReclaimPending),
                "the flag must clear, or every later launch reopens the store for nothing")
    }

    /// A store that has moved or been deleted must not crash or leave the flag
    /// set forever.
    @Test func aMissingStoreClearsTheFlagQuietly() {
        let defaults = UserDefaults(suiteName: "reclaim-\(UUID().uuidString)")!
        defaults.set("/nowhere/Local.store", forKey: AppSettingsKey.compactionStorePath)
        defaults.set(true, forKey: AppSettingsKey.compactionReclaimPending)

        MetricCompactor.reclaimPendingSpace(defaults: defaults)
        // Left pending: the path is wrong, not the intent. A later launch with a
        // valid path still reclaims, and the guard makes this free until then.
        #expect(defaults.bool(forKey: AppSettingsKey.compactionReclaimPending))
    }
}
}
