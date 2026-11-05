// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  Spreadsheet.swift
//  claudeBlast
//
//  Reads and writes the cell text of spreadsheets: .xlsx workbooks, CSV and
//  tab-separated text. Values only — no styles, no formulas (a formula's last
//  result is stored beside it and is what is read).
//

import Foundation
import Compression

/// One tab of a spreadsheet: its name and its cells' text, row by row.
///
/// Rows are as long as their last non-empty cell; an empty row is `[]`.
struct SpreadsheetTab: Equatable {
    var name: String
    var rows: [[String]]
}

enum Spreadsheet {
    enum ReadError: LocalizedError, Equatable {
        case notAWorkbook
        case unsupported(String)
        case unreadableText

        var errorDescription: String? {
            switch self {
            case .notAWorkbook: "This isn't a spreadsheet file BlasterAI can read."
            case .unsupported(let what): "This spreadsheet uses \(what), which BlasterAI can't read."
            case .unreadableText: "The file's text couldn't be read."
            }
        }
    }

    static let extensions: Set<String> = ["xlsx", "csv", "tsv", "txt"]

    /// The tabs of a file, by its extension. A CSV or text file is one tab,
    /// named `name`.
    static func tabs(from data: Data, fileExtension: String, name: String) throws -> [SpreadsheetTab] {
        switch fileExtension.lowercased() {
        case "xlsx": return try XLSX.read(data)
        case "tsv", "txt": return [SpreadsheetTab(name: name, rows: try rows(fromDelimited: text(data), separator: "\t"))]
        default:
            // A zip that came in with the wrong extension is still a workbook.
            if data.starts(with: [0x50, 0x4B]) { return try XLSX.read(data) }
            let text = try text(data)
            let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
            let separator: Character = firstLine.contains("\t") && !firstLine.contains(",") ? "\t" : ","
            return [SpreadsheetTab(name: name, rows: rows(fromDelimited: text, separator: separator))]
        }
    }

    private static func text(_ data: Data) throws -> String {
        var data = data
        if data.starts(with: [0xEF, 0xBB, 0xBF]) { data = data.dropFirst(3) }
        if let text = String(data: data, encoding: .utf8) { return text }
        // Excel on Windows still saves "CSV" as the system code page.
        if let text = String(data: data, encoding: .windowsCP1252) { return text }
        throw ReadError.unreadableText
    }

    /// RFC 4180: a quoted cell may hold the separator, newlines and `""` for a
    /// quote. Trailing empty cells and trailing empty rows are dropped.
    static func rows(fromDelimited text: String, separator: Character = ",") -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cell = ""
        var quoted = false
        var chars = text.makeIterator()
        var pending: Character? = nil
        func next() -> Character? {
            if let c = pending { pending = nil; return c }
            return chars.next()
        }
        func endRow() {
            row.append(cell); cell = ""
            while row.last?.isEmpty == true { row.removeLast() }
            rows.append(row); row = []
        }
        var sawAny = false
        while let c = next() {
            sawAny = true
            if quoted {
                if c == "\"" {
                    if let n = next() {
                        if n == "\"" { cell.append("\"") } else { quoted = false; pending = n }
                    } else { quoted = false }
                } else {
                    cell.append(c)
                }
                continue
            }
            switch c {
            case "\"" where cell.isEmpty: quoted = true
            case separator: row.append(cell); cell = ""
            case "\r\n", "\n", "\r": endRow()
            default: cell.append(c)
            }
        }
        if sawAny, !(cell.isEmpty && row.isEmpty) { endRow() }
        while rows.last?.isEmpty == true { rows.removeLast() }
        return rows
    }

    /// CSV text, quoting only the cells that need it.
    static func csv(_ rows: [[String]]) -> String {
        rows.map { row in
            row.map { cell in
                cell.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" })
                    ? "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : cell
            }.joined(separator: ",")
        }.joined(separator: "\r\n") + "\r\n"
    }
}

// MARK: - XLSX

