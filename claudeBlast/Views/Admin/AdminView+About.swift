// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  AdminView+About.swift
//  claudeBlast
//
//  Settings › About: what this is, at a glance, with the web and the notices
//  one tap away. Everything else About and Stats used to lead with (storage,
//  compaction, sync health) is under Details.
//

import SwiftUI

extension AdminView {
    static let siteURL = URL(string: "https://blasterai.app")!

    var aboutPage: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("BlasterAI").font(.title2.weight(.semibold))
                    Text(AppVersion.display)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            Section {
                LabeledContent("Words",
                               value: allTiles.filter { !$0.isStructuralChrome }.count.formatted())
                LabeledContent("Boards", value: "\(switchableScenes.count)")
                LabeledContent("Profiles", value: "\(childProfiles.count)")
                Button { show([.ai]) } label: {
                    LabeledContent("AI") {
                        HStack(spacing: 6) {
                            Circle().fill(providerStatus.color).frame(width: 8, height: 8)
                            Text(providerStatus.text)
                        }
                    }
                }
                .foregroundStyle(.primary)
                LabeledContent("iCloud", value: iCloudSyncOn ? "On" : "Off")
            }
            Section {
                Link("Website", destination: Self.siteURL)
                Link("Guides", destination: Self.siteURL.appending(path: "guides/"))
                Link("Questions and Answers", destination: Self.siteURL.appending(path: "faq/"))
                Link("Privacy Policy", destination: Self.siteURL.appending(path: "privacy/"))
            }
            Section {
                Text("BlasterAI is a communication tool. It is not medical advice and does not diagnose or treat anything. Talk with a doctor or speech-language pathologist about medical decisions.")
                Text("Free and open source under the Apache License 2.0. All tile art was made for BlasterAI and ships under the same license.")
                Link("Apache License 2.0", destination: URL(string: "https://www.apache.org/licenses/LICENSE-2.0")!)
            } header: {
                Text("Notices")
            }
            .font(.footnote)
            Section {
                NavigationLink("Details and Stats", value: AdminPage.aboutDetails)
            }
        }
        .navigationTitle("About")
    }
}
