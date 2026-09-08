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

    // MARK: - Profiles section (caregiver + child roster)

    /// The caregiver's own profile — exactly one, always present, undeletable.
    var caregiverProfile: ChildProfile? { childProfiles.first(where: \.isSystem) }

    /// The children. One list, and it no longer has a second undeletable row
    /// mixed into it that a caregiver had no way to account for.
    var realProfiles: [ChildProfile] { childProfiles.filter { !$0.isSystem } }

    @ViewBuilder
    var profilesSection: some View {
        // Two sections rather than one list with a badge in it. The caregiver
        // profile and a child are different kinds of thing — one is who is
        // using the app, the others are who it is for — and a single roster
        // made that a matter of noticing a grey capsule.
        if let caregiver = caregiverProfile {
            Section {
                profileRow(caregiver)
            } header: {
                Text("This Caregiver")
            } footer: {
                Text("Your own settings and saved color sets. Used when no child "
                     + "is selected, so the app always has something to work from.")
            }
        }

        Section {
            if realProfiles.isEmpty {
                Text("No child profiles yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(realProfiles) { profile in
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
                Text("Children")
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
                            Text("You")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                    Text(profile.isSystem
                         ? "Active when no child is selected"
                         : "\(profile.brownsStage.label) · max \(profile.effectiveTileCap) tiles")
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