/// The smallest part of Office Open XML that carries a workbook's text: the
/// tab list, the shared string table and each tab's cells.
enum XLSX {
    static func read(_ data: Data) throws -> [SpreadsheetTab] {
        let zip = try Zip(data)
        guard let workbook = try zip.file("xl/workbook.xml") else { throw Spreadsheet.ReadError.notAWorkbook }
        let sheets = WorkbookParser.parse(workbook)
        let rels = try zip.file("xl/_rels/workbook.xml.rels").map(RelsParser.parse) ?? [:]
        let strings = try zip.file("xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []
        return try sheets.map { sheet in
            var path = rels[sheet.relID] ?? "worksheets/sheet\(sheet.index + 1).xml"
            path = path.hasPrefix("/") ? String(path.dropFirst()) : "xl/" + path
            guard let xml = try zip.file(path) else { return SpreadsheetTab(name: sheet.name, rows: []) }
            return SpreadsheetTab(name: sheet.name, rows: SheetParser.parse(xml, strings: strings))
        }
    }

    /// A workbook of `tabs`, every cell an inline string.
    static func write(_ tabs: [SpreadsheetTab]) -> Data {
        var parts: [(path: String, data: Data)] = []
        func add(_ path: String, _ xml: String) { parts.append((path, Data(xml.utf8))) }
        let overrides = tabs.indices.map {
            "<Override PartName=\"/xl/worksheets/sheet\($0 + 1).xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
        }.joined()
        add("[Content_Types].xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
            <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
            <Default Extension="xml" ContentType="application/xml"/>\
            <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
            <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
            \(overrides)</Types>
            """)
        add("_rels/.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
            </Relationships>
            """)
        let sheetList = tabs.enumerated().map { i, tab in
            "<sheet name=\"\(escape(sheetName(tab.name, index: i, in: tabs)))\" sheetId=\"\(i + 1)\" r:id=\"rId\(i + 1)\"/>"
        }.joined()
        add("xl/workbook.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" \
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
            <sheets>\(sheetList)</sheets></workbook>
            """)
        let sheetRels = tabs.indices.map {
            "<Relationship Id=\"rId\($0 + 1)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet\($0 + 1).xml\"/>"
        }.joined()
        add("xl/_rels/workbook.xml.rels", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
            \(sheetRels)<Relationship Id="rId\(tabs.count + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
            </Relationships>
            """)
        add("xl/styles.xml", """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
            <fonts count="1"><font><sz val="11"/><name val="Calibri"/></font></fonts>\
            <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
            <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
            <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
            <cellXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/></cellXfs>\
            </styleSheet>
            """)
        for (i, tab) in tabs.enumerated() {
            let rows = tab.rows.enumerated().compactMap { r, row -> String? in
                let cells = row.enumerated().compactMap { c, text -> String? in
                    guard !text.isEmpty else { return nil }
                    return "<c r=\"\(column(c))\(r + 1)\" t=\"inlineStr\"><is><t xml:space=\"preserve\">\(escape(text))</t></is></c>"
                }
                return cells.isEmpty ? nil : "<row r=\"\(r + 1)\">\(cells.joined())</row>"
            }.joined()
            add("xl/worksheets/sheet\(i + 1).xml", """
                <?xml version="1.0" encoding="UTF-8" standalone="yes"?>\
                <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
                <sheetData>\(rows)</sheetData></worksheet>
                """)
        }
        return ZipWriter.archive(parts)
    }

    /// `A`, `B` … `Z`, `AA` for a zero-based column.
    static func column(_ index: Int) -> String {
        var n = index + 1, name = ""
        while n > 0 {
            let r = (n - 1) % 26
            name = String(UnicodeScalar(UInt8(65 + r))) + name
            n = (n - 1) / 26
        }
        return name
    }

    /// Zero-based column of a reference like `AB12`.
    static func columnIndex(ofReference ref: String) -> Int? {
        var n = 0, any = false
        for ch in ref.uppercased().unicodeScalars {
            guard ch.value >= 65, ch.value <= 90 else { break }
            n = n * 26 + Int(ch.value - 64); any = true
        }
        return any ? n - 1 : nil
    }

    /// A legal, unique tab name: at most 31 characters, none of `[]:*?/\`.
    static func sheetName(_ name: String, index: Int, in tabs: [SpreadsheetTab]) -> String {
        let bad = CharacterSet(charactersIn: "[]:*?/\\")
        var clean = String(name.unicodeScalars.filter { !bad.contains($0) }).prefix(31)
        if clean.isEmpty { clean = "Sheet\(index + 1)" }
        let earlier = tabs.prefix(index).map { $0.name.lowercased() }
        if earlier.contains(String(clean).lowercased()) { clean = "\(clean.prefix(27)) \(index + 1)" }
        return String(clean)
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for ch in text.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // XML 1.0 forbids most control characters even escaped.
                if ch.value < 0x20, ch != "\t", ch != "\n", ch != "\r" { continue }
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }
}

// MARK: - XML parts

/// Element names without their namespace prefix: Excel writes `sheet`,
/// some generators `x:sheet`.
private func localName(_ name: String) -> Substring {
    name.split(separator: ":").last ?? Substring(name)
}

private final class WorkbookParser: NSObject, XMLParserDelegate {
    struct Sheet { var name: String; var relID: String; var index: Int }
    var sheets: [Sheet] = []

    static func parse(_ data: Data) -> [Sheet] {
        let delegate = WorkbookParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.sheets
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard localName(name) == "sheet" else { return }
        let relID = attributes.first { $0.key.hasSuffix(":id") }?.value ?? ""
        sheets.append(Sheet(name: attributes["name"] ?? "Sheet\(sheets.count + 1)",
                            relID: relID, index: sheets.count))
    }
}

private final class RelsParser: NSObject, XMLParserDelegate {
    var targets: [String: String] = [:]

