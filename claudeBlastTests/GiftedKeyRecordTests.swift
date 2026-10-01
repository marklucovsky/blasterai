// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GiftedKeyRecordTests.swift
//  claudeBlastTests
//
//  Where the key on this device came from, and when that stops being true.
//

import Testing
import Foundation
@testable import claudeBlast

/// No SwiftData container, so not nested in `SerialTests`. Each test gets its
/// own `UserDefaults` suite rather than touching `.standard`, which would leak
/// into the simulator's real state and into whatever runs next.
struct GiftedKeyRecordTests {

    private func defaults(_ name: String = #function) -> UserDefaults {
        let suite = "gifted-key-tests-\(name)-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    private func payload(label: String = "Brandi",
                         key: String = "sk-test-000000000000000000008toA") -> GiftedKeyPayload {
        GiftedKeyPayload(key: key, label: label, issuer: "Mark Lucovsky",
                         issuedAt: "2026-09-16T00:00:00+00:00", expiresAt: nil)
    }

    /// An environment with no `OPENAI_API_KEY`, which is what these tests mean
    /// by "this device has no key".
    ///
    /// They used the real `ProcessInfo`, and that made them fail for anyone
    /// with a key in scope — which is everyone running from Xcode, because the
    /// shared scheme sets `OPENAI_API_KEY` on the Run action and marks the Test
    /// action `shouldUseLaunchSchemeArgsEnv = "YES"`. The test process inherits
    /// it, `currentKey` returns the env value by design, and the assertion that
    /// an empty store reads as nil can never hold.
    ///
    /// The env override winning is correct behaviour and `OpenAIKeyVaultTests`
    /// covers it deliberately. What was wrong is asserting on a *store* while
    /// leaving the environment free to answer first.
    private final class NoEnvProcessInfo: ProcessInfo, @unchecked Sendable {
        override var environment: [String: String] { [:] }
    }

    // MARK: - Round trip

    @Test("A saved record reads back")
    func roundTrip() {
        let store = defaults()
        let record = GiftedKeyRecord.from(payload())
        GiftedKeyRecord.save(record, to: store)
        #expect(GiftedKeyRecord.load(from: store) == record)
    }

    @Test("A device with no gift has no record")
    func absentByDefault() {
        #expect(GiftedKeyRecord.load(from: defaults()) == nil)
    }

    /// Only the last four is kept, and that is the point: the record is shown in
    /// a UI a child may be looking at, and the secret already has a home.
    @Test("The record holds the last four, never the key")
    func neverHoldsTheKey() {
        let store = defaults()
        let secret = "sk-test-000000000000000000008toA"
        GiftedKeyRecord.save(GiftedKeyRecord.from(payload(key: secret)), to: store)

        let record = GiftedKeyRecord.load(from: store)
        #expect(record?.lastFour == "8toA")
        for value in store.dictionaryRepresentation().values {
            #expect((value as? String)?.contains(secret) != true)
        }
    }

    // MARK: - Clearing

    /// A record outliving its key would label somebody else's key with the
    /// evaluator's name — a caregiver who removes a gift and pastes their own
    /// would be told their key belongs to Brandi.
    @Test("Clearing removes every field")
    func clearingIsComplete() {
        let store = defaults()
        GiftedKeyRecord.save(GiftedKeyRecord.from(payload()), to: store)
        GiftedKeyRecord.clear(from: store)

        #expect(GiftedKeyRecord.load(from: store) == nil)
        for key in [AppSettingsKey.giftedKeyLabel, AppSettingsKey.giftedKeyIssuer,
                    AppSettingsKey.giftedKeyIssued, AppSettingsKey.giftedKeyExpires,
                    AppSettingsKey.giftedKeyLastFour] {
            #expect(store.string(forKey: key) == nil)
        }
    }

    /// A half-written record — a crash between writes, a partial restore — must
    /// read as "no gift" rather than as a gift with no name.
    @Test("A record with no label is not a record")
    func labelIsThePresenceTest() {
        let store = defaults()
        store.set("Mark", forKey: AppSettingsKey.giftedKeyIssuer)
        store.set("8toA", forKey: AppSettingsKey.giftedKeyLastFour)
        #expect(GiftedKeyRecord.load(from: store) == nil)
    }

