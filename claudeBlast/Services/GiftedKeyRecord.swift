// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GiftedKeyRecord.swift
//  claudeBlast
//
//  Where the key on this device came from.
//

import Foundation

/// Provenance for a key installed from a `.blasterkey` file.
///
/// The key itself lives in the Keychain like any other, via `OpenAIKeyVault`.
/// This is everything *around* it — who it was for, who sent it, when — which
/// the vault cannot hold because a key there is a bare `String` with nowhere to
/// put a label.
///
/// It exists so two things can be true at once: the Device tab can say "Gifted
/// key — Brandi" instead of showing a masked field that looks like something the
/// caregiver typed, and the refusal banners from `OpenAIFailure` can be worded
/// for someone holding a key they did not buy and cannot fix.
///
/// **Device-local UserDefaults, deliberately not SwiftData.** Nothing here
/// touches the synced schema, which is what lets this land before CloudKit
/// promotion without interacting with gates 8 or 9. It is also simply correct:
/// the key is per-device (the Keychain item is
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, never synchronizable), so
/// a record that synced would describe a key the other device does not have.
struct GiftedKeyRecord: Equatable {
    let label: String
    let issuer: String
    let issuedAt: String
    let expiresAt: String?
    /// Last four of the key, matching how OpenAI's dashboard renders it.
    let lastFour: String

    /// "Sep 20" — the issue date, for the Device tab row. Falls back to the raw
    /// string if it will not parse, which is better than hiding a row.
    var issuedDisplay: String {
        guard let date = GiftedKeyRecord.parseDate(issuedAt) else { return issuedAt }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "expires Oct 3" — or nil when the key carries no expiry. The issuer can
    /// end a key earlier from their OpenAI dashboard; this is the date they
    /// stated, shown so a caregiver is not surprised when it stops.
    var expiresDisplay: String? {
        guard let expiresAt, !expiresAt.isEmpty else { return nil }
        guard let date = GiftedKeyRecord.parseDate(expiresAt) else { return "expires \(expiresAt)" }
        return "expires " + date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// ISO-8601 with or without fractional seconds.
    ///
    /// `ISO8601DateFormatter` does not treat `.withFractionalSeconds` as
    /// optional — a formatter carrying it *rejects* a timestamp that lacks them,
    /// and one without it rejects a timestamp that has them. The minting tool
    /// writes `datetime.now(timezone.utc).isoformat()`, which includes them, and
    /// the golden fixture's fixed date does not. Both have to parse.
    static func parseDate(_ text: String) -> Date? {
        for formatter in [Self.withFraction, Self.withoutFraction] {
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let withoutFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

extension GiftedKeyRecord {
    /// Read the record, or nil when the key on this device was not a gift.
    ///
    /// `label` is the presence test: a record with no label is not a record, and
    /// half-written defaults (a crash between writes, a restore from backup)
    /// read as absent rather than as a gift with no name.
    static func load(from defaults: UserDefaults = .standard) -> GiftedKeyRecord? {
        guard let label = defaults.string(forKey: AppSettingsKey.giftedKeyLabel),
              !label.isEmpty else { return nil }
        return GiftedKeyRecord(
            label: label,
            issuer: defaults.string(forKey: AppSettingsKey.giftedKeyIssuer) ?? "",
            issuedAt: defaults.string(forKey: AppSettingsKey.giftedKeyIssued) ?? "",
            expiresAt: defaults.string(forKey: AppSettingsKey.giftedKeyExpires),
            lastFour: defaults.string(forKey: AppSettingsKey.giftedKeyLastFour) ?? "")
    }

    static func save(_ record: GiftedKeyRecord, to defaults: UserDefaults = .standard) {
        defaults.set(record.label, forKey: AppSettingsKey.giftedKeyLabel)
        defaults.set(record.issuer, forKey: AppSettingsKey.giftedKeyIssuer)
        defaults.set(record.issuedAt, forKey: AppSettingsKey.giftedKeyIssued)
        defaults.set(record.expiresAt, forKey: AppSettingsKey.giftedKeyExpires)
        defaults.set(record.lastFour, forKey: AppSettingsKey.giftedKeyLastFour)
    }

    /// Forget the gift. Called whenever the key itself goes or changes — a
    /// record outliving its key would label someone else's key with the
    /// evaluator's name, which is worse than showing nothing.
    static func clear(from defaults: UserDefaults = .standard) {
        for key in [AppSettingsKey.giftedKeyLabel, AppSettingsKey.giftedKeyIssuer,
                    AppSettingsKey.giftedKeyIssued, AppSettingsKey.giftedKeyExpires,
                    AppSettingsKey.giftedKeyLastFour] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Build a record from a freshly opened key file.
    static func from(_ payload: GiftedKeyPayload) -> GiftedKeyRecord {
        GiftedKeyRecord(label: payload.label,
                        issuer: payload.issuer,
                        issuedAt: payload.issuedAt,
                        expiresAt: payload.expiresAt,
                        lastFour: GiftedKeyObfuscation.lastFour(of: payload.key))
    }
}
