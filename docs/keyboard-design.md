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

- **Keys: a surface, not cells (Mark, 2026-11-18).** The hybrid of key cells
  on the 10-column grid was the plan; ten columns leave no room for backspace
  beside a QWERTY row, so the keys got their own geometry from the start. A
  keyboard page is still an ordinary page of BlasterAI 60 — `sys:keyboard`,
  the navigation bar and the rail all work — with nothing stored on it: the
  grid area draws the keys. The cost is that a keyboard is not editable in
  the board editor.
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

## Keyboard pages (PR D)

`KeyboardLayout` is the key geometry; `KeyboardSurfaceView` draws it in the
grid area when the page showing is `keyboard` (QWERTY) or `keyboard_abc`
(ABC), as `<system>:` pages from any board built on BlasterAI 60. A scene's
own page of that name is just a page. Tests: `KeyboardLayoutTests`.

- Every row is 11.5 key-widths, so rows of any key count end on the grid's
  edge. QWERTY: `q`–`p` + backspace; `a`–`l`, `'` + speak; shift, `z`–`m`,
  `, . ?`; the ABC switch, space, delete word. ABC runs the alphabet the same
  way.
- The top content row is kept empty for word prediction (PR F), so the keys
  don't move when it lands.
- Shift is one-shot; a quick second tap locks it. Key caps show what will be
  typed. Keys are spoken lowercase whatever Shift shows.
- Speak (green) commits the word being typed and says the line, never a
  generated sentence (`typeSpeakLine`).
- Vowels are tinted unless Settings › Look, Sound, Feel › Keyboard ›
  Highlight Vowels is off (device-local).
- The phone's iOS keyboard path is its own PR; a phone shows the same
  surface, smaller.

## Numbers page (PR E)

`KeyboardLayout.numbers`, at `sys:numbers`: digits and backspace; `+ − × ÷ =
< > % $ .` and Speak; the clock keys `:00 :15 :30 :45`, `/` and `:`; then
QWERTY, ABC, space and delete word. No letters, no Shift. Both letter
keyboards open it with a `123` key.

- `−` is the minus sign (U+2212), which `SpeechNormalizer` reads as minus
  wherever it lands; a hyphen is minus only between digits.
- A clock key adds to the hour typed before it: `3` then `:15` is `3:15`,
  said "3 15"; `3` then `:00` is "3 o'clock". Pressed, `:45` says
  "forty-five".
- A sum typed without spaces is one word in the message box (`2+2=4`) and is
  said as a sum.

## Math helper (PR E)

The numbers page's purple `?` key (Mark, 2026-11-20). `MathHelper` solves;
`MathWalkthrough` (`MathHelperPanel.swift`) paces it in the page's top row,
in **one card that changes in place** (Mark, 2026-11-20): the sum shrinks a
pair at a time — `1 + 2 + 3 + 4`, `3 + 3 + 4`, `6 + 4` — the pair being
worked out on yellow, then, as it collapses, the number it made on green.
Each step is said before the next (`MathHelper.Frame`). A missing number is
shown as the equation turned round: `3 + ? = 7` becomes `? = 7 − 3`. Then
the answer goes in the line, the sum is said whole, and a star marks it. No AI: exact fractions, × and ÷
before + and −. Tests: `MathHelperTests`.

| typed, then `?` | working | line becomes |
|---|---|---|
| `1+2+3+4=` | 1 + 2 = 3, 3 + 3 = 6, 6 + 4 = 10 | `1+2+3+4=10` |
| `1+2+3+4` | the same | `1+2+3+4=10` |
| `3+?=7` | 7 − 3 = 4 | `3+4=7` |
| `2+2=5` | "Not quite: 2 + 2 = 4" | as typed |
| `3?5` | "3 < 5" | `3<5` |

- A `?` typed where a number goes (`3+?`) is the number to find; the helper
  waits for the rest. Speak on a line with a `?` in it asks too.
- Answers: whole, negative (`−2`), a decimal that ends within three places
  (`3.5`), else a fraction (`3 1/3`, said "3 and 1 third").
- What it can't do it says: dividing by zero, a sum with words or money in
  it, two `?`s, numbers too big.
- Typing on clears the working; Clear does too. The hint row shows
  `2 + 3 = ?` until then.
- A one-step sum (`3×4?`) shows only its answer: its one step *is* the
  answer, and showing both said it twice (Mark, 2026-11-20).
- **Each sum is said once** (`SpokenSums`, on the line and on the strip).
  Play says what was typed since the last Play when it is all sums, so
  `1+1=2`, Play, `2+2=4`, Play says each once; with nothing new it says the
  last sum again. A tap on a sum says it again (any other word still comes
  off on a tap). A line with words in it is said whole, as before. The
  helper works on the newest sum alone, after a finished one (`1+1=2`) even
  without a Play between.
