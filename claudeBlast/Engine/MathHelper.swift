// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MathHelper.swift
//  claudeBlast
//
//  The numbers page's `?` key: a sum typed with a question in it is worked
//  out a step at a time (Mark, 2026-11-20). See `docs/keyboard-design.md`.
//
//    1+2+3+4=?    adds up, one step at a time: 1 + 2 = 3, 3 + 3 = 6, 6 + 4 = 10
//    1+2+3+4?     the same; the `?` asks for the `=` and the answer
//    3+?=7        finds the missing number: 7 − 3 = 4
//    2+2=5?       checks an answer: "Not quite: 2 + 2 = 4"
//    3?5          picks the sign: 3 < 5
//
//  Exact arithmetic (fractions, not floating point), the usual order of
//  operations, and no AI: what is worked out is worked out here.
//

import Foundation

enum MathHelper {

    enum Outcome: Equatable {
        case solved(Solution)
        /// Not a question yet — `3+?` before its `= 7`. The `?` is just typed.
        case incomplete
        case cannot(Reason)
    }

    enum Reason: Equatable {
        case notMath, startWithANumber, divideByZero, tooBig, oneQuestionAtATime, noNumberWorks, anyNumberWorks
        case wholePowersOnly, noRootOfNegative

        /// Said and shown, to a child.
        var message: String {
            switch self {
            case .notMath: "I can only help with numbers."
            case .startWithANumber: "Start with a number."
            case .wholePowersOnly: "I can only do whole-number powers."
            case .noRootOfNegative: "A negative number has no square root here."
            case .divideByZero: "Nobody can divide by zero!"
            case .tooBig: "That number is too big for me."
            case .oneQuestionAtATime: "One question mark at a time."
            case .noNumberWorks: "No number works there."
            case .anyNumberWorks: "Any number works there!"
            }
        }
    }

    struct Solution: Equatable {
        enum Kind: Equatable {
            /// A number found: the answer to a sum, or the missing number.
            case answer(String)
            /// An answer checked.
            case check(correct: Bool)
            /// The sign between two numbers.
            case compare(String)
        }
        let kind: Kind
        /// Each step as said: `1 + 2 = 3`.
        let steps: [String]
        /// Each step as shown, in place: one per step (`Frame`).
        let frames: [Frame]
        /// The last card: the sum with its answer, `1 + 2 + 3 + 4 = 10`, or
        /// the verdict, `Yes! 2 + 2 = 4`.
        let summary: String
        /// What each `?` in the line becomes, by its place among the line's
        /// question marks (0 is the first). Absent: it stays.
        let edits: [Int: String]
    }

