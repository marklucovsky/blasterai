// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  UsageDetailView.swift
//  claudeBlast
//
//  Line items behind Activity → AI Usage.
//

import SwiftUI
import SwiftData

/// Every recorded API call, newest first.
///
/// Deliberately reachable rather than shown by default: the summary answers the
/// caregiver's question ("is this costing me anything?"), while this answers
/// ours ("does our arithmetic match OpenAI's bill?"). Having it in the app is
/// what makes that reconciliation possible without attaching a debugger — the
/// endpoint and model on each row line up with how OpenAI's own usage dashboard
/// breaks spend down.
struct UsageDetailView: View {
    let events: [APIUsageEvent]

    var body: some View {
        List {
            if events.isEmpty {
                Text("No API calls recorded yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(events) { event in
                        row(event)
                    }
                } footer: {
                    Text("Prices last verified \(UsageLedger.pluralize(ModelPricing.daysSinceVerified(), "day")) ago. OpenAI publishes no pricing API, so this table is maintained by hand — treat these figures as our best estimate, not as a bill.")
                }
            }
        }
        .navigationTitle("AI Usage Detail")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func row(_ event: APIUsageEvent) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(event.cause.label)
                    .font(.caption.weight(.semibold))
                if !event.detail.isEmpty {
                    Text(event.detail)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Three distinct statements, never collapsed into "$0.00":
                //   "free"     — the endpoint doesn't bill
                //   "unpriced" — it billed, but we had no price for the model
                //   $N         — an actual computed cost
                Text(costLabel(event))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(event.isUnpriced ? .orange
                                     : (event.isFreeCall ? .secondary : .primary))
            }

            Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Text(event.model.isEmpty ? "—" : event.model)
                Text(event.endpoint)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Text(tokenBreakdown(event))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)

            if event.isAggregate {
                Text("Aggregate of \(event.count) calls through \(event.periodEnd?.formatted(date: .abbreviated, time: .omitted) ?? "—") — token and cost figures are totals for the period.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func costLabel(_ event: APIUsageEvent) -> String {
        if event.isFreeCall { return "free" }
        if event.isUnpriced { return "unpriced" }
        return UsageLedger.formatUSD(micros: event.costMicros)
    }

    /// Only the token roles that actually applied — showing "image input: 0" on
    /// every chat call is noise that hides the fields that matter.
    private func tokenBreakdown(_ event: APIUsageEvent) -> String {
        var parts: [String] = ["in \(event.promptTokens)"]
        if event.cachedPromptTokens > 0 { parts.append("cached \(event.cachedPromptTokens)") }
        if event.imageInputTokens > 0 { parts.append("img-in \(event.imageInputTokens)") }
        parts.append("out \(event.completionTokens)")
        if event.imageCount > 0 { parts.append("\(event.imageCount) image\(event.imageCount == 1 ? "" : "s")") }
        return parts.joined(separator: " · ")
    }
}
