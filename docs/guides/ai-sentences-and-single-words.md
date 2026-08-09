# AI sentences and single words

Two interaction modes, what the AI does and doesn't do, and how to correct it
when it's wrong.

---

## The two modes

Set per child: **Admin → Now → Mode**, or from the profile sheet, or from the
caregiver menu (long-press Home) for a quick switch mid-session.

**Single Words.** Each tap speaks its word. Words build a strip across the top.
**No AI at all** — no network call, no key needed. This is classic AAC and it
behaves the way you'd expect.

**AI Sentences.** Tiles accumulate into a selection; when the child pauses or
taps Play, the words become a spoken sentence.

Neither is the "real" mode. Switching takes two taps and nothing is lost.

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
the model, checked in our test suite, not a filter in the code. It holds up
well and it is not a guarantee.

### The same word in different contexts

This is what the mode is for. A word is one tile, used freely:

- `like` + `chocolate` → about liking chocolate
- `don't` + `like` + `chocolate` → about not liking it
- `want` + `more` + `chocolate` → asking for more
- `yucky` + `chocolate` → a complaint

Word class disambiguates sense, so `chocolate (food)` and `chocolate_milk
(drinks)` behave differently.

Two things to know: there's no single `don't like` tile, so negation costs a
second slot; and the tile limit is **2–8, default 4** (Admin → Now → **Tiles
per group**).

### Repetition is intensity

Re-tapping the last tile doesn't repeat the word — it escalates urgency. Tap
`chocolate` once and it's a request; tap it repeatedly and the sentence gets
more insistent.

A speaking child raises their voice or tugs a sleeve. A child using tiles has
tap count. The app reads it as the same signal.

### Age

The child's age sets the grammar and vocabulary register the model aims for.
**Sentence length does not currently scale with age** — the instruction is "one
or two short sentences" for every child. That's a known gap.

---

## When the sentence is wrong

**Long-press the sentence bubble.** Three options:

**Refine / Try Again** — tell the AI what to change in plain language: "make it
shorter", "she's asking, not telling", "use her name". It regenerates. Accept
the result and it's pinned for that combination.

**Hand-Type Sentence** — write the exact sentence yourself. Prefilled with the
AI's attempt so you can edit rather than start over. From then on, *this
sentence* is spoken whenever *those tiles* are selected.

**Suppress This** — this tile combination never speaks a generated sentence
again. A hard block on every path, including replay and escalation. Reversible
by long-pressing the muted bubble.

### These corrections stick

A correction is attached to **the words the child picked** — not to the model,
the prompt version, or the child's age. It survives app updates, model changes,
and birthdays. Correct something once and it stays corrected.

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

Also absent: **question words**. There are no `what`, `who`, `where`, `when`, or
`why` tiles in the built-in vocabulary yet. You can add them
([Adding vocabulary](adding-vocabulary.md)), but they don't ship.

If you're evaluating this for language development rather than functional
communication, those gaps are the ones to weigh, and we'd rather you heard it
here than discovered it in session.

---

## Who the text is for

The written sentence is for **you**. The child's feedback loop is the tiles
they can see and the voice they hear.

That shapes a few defaults. Tapping a tile speaks its word immediately, so the
child gets confirmation before any sentence exists. And a single selected tile
just speaks that word — no AI call, no sentence.

---

## Voice

Admin → Now → voice, rate, and volume, per child.

Worth doing once, properly: iOS ships a basic voice and offers **Enhanced** and
**Premium** downloads that sound markedly better. iOS Settings →
Accessibility → Spoken Content → Voices. It's a bigger quality jump than
anything in the app.

---

## Next

- **[Adding vocabulary](adding-vocabulary.md)**
- **[Sharing a board](sharing-boards.md)**