    // MARK: - Dates
    //
    // The minting tool writes `datetime.now(timezone.utc).isoformat()`, which
    // carries fractional seconds. The golden fixture's fixed date does not.
    // `ISO8601DateFormatter` does not treat `.withFractionalSeconds` as
    // optional — a formatter carrying it rejects a timestamp without them, and
    // one lacking it rejects a timestamp with them — so both have to parse or
    // the Device tab shows a raw ISO string where a date belongs.

    @Test("Both shapes of ISO-8601 parse", arguments: [
        "2026-09-16T00:00:00+00:00",
        "2026-09-16T22:33:34.123456+00:00",
        "2026-09-16T22:33:34Z",
    ])
    func datesParse(_ text: String) {
        #expect(GiftedKeyRecord.parseDate(text) != nil)
    }

    /// A date that will not parse must not blank the row — showing the raw
    /// string is ugly and honest; showing nothing loses the provenance.
    @Test("An unparseable date falls back to its raw text")
    func unparseableDateFallsBack() {
        let record = GiftedKeyRecord(label: "x", issuer: "y", issuedAt: "sometime",
                                     expiresAt: nil, lastFour: "8toA")
        #expect(record.issuedDisplay == "sometime")
    }

    // MARK: - The refusal rule
    //
    // The sheet checks this before asking for confirmation, so nobody agrees to
    // something that was never going to happen. Asserted against the vault
    // rather than the view, which has no seam to test through.

    @Test("A gift is refused while this device already holds a key")
    func refusesWhenOccupied() {
        let store = InMemorySecretStore(initial: "sk-the-caregivers-own-key")
        #expect(OpenAIKeyVault.currentKey(env: NoEnvProcessInfo(), store: store) != nil)
    }

    @Test("A gift installs onto a device with no key")
    func installsWhenEmpty() {
        let store = InMemorySecretStore()
        #expect(OpenAIKeyVault.currentKey(env: NoEnvProcessInfo(), store: store) == nil)

        let gift = payload()
        #expect(OpenAIKeyVault.setKey(gift.key, store: store, consentGranted: true))
        #expect(OpenAIKeyVault.currentKey(env: NoEnvProcessInfo(), store: store) == gift.key)
    }

    // MARK: - Verifying before storing
    //
    // Typing a key already validates as you paste (`OpenAIKeyEntrySection`), so
    // a key arriving by file has to as well — otherwise the two routes disagree
    // about when you find out it is dead, and the file route picks the worse
    // moment: an hour later, as sentences mysteriously stopping, with nothing
    // connecting that to the file that was tapped.
    //
    // The sheet has no seam to test through, so the policy is asserted as the
    // rule it applies. Only `.invalidKey` blocks.

    /// A definitive refusal is the only thing that stops an install.
    @Test("A rejected key is not stored")
    func rejectedKeyBlocksInstall() {
        #expect(shouldInstall(.invalidKey) == false)
    }

    /// Silence is not a no. Refusing on a rate limit or a dead network would
    /// leave an evaluator holding a perfectly good key they cannot use because
    /// the hotel wifi is bad — the same rule `OpenAIFailure` applies to a 429.
    @Test("An inconclusive check still installs", arguments: [
        OpenAIKeyValidator.Outcome.valid,
        .rateLimited,
        .networkError("timed out"),
        .unexpected(503),
    ])
    func inconclusiveChecksStillInstall(_ outcome: OpenAIKeyValidator.Outcome) {
        #expect(shouldInstall(outcome))
    }

    /// Mirrors the guard in `GiftedKeyImportSheet.verifyThenInstall`.
    private func shouldInstall(_ outcome: OpenAIKeyValidator.Outcome) -> Bool {
        outcome != .invalidKey
    }

    /// Every outcome the sheet may surface has to read as a sentence — this is
    /// the text an evaluator sees under "Key installed, not verified".
    @Test("Every inconclusive outcome has something to say")
    func outcomesHaveCopy() {
        for outcome: OpenAIKeyValidator.Outcome in [.rateLimited, .networkError("x"),
                                                    .unexpected(503), .invalidKey] {
            #expect(!outcome.friendlyMessage.isEmpty)
        }
    }
}
