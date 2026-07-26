// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SceneIdentity.swift
//  claudeBlast
//
//  Decentralized scene identity — no central registry / clearinghouse.
//
//  A shareable scene carries a qualified `sceneID` = "<authority>/<slug>":
//   - user-authored scenes use the device's self-generated author id as the
//     authority (the "phone number" — stable, minted lazily, see DeviceProfile);
//   - first-party bundled scenes use `scenes.blasterai.app`.
//  Identity rides *inside* the exported file, so file-based sharing needs no
//  registration. Resolution is a ladder (id → slug → displayName) so older
//  name-only references keep working.
//

import Foundation

enum SceneIdentity {
    /// Authority for scenes BlasterAI ships (bundled/system scenes).
    static let firstPartyAuthority = "scenes.blasterai.app"

    /// Kebab-case slug derived from a display name: lowercased, non-alphanumeric
    /// runs collapsed to single dashes, trimmed. Falls back to "scene" if empty.
    static func slug(from name: String) -> String {
        var out = ""
        var pendingDash = false
        for ch in name.lowercased() {
            if ch.isLetter || ch.isNumber {
                if pendingDash && !out.isEmpty { out.append("-") }
                out.append(ch)
                pendingDash = false
            } else {
                pendingDash = true
            }
        }
        return out.isEmpty ? "scene" : out
    }

    /// Compose a qualified id from an authority + slug.
    static func id(authority: String, slug: String) -> String {
        "\(authority)/\(slug)"
    }
}
