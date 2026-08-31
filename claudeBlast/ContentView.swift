// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  ContentView.swift
//  claudeBlast
//
//  Created by MARK LUCOVSKY on 2/5/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(TileScriptRunner.self) private var scriptRunner
    @Environment(TileScriptRecorder.self) private var scriptRecorder
    @Environment(ImportCoordinator.self) private var importCoordinator
    @Environment(CaregiverMenuCoordinator.self) private var caregiverMenu
    @Environment(AdminRouteCoordinator.self) private var adminRoute
    @AppStorage(AppSettingsKey.demoMode) private var demoMode = false

    @Query private var deviceProfiles: [DeviceProfile]

    @State private var activeDestination: Destination?
    @State private var pendingImportSheet: ImportSheetURL?

    private enum Destination: Identifiable {
        case admin, tileScript
        /// Admin without a challenge, reachable only from a running TileScript.
        /// The script itself starts behind `AdminGate`, so re-challenging here
        /// would prompt a caregiver who authenticated moments ago — and would
        /// stall an unattended screenshot run at a PIN pad.
        case adminUngated
        /// TileScript without a challenge, for `-TileScriptAutorun` only.
        case tileScriptUngated
        var id: Self { self }
    }

    /// True when the device hasn't gone through onboarding yet — either no
    /// DeviceProfile exists or its onboardingCompleted flag is false.
    /// ProfileMigration always materializes a placeholder before any view
    /// appears, so the "no DeviceProfile" branch is just defensive.
    private var needsOnboarding: Bool {
        guard let device = deviceProfiles.first else { return true }
        return !device.onboardingCompleted
    }

    var body: some View {
        Group {
            if needsOnboarding {
                OnboardingView()
            } else {
                mainContent
            }
        }
        .onChange(of: needsOnboarding) { _, isNeeded in
            // Defensive reset when transitioning out of onboarding.
            // activeDestination is @State on ContentView and survives data
            // wipes (Factory Reset clears SwiftData but not @State). Without
            // this, a session that had Admin open before a reset would
            // instantly re-present AdminGate the moment mainContent mounts,
            // because $activeDestination's binding is still .admin.
            if !isNeeded {
                activeDestination = nil
                pendingImportSheet = nil
            }
        }
    }

    private var mainContent: some View {
        TileGridView()
            .fullScreenCover(item: $activeDestination) { dest in
                destinationContent(dest)
                    // The playback pill lives on the child surface, so a
                    // `screen: admin/…` used to bury the step controls under the
                    // cover: stepping a script into Admin left no way to advance
                    // it, and no way back out. A cover is its own presentation
                    // context, so an overlay on the board cannot reach over it —
                    // the controls have to be re-applied inside.
                    .overlay(alignment: .bottom) {
                        // Same rule the board uses: demo mode suppresses the
                        // pill on a straight run, because what is on screen IS
                        // the artifact. Stepping keeps it — you need the
                        // controls, and a stepped run is not being captured
                        // for anyone.
                        if scriptRunner.state != .idle,
                           !(demoMode && !scriptRunner.isStepping) {
                            TileScriptPlaybackOverlay()
                        }
                    }
            }
            // The caregiver menu (long-press Home in the tray) requests a
            // destination; present it here, where the cover lives. Both
            // destinations are wrapped in AdminGate, so the menu itself is open.
            .onChange(of: caregiverMenu.requested) { _, requested in
                guard let requested else { return }
                caregiverMenu.requested = nil
                switch requested {
                case .admin:      activeDestination = .admin
                case .tileScript: activeDestination = .tileScript
                }
            }
            .onAppear {
                // Unattended run: open the script tab so its autorun task fires.
                // Ungated on purpose — a PIN pad would stall a run nobody is
                // watching, and the argument had to be typed at launch by
                // whoever owns the machine.
                if TileScriptView.autorunScriptName != nil, activeDestination == nil {
                    activeDestination = .tileScriptUngated
                }
                scriptRunner.onSwitchToHome = { activeDestination = nil }
                scriptRecorder.onSwitchToHome = { activeDestination = nil }
                scriptRecorder.onSwitchToScript = { activeDestination = .tileScript }
                // TileScript `screen:` — ContentView owns the full-screen cover,
                // so it is the only place that can put the app on a destination.
                // Admin is entered directly rather than through AdminGate: the
                // script is running from inside TileScriptView, which is itself
                // gated, so the caregiver already authenticated at the door.
                scriptRunner.onNavigateToScreen = { screen in
                    switch screen {
                    case .board:
                        activeDestination = nil
                    case .admin(let route):
                        adminRoute.pendingDetail = nil
                        adminRoute.tab = route
                        activeDestination = .adminUngated
                    case .adminDetail(let route, let detail):
                        // The tab consumes this on arrival and pushes the
                        // sub-screen — the detail is a request, not a location,
                        // so it cannot get stuck set.
                        adminRoute.pendingDetail = detail
                        adminRoute.tab = route
                        activeDestination = .adminUngated
                    }
                }
            }
            .onChange(of: importCoordinator.pendingURL) { _, url in
                guard let url else { return }
                importCoordinator.pendingURL = nil
                // Dismiss any active fullScreenCover first, then present import
                if activeDestination != nil {
                    activeDestination = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        pendingImportSheet = ImportSheetURL(url: url)
                    }
                } else {
                    pendingImportSheet = ImportSheetURL(url: url)
                }
            }
            .sheet(item: $pendingImportSheet) { wrapper in
                ImportRouteSheet(url: wrapper.url) {
                    pendingImportSheet = nil
                }
            }
    }

    @ViewBuilder
    private func destinationContent(_ dest: Destination) -> some View {
        switch dest {
        case .admin:
            AdminGate { AdminView() }
        case .adminUngated:
            AdminView()
        case .tileScriptUngated:
            TileScriptView()
        case .tileScript:
            // Gated for the same reason Admin is, and it used not to be.
            //
            // TileScript drives the app: it navigates boards, taps tiles, speaks,
            // and manages saved recordings. That is caregiver authority, and the
            // child surface could reach it — stopping a recording calls
            // `onSwitchToScript` from an overlay that sits on the board itself,
            // so on a patient device this was an unchallenged route into script
            // management.
            //
            // Gating here also collapses two authority models into one: a
            // running script now implies an authenticated caregiver started it,
            // which is what lets script commands drive admin surfaces without
            // each one needing its own gate.
            AdminGate { TileScriptView() }
        }
    }
}

#Preview {
    ContentView()
        .previewEnvironment()
}
