<!-- SPDX-License-Identifier: Apache-2.0 -->
# Objection register

What clinicians actually push back on, what is actually true, and what we are
doing about it. One row per objection.

This is the source of truth for expert conversations (`docs/research/expert-track.md`),
for pilot onboarding, and for answering a DM without having to re-derive the
answer each time. It follows the same discipline as
`docs/claims-audit-2026-07-20.md`: every claim says exactly what it means, and
a real gap is written down as a real gap.

**Verdicts.** *Answered* — we do this, and can show it. *Partly* — true in part;
the honest answer includes a limit. *Gap* — they are right and we do not have
it. Never argue a Gap into a Partly.

Seeded 2026-08-09 from a conversation with **Brandi Lee Wentland, M.A.,
CCC-SLP** (AAC trainer, Out & About group host, Nika Project board). Rows 1–4
are hers, close to verbatim.

---

## 1. Images and icons for children with CVI

**Verdict: Gap.**

Nothing in the app addresses cortical visual impairment. `grep -ri "cvi"` over
the repo returns nothing. There is a High Contrast set, but as of 2026-08-09 it
is `isShippable: false`, invisible in release builds, missing art for 23
vocabulary keys, and measurably broken — 12% of its tiles pass their own style
contract, against 92% for both shipping sets. The 23 missing keys are almost
all core words (`i, me, my, you, your, it, that, in, on, up, down, all_done`),
so the set built for low vision is the one with no pronouns.

The only visual controls that do exist are a tile-density stepper (roughly
64–160pt) and per-tile caregiver photos.

**What we're doing.** Rebuilding High Contrast properly (see
`docs/imageset-highcontrast-log.md`). But the better answer is not our set — it
is that **art sets are commissionable**. The tooling to specify a style, generate
493 tiles, measure them against the style's own contract, and review and approve
them by hand is in the repo, and
`docs/guides/commissioning-an-image-set.md` documents it end to end. A CVI set
tuned to one child's acuity, color response, and clutter tolerance is a thing a
technical helper can produce in an afternoon for about $20 of compute — which is
a better outcome than us guessing at CVI from the literature and shipping one
compromise for everybody.

**Ask an expert:** what would actually be in the spec? Single salient target,
black field, saturated color, no competing detail, consistent placement — how
much of that generalizes, and how much has to be per-child?

---

## 2. "If AI anticipated their sentence, it may predict incorrectly"

**Verdict: Answered — but this is a misread worth correcting precisely, not
brushing off.**

BlasterAI does not predict. It does not complete a partial utterance, and it
does not guess a word the child did not choose. It **expands the exact tiles
that were selected**, and the system prompt makes that a hard instruction:

> Every selected word must be represented in the output — do not drop any tiles.

The child taps `mom` + `milk`; the model renders those two words as a sentence.
It never adds a third concept. Word class is passed as authoritative context so
sense is fixed by the tile, not guessed — `snack bar (food)` means eating one,
`snack bar (place)` means going there.

**The honest limit:** that is a model instruction, not a code-enforced filter.
There is no runtime validator asserting every tile appears in the output. We
measure adherence in an eval harness at development time
(`docs/claims-audit-2026-07-20.md` is the audit that forced this wording); we do
not gate it at runtime. Say "instruction, measured in eval" — never "guaranteed."

---

## 3. "…and not offer a way to modify it"

**Verdict: Partly. The half that is true is the important half.**

A caregiver has three durable controls, on a long-press of the sentence:

