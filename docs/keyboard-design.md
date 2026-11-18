# Keyboard design

Session 20 (2026-11-17 →). The plan and decisions live in the session's PR map
doc; this file is what the code needs to remember once the session is over.

## Scope

- QWERTY and ABC keyboards, with optional vowel highlighting.
- Each letter or digit is spoken as it is typed; Space speaks the word.
- Word matching against our vocabulary, with picture predictions (Avaz).
- An uncluttered numbers and math board (TouchChat).
- **No sentence generation** for a typed line: it is spoken as typed.
- Reachable as `sys:keyboard`, so a navigation bar can anchor it.
- Phonetic keys: off the table until a better voice for them (see the probe).

## What the other apps do

**TouchChat** (Aubrey's device). Every keyboard is an ordinary page of cells on
a 10-column grid; a key is a cell. Five pages — Beginning Keyboard, ABC 123,
Beginning Numbers, Phonics (short vowels), Phonics (long vowels) — each linking
to the others from inside the grid, so switching never goes through Settings.
Phonics pages add `ch ph sh th`, a row of silent vowels and a Long ⇄ Short
switch. The numbers page is sparse: digits, operators (`- + ÷ × = % $ ,`) and
`:00 :15 :30 :45`. Every page has clear, backspace, delete word and Space.

**Avaz.** One full-bleed keyboard with big keys, vowels tinted when the option
is on. A prediction bar shows picture tiles for words it knows and text for the
rest, predicts the next word, and pages with an arrow. `.?123` switches to
numbers. Settings: QWERTY or ABC, highlight vowels, prediction, and enlarge
keys on selection. The letters of the word being typed show in the message box
tinted red; Space turns them into a word, with a picture when it has one.

Both speak each key as it is typed and read the word on Space.

## Decisions

- **Keys: hybrid first, surface likely.** A keyboard page is an ordinary page
  (links, navigation bar, levels and editing all work) whose cells may hold key
  tokens (`key:a`, `key:space`, `key:bksp`, `key:shift`) drawn as keys. Ten
  columns is tight — a QWERTY row is exactly ten letters, with no room for
  backspace beside it — so the keyboard area is built to swap to its own key
  geometry (Mark, 2026-11-18).
- **Typed text shares the message box.** One text item per word; the word being
  typed shows tinted red until Space commits it; a committed word that is in the
  vocabulary becomes that word's chip. A line with typed text ignores the
  words-per-message cap and is never sent to sentence generation (Mark).
- **Phone: the iOS keyboard.** It can speak each character (by watching the
  text change), carry our prediction bar on top (`toolbar(placement:
  .keyboard)`), turn autocorrect off and use the number pad. It cannot tint
  vowels, offer ABC, resize keys or stay up without a focused field. The
  numbers page stays ours on both, since the system keyboard has no `÷` or
  time keys.

## Typed text in the message box (PR C)

The keyboard's side of `SentenceEngine` is its Typing extension:
`typeKey`, `typeSpace`, `typeBackspace`, `typeDeleteWord`,
`speakTypedLine`. Tests: `TypingTests`.

- **One message box.** A typed word joins whatever the box is showing: the
  active group in sentence mode, the strip in single-word mode. There is no
  second tray for typing; two trays over two engine states has bitten before.
- **The word being typed** is `typingDraft`, drawn red at the end of either
  tray (`TypingDraftView`) until Space commits it. Each key is spoken as
  pressed, each word as committed, both through `SpeechNormalizer`.
- **A word we have becomes its tile.** `TypedWords.match` looks the word up by
  label, value or key, skipping hidden words, folders and the Letters pack, so
  "cookie" is the cookie chip with its picture and "a" is the word *a*. A word
  we don't have is a text chip (`TileSelection.typed`, key `<typed>:word`).
- **A typed line** (`TileGroup.isTyped`) is never sent for a sentence and
  ignores the words-per-message cap. It stays typed even when every word
  matched a tile, and a tile tapped onto it joins it. Play says it through
  `SpeechNormalizer.line`; an emptied line stops being typed.
- **Backspace** takes a letter off the word being typed, or, with none, the
  last word. Delete word takes the word being typed, or the last word.
  Clear and Done take the word being typed too.

## Speech: `SpeechNormalizer`

`claudeBlast/Engine/SpeechNormalizer.swift`, tested case by case in
`SpeechNormalizerTests`.

- `key(_:)` — one key press. Symbols say their name (`÷` → "divided by",
  `:15` → "fifteen", `:00` → "o'clock"). A letter is said lowercase (see the
  probe); digits pass through.
- `tile(_:)` — a word tile, alone or in the message box line. A
  one-character tile says its key, so the Letters pack's "A" says "a", not
  "capital A". **The one use today:** `SentenceEngine.speakTile` and
  `speakStrip`. The pronoun *I* in a line stays a word.
- `line(_:)` — a typed line on Speak. Words are left alone ("I am 7");
  only the forms a voice misreads are rewritten:

  | typed | said |
  |---|---|
  | `2 + 2 = 4`, `2+2=4` | 2 plus 2 equals 4 |
  | `12 ÷ 4`, `6 × 7`, `10-3` | 12 divided by 4, 6 times 7, 10 minus 3 |
  | `3 < 5`, `9 > 2` | 3 is less than 5, 9 is greater than 2 |
  | `5/3`, `1/2`, `7/100` | 5 thirds, 1 half, 7 over 100 |
  | `$5`, `$1`, `$2.50` | 5 dollars, 1 dollar, 2 dollars and 50 cents |
  | `50%` | 50 percent |
  | `3:00`, `3:15` | 3 o'clock, 3 15 |

  `-` is minus only between digits: "x-ray" and "I want - no" are not
  arithmetic. A denominator past twelve reads "over".

### The probe

`swift tools/speech_probe/probe.swift <out-dir> [voice-id …]` renders every
case raw and normalised, a set of lone letters, and the phonics sounds through
IPA, with each voice, and writes a listening sheet (`index.html`, open in
Safari). With no ids it uses every Enhanced and Premium English voice plus
compact Samantha. The Mac's voices are the iPad's, so what is heard there is
what a child hears. Durations are in the sheet; 0.00 s means silence.

**First run, 2026-11-18, compact Samantha, by Mark's ear.** This Mac had no
Enhanced or Premium voice; a rerun with one is still worth doing.

Raw, the voice gets arithmetic wrong in ways a child would notice:

| typed | heard raw |
|---|---|
| `12 ÷ 4 = 3` | "twelve percent four equals three" |
| `10 - 3 = 7` | "ten three equals seven" (the minus is dropped) |
| `6 x 7` | "six x seven" |
| `5/3` | "five slash three" |
| `÷` alone | "division sign" |
| `=` alone | "equal sign" |
| `A` alone | "capital A" |

So, as with *I* (`SpeechSynthesizer.loneSpeech`), **what is spoken is spelled
out, and what is shown is what was typed**. The message box keeps `12 ÷ 4 = 3`;
only the speech goes through `SpeechNormalizer`. A letter `x` between numbers
is times, since QWERTY has no `×`. Lone letters are fine lowercase, so
`key(_:)` lowercases them.

Fractions: "slash" is tolerable, and fraction words don't scale to `5/32`.
The normaliser says the common ones as a child learns them (halves through
twelfths) and anything else "over" (`5/32` → "5 over 32").

**IPA: not good enough.** Every phonics sound renders, but all of them are
clipped (lone stops as short as 0.07 s), and none sounds like a teacher
saying the sound. **Phonetic keys are off the table for now** (Mark,
2026-11-18). They come back only with a better voice for this part of the
app: recorded audio per key, riding with the per-tile recorded-audio work, or
a different TTS.

## PR map

| PR | What |
|---|---|
| A | Build 13 + session 19 carry-forwards (#200) |
| B | `SpeechNormalizer`, the probe, this doc |
| C | Typed text in the message box |
| D | Keyboard pages: QWERTY and ABC |
| E | Numbers and math page |
| F | Word prediction |
| G | `sys:keyboard`, `sys:keyboard-abc`, `sys:numbers` in the page chooser; guide; build |
