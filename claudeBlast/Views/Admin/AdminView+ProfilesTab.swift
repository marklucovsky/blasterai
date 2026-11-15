// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+ProfilesTab.swift
//  claudeBlast
//

import SwiftUI
import SwiftData

extension AdminView {
    /// Settings › Profile › All Profiles: you, then each child, with a check
    /// on whoever is talking. A row opens that profile's page.
    var talkersPage: some View {
        List {
            Section {
                ForEach(rosterProfiles) { p in
                    NavigationLink(value: AdminPage.profileDetail(p.id)) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                ProfileNameLabel(profile: p, size: 28)
                                Text(p.isSystem ? "You · \(p.brownsStage.label)" : p.brownsStage.label)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if p.id == currentProfile?.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if p.id != currentProfile?.id {
                            Button("Switch") { profileResolver.setActive(id: p.id) }
                                .tint(.green)
                        }
                    }
                }
            }
            Section {
                Button { isAddingProfile = true } label: {
                    Label("Add Profile", systemImage: "plus")
                }
            }
        }
        .navigationTitle("All Profiles")
    }

    /// Add Profile and the delete confirmation, hosted on Settings' stack.
    func profilesModals(_ content: some View) -> some View {
        content
            .sheet(isPresented: $isAddingProfile) {
                AddProfileFlow { isAddingProfile = false }
            }
            .confirmationDialog(
                "Delete \(profileToDelete?.visibleName ?? "this profile")?",
                isPresented: Binding(get: { profileToDelete != nil },
                                     set: { if !$0 { profileToDelete = nil } }),
                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let p = profileToDelete { deleteProfile(p) }
                }
            } message: {
                Text("Its settings and Me page go with it. This can't be undone.")
            }
    }

    /// Deleting whoever is talking hands the board back to you first, so the
    /// board is never left speaking for nobody.
    func deleteProfile(_ p: ChildProfile) {
        let id = p.id
        if id == currentProfile?.id, let you = caregiverProfile {
            profileResolver.setActive(id: you.id)
        }
        path = Array(path.prefix { $0.profileID != id })
        if selection?.profileID == id { selection = .profile }
        modelContext.delete(p)
        try? modelContext.save()
        profileResolver.refresh()
        profileToDelete = nil
    }

    /// The caregiver's own profile — exactly one, always present, undeletable.
    var caregiverProfile: ChildProfile? { childProfiles.first(where: \.isSystem) }

    /// You first, then the children.
    var rosterProfiles: [ChildProfile] {
        (caregiverProfile.map { [$0] } ?? []) + childProfiles.filter { !$0.isSystem }
            .sorted { $0.visibleName.localizedStandardCompare($1.visibleName) == .orderedAscending }
    }
}
