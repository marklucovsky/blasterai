// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Mark Lucovsky
//
//  SentencePromptBuilder.swift
//  claudeBlast
//

import Foundation

struct PromptMessage: Codable {
  public var id: String? = UUID().uuidString
  var role: String
  var content: String
  
  init(role: MessageRole, content: String) {
    self.role = role.rawValue
    self.content = content
  }
}

public enum MessageRole: String, Codable {
    /// The role for the system that manages the chat interface.
    case system
    /// The role for the human user who initiates the chat.
    case user
    /// The role for the artificial assistant who responds to the user.
    case assistant
}

struct SentencePromptBuilder {
    /// The child's Brown's Stage. No default — callers must pass the active
    /// child's value (or `ChildProfileResolver.fallbackStage`) explicitly.
    /// Removing the default prevents silently falling back to a level nobody
    /// chose when a caller forgets to wire the resolver.
    ///
    /// Replaced a US grade level derived from the child's date of birth. Age
    /// does not predict expressive language level for an AAC user, and the
    /// grade phrasing consistently overshot; a stage names an MLU target and a
    /// morpheme inventory instead. See `BrownsStage`.
    var brownsStage: BrownsStage
    var repetitionCount: Int = 0
    /// The sentence a repeat escalates from (the active group's last sentence).
    /// Quoted inside the escalation directive: the eval showed gpt-4o-mini
    /// falling back to its calm first wording when only told to beat "your
    /// most recent reply above".
    var escalatingFrom: String? = nil
    var conversationContext: [String] = []

    /// Reinforces the word-class annotation rule near the end of the system
    /// turn. A small model otherwise lets its prior for a word override a
    /// surprising category (e.g. "pony (food)" comes out as a pet, not food).
    /// Kept as a system-prompt enhancement rather than appended to the user
    /// prompt so the user turn stays pure tile content.
    static let categoryHonorRule = PromptTemplate.raw("sentence_category_rule")

    func buildSystemPrompt() -> [PromptMessage] {
        var systemPrompt: [PromptMessage] = Self.loadBaseMessages(
            stage: brownsStage, escalating: repetitionCount > 0)
            .map { PromptMessage(role: .system, content: $0) }
        systemPrompt.append(PromptMessage(role: .system, content: Self.categoryHonorRule))
        if repetitionCount > 0 {
            systemPrompt.append(PromptMessage(role: .system, content: escalationPrompt(repetitionCount)))
        }

        return systemPrompt
    }

    /// The user turn: the selected tiles as `word (class)`, comma-joined.
    /// Enhancements (the category-honor rule, escalation) live in the system
    /// prompt — see `buildSystemPrompt` — with one exception: a repeat adds a
    /// short note after the tiles. The escalation directive alone sits above
    /// the conversation, and the last thing the model then reads is the same
    /// tiles as a fresh request; the eval showed ladders snapping back to the
    /// first, calm wording until the note was there.
    ///
    /// Past `topRung` the note says to hold rather than climb, so a long run of
    /// repeats doesn't stack "please, please" on itself. It is chosen here, by
    /// count, because a single note that said "hold if you're at the top" let
    /// statements and questions stall at rung 2.
    func formatUserPrompt(tiles: [TileSelection]) -> String {
        let selection = tiles.map { "\($0.value) (\($0.wordClass))" }
            .joined(separator: ", ")
        guard repetitionCount > 0 else { return selection }
        let note = repetitionCount > Self.topRung ? "sentence_escalation_hold" : "sentence_escalation_note"
        return selection + "\n" + PromptTemplate.render(note, ["count": String(repetitionCount)])
    }

    /// The last repeat that escalates; later repeats say the top sentence again.
    static let topRung = 3

    /// Caregiver refine directive, appended to the system turn when a refine
    /// carries an instruction (mirrors the tile-art refine flow): the model
    /// revises the sentence the caregiver is reacting to rather than rerolling.
    static func refinePrompt(previous: String, instruction: String) -> String {
        PromptTemplate.render("sentence_refine", ["previous": previous, "instruction": instruction])
    }

