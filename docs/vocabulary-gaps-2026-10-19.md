# Vocabulary gaps — BlasterAI 60 vs Vocal Flair 60 (2026-10-19)

A snapshot, written so we can be up front with testers about what we know is
missing. Find Word now shows testers in a few taps whether a word exists, so
expect their reports to sharpen or reorder this list.

## How this was measured

`tools/compare_levels.py` reads the Vocal Flair 60 board set (OpenAAC /
CoughDrop, CC BY 4.0) from its .obz plus CoughDrop's public board API, and
compares it with `vocabulary.json` and BlasterAI 60's pages.

- **Size.** BlasterAI 60 has 610 words. Vocal Flair 60 reaches 2,538 at its
  top level, across 95 boards.
- **Overlap.** 505 of our 610 words (83%) are somewhere on theirs. Each of our
  pages is 65–100% covered by its equivalent. Our ~105 words they lack are
  mostly kid-specific: goldfish cracker, playdoh, bubbles, potty, nap, line up,
  "I love you".
- **Where their size comes from.** A long tail: ~440 verbs on 17 alphabetical
  boards and ~650 adjectives on 18, plus domain folders (Jobs, Church,
  Holidays, Space, Travel, Kitchen, Tools, Music, Medical, News, …).
- **Levels.** Vocal Flair levels only its home board (10 levels). Every other
  board is all-or-nothing: fully shown once the folder leading to it appears.
  BlasterAI 60's prototype levels (four, on Home) follow the same model.

## What we are deliberately not copying

- **Domain folders** (church, jobs, technology, holidays…). A static board
  needs these canned; BlasterAI can build a scene for any topic with AI and
  generate its art, and vocabulary packs installed by URL let caregivers and
  domain experts fill and share them.
- **Prefix boards and word endings** (some-/any-/every-/no-, -s/-ed/-ing).
  Worth doing with clinical guidance, alongside keyboard work.
- **Adult content** — relationship status, compass points, news, organs.

## Core gaps worth closing (~90 words)

Candidates for one vocabulary PR; the final list is for clinical review.

- **Time.** The `time_when` page is sparse and names nothing.
  - Days of the week. The biggest hole; cheap, because day strips are drawn in
    code.
  - breakfast, dinner (we have lunch).
  - early, late, then, until.
  - hour, minute, clock, month, year.
  - Seasons, perhaps on Weather. Month names are lower priority.
- **Small words.** of, from, by, if, too, these, those, both, each, already;
  did, does, has, could, would, should, were. In AI Sentences mode the model
  supplies grammar, so the gap hides; in Single Words and text mode the child
  must build it.
- **Feelings.** mad, nervous, confused, embarrassed, shy, disappointed,
  curious, careful, strong, weak, dizzy, sore.
- **Social.** I need a break (self-advocacy; the most important on this list),
  you're welcome, see you later, never mind, really, oh, sounds good, please
  say that again.
- **Questions.** how many, how much, what time is it, can I have a turn.
- **People.** kid, child, man, woman, person, name, parent, son, daughter,
  uncle, cousin.
- **Actions.** fix, bring, hold, pick, change, stay, wake, hurry, visit.
- **Describe and position.** favorite, real, fake, weird, stuck, tall,
  difficult, above, below, next to, forward, backward.

Not gaps, despite what a raw diff says: gray/grey, let's/lets, "I don't know"
(spelling and punctuation differences).
