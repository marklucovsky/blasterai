// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  MathHelperTests.swift
//  claudeBlastTests
//
//  The numbers page's `?`: sums worked out a step at a time, missing numbers
//  found, answers checked, signs picked — and the answer put in the line.
//

import Testing
import SwiftData
import Foundation
@testable import claudeBlast

extension SerialTests {
@MainActor
@Suite(.serialized)
struct MathHelperTests {

    private func solution(_ line: String) throws -> MathHelper.Solution {
        guard case .solved(let s) = MathHelper.solve(line) else {
            Issue.record("\(line) → \(MathHelper.solve(line))")
            throw CancellationError()
        }
        return s
    }

    // MARK: - Sums

    @Test func aSumIsAddedUpAStepAtATime() throws {
        let s = try solution("1+2+3+4=?")
        #expect(s.steps == ["1 + 2 = 3", "3 + 3 = 6", "6 + 4 = 10"])
        #expect(s.kind == .answer("10"))
        #expect(s.summary == "1 + 2 + 3 + 4 = 10")
        #expect(s.edits == [0: "10"])
    }

    /// Shown in place: the sum shrinks a pair at a time, the pair marked,
    /// and the number it made marked in the next frame.
    @Test func theSumShrinksInPlace() throws {
        let s = try solution("1+2+3+4=?")
        #expect(s.frames.map { $0.tokens.joined(separator: " ") }
                == ["1 + 2 + 3 + 4 = ?", "3 + 3 + 4 = ?", "6 + 4 = ?"])
        #expect(s.frames.map(\.highlight) == [0..<3, 0..<3, 0..<3])
        #expect(s.frames.map(\.result) == [nil, 0, 0])
        let t = try solution("2+3×4=?")
        #expect(t.frames.map { $0.tokens.joined(separator: " ") } == ["2 + 3 × 4 = ?", "2 + 12 = ?"])
        #expect(t.frames.map(\.highlight) == [2..<5, 0..<3])
        #expect(t.frames.map(\.result) == [nil, 2])
    }

