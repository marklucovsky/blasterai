# AI sentences and single words

Two interaction modes, what the AI does and doesn't do, and how to correct it
when it's wrong.

---

## The two modes

**There is no mode switch.** The mode is a consequence of the child's
**Brown's Stage**, set per child in **Settings → Profiles**. Stage I is
single-word; Stage II-III and IV+ are sentence mode. For a quick change
mid-session there is a device-level override on the caregiver's rail: **Edit**
(or **Tools** on a narrower rail) → **Single Words** or **Sentences**.

**Stage I — single words.** Each tap speaks its word, and the words build a
strip across the top. **No AI at all** — no network call, AI mode on or off, it
makes no difference. This is classic AAC and it behaves the way you'd expect.

**Stage II-III and IV+ — sentences.** Tiles accumulate into a selection, and
the words still speak as they land. The sentence happens when the child taps
**Play** — or automatically once the selection hits its tile cap, which is four
at Stage II-III and five to eight at IV+. Left alone, the tray clears itself
after 30 seconds and what was said is recorded in the activity log.

Both of those numbers are settable, and the timeout can be switched off
entirely by setting it to zero.

**Why the stage decides it:** at Brown's Stage I a child is communicating in
single words, and at II-III they are putting words together. The mode follows
what the child is actually doing rather than asking you to set the same thing
twice.

When you want a different experience on a particular device — a session where
you want to show a family what sentence mode looks like, say — the override in
the rail's Edit menu gives you that, without changing what you've recorded about
the child.

---

## What the AI actually does

It **expands the tiles the child selected**. It does not predict, and it does
not complete a partial utterance.

`mom` + `milk` becomes "Mom, can I have some milk?" — it never adds a third
idea the child didn't choose. The model is instructed that every selected word
must appear in the output.

**Be precise about this, because it's the thing people most often assume
wrongly.** The risk with this design is not that the AI guesses what the child
wanted to say. It's that the *phrasing* it chooses may not be the phrasing you
wanted. Those are different problems and the second one is fixable.

**One honest limit:** "every selected word must appear" is an instruction to
the model, checked in our test suite, not a filter enforced in code. Models
follow it well — that is what the eval measures — but an instruction is not a
mechanism. Where it bends is usually a judgment call rather than a failure: a
word that reads more naturally as an inflection, or two tiles that collapse
into one idiomatic phrase. The result is generally faithful to what the child
chose even when it is not literally word-for-word.

### The same word in different contexts

This is what sentence mode is for. A word is one tile, used freely:

- `like` + `chocolate` → about liking chocolate
- `don't` + `like` + `chocolate` → about not liking it
- `want` + `more` + `chocolate` → asking for more

- `yucky` + `chocolate` → a complaint, and for many children `yucky` *is*
  "don't like" — one tile instead of two

Word class disambiguates sense when the *same* word means two things:
`snack bar (food)` is something to eat, `snack bar (places)` is somewhere to
go, and the class is what tells the model which one the child meant.

The tile limit is set by the child's stage: four at Stage II-III, and five to
eight at IV+ where the caregiver chooses.

### Repetition is intensity

Re-tapping a tile does not *just* repeat the word. The word always speaks —
every tap of an audible tile does — and in sentence mode the sentence is
regenerated too, one notch more insistent each time. Tap `chocolate` once and
it's a request; tap it again and again and it becomes a demand.

A speaking child raises their voice or tugs a sleeve. A child using tiles has
tap count. The app reads it as the same signal.

### What sets the level

The child's **Brown's Stage** sets the grammar and vocabulary the model aims
for — a clinical signal about how this child communicates, rather than a proxy
like age.

Stage also caps how many tiles can be selected at a time, so it governs
complexity from both ends: how many ideas go in, and how elaborate what comes
out is allowed to be.

---

## When the sentence is wrong

**Long-press the sentence bubble** while it's still on screen — it stays for
about 30 seconds, or until someone clears it. Three options:

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
committed — by Done, by Clear, or by the 30-second timeout — that bubble is
gone and there is nothing left to long-press. Nothing is lost, though: a
correction is stored against the *tile combination*, not that one moment. Select
the same tiles again and your version comes back, and you can correct it then.

In practice: if a sentence is wrong and you want it fixed, fix it before the
tray clears, or re-tap the tiles and fix it then.

**To find what to fix, use the activity log** (Settings → Activity). It records
every combination the child pressed, when, and the sentence that came back —
so you can review a session afterwards, spot the ones that came out wrong, and
go re-tap those tiles deliberately rather than trying to catch them live.

### These corrections stick

A correction is attached to **the words the child picked** — not to the model,
the prompt version, or the child's stage. It survives app updates, model
changes, prompt rewrites, and the child moving to a new Brown's Stage.

That is a deliberate split rather than a happy accident: ordinary cached
sentences are keyed to the model and prompt that produced them, so they fall
away when either changes, while a caregiver's correction is keyed only to the
words and the child. Correct something once and it stays corrected.

### The limit worth naming

**Only a caregiver can do any of this.** The child can add a tile, remove a
tray chip, or re-tap to escalate — they cannot reword the sentence.

If a child needs to control their own phrasing, single-word mode gives them
literal control over every word spoken. That's a real trade-off, not a
workaround, and it's the honest reason both modes exist.

---

## What this is not

BlasterAI does not currently teach sentence construction. There's no modeling
mode, no aided language stimulation, no parts-of-speech scaffolding. Single-word
mode is *AI off*, not *AI that teaches*.

The words are there — question words, negation, feelings, the core vocabulary
a child needs. What is absent is the *teaching*: nothing prompts a child toward
a question, models one, or scaffolds building one. If you're evaluating
this for language development rather than functional communication, that gap is
the one to weigh, and we'd rather you heard it here than discovered it in
session.

---

## Who the text is for

The written sentence is for **you**. The child's feedback loop is the tiles
they can see and the voice they hear.

That shapes a few defaults. Tapping a tile speaks its word immediately, so the
child gets confirmation before any sentence exists. And a single selected tile
just speaks that word — no AI call, no sentence.

---

## Voice

Settings → Now → voice, rate, and volume, per child.

Worth doing once, properly: iOS ships a basic voice and offers **Enhanced** and
**Premium** downloads that sound markedly better. iOS Settings →
Accessibility → Spoken Content → Voices. It's a bigger quality jump than
anything in the app.

If you want a starting point, **Joelle (Enhanced)** is unusually well
constructed — natural pacing, and it holds up over a long session rather than
grating. Voice is the one part of this a child hears every single time, so it
is worth more attention than it usually gets.

---

## Next

- **[Adding vocabulary](adding-vocabulary.md)**
- **[Sharing a scene](sharing-scenes.md)**
