// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  GiftedKeyTransfer.swift
//  claudeBlast
//
//  Handing an evaluator an OpenAI key without making them buy one.
//

import Foundation
import CryptoKit
import UniformTypeIdentifiers

extension UTType {
    static let blasterKey = UTType(exportedAs: "com.claudeblast.giftedkey", conformingTo: .json)
}

enum BlasterKeyFormat {
    static let mediaType = "application/vnd.claudeblast.giftedkey+json"
    static let currentVersion = "1.0.0"
    static let fileExtension = "blasterkey"
}

/// What is sealed inside the file.
///
/// Deliberately small: a key, who it is for, and who sent it. No scene, no
/// colorway — a provisioning bundle is a separate post-launch feature designed
/// against a real district conversation, not smuggled in here.
///
/// Dates are ISO-8601 strings rather than `Date`, because the other end of this
/// format is a Python script and a `Codable` date strategy is an invisible way
/// for the two to disagree.
struct GiftedKeyPayload: Codable, Equatable {
    let key: String
    let label: String
    let issuer: String
    let issuedAt: String
    /// Display only — nothing enforces it. Mark invalidates keys at the OpenAI
    /// console, which is the only revocation that actually works; an expiry in a
    /// file binds an honest client and nothing else. Carried because a format is
    /// hard to change once files exist in the wild.
    let expiresAt: String?
}

/// The file itself.
///
/// `label` appears here as well as inside the payload. The outer one is an
/// unauthenticated display hint so the sheet can say who the key is for; the
/// inner one is what gets stored. They will normally match, and nothing
/// important depends on it.
struct SealedGiftedKey: Codable {
    let type: String
    let version: String
    let comment: String
    let label: String
    /// Base64, 16 bytes.
    let nonce: String
    /// Base64 of the obfuscated payload JSON.
    let payload: String
    /// Hex SHA-256 of the *plaintext* payload. See `GiftedKeyObfuscation`: this
    /// catches a truncated or mangled file, not a hostile one.
    let checksum: String

    enum CodingKeys: String, CodingKey {
        case type = "@type"
        case version
        case comment = "_comment"
        case label, nonce, payload, checksum
    }
}

enum GiftedKeyError: LocalizedError, Equatable {
    case decodingFailed
    case invalidType
    case unsupportedVersion(String)
    case corrupted
    case missingKey

    var errorDescription: String? {
        switch self {
        case .decodingFailed:
            return "This file isn't a Blaster key file, or it was damaged in transit."
        case .invalidType:
            return "This file isn't a Blaster key file."
        case .unsupportedVersion(let v):
            return "This key file was made by a newer version of Blaster (format \(v))."
        case .corrupted:
            return "This key file arrived damaged. Ask for it to be sent again."
        case .missingKey:
            return "This key file doesn't contain a key."
        }
    }
}

/// Scrambling, not securing — and the name says so on purpose.
///
/// The "secret" is the app's bundle identifier, which is printed in the App
/// Store listing and sits in the Info.plist of any downloaded build. Anyone who
/// wants the key inside one of these files can have it in ten minutes. That is a
/// deliberate trade, not an oversight, and it rests on what a gifted key is
/// worth: one key per evaluator in a capped OpenAI project, scoped to
/// `gpt-4o-mini`, `omni-moderation-latest` and `gpt-image-2`, revocable from the
/// dashboard in one click. A leaked key drains a small cap and identifies its
/// owner by name.
///
/// **Do not "improve" this into real encryption with an app-side secret.** The
/// repo is Apache-2.0 on GitHub, so a random constant in source would be exactly
/// as public as the bundle identifier while *looking* like a secret to every
/// contributor who reads it. There is no such thing as an embedded secret in an
/// open-source app, and pretending otherwise is worse than not pretending.
/// Keeping it honest also keeps `ITSAppUsesNonExemptEncryption = false` true: a
/// hash is not encryption, and an XOR against a non-secret keystream is not a
/// cryptographic algorithm for export purposes.
///
/// What it does buy, and the reason it is not simply plaintext, is
/// **non-possession**. The evaluator never holds the key in a usable form, so
/// they cannot paste it into something, forward it to a colleague who also wants
/// a look, or have it lifted out of an iCloud backup by an `sk-`-pattern
/// scanner. A raw key in a text message loses all three.
enum GiftedKeyObfuscation {
    /// The app's bundle identifier, as a constant rather than
    /// `Bundle.main.bundleIdentifier`.
    ///
    /// The test bundle is `summerland.claudeBlastTests`, so reading it at runtime
    /// would produce a different keystream under tests than in the app — and the
    /// golden fixture, whose entire job is proving the Swift and Python sides
    /// agree, would be unopenable exactly where it is checked. A value that is
    /// public anyway loses nothing by being written down.
    ///
    /// Must match `BUNDLE_ID` in `tools/make_gifted_key.py`.
    static let bundleID = "app.blasterai.ios"