    /// Typed text that is a sum or a piece of one: `2`, `+`, `1+1=2`, `3+?`,
    /// `6x7`. Not a word, and not `x` alone.
    static func isMathText(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }
        let hasDigit = text.contains { $0.isASCII && $0.isNumber }
        return text.allSatisfy { c in
            (c.isASCII && c.isNumber) || "+-\u{2212}×÷*/=<>?.%$:()^²³√→".contains(c)
                || (hasDigit && (c == "x" || c == "X"))
        }
    }

    /// A whole sum, answered: `1+1=2`, `3<5`. What comes after it is a new one.
    static func isFinishedStatement(_ text: String) -> Bool {
        guard isMathText(text), !text.contains("?"),
              let last = text.last, !"=<>".contains(last) else { return false }
        return text.contains { "=<>".contains($0) }
    }

    static func solve(_ line: String) -> Outcome {
        do {
            let tokens = try tokenize(line)
            guard !tokens.isEmpty else { return .incomplete }
            switch tokens.first {
            case .op(let op) where op != .minus: return .cannot(.startWithANumber)
            case .relation: return .cannot(.startWithANumber)
            default: return try interpret(tokens)
            }
        } catch let failure as Failure {
            return failure.outcome
        } catch MathHelperError.divideByZero {
            return .cannot(.divideByZero)
        } catch MathHelperError.tooBig {
            return .cannot(.tooBig)
        } catch MathHelperError.wholePowersOnly {
            return .cannot(.wholePowersOnly)
        } catch MathHelperError.negativeRoot {
            return .cannot(.noRootOfNegative)
        } catch {
            return .cannot(.notMath)
        }
    }

    // MARK: - Reading the line

    enum Op: Equatable {
        case plus, minus, times, divide
        /// `2^5`, `3²`: before × and ÷, and right to left (`2^3^2` is 2^9).
        case power
        var symbol: String {
            switch self {
            case .plus: "+"; case .minus: "\u{2212}"; case .times: "×"; case .divide: "÷"; case .power: "^"
            }
        }
        var precedence: Int {
            switch self {
            case .plus, .minus: 1
            case .times, .divide: 2
            case .power: 3
            }
        }
    }

    enum Relation: Equatable {
        case equal, less, greater
        var symbol: String { switch self { case .equal: "="; case .less: "<"; case .greater: ">" } }
        func holds(_ a: Rational, _ b: Rational) -> Bool {
            switch self { case .equal: a == b; case .less: a < b; case .greater: a > b }
        }
        static func between(_ a: Rational, _ b: Rational) -> Relation {
            a == b ? .equal : a < b ? .less : .greater
        }
    }

    enum Token: Equatable {
        case number(Rational)
        case op(Op)
        case relation(Relation)
        /// A `?`, with its place among the line's question marks.
        case question(Int)
        case open, close
        /// `√`, the square root of what follows it.
        case root
    }

    private struct Failure: Error {
        let outcome: Outcome
        static func cannot(_ r: Reason) -> Failure { Failure(outcome: .cannot(r)) }
        static let incomplete = Failure(outcome: .incomplete)
    }

    private static func tokenize(_ line: String) throws -> [Token] {
        var tokens: [Token] = []
        var questions = 0
        let chars = Array(line)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isASCII, c.isNumber || c == "." {
                var text = ""
                while i < chars.count, chars[i].isASCII, chars[i].isNumber || chars[i] == "." {
                    text.append(chars[i]); i += 1
                }
                tokens.append(.number(try Rational(decimal: text)))
                continue
            }
            switch c {
            case "+": tokens.append(.op(.plus))
            case "-", "\u{2212}", "\u{2013}": tokens.append(.op(.minus))
            // A letter x is times: QWERTY has no `×` (as in `SpeechNormalizer`).
            case "×", "*", "x", "X": tokens.append(.op(.times))
            case "÷", "/": tokens.append(.op(.divide))
            case "=": tokens.append(.relation(.equal))
            case "<": tokens.append(.relation(.less))
            case ">": tokens.append(.relation(.greater))
            case "?": tokens.append(.question(questions)); questions += 1
            case "(", "[": tokens.append(.open)
            case ")", "]": tokens.append(.close)
            case "^": tokens.append(.op(.power))
            // The calculator's x² key types `²`: a power of two.
            case "²": tokens += [.op(.power), .number(Rational(2))]
            case "³": tokens += [.op(.power), .number(Rational(3))]
            case "√": tokens.append(.root)
            default: throw Failure.cannot(.notMath)
            }
            i += 1
        }
        return tokens
    }

    // MARK: - What is being asked

    private static func interpret(_ tokens: [Token]) throws -> Outcome {
        let questions = tokens.compactMap { if case .question(let q) = $0 { q } else { nil } }

        // Every `?` a number to find: `1+2=?`, `3+?=7`, `?=2×4`.
        if questions.count == 1, let sides = try? equation(tokens), sides.relation == .equal {
            return .solved(try findUnknown(sides, marker: nil))
        }

        // A trailing `?` asks about what comes before it.
        if case .question(let marker) = tokens.last {
            let rest = Array(tokens.dropLast())
            if rest.isEmpty { return .incomplete }
            if endsOpen(rest) { return .incomplete }
            let inner = questions.count - 1
            if inner > 1 { throw Failure.cannot(.oneQuestionAtATime) }
            if inner == 1 {
                if let sides = try? equation(rest), sides.relation == .equal {
                    return .solved(try findUnknown(sides, marker: marker))
                }
                if let solution = try compare(rest, marker: marker) { return .solved(solution) }
                throw Failure.cannot(.notMath)
            }
            let sides = try equation(rest)
            if let relation = sides.relation, let right = sides.right {
                return .solved(try check(sides.left, relation, right, marker: marker))
            }
            // `3?` is the start of `3?5`, not a question about 3.
            if case .number = sides.left { return .incomplete }
            return .solved(try evaluate(sides.left, marker: marker))
        }

        if endsOpen(tokens) { return .incomplete }
        if questions.count > 1 { throw Failure.cannot(.oneQuestionAtATime) }
        if questions.count == 1, let solution = try compare(tokens, marker: nil) { return .solved(solution) }
        return .incomplete
    }

    /// Ends on a sign, or on a `?` right after one: still being typed.
    private static func endsOpen(_ tokens: [Token]) -> Bool {
        var t = tokens[...]
        if case .question = t.last, t.count > 1 {
            switch t[t.endIndex - 2] {
            case .op, .relation, .open, .root: return true
            default: break
            }
            t = t.dropLast()
        }
        switch t.last {
        case .op, .relation, .open, .root: return true
        default: return false
        }
    }

    // MARK: - Parsing

    indirect enum Node: Equatable {
        case number(Rational)
        case unknown(Int)
        case binary(Op, Node, Node)
        /// `√9`.
        case root(Node)

        var hasUnknown: Bool {
            switch self {
            case .number: false
            case .unknown: true
            case .binary(_, let l, let r): l.hasUnknown || r.hasUnknown
            case .root(let x): x.hasUnknown
            }
        }

        var isNumber: Bool { if case .number = self { true } else { false } }

        /// The sum with its `?` filled in.
        func filling(_ value: Rational?) -> Node {
            switch self {
            case .number: self
            case .unknown: value.map(Node.number) ?? self
            case .binary(let op, let l, let r): .binary(op, l.filling(value), r.filling(value))
            case .root(let x): .root(x.filling(value))
            }
        }

        /// As typed, tidied: `1 + 2 × 3`, `2 × (3 + 4)`, `3²`, `√9`. Brackets
        /// only where the order needs them.
        func shown(filling unknown: Rational? = nil) -> String {
            MathHelper.join(MathHelper.layout(filling(unknown)).tokens)
        }
    }

    /// Pieces of a sum as one line: spaced, except inside brackets, after `√`
    /// and before `²`.
    static func join(_ tokens: [String]) -> String {
        var out = ""
        for (i, t) in tokens.enumerated() {
            let tight = i == 0 || ["(", "√"].contains(tokens[i - 1]) || [")", "²", "³"].contains(t)
            out += (tight ? "" : " ") + t
        }
        return out
    }

    private struct Sides {
        let left: Node
        let relation: Relation?
        let right: Node?
    }

    private static func equation(_ tokens: [Token]) throws -> Sides {
        let relations = tokens.indices.filter { if case .relation = tokens[$0] { true } else { false } }
        guard relations.count <= 1 else { throw Failure.cannot(.notMath) }
        guard let at = relations.first, case .relation(let relation) = tokens[at] else {
            return Sides(left: try expression(tokens[...]), relation: nil, right: nil)
        }
        return Sides(left: try expression(tokens[..<at]),
                     relation: relation,
                     right: try expression(tokens[(at + 1)...]))
    }

    private static func expression(_ tokens: ArraySlice<Token>) throws -> Node {
        var parser = Parser(tokens: Array(tokens))
        let node = try parser.expression(minimum: 1)
        guard parser.atEnd else { throw Failure.cannot(.notMath) }
        return node
    }

    /// Precedence climbing: × and ÷ before + and −, left to right.
    private struct Parser {
        let tokens: [Token]
        var i = 0
        var atEnd: Bool { i == tokens.count }

        mutating func expression(minimum: Int) throws -> Node {
            var left = try operand()
            while i < tokens.count, case .op(let op) = tokens[i], op.precedence >= minimum {
                i += 1
                // A power groups to the right: `2^3^2` is 2^(3^2).
                let right = try expression(minimum: op == .power ? op.precedence : op.precedence + 1)
                left = .binary(op, left, right)
            }
            return left
        }

        mutating func operand() throws -> Node {
            guard i < tokens.count else { throw Failure.incomplete }
            switch tokens[i] {
            case .number(let n): i += 1; return .number(n)
            case .question(let q): i += 1; return .unknown(q)
            case .open:
                i += 1
                let inner = try expression(minimum: 1)
                guard i < tokens.count else { throw Failure.incomplete }
                guard tokens[i] == .close else { throw Failure.cannot(.notMath) }
                i += 1
                return inner
            case .root:
                i += 1
                return .root(try operand())
            case .op(.minus):
                // A negative number: `−3 + 5`.
                i += 1
                guard i < tokens.count, case .number(let n) = tokens[i] else { throw Failure.cannot(.notMath) }
                i += 1
                return .number(try Rational(0).minus(n))
            default: throw Failure.cannot(.notMath)
            }
        }
    }

    // MARK: - Working it out

    /// What the helper shows of one step, in place: the whole sum as it
    /// stands, the pair being worked out marked, and the number the last step
    /// made marked too. The sum shrinks a pair at a time — `1 + 2 + 3 + 4`,
    /// `3 + 3 + 4`, `6 + 4` — as it would on paper (Mark, 2026-11-20).
    struct Frame: Equatable {
        let tokens: [String]
        /// The pair being worked out now.
        let highlight: Range<Int>?
        /// Where the number the last step made sits.
        let result: Int?
    }

    /// The working, step by step: each step as a line (`1 + 2 = 3`, what is
    /// said) and as a frame (what is shown).
    private struct Working {
        var steps: [String] = []
        var frames: [Frame] = []

        /// Work out every pair it can on both sides of `relation`, in the
        /// order a child would — × and ÷ first, left to right — a frame each.
        mutating func reduce(_ left: Node, _ relation: String? = nil,
                             _ right: Node? = nil) throws -> (Node, Node?) {
            var l = left, r = right
            var result: Int?
            while true {
                let lt = MathHelper.layout(l)
                let rt = r.map(MathHelper.layout)
                var tokens = lt.tokens
                if let relation, let rt { tokens += [relation] + rt.tokens }
                let range: Range<Int>
                let step: (Node, String)
                if let ready = lt.ready, let once = try MathHelper.reduceOnce(l) {
                    range = ready
                    step = once
                    l = once.0
                } else if let rr = r, let ready = rt?.ready, let once = try MathHelper.reduceOnce(rr) {
                    let offset = lt.tokens.count + 1
                    range = (ready.lowerBound + offset)..<(ready.upperBound + offset)
                    step = once
                    r = once.0
                } else {
                    return (l, r)
                }
                frames.append(Frame(tokens: tokens, highlight: range, result: result))
                steps.append(step.1)
                // The pair becomes one number where it started.
                result = range.lowerBound
            }
        }

        mutating func value(_ node: Node) throws -> Rational {
            guard case .number(let n) = try reduce(node).0 else { throw Failure.cannot(.notMath) }
            return n
        }
    }

    /// A sum as its pieces, and where its first ready pair is — the first,
    /// in working order, with a number on each side. `reduceOnce` works out
    /// the same pair.
    static func layout(_ node: Node) -> (tokens: [String], ready: Range<Int>?) {
        func shifted(_ r: Range<Int>?, _ by: Int) -> Range<Int>? {
            r.map { ($0.lowerBound + by)..<($0.upperBound + by) }
        }
        func wrapped(_ l: (tokens: [String], ready: Range<Int>?)) -> (tokens: [String], ready: Range<Int>?) {
            (["("] + l.tokens + [")"], shifted(l.ready, 1))
        }
        switch node {
        case .number(let v): return ([v.shown], nil)
        case .unknown: return (["?"], nil)
        case .root(let x):
            var inner = layout(x)
            if case .binary = x { inner = wrapped(inner) }
            let tokens = ["√"] + inner.tokens
            if let ready = inner.ready { return (tokens, shifted(ready, 1)) }
            if case .number = x { return (tokens, 0..<tokens.count) }
            return (tokens, nil)
        case .binary(let op, let l, let r):
            var left = layout(l), right = layout(r)
            if needsBrackets(l, under: op, onRight: false) { left = wrapped(left) }
            if needsBrackets(r, under: op, onRight: true) { right = wrapped(right) }
            let tokens: [String]
            if op == .power, case .number(let e) = r, e == Rational(2) || e == Rational(3) {
                tokens = left.tokens + [e == Rational(2) ? "²" : "³"]
            } else {
                tokens = left.tokens + [op.symbol] + right.tokens
            }
            if let ready = left.ready { return (tokens, ready) }
            if let ready = right.ready { return (tokens, shifted(ready, left.tokens.count + 1)) }
            if l.isNumber, r.isNumber { return (tokens, 0..<tokens.count) }
            return (tokens, nil)
        }
    }

    /// Brackets a child needs to read back in the order it is worked out.
    private static func needsBrackets(_ child: Node, under op: Op, onRight: Bool) -> Bool {
        switch child {
        case .binary(let inner, _, _):
            if inner.precedence < op.precedence { return true }
            if inner.precedence == op.precedence {
                // `a − (b − c)`, `a ÷ (b × c)`, `(2^3)^2`.
                return op == .power ? !onRight : onRight && (op == .minus || op == .divide)
            }
            return false
        case .number(let n):
            // `(−3)²`, not `−3²`.
            return op == .power && !onRight && n < Rational(0)
        default:
            return false
        }
    }

    /// The first ready pair worked out: the sum with it replaced by its
    /// value, and the step as a line.
    private static func reduceOnce(_ node: Node) throws -> (Node, String)? {
        switch node {
        case .root(let x):
            if let once = try reduceOnce(x) { return (.root(once.0), once.1) }
            guard case .number(let v) = x else { return nil }
            let (c, exact) = try v.squareRoot()
            return (.number(c), "\(join(layout(node).tokens)) \(exact ? "=" : "≈") \(c.shown)")
        case .binary(let op, let l, let r):
            if let once = try reduceOnce(l) { return (.binary(op, once.0, r), once.1) }
            if let once = try reduceOnce(r) { return (.binary(op, l, once.0), once.1) }
            guard case .number(let a) = l, case .number(let b) = r else { return nil }
            let c = try apply(op, a, b)
            return (.number(c), "\(join(layout(node).tokens)) = \(c.shown)")
        default:
            return nil
        }
    }

    private static func apply(_ op: Op, _ a: Rational, _ b: Rational) throws -> Rational {
        switch op {
        case .plus: try a.plus(b)
        case .minus: try a.minus(b)
        case .times: try a.times(b)
        case .divide: try a.divided(by: b)
        case .power: try a.power(b)
        }
    }

    /// `1+2+3+4?` — the sum, and `=10` in place of the `?`.
    private static func evaluate(_ node: Node, marker: Int) throws -> Solution {
        var work = Working()
        let answer = try work.value(node)
        return Solution(kind: .answer(answer.shown), steps: work.steps, frames: work.frames,
                        summary: "\(node.shown()) = \(answer.shown)",
                        edits: [marker: "=" + answer.shown])
    }

    /// `2+2=5?` — worked out, and said right or not.
    /// The mark a checked answer leaves in the line: `5+5=9→10` is "9 is
    /// wrong, it's 10"; `3>5→3<5` puts a whole sum right. Drawn with the
    /// wrong part struck and the right part green (`MathChipView`), said as
    /// "is not 9, it's 10" (`SpeechNormalizer`) — Mark, 2026-11-20.
    static let correction: Character = "→"

    private static func check(_ left: Node, _ relation: Relation, _ right: Node,
                              marker: Int) throws -> Solution {
        var work = Working()
        let sides = try work.reduce(left, relation.symbol, right)
        guard case .number(let a) = sides.0, case .number(let b)? = sides.1 else {
            throw Failure.cannot(.notMath)
        }
        let typed = "\(left.shown()) \(relation.symbol) \(right.shown())"
        if relation.holds(a, b) {
            // Right: the `?` comes off, and the sum stands as typed.
            return Solution(kind: .check(correct: true), steps: work.steps, frames: work.frames,
                            summary: "Yes! \(typed)", edits: [marker: ""])
        }
        // `2+2=5` is put right as `2 + 2 = 4`; otherwise the right sign. The
        // line keeps the wrong answer and gains the right one.
        let corrected: String
        let mark: String
        if relation == .equal, case .number = right {
            corrected = "\(left.shown()) = \(a.shown)"
            mark = String(correction) + a.shown
        } else {
            corrected = "\(left.shown()) \(Relation.between(a, b).symbol) \(right.shown())"
            mark = String(correction) + corrected.filter { !$0.isWhitespace }
        }
        return Solution(kind: .check(correct: false), steps: work.steps, frames: work.frames,
                        summary: "Not quite: \(corrected)", edits: [marker: mark])
    }

    /// `3?5` — the sign between two sides.
    private static func compare(_ tokens: [Token], marker: Int?) throws -> Solution? {
        guard let at = tokens.firstIndex(where: { if case .question = $0 { true } else { false } }),
              case .question(let q) = tokens[at], at > 0, at < tokens.count - 1,
              !tokens.contains(where: { if case .relation = $0 { true } else { false } }),
              let left = try? expression(tokens[..<at]),
              let right = try? expression(tokens[(at + 1)...]),
              !left.hasUnknown, !right.hasUnknown
        else { return nil }
        var work = Working()
        let sides = try work.reduce(left, "?", right)
        guard case .number(let a) = sides.0, case .number(let b)? = sides.1 else {
            throw Failure.cannot(.notMath)
        }
        let sign = Relation.between(a, b).symbol
        var edits = [q: sign]
        if let marker { edits[marker] = "" }
        return Solution(kind: .compare(sign), steps: work.steps, frames: work.frames,
                        summary: "\(left.shown()) \(sign) \(right.shown())", edits: edits)
    }

    /// `3+?=7` — the missing number: each side worked out as far as it
    /// goes, then the sum undone a step at a time, shown as the equation
    /// turned round: `3 + ? = 7` becomes `? = 7 − 3`.
    private static func findUnknown(_ sides: Sides, marker: Int?) throws -> Solution {
        guard let right = sides.right else { throw Failure.cannot(.notMath) }
        var work = Working()
        let reduced = try work.reduce(sides.left, "=", right)
        let l = reduced.0
        guard let r = reduced.1 else { throw Failure.cannot(.notMath) }
        var node: Node
        var target: Rational
        switch (l, r) {
        case (_, .number(let n)) where l.hasUnknown: node = l; target = n
        case (.number(let n), _) where r.hasUnknown: node = r; target = n
        default: throw Failure.cannot(.notMath)
        }
        guard case .some(.unknown(let q)) = unknownLeaf(node) else { throw Failure.cannot(.notMath) }

        while case .binary(let op, let a, let b) = node {
            // A power or root over the missing number is past this helper.
            guard op != .power else { throw Failure.cannot(.notMath) }
            let unknownOnLeft = a.hasUnknown
            guard case .number(let n) = unknownOnLeft ? b : a else { throw Failure.cannot(.notMath) }
            let (undo, x, y) = try inverse(op, unknownOnLeft: unknownOnLeft, n, target)
            let next = try apply(undo, x, y)
            node = unknownOnLeft ? a : b
            let side = layout(node).tokens
            work.frames.append(Frame(tokens: side + ["=", x.shown, undo.symbol, y.shown],
                                     highlight: (side.count + 1)..<(side.count + 4), result: nil))
            work.steps.append("\(x.shown) \(undo.symbol) \(y.shown) = \(next.shown)")
            target = next
        }
        guard case .unknown = node else { throw Failure.cannot(.notMath) }

        let filled = "\(sides.left.shown(filling: target)) = \(right.shown(filling: target))"
        var edits = [q: target.shown]
        if let marker { edits[marker] = "" }
        return Solution(kind: .answer(target.shown), steps: work.steps, frames: work.frames,
                        summary: filled, edits: edits)
    }

    /// The step that undoes `op`, as `x undo y`.
    private static func inverse(_ op: Op, unknownOnLeft: Bool, _ n: Rational,
                                _ target: Rational) throws -> (Op, Rational, Rational) {
        switch (op, unknownOnLeft) {
        case (.plus, _): return (.minus, target, n)       // ? + n = t → t − n
        case (.minus, true): return (.plus, target, n)    // ? − n = t → t + n
        case (.minus, false): return (.minus, n, target)  // n − ? = t → n − t
        case (.times, _):                                 // ? × n = t → t ÷ n
            if n.isZero { throw Failure.cannot(target.isZero ? .anyNumberWorks : .noNumberWorks) }
            return (.divide, target, n)
        case (.divide, true): return (.times, target, n)  // ? ÷ n = t → t × n
        case (.divide, false):                            // n ÷ ? = t → n ÷ t
            if target.isZero { throw Failure.cannot(n.isZero ? .anyNumberWorks : .noNumberWorks) }
            return (.divide, n, target)
        case (.power, _):
            throw Failure.cannot(.notMath)
        }
    }

    private static func unknownLeaf(_ node: Node) -> Node? {
        switch node {
        case .unknown: node
        case .number: nil
        case .binary(_, let l, let r): unknownLeaf(l) ?? unknownLeaf(r)
        case .root(let x): unknownLeaf(x)
        }
    }
}

