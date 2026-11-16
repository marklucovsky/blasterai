# Single words and sentences

Two ways a message can work, what the AI does and doesn't do, and how to
correct it when it's wrong.

---

## The two modes

**The profile decides.** Each profile owns three settings, in **Settings ›
Profile › AI**: **AI** on or off, **Sentences** on or off, and **Words per
Message** (4–8). Sentences start off at every stage; turning them on is a
deliberate step. For a quick change mid-session the rail in Setup mode has the
same switch: **Edit** (or **Tools** on a narrower rail) → **Message** →
**Single Words** or **Sentences**. **Settings › Message Box › Message** is the
same switch again. If AI is off for the whole device (**Settings › AI**), the
profile's switches wait until it is turned on.

**Single Words.** Each tap speaks its word, and the words build a strip across
the top. **No AI at all** — no network call, AI on or off, it makes no
difference. This is classic AAC and it behaves the way you'd expect.

**Sentences.** Tiles accumulate into a selection, and the words still speak as
they land. The sentence happens when Aubrey taps **Play** — or automatically
once the selection hits Words per Message. Left alone, the message box clears
itself after 30 seconds and what was said is recorded in the activity log.

Both of those numbers are settable: Words per Message on the profile, and the
timeout in **Settings › Message Box › Auto-Clear**, which can be switched
**Off** entirely.

**What the stage does:** Brown's Stage only sets where Words per Message and
the message box's pictures start (four words at Stage I and II-III, five at
IV+). Changing the stage offers its starting point and changes nothing else on
its own; **Reset to Stage Defaults** puts everything back, with AI on and
Sentences off.

When you want a different experience for a while — a session where you want to
show a family what Sentences look like, say — the switch on the rail gives you
that. It flips the profile's Sentences setting and leaves Aubrey's stage alone.

---

## What the AI actually does

It **expands the tiles Aubrey selected**. It does not predict, and it does
not complete a partial utterance.

`mom` + `milk` becomes "Mom, can I have some milk?" — it never adds a third
idea Aubrey didn't choose. The model is instructed that every selected word
must appear in the output.

**Be precise about this, because it's the thing people most often assume
wrongly.** The risk with this design is not that the AI guesses what Aubrey
wanted to say. It's that the *phrasing* it chooses may not be the phrasing you
wanted. Those are different problems and the second one is fixable.

**One honest limit:** "every selected word must appear" is an instruction to
the model, checked in our test suite, not a filter enforced in code. Models
follow it well — that is what the eval measures — but an instruction is not a
mechanism. Where it bends is usually a judgment call rather than a failure: a
word that reads more naturally as an inflection, or two tiles that collapse
into one idiomatic phrase. The result is generally faithful to what Aubrey
chose even when it is not literally word-for-word.

### The same word in different contexts

This is what Sentences are for. A word is one tile, used freely:

- `like` + `chocolate` → about liking chocolate
- `don't` + `like` + `chocolate` → about not liking it
- `want` + `more` + `chocolate` → asking for more

- `yucky` + `chocolate` → a complaint, and for many children `yucky` *is*
  "don't like" — one tile instead of two

Word class disambiguates sense when the *same* word means two things:
`snack bar (food)` is something to eat, `snack bar (places)` is somewhere to
go, and the class is what tells the model which one Aubrey meant.

The tile limit is the profile's Words per Message: anywhere from four to
eight, starting where the stage puts it.

### Repetition is intensity

Re-tapping a tile does not *just* repeat the word. The word always speaks —
every tap of an audible tile does — and with Sentences on the sentence is
regenerated too, one notch more insistent each time. Tap `chocolate` once and
it's a request; tap it again and again and it becomes a demand.

A speaking child raises their voice or tugs a sleeve. Aubrey, using tiles, has
tap count. The app reads it as the same signal.

### What sets the level