- **Refine** — a plain-language instruction ("make it shorter", "she's asking,
  not telling"), which regenerates and can be accepted as a pinned override.
- **Hand-Type** — replace the sentence outright. This exact text is spoken
  whenever those tiles are selected, from then on.
- **Suppress** — this tile combination never speaks a generated sentence again.
  Enforced on every path, including replay and escalation.

These persist against the *words the child picked*, not against the model or
prompt version, so a correction survives a model swap and a birthday
(`CacheKeyPolicy.stableKey`).

**The limit, stated plainly: the child cannot modify the sentence.** Only the
caregiver can. A child's controls are to add a tile, remove a tray chip, or
re-tap to escalate urgency. That asymmetry is real and it is the actual
substance of the objection.

---

## 4. "Kids need AAC that grows with them and teaches sentence building"

**Verdict: Gap.**

There is no modeling mode, no aided language stimulation, no parts-of-speech
scaffold, no prompt hierarchy. Single-word mode is **AI off** — each tap speaks
its word into a FIFO strip — which is classic AAC, not AAC that teaches. It is a
good honest fallback and it is not what she is asking for.

Three specific shortfalls behind the general one:

- **No question words.** `what`, `who`, `where`, `when`, `why` do not exist in
  the 493-word vocabulary. A child cannot ask a question.
- **Sentence length does not scale with age.** One fixed instruction — "one or
  two short, natural spoken sentences" — for a 3-year-old and a 15-year-old.
  Grade affects register through a single prompt line and nothing else.
- **Nothing adapts.** Utterances are logged for review, but nothing reads them
  back to change behavior. There is no progression and no measurement of the
  child's expressive level.

**Disposition:** all three are on the list and none are in the first TestFlight.
Question words and age-scaled length are small and were deliberately deferred to
keep the pilot build focused. A teaching mode is a genuine design problem, not a
backlog item, and it is the one to bring to experts before building anything.

---

## 5. "Would your app let a child use *chocolate* in other contexts?"

**Verdict: Answered. This is the strongest true answer we have.**

Yes, and it is the core of the design. A word is one `TileModel` with one
identity, appearing on as many pages and scenes as you like. Selecting up to
`maxSelectedTiles` (2–8, default 4) tiles composes freely:

- `like` + `chocolate` → liking it
- `don't` + `like` + `chocolate` → not liking it
- `want` + `more` + `chocolate` → asking for more
- `chocolate` + `ice_cream` → the compound

Word class disambiguates sense in the prompt, so `chocolate (food)` and
`chocolate_milk (drinks)` behave differently.

**Two honest caveats.** There is no single `don't like` tile, so negation costs
a second slot out of a default four. And duplicate tiles are not allowed in
sentence mode — re-tapping the last tile escalates urgency rather than repeating
the word.

---

## 6. Cost, and bring-your-own-key

**Verdict: Partly.**

BYOK means no BlasterAI server, no subscription, and the family pays OpenAI
directly. Sentence generation is cache-first, so repeated utterances cost
nothing.

**But the published figure is not yet verified.** "$0.10–0.50/month" appears in
`docs/gtm.md`, the in-app key guide, the FAQ, and the deck, and there is no
token accounting in the app to support it — that is gate 4 of
`docs/plan-2026-08-06.md`. Art generation almost certainly dwarfs sentence
generation, so the honest claim is probably "pennies a month to talk, plus a
one-time cost when a caregiver builds a new scene." Do not quote the number
until the ledger ships.

The real friction is not the money, it is that a caregiver must create an
OpenAI Platform account. That is a genuine adoption barrier and there is an
in-app guide for it, not a solution to it.

---

## 7. Privacy and training data

**Verdict: Answered.**

No BlasterAI backend. Data lives in SwiftData plus the family's own iCloud. API
calls are stateless and carry the selected words and nothing else — no child
name, no history beyond conversational context. Because the key is the family's,
they are OpenAI's customer directly, and API data is not used for training by
default (`docs/openai-tos-memo-2026-07-21.md`).

Single-word mode makes no network calls at all.

---

## 8. Will families actually use it? (abandonment)

**Verdict: Open — and the honest answer is we don't know yet.**

AAC abandonment is the field's central problem and nothing in the product has
been validated against it. Zero families have used this outside the author's
own. The pilot exists to find out.

Do not answer this with features. It is the reason to run the pilot, and saying
so is more credible than a pitch.

---

## 9. Open source — who maintains it?

**Verdict: Partly.**

Apache-2.0, developed in public. One author today. That is a real
bus-factor question for a clinician deciding whether to recommend it to a
family, and "it's open source so anyone can fork it" is not a satisfying answer
to someone who does not write software.

Worth being straight: the licence guarantees the work cannot be taken away or
paywalled; it does not guarantee anybody maintains it. The honest pitch is that
this is early and that early collaborators shape it.

---

## Cross-cutting note: TestFlight timing

`docs/plan-2026-08-06.md` recommends **internal testers only** for round 1, and
internal TestFlight testers must hold App Store Connect team accounts. Any
outside clinician needs **external** testing, which requires Beta App Review.
Factor that in before promising anyone a build date.
