// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SpeechNormalizer.swift
//  claudeBlast
//
//  What typed text is said as. The keyboard speaks each key as it is pressed
//  and the whole line on Speak, and a voice left to itself reads `÷` as
//  nothing, `5/3` as a date, and a lone `-` as silence. See
//  `docs/keyboard-design.md`.
//

import Foundation

enum SpeechNormalizer {

    // MARK: - One key

    /// What one key press says.
    ///
    /// A letter is said lowercase whatever Shift shows: a voice reads a lone
    /// capital as "capital A" (the probe in `docs/keyboard-design.md`; the
    /// fault `SpeechSynthesizer.loneSpeech` fixes for *I*). Digits pass
    /// through. Symbols say their name, which a voice gets wrong or
    /// inconsistently on its own.
    static func key(_ key: String) -> String {
        if let name = keyNames[key] { return name }
        if key.count == 1, key.first?.isLetter == true { return key.lowercased() }
        return key
    }

    /// The names of the keys a voice gets wrong alone. The time keys say what
    /// they mean on a clock face, not their characters.
    static let keyNames: [String: String] = [
        "+": "plus", "-": "minus", "\u{2212}": "minus",
        "×": "times", "*": "times", "÷": "divided by", "/": "slash",
        "=": "equals", "<": "less than", ">": "greater than",
        "%": "percent", "$": "dollar", "¢": "cents",
        ",": "comma", ".": "period", "?": "question mark", "!": "exclamation mark",
        "'": "apostrophe", "\u{2019}": "apostrophe", "\"": "quote",
        ":": "colon", ";": "semicolon", "(": "open bracket", ")": "close bracket",
        "&": "and", "@": "at", "#": "number",
        ":00": "o'clock", ":15": "fifteen", ":30": "thirty", ":45": "forty-five",
    ]

    // MARK: - A tile

    /// What a word tile says, alone or in the message box line.
    ///
    /// A one-character tile is a key: the Letters pack's tiles are named
    /// "A", "B", …, and a voice reads a lone capital as "capital A" (Mark,
    /// 2026-11-18). The pronoun *I* is the exception in a line, where it is a
    /// word; alone, `SpeechSynthesizer.loneSpeech` says it by tile key, and
    /// the Letters pack's *I* (`wordClass` "letter") says its letter name.
    /// Anything longer is a word and is left as it is.
    static func tile(_ value: String, wordClass: String? = nil, inLine: Bool = false) -> String {
        guard value.count == 1 else { return value }
        if inLine, value == "I", wordClass != "letter" { return value }
        return key(value)
    }

    // MARK: - A line

    /// What a typed line says on Speak.
    ///
    /// Words are left alone — "I am 7" is said as typed. Only the forms a
    /// voice misreads are rewritten: times (`3:00` → "3 o'clock"), fractions
    /// (`3/4` → "3 fourths"), money, percent, and arithmetic operators between
    /// numbers (`2 + 2 = 4` → "2 plus 2 equals 4"). A hyphen between letters
    /// stays a hyphen: "x-ray" is not "x minus ray".
    ///
    /// A line that is one key on its own (`+`, `:15`) says the key's name.
    static func line(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let name = keyNames[trimmed] { return name }
        // One letter alone is a key, not a word: "A" would be "capital A".
        if trimmed.count == 1 { return key(trimmed) }

        var s = trimmed
        s = replace(s, #"\b(\d{1,2}):00\b"#) { "\($0[1]) o'clock" }
        s = replace(s, #"\b(\d{1,2}):(\d{2})\b"#) { "\($0[1]) \($0[2])" }
        s = replace(s, #"(?<![\d:]):(00|15|30|45)\b"#) { keyNames[":" + $0[1]] ?? $0[0] }
        s = replace(s, #"\$(\d+)\.(\d{2})\b"#) { m in
            "\(m[1]) \(Int(m[1]) == 1 ? "dollar" : "dollars") and \(m[2]) cents"
        }
        s = replace(s, #"\$(\d+)\b"#) { "\($0[1]) \(Int($0[1]) == 1 ? "dollar" : "dollars")" }
        s = replace(s, #"(\d)\s*%"#) { "\($0[1]) percent" }
        // A mixed number, as the math helper shows one: `3 1/3` is "3 and 1 third".
        s = replace(s, #"\b(\d+) (\d+)/(\d+)\b"#) { "\($0[1]) and \(fraction($0[2], over: $0[3]))" }
        s = replace(s, #"\b(\d+)/(\d+)\b"#) { fraction($0[1], over: $0[2]) }
        // Operators between numbers, or standing alone between spaces.
        let operand = #"(?:(?<=\d)|(?<=\s)|^)"#
        let next = #"(?=\s*[\d\-−(]|\s|$)"#
        for (symbol, word) in [("+", "plus"), ("×", "times"), ("*", "times"),
                               ("÷", "divided by"), ("=", "equals"),
                               ("<", "is less than"), (">", "is greater than"),
                               ("\u{2212}", "minus")] {
            s = replace(s, operand + #"\s*"# + NSRegularExpression.escapedPattern(for: symbol)
                        + #"\s*"# + next) { _ in " \(word) " }
        }
        // A letter x between numbers is times: a QWERTY keyboard has no `×`,
        // and a voice reads "6 x 7" as "six x seven" (Mark, 2026-11-18).
        s = replace(s, #"(?<=\d)\s*[xX]\s*(?=\d)"#) { _ in " times " }
        // `-` is minus only between numbers. Anywhere else it is a hyphen or
        // a dash, and "I want - no" is not arithmetic.
        s = replace(s, #"(?<=\d)\s*-\s*(?=\d)"#) { _ in " minus " }
        s = replace(s, #"\s+"#) { _ in " " }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// `3/4` → "3 fourths", `1/2` → "1 half", `5/3` → "5 thirds". A
    /// denominator past twelve, or zero, is read "over", as a teacher would.
    static func fraction(_ numerator: String, over denominator: String) -> String {
        guard let d = Int(denominator), (2...12).contains(d), let n = Int(numerator) else {
            return "\(numerator) over \(denominator)"
        }
        let singular = d == 2 ? "half" : ordinal(d)
        let plural = d == 2 ? "halves" : singular + "s"
        return "\(numerator) \(n == 1 ? singular : plural)"
    }

    /// Spelled out by hand: English only, like the rest of the keyboard, and
    /// a formatter's spell-out gives "third" in one locale and a digit in another.
    private static func ordinal(_ n: Int) -> String {
        ["", "", "half", "third", "fourth", "fifth", "sixth", "seventh",
         "eighth", "ninth", "tenth", "eleventh", "twelfth"][n]
    }

    /// Replace every match of `pattern`, with the match's groups.
    private static func replace(_ text: String, _ pattern: String,
                                with transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: match.range.location - last))
            let groups = (0..<match.numberOfRanges).map { i -> String in
                let r = match.range(at: i)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            out += transform(groups)
            last = match.range.location + match.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}