    static func parse(_ data: Data) -> [String: String] {
        let delegate = RelsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.targets
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard localName(name) == "Relationship", let id = attributes["Id"],
              let target = attributes["Target"] else { return }
        targets[id] = target
    }
}

/// Each `<si>` is one string: its `<t>` runs joined, less phonetic guides.
private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    private var current: String?
    private var inText = false
    private var inPhonetic = false

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        switch localName(name) {
        case "si": current = ""
        case "t": inText = true
        case "rPh": inPhonetic = true
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch localName(name) {
        case "si": strings.append(current ?? ""); current = nil
        case "t": inText = false
        case "rPh": inPhonetic = false
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inText, !inPhonetic { current?.append(string) }
    }
}

private final class SheetParser: NSObject, XMLParserDelegate {
    let strings: [String]
    var cells: [Int: [Int: String]] = [:]
    private var row = 0
    private var col = 0
    private var type = ""
    private var value: String?
    private var inValue = false
    private var inInline = false

    init(strings: [String]) { self.strings = strings }

    static func parse(_ data: Data, strings: [String]) -> [[String]] {
        let delegate = SheetParser(strings: strings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        guard let last = delegate.cells.keys.max() else { return [] }
        return (0...last).map { r in
            guard let row = delegate.cells[r], let width = row.keys.max() else { return [] }
            return (0...width).map { row[$0] ?? "" }
        }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        switch localName(name) {
        case "row":
            row = attributes["r"].flatMap(Int.init).map { $0 - 1 } ?? row
            col = 0
        case "c":
            if let ref = attributes["r"], let c = XLSX.columnIndex(ofReference: ref) { col = c }
            type = attributes["t"] ?? ""
            value = nil
        case "v": inValue = true; value = value ?? ""
        case "is": inInline = true; value = value ?? ""
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch localName(name) {
        case "v": inValue = false
        case "is": inInline = false
        case "c":
            var text = value ?? ""
            switch type {
            case "s": text = Int(text).flatMap { strings.indices.contains($0) ? strings[$0] : nil } ?? ""
            case "b": text = text == "1" ? "TRUE" : "FALSE"
            default: break
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { cells[row, default: [:]][col] = text }
            col += 1
        case "row":
            row += 1
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inValue || inInline { value?.append(string) }
    }
}

// MARK: - Zip

/// Reads the entries of a zip archive: stored or deflated, not Zip64.
private struct Zip {
    private let bytes: [UInt8]
    private var entries: [String: (method: UInt16, compressed: Int, size: Int, offset: Int)] = [:]

    init(_ data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw Spreadsheet.ReadError.notAWorkbook }
        // The end-of-central-directory record, behind an optional comment.
        var eocd = -1
        var i = bytes.count - 22
        while i >= max(0, bytes.count - 22 - 65_535) {
            if u32(i) == 0x0605_4B50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw Spreadsheet.ReadError.notAWorkbook }
        let count = Int(u16(eocd + 10))
        var p = Int(u32(eocd + 16))
        if u32(eocd + 16) == 0xFFFF_FFFF { throw Spreadsheet.ReadError.unsupported("Zip64") }
        for _ in 0..<count {
            guard p + 46 <= bytes.count, u32(p) == 0x0201_4B50 else { throw Spreadsheet.ReadError.notAWorkbook }
            let nameLength = Int(u16(p + 28)), extra = Int(u16(p + 30)), comment = Int(u16(p + 32))
            guard p + 46 + nameLength <= bytes.count else { throw Spreadsheet.ReadError.notAWorkbook }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLength)], as: UTF8.self)
            entries[name] = (u16(p + 10), Int(u32(p + 20)), Int(u32(p + 24)), Int(u32(p + 42)))
            p += 46 + nameLength + extra + comment
        }
    }

    func file(_ name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        let p = entry.offset
        guard p + 30 <= bytes.count, u32(p) == 0x0403_4B50 else { throw Spreadsheet.ReadError.notAWorkbook }
        let start = p + 30 + Int(u16(p + 26)) + Int(u16(p + 28))
        guard start + entry.compressed <= bytes.count else { throw Spreadsheet.ReadError.notAWorkbook }
        let source = bytes[start..<(start + entry.compressed)]
        switch entry.method {
        case 0: return Data(source)
        case 8:
            guard entry.size > 0 else { return Data() }
            var out = [UInt8](repeating: 0, count: entry.size)
            let written = source.withUnsafeBufferPointer { src in
                // Apple's ZLIB is raw DEFLATE, which is what a zip holds.
                compression_decode_buffer(&out, entry.size, src.baseAddress!, entry.compressed,
                                          nil, COMPRESSION_ZLIB)
            }
            guard written == entry.size else { throw Spreadsheet.ReadError.notAWorkbook }
            return Data(out)
        default:
            throw Spreadsheet.ReadError.unsupported("compression method \(entry.method)")
        }
    }

    private func u16(_ i: Int) -> UInt16 { UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8 }
    private func u32(_ i: Int) -> UInt32 {
        UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
    }
}
