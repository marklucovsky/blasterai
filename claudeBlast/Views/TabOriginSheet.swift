// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  TabOriginSheet.swift
//  claudeBlast
//
//  The top of a spreadsheet tab, as the sheet shows it, to say where the
//  board starts.
//

import SwiftUI

/// A tab's top-left cells as text, lettered and numbered like the sheet. The
/// board is tinted; tap a cell to start the board there.
struct TabOriginSheet: View {
    let tab: SpreadsheetTab
    let cols: Int
    let origin: BoardWorkbook.Origin
    /// Where detection put it, for Reset.
    let detected: BoardWorkbook.Origin
    let onChoose: (BoardWorkbook.Origin) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: BoardWorkbook.Origin

    init(tab: SpreadsheetTab, cols: Int, origin: BoardWorkbook.Origin, detected: BoardWorkbook.Origin,
         onChoose: @escaping (BoardWorkbook.Origin) -> Void) {
        self.tab = tab
        self.cols = cols
        self.origin = origin
        self.detected = detected
        self.onChoose = onChoose
        _chosen = State(initialValue: origin)
    }

    private var shownRows: Int { min(max(tab.rows.count, chosen.row + 6), chosen.row + 14) }
    private var shownCols: Int {
        min(max(tab.rows.map(\.count).max() ?? 0, chosen.col + cols), chosen.col + cols + 2)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Tap the board's first cell — its top-left word. Everything above and to the left is left out.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ScrollView([.horizontal, .vertical]) {
                    Grid(horizontalSpacing: 1, verticalSpacing: 1) {
                        GridRow {
                            Text("").frame(width: 28)
                            ForEach(0..<shownCols, id: \.self) { c in
                                Text(XLSX.column(c)).font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    .frame(width: 84)
                            }
                        }
                        ForEach(0..<shownRows, id: \.self) { r in
                            GridRow {
                                Text("\(r + 1)").font(.caption2.monospaced()).foregroundStyle(.secondary)
                                    .frame(width: 28)
                                ForEach(0..<shownCols, id: \.self) { c in cell(r, c) }
                            }
                        }
                    }
                    .padding(4)
                }
                Text(chosen.cell == detected.cell ? "Starts at \(chosen.cell), as found."
                                                  : "Starts at \(chosen.cell) — found at \(detected.cell).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle(tab.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onChoose(chosen)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset to \(detected.cell)") { chosen = detected }
                        .disabled(chosen == detected)
                }
            }
        }
    }

    private func text(_ r: Int, _ c: Int) -> String {
        guard r < tab.rows.count, c < tab.rows[r].count else { return "" }
        return tab.rows[r][c]
    }

    private func cell(_ r: Int, _ c: Int) -> some View {
        let inBoard = r >= chosen.row && c >= chosen.col && c < chosen.col + cols
        let isFirst = r == chosen.row && c == chosen.col
        return Button {
            chosen = BoardWorkbook.Origin(row: r, col: c,
                                          skipped: r == detected.row && c == detected.col ? detected.skipped : [])
        } label: {
            Text(text(r, c))
                .font(.caption)
                .lineLimit(1)
                .frame(width: 84, height: 28, alignment: .leading)
                .padding(.horizontal, 4)
                .foregroundStyle(inBoard ? Color.primary : Color.secondary)
                .background(inBoard ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.05))
                .overlay {
                    if isFirst { RoundedRectangle(cornerRadius: 3).stroke(Color.accentColor, lineWidth: 2) }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(XLSX.column(c))\(r + 1) \(text(r, c))")
    }
}
