// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  OpenAIKeySetupGuide.swift
//  claudeBlast
//
//  Education-first walkthrough for getting an OpenAI key. It lives *outside* the
//  onboarding action: it's presented as a sheet from the welcome screen and from
//  the key field's "setup guide" link, and it's the key-management help reachable
//  from Admin → Device.
//
//  The content is split to mirror what happens where:
//    • "Before you start" — the one-time PREREQUISITE done on OpenAI's site:
//      a funded Platform account (which is separate from a ChatGPT consumer
//      login) with billing enabled.
//    • "Then get your key" — the "Get an API Key for Blaster" action: create a
//      secret key and paste it into Blaster.

import SwiftUI

struct OpenAIKeySetupGuide: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Blaster turns the tiles your child taps into spoken sentences using OpenAI. You bring your own key, so there’s no Blaster server in between — your data stays in your iCloud and you pay OpenAI directly, usually pennies a month.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                groupHeader("Before you start",
                            "A one-time prerequisite — done on OpenAI’s site, not here.")
                twoUp {
                    block("person.crop.circle.badge.plus",
                          "Create an OpenAI Platform account",
                          "Sign up free at platform.openai.com. This developer “Platform” account is separate from ChatGPT — a chatgpt.com login or ChatGPT Plus subscription won’t work here. Already have one? Just sign in.")
                } trailing: {
                    block("creditcard",
                          "Add billing and a little credit",
                          "On the Platform, open Settings → Billing, add a payment method, and add about $5 of credit. The API is pay-as-you-go with no free tier, so without credit your key is valid but every request fails. $5 lasts a long time — sentences cost a fraction of a cent each, and a picture for a new word is about 6¢.")
                }

                groupHeader("Then get your key",
                            "This is the “Get an API Key for Blaster” step.")
                twoUp {
                    block("key.horizontal.fill",
                          "Create a secret key",
                          "On the Platform, go to API keys → “Create new secret key.” Name it “Blaster.”")
                } trailing: {
                    block("doc.on.clipboard",
                          "Copy it once, then paste",
                          "OpenAI shows the full key only once, right after you create it — copy it immediately. The keys list never shows it again (there’s no copy button there). Paste it into Blaster’s key field; valid keys start with “sk-.” It’s completely fine to make more than one key — if you forget to copy one, just delete it, create a new one, and move on.")
                }
            }
            .padding()
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Pieces

    private func groupHeader(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 4)
    }

    /// Two blocks side by side when there's width (iPad landscape), stacked when narrow.
    private func twoUp<L: View, T: View>(@ViewBuilder leading: () -> L,
                                         @ViewBuilder trailing: () -> T) -> some View {
        let l = leading(), t = trailing()
        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 20) {
                l.frame(maxWidth: .infinity, alignment: .leading)
                t.frame(maxWidth: .infinity, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 14) {
                l.frame(maxWidth: .infinity, alignment: .leading)
                t.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func block(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Sheet wrapper

/// Presents `OpenAIKeySetupGuide` modally with a title and Done button. Used by
/// the onboarding welcome callout and the key field's "setup guide" link.
struct OpenAIKeySetupSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            OpenAIKeySetupGuide()
                .navigationTitle("Getting your API key")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}