Aubrey's **Brown's Stage** sets the grammar and vocabulary the model aims
for — a clinical signal about how Aubrey communicates, rather than a proxy
like age.

Words per Message caps how many tiles can be selected at a time, so between
them the two govern complexity from both ends: how many ideas go in, and how
elaborate what comes out is allowed to be.

---

## When the sentence is wrong

**Long-press the sentence bubble** while it's still on screen — it stays for
about 30 seconds (Auto-Clear), or until someone clears it. Three options:

**Refine / Try Again** — tell the AI what to change in plain language: "make it
shorter", "she's asking, not telling", "use her name". It regenerates. Accept
the result and it's pinned for that combination.

**Hand-Type Sentence** — write the exact sentence yourself. Prefilled with the
AI's attempt so you can edit rather than start over. From then on, *this
sentence* is spoken whenever *those tiles* are selected.

**Suppress This** — this tile combination never speaks a generated sentence
again. A hard block on every path, including replay and escalation. Reversible
by long-pressing the muted bubble.

**You correct the live bubble, not the transcript.** Once the group is
committed — by Clear or by Auto-Clear — that bubble is
gone and there is nothing left to long-press. Nothing is lost, though: a
correction is stored against the *tile combination*, not that one moment. Select
the same tiles again and your version comes back, and you can correct it then.

In practice: if a sentence is wrong and you want it fixed, fix it before the
message box clears, or re-tap the tiles and fix it then.

**To find what to fix, use the activity log** (Settings › Activity › Activity
Log). It records every combination Aubrey pressed, when, and the sentence that came back —
so you can review a session afterwards, spot the ones that came out wrong, and
go re-tap those tiles deliberately rather than trying to catch them live.

### These corrections stick

A correction is attached to **the words Aubrey picked** — not to the model,
the prompt version, or Aubrey's stage. It survives app updates, model
changes, prompt rewrites, and Aubrey moving to a new Brown's Stage.

That is a deliberate split rather than a happy accident: ordinary cached
sentences are keyed to the model and prompt that produced them, so they fall
away when either changes, while your correction is keyed only to the
words and the profile. Correct something once and it stays corrected.

### The limit worth naming

**Only you can do any of this.** Aubrey can add a tile, remove a
chip from the message box, or re-tap to escalate — not reword the sentence.

If Aubrey needs to control their own phrasing, Single Words gives them
literal control over every word spoken. That's a real trade-off, not a
workaround, and it's the honest reason both modes exist.

---

## What this is not

BlasterAI does not currently teach sentence construction. There's no modeling
mode, no aided language stimulation, no parts-of-speech scaffolding. Single
Words is *no AI*, not *AI that teaches*.

The words are there — question words, negation, feelings, the core vocabulary
a child needs. What is absent is the *teaching*: nothing prompts a child toward
a question, models one, or scaffolds building one. If you're evaluating
this for language development rather than functional communication, that gap is
the one to weigh, and we'd rather you heard it here than discovered it in
session.

---

## Who the text is for

The written sentence is for **you**. Aubrey's feedback loop is the tiles
they can see and the voice they hear.

That shapes a few defaults. Tapping a tile speaks its word immediately, so
Aubrey gets confirmation before any sentence exists. And a single selected tile
just speaks that word — no AI call, no sentence.

---

## Voice

**Settings › Profile › Voice** — voice, rate, and volume, per profile.

Worth doing once, properly: iOS ships a basic voice and offers **Enhanced** and
**Premium** downloads that sound markedly better. iOS Settings →
Accessibility → Spoken Content → Voices. It's a bigger quality jump than
anything in the app.

If you want a starting point, **Joelle (Enhanced)** is unusually well
constructed — natural pacing, and it holds up over a long session rather than
grating. Voice is the one part of this Aubrey hears every single time, so it
is worth more attention than it usually gets.

---

## Next

- **[Adding vocabulary](adding-vocabulary.md)**
- **[Sharing a board](sharing-boards.md)**