// MARK: - Exact numbers

/// A fraction in lowest terms, so `1 ÷ 3 × 3` is 1 and `0.1 + 0.2` is 0.3.
/// Overflow is a "too big", never a wrong answer.
struct Rational: Equatable, Comparable {
    let numerator: Int
    let denominator: Int

    init(_ whole: Int) { numerator = whole; denominator = 1 }

    fileprivate init(_ n: Int, over d: Int) throws {
        guard d != 0 else { throw MathHelperError.divideByZero }
        let g = Self.gcd(abs(n), abs(d))
        let sign = d < 0 ? -1 : 1
        numerator = sign * n / max(g, 1)
        denominator = sign * d / max(g, 1)
    }

    /// `2.50` → 5/2. Fifteen digits at most.
    fileprivate init(decimal text: String) throws {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, text != "." else { throw MathHelperError.notMath }
        let whole = String(parts[0]), fraction = parts.count == 2 ? String(parts[1]) : ""
        guard whole.count + fraction.count <= 15 else { throw MathHelperError.tooBig }
        guard let n = Int(whole + fraction) else { throw MathHelperError.notMath }
        var d = 1
        for _ in 0..<fraction.count { d *= 10 }
        try self.init(n, over: d)
    }

    var isZero: Bool { numerator == 0 }