    /// A missing number is shown as the equation turned round.
    @Test func aMissingNumberIsShownTurnedRound() throws {
        let s = try solution("2×?+1=9")
        #expect(s.frames.map { $0.tokens.joined(separator: " ") }
                == ["2 × ? = 9 \u{2212} 1", "? = 8 ÷ 2"])
        #expect(s.frames.map(\.highlight) == [4..<7, 2..<5])
        #expect(s.frames.count == s.steps.count)
    }

    /// No `=`: the `?` asks for it, and becomes `=10`.
    @Test func aQuestionMarkWithoutEqualsAsksForTheAnswer() throws {
        let s = try solution("1+2+3+4?")
        #expect(s.kind == .answer("10"))
        #expect(s.edits == [0: "=10"])
    }

    @Test func timesAndDivideGoFirst() throws {
        let s = try solution("2 + 3 × 4 = ?")
        #expect(s.steps == ["3 × 4 = 12", "2 + 12 = 14"])
        #expect(try solution("20−12÷4=?").kind == .answer("17"))
        #expect(try solution("6x7=?").kind == .answer("42"), "a letter x between numbers is times")
        #expect(try solution("10-3=?").kind == .answer("7"))
    }

    @Test func answersCanBeNegativeDecimalOrFractions() throws {
        #expect(try solution("3−5=?").kind == .answer("\u{2212}2"))
        #expect(try solution("7÷2=?").kind == .answer("3.5"))
        #expect(try solution("1÷4=?").kind == .answer("0.25"))
        #expect(try solution("10÷3=?").kind == .answer("3 1/3"))
        #expect(try solution("2÷3=?").kind == .answer("2/3"))
        #expect(try solution("0.1+0.2=?").kind == .answer("0.3"), "exact, not floating point")
        #expect(try solution("1÷3×3=?").kind == .answer("1"))
    }

    // MARK: - Brackets, powers, roots (the calculator)

    @Test func bracketsGoFirstAndShowWhereTheyAre() throws {
        let s = try solution("2×(3+4)=?")
        #expect(s.frames.map { $0.tokens.joined(separator: " ") } == ["2 × ( 3 + 4 ) = ?", "2 × 7 = ?"])
        #expect(s.frames.first?.highlight == 3..<6)
        #expect(s.kind == .answer("14"))
        #expect(s.summary == "2 × (3 + 4) = 14")
        #expect(try solution("(1+2)×(3+4)=?").steps == ["1 + 2 = 3", "3 + 4 = 7", "3 × 7 = 21"])
        #expect(try solution("10−(4−1)=?").kind == .answer("7"))
    }

    @Test func powersAndRoots() throws {
        let sq = try solution("3²+1=?")
        #expect(sq.steps == ["3² = 9", "9 + 1 = 10"])
        #expect(try solution("2^5=?").kind == .answer("32"))
        #expect(try solution("2^3^2=?").kind == .answer("512"), "powers group to the right")
        #expect(try solution("2^-1=?").kind == .answer("0.5"))
        #expect(try solution("(−3)²=?").kind == .answer("9"))
        let root = try solution("√9+1=?")
        #expect(root.steps == ["√9 = 3", "3 + 1 = 4"])
        #expect(try solution("√(9÷4)=?").kind == .answer("1.5"))
        #expect(try solution("√2=?").steps == ["√2 ≈ 1.414"])
        #expect(MathHelper.solve("2^0.5=?") == .cannot(.wholePowersOnly))
        #expect(MathHelper.solve("√(0−4)=?") == .cannot(.noRootOfNegative))
        #expect(MathHelper.solve("2×(3+4") == .incomplete)
        #expect(MathHelper.solve("2×(") == .incomplete)
        #expect(MathHelper.solve("√") == .incomplete)
        #expect(MathHelper.solve("?²=9") == .cannot(.notMath), "a power over the missing number is past it")
    }

    @Test func powersAndRootsAreSaid() {
        #expect(SpeechNormalizer.line("3² = 9") == "3 squared equals 9")
        #expect(SpeechNormalizer.line("2 ^ 5 = 32") == "2 to the power of 5 equals 32")
        #expect(SpeechNormalizer.line("√9 = 3") == "the square root of 9 equals 3")
        #expect(SpeechNormalizer.line("√2 ≈ 1.414") == "the square root of 2 is about 1.414")
        #expect(MathHelper.isMathText("2×(3+4)") && MathHelper.isMathText("√9") && MathHelper.isMathText("3²"))
    }

    // MARK: - Missing numbers

    @Test func theMissingNumberIsFoundByUndoingTheSum() throws {
        let s = try solution("3+?=7")
        #expect(s.steps == ["7 \u{2212} 3 = 4"])
        #expect(s.kind == .answer("4"))
        #expect(s.summary == "3 + 4 = 7")
        #expect(s.edits == [0: "4"])
    }

    /// Typed with the `?` key at the end, the trailing `?` comes out.
    @Test func aTrailingQuestionMarkOnAMissingNumberComesOut() throws {
        let s = try solution("3+?=7?")
        #expect(s.edits == [0: "4", 1: ""])
    }

    @Test func missingNumbersEverywhere() throws {
        #expect(try solution("?−4=6").kind == .answer("10"))
        #expect(try solution("10−?=6").kind == .answer("4"))
        #expect(try solution("?×3=12").kind == .answer("4"))
        #expect(try solution("12÷?=4").kind == .answer("3"))
        #expect(try solution("?÷2=5").kind == .answer("10"))
        #expect(try solution("2×?+1=9").steps == ["9 \u{2212} 1 = 8", "8 ÷ 2 = 4"])
        #expect(try solution("?=2×4").kind == .answer("8"))
        #expect(try solution("1+?=2+3").steps == ["2 + 3 = 5", "5 \u{2212} 1 = 4"])
    }

    // MARK: - Checking an answer

    @Test func aRightAnswerIsCheered() throws {
        let s = try solution("2+2=4?")
        #expect(s.kind == .check(correct: true))
        #expect(s.summary == "Yes! 2 + 2 = 4")
        #expect(s.edits == [0: ""], "the ? comes off; the sum stands as typed")
    }

    @Test func aWrongAnswerIsPutRight() throws {
        let s = try solution("2+2=5?")
        #expect(s.kind == .check(correct: false))
        #expect(s.summary == "Not quite: 2 + 2 = 4")
        // The line keeps the wrong answer and gains the right one.
        #expect(s.edits == [0: "→4"])
        #expect(try solution("3 > 5?").edits == [0: "→3<5"])
        #expect(try solution("3 > 5?").summary == "Not quite: 3 < 5")
        #expect(try solution("3+4>5?").kind == .check(correct: true))
    }

    // MARK: - Comparing

    @Test func theSignBetweenTwoNumbersIsPicked() throws {
        let s = try solution("3?5")
        #expect(s.kind == .compare("<"))
        #expect(s.summary == "3 < 5")
        #expect(try solution("2+2?4?").edits == [0: "=", 1: ""])
        #expect(try solution("9?2×3").kind == .compare(">"))
    }

    // MARK: - Not a question yet, or not one we can answer

    @Test func halfTypedQuestionsWait() {
        for line in ["?", "3+?", "3+?=", "3?", "3+", "1+2="] {
            #expect(MathHelper.solve(line) == .incomplete, "\(line)")
        }
    }

    @Test func whatTheHelperCannotDoItSays() {
        #expect(MathHelper.solve("5÷0=?") == .cannot(.divideByZero))
        #expect(MathHelper.solve("×4?") == .cannot(.startWithANumber))
        #expect(MathHelper.solve("I want 2=?") == .cannot(.notMath))
        #expect(MathHelper.solve("$5+$2=?") == .cannot(.notMath))
        #expect(MathHelper.solve("?+?=4") == .cannot(.oneQuestionAtATime))
        #expect(MathHelper.solve("0×?=5") == .cannot(.noNumberWorks))
        #expect(MathHelper.solve("0×?=0") == .cannot(.anyNumberWorks))
        #expect(MathHelper.solve("999999999999999×999999999999999=?") == .cannot(.tooBig))
    }

    /// The working is said as a sum is said.
    @Test func theWorkingIsSaidAsASum() {
        #expect(SpeechNormalizer.line("6 + 4 = 10") == "6 plus 4 equals 10")
        #expect(SpeechNormalizer.line("10 ÷ 3 = 3 1/3") == "10 divided by 3 equals 3 and 1 third")
        #expect(SpeechNormalizer.line("Yes! 2 + 2 = 4") == "Yes! 2 plus 2 equals 4")
    }

    // MARK: - The answer in the line

    @Test func theAnswerGoesInTheLine() throws {
        let container = TestStore.freshContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", brownsStage: .fourPlus, isActive: true)
        profile.aiMode = .sentences
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)

        // Typed with spaces: five words, and the `?` is the draft.
        for word in ["1", "+", "2", "="] {
            engine.typeKey(word)
            engine.typeSpace()
        }
        engine.typeKey("?", speaking: false)
        #expect(engine.typingLine == "1 + 2 = ?")
        engine.fillTypedQuestions(try solution(engine.typingLine).edits)
        #expect(engine.typingDraft == "")
        // Said, the sum is one word: one card, one tap, one backspace.
        #expect(engine.selectedTiles.map(\.value) == ["1+2=3"])

        // Typed without: one word, `3+?=7?` → `3+4=7`.
        engine.clearSelection()
        for ch in "3+?=7?" { engine.typeKey(String(ch), speaking: false) }
        engine.fillTypedQuestions(try solution(engine.typingLine).edits)
        #expect(engine.selectedTiles.map(\.value) == ["3+4=7"])
        withExtendedLifetime(container) {}
    }

    private func engineForTyping() -> (SentenceEngine, ModelContainer) {
        let container = TestStore.freshContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", brownsStage: .fourPlus, isActive: true)
        profile.aiMode = .sentences
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)
        return (engine, container)
    }

    private func type(_ text: String, into engine: SentenceEngine) {
        for ch in text {
            if ch == " " { engine.typeSpace() } else { engine.typeKey(String(ch), speaking: false) }
        }
    }

    // MARK: - Each sum said once

    /// `1+1=2`, Play, `2+2=4`, Play: the second Play says only the new sum.
    @Test func playSaysEachSumOnce() {
        let (engine, container) = engineForTyping()
        type("1+1=2 3+3=6", into: engine)
        engine.triggerGo()
        #expect(engine.activeGroup.spokenSums.count == 2)
        type("2+2=4", into: engine)
        #expect(engine.typingQuestion == "2+2=4")
        engine.triggerGo()
        #expect(engine.activeGroup.spokenSums.starts == [0, 1, 2])
        #expect(engine.activeGroup.spokenSums.count == 3)
        #expect(engine.selectedTiles.count == 3, "the sums stay in the box")
        withExtendedLifetime(container) {}
    }

    /// In single-word mode the strip says each sum once too, and a tap on
    /// one says it again rather than taking it off.
    @Test func theStripSaysEachSumOnce() {
        let container = TestStore.freshContainer()
        let ctx = container.mainContext
        let profile = ChildProfile(displayName: "Test", brownsStage: .one, isActive: true)
        ctx.insert(profile)
        try? ctx.save()
        let resolver = ChildProfileResolver()
        resolver.configure(modelContext: ctx)
        let engine = SentenceEngine(provider: MockSentenceProvider(minLatency: 0, maxLatency: 0))
        engine.configure(modelContext: ctx, profileResolver: resolver)
        #expect(engine.interactionMode == .singleWord)

        type("1+1=2", into: engine)
        engine.typeSpeakLine()
        #expect(engine.stripSpokenSums == SpokenSums(count: 1, starts: [0]))
        type("2+2=4", into: engine)
        engine.typeSpeakLine()
        #expect(engine.stripSpokenSums == SpokenSums(count: 2, starts: [0, 1]))
        engine.tapTile(at: 0)
        #expect(engine.spokenStrip.count == 2)
        engine.typeBackspace()
        #expect(engine.stripSpokenSums == SpokenSums(count: 1, starts: [0]))
        withExtendedLifetime(container) {}
    }

    @Test func spokenSumsFollowTheirWords() {
        var sums = SpokenSums()
        sums.said(from: 0, to: 2)
        sums.said(from: 2, to: 5)
        #expect(sums.range(around: 3) == 2..<5)
        #expect(sums.range(around: 1) == 0..<2)
        sums.dropFirst(2)
        #expect(sums == SpokenSums(count: 3, starts: [0]))
        sums.remove(at: 2)
        #expect(sums == SpokenSums(count: 2, starts: [0]))
    }

    /// Typed with spaces, a said sum becomes one word; two whole sums stay two.
    @Test func aSaidSumBecomesOneWord() {
        let (engine, container) = engineForTyping()
        type("1 + 1 = 2 3+3=6 ", into: engine)
        engine.triggerGo()
        #expect(engine.selectedTiles.map(\.value) == ["1+1=2", "3+3=6"])
        #expect(engine.activeGroup.spokenSums == SpokenSums(count: 2, starts: [0, 1]))
        #expect(engine.activeGroup.spokenSums.chipStyle(at: 1) == .latest)
        #expect(engine.activeGroup.spokenSums.chipStyle(at: 0) == .spoken)
        engine.typeBackspace()
        #expect(engine.selectedTiles.map(\.value) == ["1+1=2"], "one backspace takes the whole sum")
        withExtendedLifetime(container) {}
    }

    /// On the numbers page a tap on a said sum hands it to the helper to
    /// replay; a sum not yet said is just said.
    @Test func aTapOnASaidSumReplaysIt() {
        let (engine, container) = engineForTyping()
        var replayed: [String] = []
        engine.mathReplayHandler = { replayed.append($0) }
        type("1 + 2 + 3 = 6", into: engine)
        engine.triggerGo()
        type("2+2=4 ", into: engine)
        engine.tapTile(at: 0)
        engine.tapTile(at: 1)
        #expect(replayed == ["1+2+3=6"], "the unsaid sum is not replayed")
        withExtendedLifetime(container) {}
    }

    /// A wrong answer checked: the line shows it put right, it is said as
    /// put right, and it is still one finished sum.
    @Test func aWrongAnswerIsPutRightInTheLine() throws {
        let (engine, container) = engineForTyping()
        type("5+5=9?", into: engine)
        engine.fillTypedQuestions(try solution(engine.typingQuestion).edits)
        #expect(engine.selectedTiles.map(\.value) == ["5+5=9→10"])
        #expect(engine.selectedTiles.first?.isMath == true)
        #expect(MathHelper.isFinishedStatement("5+5=9→10"))
        #expect(SpeechNormalizer.line("5+5=9→10") == "5 plus 5 is not 9, it's 10")
        #expect(SpeechNormalizer.line("3>5→3<5") == "3 is greater than 5, no, 3 is less than 5")
        withExtendedLifetime(container) {}
    }

    /// A lone sum played with the one-word Play still counts as said.
    @Test func aLoneSumPlayedIsSaid() {
        let (engine, container) = engineForTyping()
        type("1+1=2 ", into: engine)
        engine.playSingleTile()
        type("2+2=", into: engine)
        #expect(engine.typingQuestion == "2+2=")
        withExtendedLifetime(container) {}
    }

    /// Typed without Play between them, a finished sum still ends: the
    /// helper works on the new one alone.
    @Test func theHelperWorksOnTheNewSumAlone() throws {
        let (engine, container) = engineForTyping()
        type("1+1=2 2+2=?", into: engine)
        #expect(engine.typingQuestion == "2+2=?")
        engine.fillTypedQuestions(try solution(engine.typingQuestion).edits)
        #expect(engine.selectedTiles.map(\.value) == ["1+1=2", "2+2=4"])
        #expect(engine.activeGroup.spokenSums.count == 2, "the helper said it")
        withExtendedLifetime(container) {}
    }

    /// A line with words in it is said whole, as before.
    @Test func wordsAreNotSums() {
        #expect(MathHelper.isMathText("1+1=2"))
        #expect(MathHelper.isMathText("6x7"))
        #expect(MathHelper.isMathText("+"))
        #expect(!MathHelper.isMathText("x"))
        #expect(!MathHelper.isMathText("cookie"))
        #expect(MathHelper.isFinishedStatement("1+1=2"))
        #expect(!MathHelper.isFinishedStatement("1+1="))
        #expect(!MathHelper.isFinishedStatement("3+?=7"))
    }

    /// Tapping a sum says it; tapping a word still takes it off.
    @Test func tappingASumKeepsIt() {
        let (engine, container) = engineForTyping()
        type("hello 1+1=2 ", into: engine)
        engine.tapTile(at: 1)
        #expect(engine.selectedTiles.count == 2)
        engine.tapTile(at: 0)
        #expect(engine.selectedTiles.map(\.value) == ["1+1=2"])
        withExtendedLifetime(container) {}
    }
}
}
