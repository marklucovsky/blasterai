// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  UsageReportRenderer.swift
//  claudeBlast
//
//  The usage report as a PDF someone can open in Messages.
//

import Foundation
import UIKit

struct UsageReportOptions: Equatable {
    var paper: PaperSize = .usLetter

    /// Carry what the child actually said.
    ///
    /// Off by default. See `UsageReport.includesUtterances` — this is the one
    /// question 4E left open, and false is the answer that can be walked back.
    var includeUtterances: Bool = false

    var includeCoverage: Bool = true
    var includePatterns: Bool = true
}

/// Draws `UsageReport` onto paper.
///
/// ## Flowing, not gridded
///
/// `BoardPDFRenderer` lays out a fixed grid and knows how many cells fit a
/// sheet before it starts. This cannot: a report is variable-height prose,
/// charts and lists, and how much fits depends on what the child did. So it
/// carries a cursor down the page and breaks when the next block will not fit —
/// which means every block has to be able to say how tall it is before it draws.
///
/// ## Vector only
///
/// No tile art. Partly size — a report is emailed, and a board's worth of HEIC
/// would dwarf everything else in it — but mainly because this reader is not
/// looking at the board. They want the words, the counts and the shape; the
/// pictures are the child's interface, not the therapist's.
enum UsageReportRenderer {

