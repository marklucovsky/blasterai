// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+ProfilesTab.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

extension AdminView {
    var profilesTab: some View {
        NavigationStack {
            List {
                profilesSection
            }
            .navigationTitle("Profiles")
            .toolbar { adminDoneToolbar }
        }
        .tabItem { Label("Profiles", systemImage: "person.2.fill") }
        .sheet(item: $profileSheet) { sheet in
            switch sheet {
            case .create:
                ChildProfileFormSheet(mode: .create) { profileSheet = nil }
            case .edit(let profile):
                ChildProfileFormSheet(mode: .edit(profile)) { profileSheet = nil }
            }
        }
    }

    // MARK: - Profiles section (child roster)

    @ViewBuilder
    var profilesSection: some View {
        Section {
            if childProfiles.isEmpty {
                Text("No child profiles yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(childProfiles) { profile in
                    profileRow(profile)
                }
            }
            Button {
                profileSheet = .create
            } label: {
                Label("Add Profile", systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text("Child Profiles")
                Spacer()
                if let active = profileResolver.active {
                    Text("Active: \(active.displayName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    func profileRow(_ profile: ChildProfile) -> some View {
        Button {
            profileResolver.setActive(id: profile.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: profile.isSystem
                      ? "gearshape.fill"
                      : "person.crop.circle.fill")
                    .foregroundStyle(profile.isSystem ? Color.gray : Color.accentColor)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(profile.displayName).font(.body)
                        if profile.isSystem {
                            Text("Sandbox")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(profile.isSystem
                         ? "Default when no real patient is active"
                         : "Age \(profile.age) · grade \(profile.ageGrade) · max \(profile.maxSelectedTiles) tiles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if profile.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button {
                    profileSheet = .edit(profile)
                } label: {
                    Image(systemName: "pencil.circle")
                }
                .buttonStyle(.borderless)
            }
            // Without contentShape(Rectangle()) the outer Button only
            // registers taps on the labeled content (icon + name + meta);
            // the Spacer between the text and the trailing pencil/check
            // fell through as un-hittable, making most of the row visually
            // dead. Forcing the hit area to the full HStack makes the
            // whole row tappable while the pencil's own .borderless Button
            // still takes priority for the edit affordance.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            // Sandbox can't be deleted — the resolver depends on its
            // existence. Real profiles can be deleted if not currently
            // active.
            if !profile.isActive && !profile.isSystem {
                Button(role: .destructive) {
                    modelContext.delete(profile)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}