    /// The conversation context handed to the provider: prior sentences, then
    /// the user prompt last. The provider sends every entry but the last as a
    /// prior assistant turn, and the last as the user turn.
    ///
    /// For escalation the model must see the exact sentence it is escalating
    /// from, but `history` (derived from `groupHistory`) doesn't include it —
    /// the group is still active, so its sentence hasn't been flushed. It is
    /// spliced in here. A refine likewise gets the sentence it's revising as
    /// its prior turn, so the instruction has an explicit target to rework.
    static func context(history: [String], escalatingFrom prior: String?,
                        refining original: String?, userPrompt: String) -> [String] {
        var context = history
        if let prior { context.append(prior) }
        if let original, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            context.append(original)
        }
        return context + [userPrompt]
    }

    private static func loadBaseMessages(stage: BrownsStage,
                                        escalating: Bool = false) -> [String] {
        guard let url = Bundle.main.url(forResource: "sentence_prompt", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let messages = try? JSONDecoder().decode([String].self, from: data)
        else { return hardcodedFallback(stage: stage, escalating: escalating) }
        return messages.map {
            $0.replacingOccurrences(of: "{stage}",
                                    with: stage.promptDescriptor(escalating: escalating))
        }
    }

    private static func hardcodedFallback(stage: BrownsStage,
                                          escalating: Bool = false) -> [String] {
        [
            "Your user has a disability that leaves them non verbal. You are their voice and soul. You are responsible for communication on their behalf.",
            "Users have a small vocabulary of words and phrases, they communicate with you using these items selected from their touch screen phone or device. Your job is to communicate your user's intent using full sentences to one or more folks that do not have any communication disabilities.",
            "Never generate anything that might be viewed as refering to sex acts, sound pornographic, or violent. For instance if the two words are make and love, do not generate a sentence like, I want to feel good, lets make love.",
            "Users often intend to communicate with a question that relates to themselves. E.g., when presented with the items: mom, tired -- the generated response should be something like: 'Mom, I am tired. Can I go lie down' or 'Mom, are you tired? I am, Lets go lie down and take a nap.'. It would be very rare for the response to be centered on someone else, like 'Mom are you tired?'",
            "Assume that most usage is self centered. For instance selection of: mom, milk should translate to 'Mom can I have some milk' and not 'Mom, you should drink some milk'",
            "Words can either be a comma seperated list of words, or a comma seperated list of words with a word class annotation in parens, after the word. The annotion should be used by you to provide context on how the word should be used. For instance the word 'snack bar' can be a place where a person goes to eat something. The word can also mean a type of food, like a granola bar, a protein bar, etc. An annotation of (place) would imply the first case, while an annotation of (food) would imply the second case. When faced with a word list of 'mom, snack bar (food)', you should never generate a sentence that includes going to a snack bar. In this case, since it's annotation is 'food', the snack bar is something you eat, not a place you go to.'",
            "GRAMMAR BY WORD CLASS. The class in parentheses tells you the grammatical role the word must play. Putting a word in the wrong role is the most common way these sentences break. (people) = who the child is speaking TO — address them by name, never as something wanted. (feeling), (health) = a state the child IS in, never something they want, need or are given — write \"I am hungry\" or \"my tummy hurts\", NEVER \"I want hungry\" or \"I need HUNGRY\". (food), (drinks), (toy), (art), (object) = things that can be given — \"I want X\", \"can I have X\". (actions) = verbs — \"I want to X\", never \"I want X\". (places) = destinations — \"I want to go to X\". (sports), (games), (play) = activities — \"I want to play X\". (describe), (colors), (shape) = adjectives that modify something else; they do not stand alone as the thing wanted. (body) = body parts, normally paired with a feeling or action — \"my ARM hurts\". (weather) = a state of the world — \"it is X outside\". (social) = greetings and politeness; they open or close the sentence. (core) = ordinary function words, used as glue. (question) = makes the sentence a question.",
            "Your user is \(stage.promptDescriptor(escalating: escalating)). Match that level exactly — this is the voice you should communicate in."
        ]
    }

    /// Escalation directive for a repeated selection. Repetition is the child's
    /// volume knob — the same tiles tapped again means "I want this MORE."
    ///
    /// Design (rewritten after the eval harness showed the old prompt jumped one
    /// notch on the first repeat then flatlined or regressed):
    /// - **Cumulative.** Each rung must be strictly more insistent than the
    ///   model's own previous sentence (supplied as its most recent reply), never
    ///   calmer and never a restatement. This is the fix for flat ramps.
    /// - **Graduated by count.** A concrete intensity ladder the model climbs as
    ///   the repeat count rises, so there's always a hotter rung to reach.
    /// - **No fixed anchor.** The illustration uses a neutral want ("juice") that
    ///   isn't real vocabulary, so the model learns the trajectory shape without
    ///   anchoring its wording to a specific example (the old "mom, hungry"
    ///   few-shot caused that case to regress toward the example).
    ///
    /// ## Escalation is exempt from the stage's length ceiling
    ///
    /// `brownsStage` governs the *baseline* utterance. Escalation deliberately
    /// overrides it, and the reason is that escalation has to be **heard**.
    ///
    /// A first attempt escalated by emphasis alone — capitals and exclamation
    /// marks, no new words — so that a Stage II-III child never exceeded a mean
    /// utterance length of 3. The live eval passed. The result was still wrong:
    /// `AVSpeechSynthesizer` barely inflects on "!" and does nothing useful with
    /// capitals (some voices read a short ALL-CAPS token letter by letter). Every
    /// rung of that ladder *sounded identical*. In a speech-generating device,
    /// escalation a listener cannot hear is not escalation.
    ///
    /// Adding words is what changes the audio today. It is also aimed at the
    /// right audience: the generated sentence is read by the caregiver, while the
    /// child's own feedback loop is the tiles and the speech. "I need chocolate
    /// NOW" tells an adult *he really means it* in a way that "chocolate!!!"
    /// does not.
    ///
    /// When prosody escalation lands — driving rate, pitch and volume from the
    /// repeat count — the audible ramp moves into the TTS layer and this ladder
    /// can get shorter again. Until then the words carry it.
    private func escalationPrompt(_ count: Int) -> String {
        PromptTemplate.render("sentence_escalation",
                              ["count": String(count), "previous": escalatingFrom ?? ""])
    }
}