    static func < (a: Rational, b: Rational) -> Bool {
        // Cross-multiplied in Double: comparison only, never an answer.
        Double(a.numerator) * Double(b.denominator) < Double(b.numerator) * Double(a.denominator)
    }

    func plus(_ o: Rational) throws -> Rational {
        try Rational(Self.add(Self.mul(numerator, o.denominator), Self.mul(o.numerator, denominator)),
                     over: Self.mul(denominator, o.denominator))
    }
    func minus(_ o: Rational) throws -> Rational {
        try plus(Rational(-o.numerator, over: o.denominator))
    }
    func times(_ o: Rational) throws -> Rational {
        try Rational(Self.mul(numerator, o.numerator), over: Self.mul(denominator, o.denominator))
    }
    func divided(by o: Rational) throws -> Rational {
        guard !o.isZero else { throw MathHelperError.divideByZero }
        return try Rational(Self.mul(numerator, o.denominator), over: Self.mul(denominator, o.numerator))
    }

    /// As a child reads it: `10`, `−2`, `3.5`, `0.25`, `3 1/3`, `2/3`. A
    /// decimal when it ends within three places, a fraction otherwise.
    var shown: String {
        let sign = numerator < 0 ? "\u{2212}" : ""
        let n = abs(numerator)
        if denominator == 1 { return sign + String(n) }
        var scale = 1
        for places in 1...3 where n < Int.max / 1000 {
            scale *= 10
            if scale % denominator == 0 {
                let scaled = n * (scale / denominator)
                let frac = String(scaled % scale)
                let padded = String(repeating: "0", count: places - frac.count) + frac
                let trimmed = padded.replacingOccurrences(of: "0+$", with: "", options: .regularExpression)
                return "\(sign)\(scaled / scale).\(trimmed)"
            }
        }
        let whole = n / denominator, rest = n % denominator
        return whole == 0 ? "\(sign)\(rest)/\(denominator)" : "\(sign)\(whole) \(rest)/\(denominator)"
    }

