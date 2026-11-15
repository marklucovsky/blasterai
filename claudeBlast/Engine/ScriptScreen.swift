// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ScriptScreen.swift
//  claudeBlast
//
//  Named destinations a TileScript can navigate to.
//

import Foundation
import SwiftUI

/// A tab within Admin.
enum AdminRoute: String, CaseIterable, Equatable, Sendable {
    case now, profiles, scenes, device, activity

    /// Sub-destinations reachable from a tab. Kept as a flat list rather than a
    /// nested tree because a route is a *name*, and `admin/scenes/vocabulary`
    /// reads better than a structure the author has to reason about.
    enum Detail: String, CaseIterable, Equatable, Sendable, Identifiable {
        var id: String { rawValue }

        /// Scenes → Manage Vocabulary.
        case vocabulary
        /// Settings › About.
        case about
        /// Device → TileScript.
        case tileScript = "tilescript"
    }
}

/// A destination a script can ask for by name.
///
/// ## Names, not taps
///
/// TileScript's durability comes from driving the *domain* — `addTile`,
/// `navigate` — rather than pixels, so a script survives the layout churn that
/// a polish session produces. Extending it to admin screens has to keep that
/// property, which means a script names **where to be**, never how to get there:
///
/// ```yaml
/// - screen: admin/scenes
/// - screenshot: scenes-list
/// ```
///
/// `tap the third row` would break every time a view moves. A route is a
/// contract the UI has to satisfy, and the compiler helps keep it.
///
/// ## Authority
///
/// A script reaching an admin screen is not a back door: `TileScriptView` is
/// itself behind `AdminGate`, so a running script already implies an
/// authenticated caregiver started it. That is what lets these routes exist
/// without each one re-challenging.
enum ScriptScreen: Equatable, Sendable {
    /// The child surface — the board itself.
    case board
    /// Admin, on a named tab.
    case admin(AdminRoute)
    /// Admin, on a named tab, pushed to one of its sub-screens.
    case adminDetail(AdminRoute, AdminRoute.Detail)

    /// Parse a route string. Returns nil for anything unrecognised so the
    /// **parser** can reject it before the run starts. A screenshot script that
    /// silently photographs the wrong screen is worse than one that refuses to
    /// run, and a typo is far likelier than a missing destination.
    static func parse(_ raw: String) -> ScriptScreen? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        switch trimmed {
        case "board", "home", "child":
            return .board
        case "admin":
            // Bare `admin` lands on the tab Admin opens to on its own.
            return .admin(.now)
        default:
            break
        }

        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.first == "admin" else { return nil }

        switch parts.count {
        case 2:
            guard let route = AdminRoute(rawValue: String(parts[1])) else { return nil }
            return .admin(route)
        case 3:
            guard let route = AdminRoute(rawValue: String(parts[1])),
                  let detail = AdminRoute.Detail(rawValue: String(parts[2])),
                  detail.parent == route
            else { return nil }
            return .adminDetail(route, detail)
        default:
            return nil
        }
    }

    /// Every accepted spelling, for error messages that tell the author what
    /// they could have written instead.
    static var allRouteNames: [String] {
        ["board", "admin"]
            + AdminRoute.allCases.map { "admin/\($0.rawValue)" }
            + AdminRoute.Detail.allCases.map { "admin/\($0.parent.rawValue)/\($0.rawValue)" }
    }

    var description: String {
        switch self {
        case .board:            return "board"
        case .admin(let route): return "admin/\(route.rawValue)"
        case .adminDetail(let route, let detail):
            return "admin/\(route.rawValue)/\(detail.rawValue)"
        }
    }
}

/// Where a script has asked Settings to be.
///
/// Settings was a `TabView` and this held the selected tab. It is now one list
/// with pages pushed from it, so a route is a *request* that `AdminView` turns
/// into a navigation path and then clears. The route names a script writes
/// (`admin/scenes`, `admin/device/about`) are unchanged — they are a contract
/// with every recorded script, and the pages they land on are mapped in
/// `AdminView.path(for:)`.
@Observable
@MainActor
final class AdminRouteCoordinator {
    struct Request: Equatable {
        let route: AdminRoute
        let detail: AdminRoute.Detail?
        /// Distinct per request, so asking for the same place twice still
        /// moves Settings there after a caregiver has wandered off.
        let id = UUID()
    }

    /// The request waiting to be shown. Set by the script runner.
    var pending: Request?

    func show(_ route: AdminRoute, detail: AdminRoute.Detail? = nil) {
        pending = Request(route: route, detail: detail)
    }

    /// Take the waiting request, if any.
    func consume() -> Request? {
        defer { pending = nil }
        return pending
    }
}

extension AdminRoute.Detail {
    /// The route this sub-screen is named under. Encoded here so a route
    /// string can be validated against reality rather than trusted.
    var parent: AdminRoute {
        switch self {
        case .vocabulary:  return .scenes
        case .about:       return .device
        case .tileScript:  return .device
        }
    }
}
