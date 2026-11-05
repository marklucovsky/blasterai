// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  BoardOrigin.swift
//  claudeBlast
//
//  Where a tab's board starts, when the sheet does not start with it.
//

import Foundation

extension BoardWorkbook {
    /// The first cell of a tab's board, and what came before it.
    ///
    /// People write more than a board in a sheet: a title, an owner and a
    /// description, notes, row numbers and column letters. Read from A1, all of
    /// it became words to settle — or worse, real tiles: a label column 1, 2, 3
    /// placed three number words. So each tab's board is found first, and the
    /// import preview says where, for the author to correct.
    struct Origin: Equatable {
        var row: Int
        var col: Int
        var skipped: [Skip] = []

        static let topLeft = Origin(row: 0, col: 0)

        /// "B5", as the sheet names the cell.
        var cell: String { "\(XLSX.column(col))\(row + 1)" }

        /// "Starts at A5 · skipped 2 rows of details" — nil when the board is
        /// simply at A1.
        var summary: String? {
            guard row > 0 || col > 0 || !skipped.isEmpty else { return nil }
            let what = skipped.map(\.description)
            return "Starts at \(cell)" + (what.isEmpty ? "" : " · skipped " + what.joined(separator: ", "))
        }
    }

    enum Skip: Equatable {
        /// `Owner: Mark` rows.
        case details(Int)
        /// Rows of text that are not the board.
        case title(Int)
        case columnLetters
        case rowNumbers
        case emptyColumns(Int)
        /// A `#board` cell says where it starts.
        case marker

        var description: String {
            switch self {
            case .details(let n): n == 1 ? "a details row" : "\(n) details rows"
            case .title(let n): n == 1 ? "a title row" : "\(n) title rows"
            case .columnLetters: "the column labels"
            case .rowNumbers: "the row labels"
            case .emptyColumns(let n): n == 1 ? "an empty column" : "\(n) empty columns"
            case .marker: "everything above #board"
            }
        }
    }

    /// The marker cell an author can write above a board to say where it is.
    static let boardMarker = "#board"