- **A said sum is one word** (`markSpoken`): typed with spaces, `1 + 1 = 2`
  becomes `1+1=2` once said, so it is one card, one tap to hear again, one
  backspace to take off. Two whole sums stay two.
- **A checked answer marks the line** (`MathHelper.correction`): right, the
  `?` comes off; wrong, `5+5=9?` becomes `5+5=9→10`, drawn `5 + 5 = 9̶ 10`
  (the 9 struck in red, 10 in green, an orange card) and said "5 plus 5 is
  not 9, it's 10". A sum put right whole is `3>5→3<5`. Tapped, it replays
  the whole check: the working, then "Not quite" (Mark, 2026-11-20).
- **A tap on a said sum replays its working** in the helper row, as when it
  was first worked out (`mathReplayHandler`); one that doesn't add up
  replays as checked. Off the numbers page, the tap just says it.
- **How sums draw** is an experiment setting (`SumStyle`): *One Card per
  Sum* (default) — the newest said sum green with a star, older ones grey
  and smaller, and the helper's answer moves up into the message box when
  it is said, freeing the row; or *Key per Character* — a plate per
  character. Either way red while being typed, purple-edged until said.

## Phone layouts and the calculator (E.5)

**Phone portrait** (a grid under 500 pt wide) takes compact layouts
(`KeyboardLayout.compactRows`, Mark 2026-11-20: 11.5 keys across drew thin,
tall slats):

- **Letters:** 10 across, as the iPhone's own keyboard: backspace beside
  z–m; 123, the other letter keyboard, `,` space `.` `?` and Speak on the
  bottom row. No delete word.
- **Numbers:** a calculator's pad, 5 across: `789÷⌫`, `456×=`, `123−<`,
  `0.%+>`, the clock keys and `?`, `$ / :` and space, then the switches
  and Speak.
- Keys are never taller than 1.45 of their width; they sit at the bottom
  by the rail, letters sized to the key's narrower side.

**The calculator** (`KeyboardLayout.calculator`, `sys:calculator`, the
*Calc* key on the numbers page) is five across at every size, styled as a
calculator: a dark display (`CalculatorDisplay`) over square keys, the
display taking the height they leave.

- Keys: `C ( ) % ÷`, `x² 7 8 9 ×`, `√ 4 5 6 −`, `xʸ 1 2 3 +`, `⌫ 0 . =`,
  then 123, ABC, QWERTY, `?` and Speak. C is delete word.
- `=` is a plain key, so a child can type `5+5=10` and say it. The purple
  `?` is the math helper, as on the numbers page; its working shows in
  place in the display, then the answer (Mark, 2026-11-20: overloading `=`
  left no way to type a sum's answer yourself).
- The math engine now takes brackets (`2 × (3 + 4)`), whole-number powers
  (`3²`, `2^5`, `2^3^2` = 2^9) and square roots (`√9 = 3`; `√2 ≈ 1.414`,
  to three places). Said as "squared", "to the power of", "the square
  root of", "is about". A power or root over a missing number is past it.

## Word prediction (PR F)

The letter keyboards' top row is the prediction bar (`PredictionBar`, over
`WordPredictor`), built from the vocabulary and the last 3,000 utterances
when a letter keyboard opens. Nothing leaves the device.

- **Typing:** words starting with what is typed — our words (a picture
  chip) and words typed before that we don't have (a text chip) — ranked by
  what has followed the last word, then the person's own use, then words
  with pictures, then shorter. Hidden
  words, folders, the Letters pack and sums are never offered.
- **Only once a word is started** (Mark, 2026-11-20): with nothing typed
  the bar is empty. While typing, words that have followed the last word in
  the line (from their own history) rank first.
- **Order** is an experiment setting (`WordPredictor.Order`):
  *Alphabetical* (default) keeps the same letters showing the same words in
  the same places, so a person learns how many letters it takes — fixed
  positions are what AAC motor planning rests on (Mark, 2026-11-20);
  *Most Used* ranks as above.
- A tap types the word in full and commits it, as Space would. More than
  fit, an arrow pages. Settings › Keyboard › Word Prediction turns it off.

## Keyboard settings

Settings › Look, Sound, Feel › Keyboard (Mark, 2026-11-20), all
device-local (`AppSettingsKey.keyboard*`):

- **Keyboard Button Opens** — QWERTY (default), ABC, Numbers or Calculator: the page
  the rail's Keyboard button opens. Each keyboard still switches to the
  others.
- **Word Prediction** (letters), **Highlight Vowels** and **Highlight Signs** (numbers: `+ − × ÷
  = < >` in pale blue).
- **Math Helper** — off, `?` is just a key and the hint row is empty;
  **Show the Working** — off, `?` goes straight to the answer.
- **Experiments** — Sums in the Message Box (cards or keys), Older Sums
  Smaller.

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