    static let nonceLength = 16

    /// Keystream block *i* is `SHA256(SHA256(bundleID) ‖ nonce ‖ bigEndian(i))`,
    /// XORed over the payload.
    ///
    /// Big-endian and 8 bytes, stated because this is the seam where two
    /// languages agree or silently do not. `GiftedKeyTransferTests` pins the
    /// first block against a hand-computed vector so a byte-order or width
    /// change fails loudly rather than as "the file just won't open".
    static func keystream(nonce: Data, count: Int) -> Data {
        let seed = Data(SHA256.hash(data: Data(bundleID.utf8)))
        var out = Data()
        out.reserveCapacity(count)
        var block: UInt64 = 0
        while out.count < count {
            var input = seed
            input.append(nonce)
            withUnsafeBytes(of: block.bigEndian) { input.append(contentsOf: $0) }
            out.append(contentsOf: SHA256.hash(data: input))
            block += 1
        }
        return out.prefix(count)
    }

    private static func xor(_ data: Data, nonce: Data) -> Data {
        let stream = keystream(nonce: nonce, count: data.count)
        return Data(zip(data, stream).map { $0 ^ $1 })
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    /// Wrap a payload into a file. Used by tests and by nothing in the app —
    /// minting is `tools/make_gifted_key.py`'s job, on a Mac, by Mark.
    static func seal(_ payload: GiftedKeyPayload) throws -> Data {
        let plaintext = try JSONEncoder().encode(payload)
        var nonce = Data(count: nonceLength)
        nonce.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, nonceLength, $0.baseAddress!) }

        let sealed = SealedGiftedKey(
            type: BlasterKeyFormat.mediaType,
            version: BlasterKeyFormat.currentVersion,
            comment: "A Blaster API key for \(payload.label), from \(payload.issuer). "
                   + "The contents are obfuscated, not encrypted — treat this file as you would the key itself.",
            label: payload.label,
            nonce: nonce.base64EncodedString(),
            payload: xor(plaintext, nonce: nonce).base64EncodedString(),
            checksum: hex(Data(SHA256.hash(data: plaintext))))

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(sealed)
    }

    /// Read a file back. Every failure is a named case, so the sheet can say
    /// something true rather than "something went wrong".
    static func open(_ data: Data) throws -> GiftedKeyPayload {
        guard let sealed = try? JSONDecoder().decode(SealedGiftedKey.self, from: data) else {
            throw GiftedKeyError.decodingFailed
        }
        guard sealed.type == BlasterKeyFormat.mediaType else { throw GiftedKeyError.invalidType }
        guard sealed.version.hasPrefix("1.") else {
            throw GiftedKeyError.unsupportedVersion(sealed.version)
        }
        guard let nonce = Data(base64Encoded: sealed.nonce),
              let ciphertext = Data(base64Encoded: sealed.payload) else {
            throw GiftedKeyError.corrupted
        }

        let plaintext = xor(ciphertext, nonce: nonce)
        guard hex(Data(SHA256.hash(data: plaintext))) == sealed.checksum else {
            throw GiftedKeyError.corrupted
        }
        guard let payload = try? JSONDecoder().decode(GiftedKeyPayload.self, from: plaintext) else {
            throw GiftedKeyError.corrupted
        }
        guard !payload.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GiftedKeyError.missingKey
        }
        return payload
    }

    /// Last four of the key, for showing which key is installed without showing
    /// the key. Matches how OpenAI's own dashboard renders it (`sk-…8toA`).
    static func lastFour(of key: String) -> String {
        String(key.suffix(4))
    }
}