    /// Where `tab`'s board starts.
    ///
    /// - A `#board` cell wins: the board starts in the row below it.
    /// - Otherwise leading rows are skipped while they are details (`Owner:
    ///   Mark`), labels (`1 2 3…`, `A B C…`) or a title — a cell or two of
    ///   text that does not read as the board. Empty rows among them go
    ///   too — but empty rows before any of them are the board's own.
    /// - Then a column of row labels down the left, and empty columns the
    ///   board would otherwise spill past `cols` to make room for.
    ///
    /// - Parameter reads: whether a cell's text is something a board holds.
    static func detectOrigin(_ tab: SpreadsheetTab, cols: Int, reads: (String) -> Bool) -> Origin {
        let rows = tab.rows.map { $0.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        for (r, row) in rows.enumerated() {
            if let c = row.firstIndex(where: { $0.lowercased() == boardMarker }) {
                return Origin(row: r + 1, col: c, skipped: [.marker])
            }
        }

        var origin = Origin.topLeft
        var details = 0, titles = 0, sawJunk = false
        var firstBoardRow = rows.count
        for (r, row) in rows.enumerated() {
            let filled = row.filter { !$0.isEmpty }
            if filled.isEmpty { continue }
            if isDetailsRow(row) {
                details += 1; sawJunk = true
            } else if isLabelLine(filled), wordsFollow(rows, after: r) {
                // A numbers or letters page starts 1…10 or A…J too; it is a
                // label only when words, not more of the sequence, come next.
                origin.skipped.append(.columnLetters); sawJunk = true
            } else if filled.count <= 2, !filled.contains(where: reads),
                      filled.contains(where: { isProse($0) }) {
                // A title or a note: a cell or two of text that is not the
                // board. A wide row is board, words still to settle and all.
                titles += 1; sawJunk = true
            } else {
                firstBoardRow = r
                break
            }
        }
        if sawJunk { origin.row = min(firstBoardRow, rows.count) }
        if details > 0 { origin.skipped.insert(.details(details), at: 0) }
        if titles > 0 { origin.skipped.append(.title(titles)) }

        // Row labels down the left of the board.
        let body = rows.dropFirst(origin.row)
        let firstColumn = body.compactMap { $0.first }.filter { !$0.isEmpty }
        if firstColumn.count >= 2, isLabelLine(firstColumn) {
            origin.col = 1
            origin.skipped.append(.rowNumbers)
        }
        // A board typed starting further right, that would otherwise run off
        // the board's last column.
        let widths = body.map { row in row.lastIndex(where: { !$0.isEmpty }).map { $0 + 1 } ?? 0 }
        if let widest = widths.max(), widest - origin.col > cols {
            let leading = body.compactMap { row -> Int? in
                guard let first = row.firstIndex(where: { !$0.isEmpty }) else { return nil }
                return first
            }.min() ?? origin.col
            let shift = min(leading, widest - cols) - origin.col
            if shift > 0 {
                origin.col += shift
                origin.skipped.append(.emptyColumns(shift))
            }
        }
        return origin
    }

    /// The next row with anything in it holds words, not more numbers or
    /// letters.
    private static func wordsFollow(_ rows: [[String]], after r: Int) -> Bool {
        guard let next = rows.dropFirst(r + 1).first(where: { $0.contains { !$0.isEmpty } }) else { return false }
        let filled = next.filter { !$0.isEmpty }
        let sequenceLike = filled.allSatisfy { Int($0) != nil || ($0.count == 1 && $0.first?.isLetter == true) }
        return !sequenceLike
    }

    /// Plain text of two words or more: a title or a note. A cell written in
    /// the board's grammar (`go > places`, `cat, animal`) is never prose.
    static func isProse(_ text: String) -> Bool {
        !text.contains(">") && !text.contains(",")
            && text.split(whereSeparator: \.isWhitespace).count >= 2
    }

    /// `Owner: Mark` — a label ending in a colon, and at most a value.
    static func isDetailsRow(_ row: [String]) -> Bool {
        let filled = row.filter { !$0.isEmpty }
        guard let first = filled.first, filled.count <= 2 else { return false }
        return first.hasSuffix(":") && first.count > 1
    }

    /// The details a sheet's top rows give, by lowercased label: `name`,
    /// `description`, `owner`.
    static func details(of tab: SpreadsheetTab) -> [String: String] {
        var out: [String: String] = [:]
        for row in tab.rows {
            let filled = row.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            guard isDetailsRow(filled), filled.count == 2 else { continue }
            out[String(filled[0].dropLast()).lowercased()] = filled[1]
        }
        return out
    }

    /// `1 2 3…`, `A B C…`, `R1 R2…`, `Row 1…`, `Col A…`: consecutive from the
    /// start, at least two of them.
    static func isLabelLine(_ cells: [String]) -> Bool {
        guard cells.count >= 2 else { return false }
        let bare = cells.map { cell -> String in
            var s = cell.lowercased()
            for prefix in ["row ", "col ", "column ", "row", "col", "r", "c"] where s.hasPrefix(prefix) {
                let rest = String(s.dropFirst(prefix.count))
                if Int(rest) != nil || (rest.count == 1 && rest.first?.isLetter == true && prefix.count > 1) {
                    s = rest
                    break
                }
            }
            return s.trimmingCharacters(in: .whitespaces)
        }
        if let numbers = Optional(bare.compactMap(Int.init)), numbers.count == bare.count {
            return numbers == Array(numbers[0]..<(numbers[0] + numbers.count)) && (numbers[0] == 0 || numbers[0] == 1)
        }
        let letters = bare.map { $0.uppercased() }
        guard letters.allSatisfy({ $0.count == 1 && ($0.first?.isLetter ?? false) }) else { return false }
        let expected = (0..<letters.count).map { XLSX.column($0) }
        return letters == expected
    }

    /// Excel's and Sheets' own name for a tab nobody named.
    static func isDefaultTabName(_ name: String) -> Bool {
        name.range(of: #"^\s*(sheet|tab|blad|hoja|feuil)\s*\d*\s*$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