    static func render(_ report: UsageReport,
                       options: UsageReportOptions = UsageReportOptions()) -> Data {
        let size = options.paper.size(in: .portrait)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String:
                "\(report.childName.isEmpty ? "Blaster" : report.childName) — \(report.periodLabel)",
            kCGPDFContextCreator as String: "Blaster",
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size),
                                             format: format)

        return renderer.pdfData { ctx in
            var writer = PageWriter(context: ctx, paper: size, report: report)
            writer.beginPage()

            drawTitle(&writer, report)
            drawSummary(&writer, report)
            if options.includePatterns { drawPatterns(&writer, report) }
            if options.includeCoverage { drawCoverage(&writer, report) }
            drawSessions(&writer, report, includeUtterances: options.includeUtterances)

            writer.finishPage()
        }
    }

    // MARK: - Page cursor

    /// A vertical cursor with page breaks, and the running footer.
    ///
    /// The footer is the renderer's job rather than each section's because it has
    /// to be on **every** page: a report that says what it contains only on page
    /// one is a report whose page four can be forwarded without that warning.
    private struct PageWriter {
        let context: UIGraphicsPDFRendererContext
        let paper: CGSize
        let report: UsageReport

        let margin: CGFloat = 54          // 0.75"
        var y: CGFloat = 0
        var pageNumber = 0

        var contentWidth: CGFloat { paper.width - margin * 2 }
        var bottomLimit: CGFloat { paper.height - margin - 28 }

        mutating func beginPage() {
            if pageNumber > 0 { drawFooter() }
            context.beginPage()
            pageNumber += 1
            y = margin
        }

        mutating func finishPage() { drawFooter() }

        /// Reserve vertical space, breaking first if it will not fit.
        mutating func need(_ height: CGFloat) {
            if y + height > bottomLimit { beginPage() }
        }

        mutating func advance(_ height: CGFloat) { y += height }

        private func drawFooter() {
            let text: String
            if report.includesUtterances {
                // Named on every page, deliberately. This file contains a child's
                // speech, and a page of it can be forwarded on its own.
                text = "Contains \(report.childName.isEmpty ? "the child" : report.childName)’s own words · page \(pageNumber)"
            } else {
                text = "Blaster usage report · page \(pageNumber)"
            }
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 8),
                .foregroundColor: UIColor.secondaryLabel,
            ]
            let rect = CGRect(x: margin, y: paper.height - margin - 10,
                              width: paper.width - margin * 2, height: 12)
            (text as NSString).draw(in: rect, withAttributes: attrs)
        }
    }

    // MARK: - Text helpers

    private static func draw(_ text: String, _ writer: inout PageWriter,
                             font: UIFont, colour: UIColor = .label,
                             spacingAfter: CGFloat = 4, indent: CGFloat = 0) {
        let width = writer.contentWidth - indent
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let height = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs, context: nil).height
        writer.need(height + spacingAfter)
        (text as NSString).draw(
            in: CGRect(x: writer.margin + indent, y: writer.y, width: width, height: height),
            withAttributes: attrs)
        writer.advance(height + spacingAfter)
    }

    /// A heading inside a section, for the several lists that share one.
    ///
    /// Set apart from the row labels beside it, because at the same weight a
    /// heading reads as another data row — "By page" sat directly above "Colors
    /// Shapes" in the same size and became one of the bars.
    ///
    /// Reserves the heading PLUS a row, so it can never be the last thing on a
    /// page. A heading stranded at the bottom is worse than no heading: the list
    /// it names starts overleaf looking unlabelled, which is the bug this fixes.
    private static func subHeading(_ text: String, _ writer: inout PageWriter) {
        writer.need(20 + 16)
        writer.advance(8)
        draw(text, &writer, font: .systemFont(ofSize: 11, weight: .semibold),
             spacingAfter: 4)
    }

    private static func sectionHeading(_ text: String, _ writer: inout PageWriter) {
        writer.need(34)
        writer.advance(10)
        draw(text, &writer, font: .systemFont(ofSize: 13, weight: .semibold),
             colour: .label, spacingAfter: 2)
        let line = CGRect(x: writer.margin, y: writer.y, width: writer.contentWidth, height: 0.6)
        UIColor.separator.setFill()
        UIBezierPath(rect: line).fill()
        writer.advance(8)
    }

    // MARK: - Sections

    private static func drawTitle(_ w: inout PageWriter, _ r: UsageReport) {
        draw(r.childName.isEmpty ? "Usage report" : r.childName, &w,
             font: .systemFont(ofSize: 24, weight: .bold), spacingAfter: 2)
        var subtitle = r.periodLabel
        if !r.sceneName.isEmpty { subtitle += " · \(r.sceneName)" }
        subtitle += " · generated \(r.generatedAt.formatted(date: .abbreviated, time: .shortened))"
        draw(subtitle, &w, font: .systemFont(ofSize: 10), colour: .secondaryLabel,
             spacingAfter: 10)

        if r.isSingleWord {
            draw("Single word mode. Counts are words pressed; there are no generated sentences, and so no escalation.",
                 &w, font: .systemFont(ofSize: 9), colour: .secondaryLabel, spacingAfter: 8)
        }
    }

    private static func drawSummary(_ w: inout PageWriter, _ r: UsageReport) {
        sectionHeading("Summary", &w)

        let saidLabel = r.isSingleWord ? "words" : "said"
        var cells: [(String, String, String?)] = [
            ("\(r.summary.sessionCount)", r.summary.sessionCount == 1 ? "session" : "sessions", nil),
            ("\(r.summary.saidCount)", saidLabel, delta(r.summary.saidCount, r.summary.previous?.said)),
            ("\(r.summary.distinctWordCount)", "different words",
             delta(r.summary.distinctWordCount, r.summary.previous?.distinct)),
        ]
        if r.summary.previous == nil { cells = cells.map { ($0.0, $0.1, nil) } }

        w.need(56)
        let cellWidth = w.contentWidth / CGFloat(cells.count)
        for (index, cell) in cells.enumerated() {
            let x = w.margin + CGFloat(index) * cellWidth
            (cell.0 as NSString).draw(
                in: CGRect(x: x, y: w.y, width: cellWidth, height: 26),
                withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 21, weight: .semibold)])
            (cell.1 as NSString).draw(
                in: CGRect(x: x, y: w.y + 26, width: cellWidth, height: 12),
                withAttributes: [.font: UIFont.systemFont(ofSize: 9),
                                 .foregroundColor: UIColor.secondaryLabel])
            if let change = cell.2 {
                (change as NSString).draw(
                    in: CGRect(x: x, y: w.y + 38, width: cellWidth, height: 12),
                    withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                                     .foregroundColor: UIColor.secondaryLabel])
            }
        }
        w.advance(56)

        if r.summary.previous != nil {
            draw("Change is against the period immediately before this one.", &w,
                 font: .systemFont(ofSize: 9), colour: .secondaryLabel, spacingAfter: 6)
        }
    }

    private static func delta(_ now: Int, _ before: Int?) -> String? {
        guard let before else { return nil }
        let change = now - before
        if change == 0 { return "no change" }
        return "\(change > 0 ? "+" : "")\(change) vs previous"
    }

    // MARK: Patterns

    private static func drawPatterns(_ w: inout PageWriter, _ r: UsageReport) {
        guard r.patterns.totalPresses > 0 else { return }
        sectionHeading("When words get used", &w)

        if let hours = r.patterns.activeHours, !r.patterns.weekdays.isEmpty {
            let counts = Dictionary(
                r.patterns.cells.map { ("\($0.weekday)-\($0.hour)", $0.presses) },
                uniquingKeysWith: { a, _ in a })
            let columns = hours.count
            let labelWidth: CGFloat = 26
            let cell = min(14, (w.contentWidth - labelWidth) / CGFloat(columns))
            let gridHeight = CGFloat(r.patterns.weekdays.count) * (cell + 2) + 16
            w.need(gridHeight)

            // Hour ruler — every third column, so it stays readable at 14pt cells.
            for (i, hour) in hours.enumerated() where i % 3 == 0 {
                let x = w.margin + labelWidth + CGFloat(i) * (cell + 2)
                (hourLabel(hour) as NSString).draw(
                    in: CGRect(x: x, y: w.y, width: cell * 3, height: 10),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 6.5),
                                     .foregroundColor: UIColor.tertiaryLabel])
            }
            w.advance(10)

            let symbols = Calendar.current.shortWeekdaySymbols
            for weekday in r.patterns.weekdays {
                let label = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
                (label as NSString).draw(
                    in: CGRect(x: w.margin, y: w.y + 1, width: labelWidth - 4, height: cell),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 7),
                                     .foregroundColor: UIColor.secondaryLabel])
                for (i, hour) in hours.enumerated() {
                    let count = counts["\(weekday)-\(hour)"] ?? 0
                    let x = w.margin + labelWidth + CGFloat(i) * (cell + 2)
                    let rect = CGRect(x: x, y: w.y, width: cell, height: cell)
                    // Floored so one press is visibly different from none — the
                    // difference between "once" and "never" is most of the point.
                    let alpha = count == 0 ? 0.06
                        : 0.2 + 0.8 * (Double(count) / Double(max(r.patterns.busiestCell, 1)))
                    UIColor.label.withAlphaComponent(alpha).setFill()
                    UIBezierPath(roundedRect: rect, cornerRadius: 1.5).fill()
                }
                w.advance(cell + 2)
            }
            w.advance(4)
            draw("Every week in this period folded onto one, so a habit shows as a column.",
                 &w, font: .systemFont(ofSize: 9), colour: .secondaryLabel, spacingAfter: 4)
        }

        drawDailyBars(&w, r)
    }

    private static func drawDailyBars(_ w: inout PageWriter, _ r: UsageReport) {
        let days = r.patterns.days
        guard days.count > 1 else { return }
        sectionHeading("How much, and how varied", &w)

        let height: CGFloat = 70
        w.need(height + 24)
        let peak = max(days.map(\.presses).max() ?? 1, 1)
        let barSpace = w.contentWidth / CGFloat(days.count)
        let barWidth = max(1.5, min(14, barSpace - 2))

        for (index, day) in days.enumerated() {
            let x = w.margin + CGFloat(index) * barSpace
            let total = height * CGFloat(day.presses) / CGFloat(peak)
            let distinct = height * CGFloat(day.distinctWords) / CGFloat(peak)
            UIColor.label.withAlphaComponent(0.22).setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: w.y + height - total,
                                             width: barWidth, height: total),
                         cornerRadius: 1).fill()
            UIColor.label.withAlphaComponent(0.85).setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: w.y + height - distinct,
                                             width: barWidth, height: distinct),
                         cornerRadius: 1).fill()
        }
        w.advance(height + 4)

        if let first = days.first, let last = days.last {
            let range = "\(first.date.formatted(.dateTime.month(.abbreviated).day())) – \(last.date.formatted(.dateTime.month(.abbreviated).day()))"
            draw(range, &w, font: .systemFont(ofSize: 8), colour: .tertiaryLabel, spacingAfter: 2)
        }
        draw("Light bars are words said; dark bars are how many of them were different. The gap between the two is the part worth watching — saying more is not the same as saying more things.",
             &w, font: .systemFont(ofSize: 9), colour: .secondaryLabel, spacingAfter: 4)
    }

    private static func hourLabel(_ hour: Int) -> String {
        switch hour {
        case 0: return "12a"
        case 12: return "12p"
        case ..<12: return "\(hour)a"
        default: return "\(hour - 12)p"
        }
    }

    // MARK: Coverage

    private static func drawCoverage(_ w: inout PageWriter, _ r: UsageReport) {
        let c = r.coverage
        guard c.sceneWordCount > 0 else { return }
        sectionHeading("How much of \(c.sceneName.isEmpty ? "the board" : c.sceneName) is being used", &w)

        let pct = Int((c.usedFraction * 100).rounded())
        draw("\(c.allTimeUsedCount) of \(c.sceneWordCount) words have been pressed at least once — \(pct)%. Measured over all time, not just this period: a word used last month has been used.",
             &w, font: .systemFont(ofSize: 10), spacingAfter: 8)

        subHeading("By kind of word", &w)
        for row in c.usageByKind.prefix(8) {
            drawBarRow(&w, label: row.label,
                       detail: "\(row.used) of \(row.available)",
                       fraction: row.usedFraction)
        }

        if !c.usageByPage.isEmpty {
            subHeading("By page", &w)
            for row in c.usageByPage.prefix(10) {
                drawBarRow(&w, label: PageNaming.displayName(row.pageKey),
                           detail: "\(row.used) of \(row.available)",
                           fraction: row.usedFraction)
            }
            if c.unattributedPresses > 0 {
                draw("\(c.unattributedPresses) earlier presses were recorded before pages were, and count towards no page — so these figures understate use.",
                     &w, font: .systemFont(ofSize: 8), colour: .tertiaryLabel, spacingAfter: 4)
            }
        }

        if !c.mostUsed.isEmpty {
            subHeading("Most used", &w)
            let top = c.mostUsed.first?.count ?? 1
            for word in c.mostUsed {
                drawBarRow(&w, label: word.key, detail: "\(word.count)",
                           fraction: Double(word.count) / Double(max(top, 1)))
            }
        }

        if !c.wentQuiet.isEmpty {
            subHeading("Went quiet", &w)
            draw(c.wentQuiet.joined(separator: ", "), &w,
                 font: .systemFont(ofSize: 10), spacingAfter: 2)
            draw("Used before, and not in this period.", &w,
                 font: .systemFont(ofSize: 9), colour: .secondaryLabel, spacingAfter: 4)
        }
    }

    private static func drawBarRow(_ w: inout PageWriter, label: String,
                                   detail: String, fraction: Double) {
        let rowHeight: CGFloat = 16
        w.need(rowHeight)
        let labelWidth = w.contentWidth * 0.32
        let detailWidth: CGFloat = 58
        let barX = w.margin + labelWidth
        let barWidth = w.contentWidth - labelWidth - detailWidth

        (label as NSString).draw(
            in: CGRect(x: w.margin, y: w.y, width: labelWidth - 6, height: rowHeight),
            withAttributes: [.font: UIFont.systemFont(ofSize: 9.5)])

        let track = CGRect(x: barX, y: w.y + 4, width: barWidth, height: 6)
        UIColor.label.withAlphaComponent(0.10).setFill()
        UIBezierPath(roundedRect: track, cornerRadius: 3).fill()
        let filled = CGRect(x: barX, y: w.y + 4,
                            width: barWidth * CGFloat(max(0, min(1, fraction))), height: 6)
        UIColor.label.withAlphaComponent(fraction == 0 ? 0.10 : 0.6).setFill()
        UIBezierPath(roundedRect: filled, cornerRadius: 3).fill()

        (detail as NSString).draw(
            in: CGRect(x: barX + barWidth + 6, y: w.y, width: detailWidth, height: rowHeight),
            withAttributes: [.font: UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                             .foregroundColor: UIColor.secondaryLabel])
        w.advance(rowHeight)
    }

    // MARK: Sessions

    private static func drawSessions(_ w: inout PageWriter, _ r: UsageReport,
                                     includeUtterances: Bool) {
        guard !r.sessions.isEmpty else {
            sectionHeading("Sessions", &w)
            draw("Nothing was recorded in this period.", &w,
                 font: .systemFont(ofSize: 10), colour: .secondaryLabel)
            return
        }

        sectionHeading("Sessions", &w)
        draw("A session is a run of use with no gap longer than ten minutes.", &w,
             font: .systemFont(ofSize: 9), colour: .secondaryLabel, spacingAfter: 6)

        for session in r.sessions {
            let minutes = Int(session.duration / 60)
            var line = session.startedAt.formatted(date: .abbreviated, time: .shortened)
            if minutes >= 1 { line += " · \(minutes) min" }
            line += " · \(session.count) \(r.isSingleWord ? "words" : "said")"
            if session.distinctWordCount < session.count {
                line += " · \(session.distinctWordCount) different"
            }
            if !r.isSingleWord && session.escalatedCount > 0 {
                line += " · \(session.escalatedCount) escalated"
            }
            draw(line, &w, font: .systemFont(ofSize: 9.5, weight: .medium), spacingAfter: 2)

            if includeUtterances {
                for entry in session.entries {
                    let time = entry.createdAt.formatted(date: .omitted, time: .shortened)
                    let said = entry.sentence.isEmpty ? "—" : entry.sentence
                    draw("\(time)   \(said)", &w, font: .systemFont(ofSize: 9),
                         colour: .secondaryLabel, spacingAfter: 1, indent: 14)
                }
            }
            w.advance(4)
        }

        if !includeUtterances {
            w.advance(4)
            draw("This report shows how much and when, not what was said. A version including the sentences can be shared separately.",
                 &w, font: .systemFont(ofSize: 9), colour: .secondaryLabel)
        }
    }
}
