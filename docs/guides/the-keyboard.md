# The keyboard

Typing, numbers and sums: for the user who spells some of what they want to
say, and for maths. Everything here says what is typed — no AI is involved.

---

## Opening it

The **Keyboard** button on the rail opens it. Which keyboard it opens is in
**Settings › Look, Sound, Feel › Keyboard › Keyboard Button Opens**: QWERTY,
ABC, Numbers or Calculator.

Each keyboard is also a page of BlasterAI 60, so it can sit in a navigation
bar like any folder. In the page editor, type a word and the page it opens
(see [Editing a board](editing-a-board.md)):

| Type in a cell | Opens |
|---|---|
| `keyboard > sys:keyboard` | QWERTY |
| `keyboard > sys:keyboard_abc` | ABC |
| `keyboard > sys:numbers` | Numbers |
| `keyboard > sys:calculator` | Calculator |

Or type **>** and tap **Browse** to choose one from BlasterAI 60's pages.

When the board's navigation bar already has the keyboard the rail's button
would open, the button opens the next one instead — Calculator, then
Numbers, QWERTY, ABC — and its label says which. A bar with **Keyboard** in
it gets a **Calculator** button on the rail. Every keyboard has
keys for the others, so the user can switch without leaving it.

## Typing words

- **Each key is said as it is pressed,** and **Space** says the word.
- The word being typed shows **in red** at the end of the message box until
  Space finishes it.
- A word that is in the vocabulary becomes **its tile**, picture and all:
  typing *cookie* puts the cookie tile in the message box. Anything else
  stays as the word.
- **Speak** (the green key) says the whole line **as typed**. A typed line is
  never sent to the AI for a sentence, and isn't held to the words-per-message
  limit.
- **Backspace** takes off a letter, or the last word when nothing is being
  typed. **Delete word** takes the whole word.
- **Shift** capitalises one letter; tap it twice quickly to lock it. Letters
  are always *said* lowercase, because a voice reads a lone capital as
  "capital A".

**Vowels are tinted** to help find them. Turn this off in **Settings ›
Keyboard › Highlight Vowels**.

## Word prediction

Once a word is started, the row above the keys offers words it could be —
with their pictures where we have them, and words the user has typed before.
Tap one to type it in full.

The words are in **alphabetical order**, so the same letters always show the
same words in the same places. A user learns how many letters it takes to
find a word, as they learn where a tile is on a board. If you'd rather have
the most-used words first, **Settings › Keyboard › Prediction Order** has
**Most Used** to try.

Nothing is offered until a word is started. Prediction can be turned off.

## Numbers

**123** opens the numbers page: digits, the signs a sum needs (+ − × ÷ = < >),
%, $, a decimal point, and the clock keys **:00 :15 :30 :45**, which add to
the hour typed before them (3 then :15 is 3:15).

Sums are **said as sums**: *12 ÷ 4 = 3* is "12 divided by 4 equals 3", *5/3* is
"5 thirds", *$2.50* is "2 dollars and 50 cents". What is shown is what was
typed.

## The ? key: working a sum out

The purple **?** works out the sum typed before it, a step at a time:

- **1+2+3+4=?** — the sum shrinks a pair at a time (1 + 2 = 3, then 3 + 3 = 6,
  then 6 + 4 = 10), each step said, and the answer goes in the message box.
  × and ÷ come before + and −.
- **3+?=7** — finds the missing number, by turning the sum round: ? = 7 − 3.
- **5+5=9?** — checks an answer. Wrong, it says "Not quite: 5 + 5 = 10", and
  the message box shows the 9 struck through with 10 beside it. Right, it
  says "Yes!".
- **3?5** — picks the sign: 3 < 5.

When it can't help — dividing by zero, a word in the sum — it says so.

**Each sum is said once.** Type and play sums one after another, and **Play**
says only the new one. Tap a sum in the message box to see and hear its
working again.

**Show the Working** in Settings turns the steps off, so ? goes straight to
the answer, and **Math Helper** turns ? into an ordinary key. **=** is always
an ordinary key: a learner can type *5+5=10* and say it themselves.

## The calculator

**Calc** on the numbers page opens a calculator: a display over big keys, with
brackets, squares (x²), square roots (√) and powers (xʸ) down the left. It
works sums out the same way, with the steps in its display: *2 × (3 + 4)* does
the brackets first, *√9* is 3, and *√2* is about 1.414.

## On a phone

In portrait the keyboards are laid out for a phone: letters ten across, as on
the phone's own keyboard, and the numbers as a calculator pad.

## What it doesn't do

- **Phonics keys** (*ch*, *sh*, *th*, long and short vowels) are not here yet.
  The phone's voice clips single sounds too short to teach from; they will
  come with recorded sounds.
- The keyboards **can't be edited** in the board editor; their keys are fixed.
- **Fractions** work out exactly, but there is no fraction key — type *3/4*.