    /// A whole-number power: `2^5`, `2^−1` = 1/2. Thirty-two at most.
    func power(_ e: Rational) throws -> Rational {
        guard e.denominator == 1 else { throw MathHelperError.wholePowersOnly }
        guard abs(e.numerator) <= 32 else { throw MathHelperError.tooBig }
        var result = Rational(1)
        for _ in 0..<abs(e.numerator) { result = try result.times(self) }
        return e.numerator < 0 ? try Rational(1).divided(by: result) : result
    }

    /// The square root, and whether it is exact. A whole square (`√9`,
    /// `√(9/4)`) is exact; anything else is to three places (`√2 ≈ 1.414`).
    func squareRoot() throws -> (Rational, exact: Bool) {
        guard numerator >= 0 else { throw MathHelperError.negativeRoot }
        func whole(_ n: Int) -> Int? {
            let r = Int(Double(n).squareRoot().rounded())
            return r * r == n ? r : nil
        }
        if let n = whole(numerator), let d = whole(denominator) {
            return (try Rational(n, over: d), true)
        }
        let approx = (Double(numerator) / Double(denominator)).squareRoot()
        return (try Rational(Int((approx * 1000).rounded()), over: 1000), false)
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
    private static func mul(_ a: Int, _ b: Int) throws -> Int {
        let (r, o) = a.multipliedReportingOverflow(by: b)
        if o { throw MathHelperError.tooBig }
        return r
    }
    private static func add(_ a: Int, _ b: Int) throws -> Int {
        let (r, o) = a.addingReportingOverflow(b)
        if o { throw MathHelperError.tooBig }
        return r
    }
}

/// What `Rational` throws; `MathHelper.solve` turns it into a reason.
enum MathHelperError: Error {
    case divideByZero, tooBig, notMath, wholePowersOnly, negativeRoot
}
