<!-- SPDX-License-Identifier: Apache-2.0 -->
# Porting BlasterAI

Written for someone building an AAC app on another platform — Linux, Android,
Windows, the web — who would rather not rediscover everything this one learned
the hard way.

Everything here is Apache-2.0, including the artwork. You owe us nothing but the
`NOTICE` file. What follows is the part that is worth more than the code.

---

## 1. What you are actually forking

**The Swift is the least valuable thing in this repository.**

BlasterAI is SwiftUI + SwiftData targeting iOS 26. There is no portable core to
lift out — the data layer is SwiftData model classes, the UI is SwiftUI, the
speech is `AVSpeechSynthesizer`, and the sync is CloudKit. Porting is a rewrite,
not a translation, and anyone who starts by reading `.swift` files will spend a
month learning that.

What transfers is everything else, and it is most of the work:

| What | Where | Why it took time |
|---|---|---|
| 508-word vocabulary with word classes | `claudeBlast/Resources/vocabulary.json` | Curation, deduplication, singular/plural rules |
| Scene and page structure | `claudeBlast/Resources/scenes/*.json` | Board design, link topology |
| 3,252 tile images, 5 styles | `claudeBlast/TileImageSets/` | ~$12–$42 per style in API spend (gpt-image-2), plus review |
| 504 subject prompts, for bulk generation of a new image style | `tools/prompts.json` | One hand-tuned prompt per word |
| 4 style prompts | `claudeBlast/Resources/image_styles.json` | Many iterations each |
| The generation pipeline | `tools/generate_sets.py` and friends | Scoring, refinement, tone transforms |
| The sentence prompt | `claudeBlast/Engine/SentencePromptBuilder.swift` | Rewritten repeatedly against an eval harness |
| The rules in this document | here | Shipped bugs |

Read this document, take the JSON and the images, and write the app in whatever
language you like.

---

## 2. The assets, and the licence

### Artwork

`claudeBlast/TileImageSets/` is one flat directory of HEIC files at 512px,
named `{set_prefix}_{key}.heic`:

| Set slug | File prefix | Description |
|---|---|---|
| `classic` | `cls` | Flat pictogram, light skin tone |
| `classic_medium` | `clsm` | Same art, medium skin tone |
| `classic_medium_dark` | `clsmd` | Same art, medium-dark skin tone |
| `playful_3d` | `p3d` | Soft clay/plasticine 3D |
| `high_contrast` | `hc` | White on black, accessibility |

`claudeBlast/Services/ImageSetCatalog.swift` is the source of truth for which
sets exist and which ship. 567 distinct keys have art; the per-set counts run
557–563, so coverage is near-total rather than total.

**All of it is OpenAI-generated and Apache-2.0.** This matters more than it
sounds. Every other open AAC project runs into symbol licensing — ARASAAC's
terms, SymbolStix, PCS — and the licence tends to be the thing that stops a
hobby project becoming something a school can install. You can ship these in a
distro, print them, put them on a worksheet, and sell the result. ARASAAC art
was removed from this project in July 2026 and survives only as a style
description; see `NOTICE`.

### Vocabulary

`vocabulary.json` is deliberately boring:

```json
[
  { "key": "apple",  "wordClass": "food" },
  { "key": "all_done", "wordClass": "core" }
]
```

`key` is lowercase, with internal whitespace collapsed to underscores
(`TileModel.normalizeKey`). It is the asset name, the cache identity, and the
cross-platform identifier all at once.

> **The one irreversible rule: `key` is a language-neutral concept id and is
> never translated.** The human-readable label is a separate field. Translate
> keys and every image filename, cache entry, exported board and shared scene
> breaks across languages. This is the decision that is expensive to reverse
> later, so make it now.

### Scenes

`scenes/core_first.json` shows the shape:

```json
{
  "key": "core_first",
  "name": "Core-First - System Supplied",
  "homePageKey": "home",
  "isDefault": true,
  "pages": [
    { "key": "home",
      "tiles": [ { "link": "people", "to": "people", "audible": false } ] }
  ]
}
```

A tile on a page is a reference to vocabulary plus page-local behaviour: where
tapping navigates (`to`), and whether tapping speaks (`audible`). The same word
can be a link on one page and a spoken tile on another.

### Attribution

Apache-2.0 obliges you to keep the licence, state significant changes, and
preserve the `NOTICE` file. That is the whole obligation. You do not need
permission, you do not owe a link, and a fork is not a favour anyone is granting
you.

---

## 3. The data model, without SwiftData

Implement this in SQLite, Postgres, files, whatever. The shape matters; the
storage does not.

The mapping is deliberately boring: one table per model type works, and so does
a document store — these are self-contained records with string keys and no
interesting joins. **It only gets hard if you chase a serverless design that
syncs.** Sync is what forces the rules further down this section, and it is worth
being honest with yourself about whether you need it.

### Sync is not how most things actually move

BlasterAI does sync, within one family's CloudKit space — and that is a narrow
window. It covers a parent's iPad and a parent's iPhone. It does not cover the
therapist, the school device, the grandparent, or anyone on another platform, and
those are most of the people who need to hand something to someone else.

So the app leans heavily on **import and export as first-class features**, not as
a backup afterthought. Scenes, vocabulary packs, colour settings and tile art all
travel as files a person can text or email. A therapist builds a board and sends
it to a family; it arrives complete, artwork included, and tapping it rebuilds the
board. No account, no server, no shared iCloud.

If you are porting, this is the good news: **build the file formats and you have
covered the cases sync never reaches.** A single-device app with solid import and
export is more useful to a real family than a synced app that only syncs within
one vendor's ecosystem, and it avoids every constraint in the rest of this
section. For a Linux laptop that lives on one desk, it is almost certainly the
right answer.

- **Tile** — `key`, display value, `wordClass`, optional art alias, plus review
  state. See `claudeBlast/Models/TileModel.swift`.
- **Page** — a key and an ordered list of page-tiles.
- **PageTile** — tile key + `link` target + `audible`.
- **Scene** — named set of pages with a designated home page.
- **SentenceCache** — generated sentences keyed by tile combination.
- **Utterance log** — the immutable record of what was actually said.

### Rules worth carrying over

**Art belongs to the picture, not the tile.** A tile's art key is its alias when
it has one, otherwise its own key (`TileModel.artKey`). Several tiles
deliberately share one picture — a page cover, a pronoun borrowing another
word's image. We shipped a bug where reads went through the alias and writes
went through the key, so generated art landed where nothing ever looked and a
page cover reported "needs art" forever. Pick one accessor and route everything
through it.

**A word hidden from the child must be hidden everywhere.** `isHiddenFromChild`
is a single named invariant (retired **or** awaiting review), and every
child-facing surface reads it. Two independent booleans checked ad hoc is how a
board ends up showing a word a caregiver hid.

**Reversible hiding beats deletion.** Retirement keeps the record so history
still renders and sync stays additive. Hard delete is a separate, explicit path.

**Sentinel defaults rather than nulls, if you ever sync.** Our constraint is
CloudKit-specific — it stores no nulls, so a nil-valued optional never
materialises its field in the schema, and after promotion the schema is
read-only. The general lesson survives the platform: decide early whether
"absent" and "empty" are the same thing, because changing your mind later is a
migration. `claudeBlast/Models/SchemaVersions.swift` has the full rule set and
the reasoning, including why there are no relationships and no unique
constraints anywhere.

---

## 4. The child's surface

The part that must be right before anything clever matters.

**A tap speaks immediately.** Before any network, any lookup, any spinner. The
word the child touched comes out of the speaker now. Everything else in this
document is negotiable; this is not.

**Home is cell 0 of every page.** Not a chrome button in a toolbar — the first
cell of the grid, in the same position on every page, styled as chrome rather
than vocabulary. Invariant position is motor planning, which is how AAC users
actually navigate: the hand learns where a word lives. Moving a target between
pages costs a child fluency they spent months acquiring.

**Two interaction modes.** Single-word (every tap speaks its word, no AI, no
network) and sentence mode (tiles collect in a tray and a model assembles them).
Single-word is the majority configuration and the one that must work perfectly
with no key and no connection.

**The tray has no back button.** Tapping a tile in the tray removes it. One
gesture, reversible, no separate control to find.

**Who reads what.** The generated sentence text is for the adult. The child's
feedback loop is the tiles and the speech. This distinction decides several
design arguments — it is why escalation adds words rather than exclamation
marks, and why the sentence appearing on screen is not a failure of the
interface.

**Grid geometry is computed, not fixed.** Tiles per page derive from available
space against a minimum tile size, so a phone and a tablet show different counts
of the same board. See `GridLayoutCalculator`.

---

## 5. The AI layer

Seven surfaces call OpenAI. The models today are `gpt-4o-mini` for text,
`gpt-image-2` for art, and `omni-moderation-latest` for the policy net. Run
`python3 tools/audit_openai_models.py` for the current authoritative list.

### Why a small model, and not the best one available

Cost is the obvious reason and it is the less interesting one. `gpt-4o-mini`
reaches roughly 34,000 sentences per dollar, so the child-facing path is
effectively free — but we would pay more for better output if better output were
what we got.

**The larger models drift.** Given three tiles they start being helpful:
*"Did you mean to ask your mom for chocolate?"* — clarifying, hedging, offering
alternatives. That is good assistant behaviour and completely wrong here. The
job is not to converse with the child; it is to say the one thing the child
selected, in their voice, immediately. A model that asks a follow-up question has
put itself in the conversation, and the child now has to answer a machine instead
of talking to their mother.

Test for this specifically when you choose a model. A bigger model will look
better on a generic benchmark and be worse at this. What you want is a model that
does exactly as it is told and then stops.

### 5.1 Sentence generation

`claudeBlast/Engine/SentenceEngine.swift`. The order of operations matters and
is worth copying exactly:

1. **Suppressed override → stop.** A caregiver can silence a tile combination
   permanently. This is a hard block on every path including escalation and
   replay. The tiles show; nothing is said.
2. **Record the hit** when this is a repeat, even though the cached sentence is
   about to be bypassed.
3. **Durable caregiver override → serve it.** A hand-typed or accepted-refined
   sentence wins over anything generated.
4. **Cache lookup** — skipped for repeats, replays and refines, because the
   whole point of those is to produce something different.
5. **Build the prompt and call the model.**

**The staleness guard.** After every await, check that the tiles you generated
for are still the tiles on screen (`tiles == activeGroup.tiles`) and discard the
result if not. Without it a slow response overwrites a selection the child has
already moved on from, and the device speaks a sentence about the previous
thought. This check appears at every return point in the generation path, and
each one is load-bearing.

**Timers, with defaults:**

| Behaviour | Default | Range |
|---|---|---|
| Idle nudge before prompting to play | 2.5 s | 0.5–5 s |
| Attention on the Done button after lock | 5 s | fixed |
| Auto-commit the group | 30 s | 5–120 s, 0 disables |
| Max tiles per group | 4 | 2–8 |
| Conversation history fed back | 5 sentences | fixed |

Generation fires immediately when the tile cap is hit; below the cap it waits
for the child to stop.

**Keep idle timing and the in-flight request on separate handles.** They were
one task once, and re-arming the idle timer cancelled the generation.

### 5.2 The prompt

`SentencePromptBuilder.swift`. System messages load from a bundled JSON file
with a `{stage}` placeholder substituted per child; the user turn is only the
tiles, formatted `word (class), word (class)`.

Things that were learned rather than designed:

- **Assume self-centred intent.** `mom, milk` means *can I have some milk*, not
  *you should drink some milk*. This single instruction fixes a large fraction
  of wrong outputs.
- **The word class is authoritative.** A small model lets its prior for a word
  override a surprising category — `pony (food)` comes out as a pet. An explicit
  "honour the category even when unusual" rule, placed near the end of the
  system turn, is what holds it.
- **Grammar by word class.** The longest instruction in the prompt, and the one
  that earns its length: `(people)` is who you address, `(feeling)` and
  `(health)` are states the child *is in* and never things they want. Without it
  you get "I want hungry".
- **Tile order is explicitly incidental.** Say so, or the model infers meaning
  from tap order and infers it differently per phrasing.

### 5.3 Escalation

Repeating the same tiles is how a non-verbal child turns up the volume. The
prompt climbs a four-rung intensity ladder keyed to the repeat count, must be
strictly more insistent than its own previous sentence, and must not change the
want.

**Escalation deliberately breaks the length ceiling, and here is why.** The
first implementation escalated by emphasis alone — capitals and exclamation
marks, no new words — so a Stage I child's utterance length stayed correct. The
eval passed. It was still wrong: `AVSpeechSynthesizer` barely inflects on "!"
and some voices read short ALL-CAPS tokens letter by letter, so every rung
*sounded identical*. In a speech-generating device, escalation the listener
cannot hear is not escalation.

If your TTS layer can drive rate, pitch and volume from a repeat count, do that
instead and keep the ladder short. Ours cannot, so the words carry it.

### 5.4 The cache

`claudeBlast/Engine/Cache/CacheKeyPolicy.swift`.

```
<model>/v<promptVersion>/b<stage>#<sorted key:class pairs>
```

- **Order-independent.** Tiles are deduplicated and sorted, so two tap orders of
  the same words share one entry. This is a deliberate hit-rate decision with a
  sharp edge: whichever order generated first wins forever, so any ambiguity
  about what order *means* becomes invisible on every later hit. That is what
  forced a prompt-version bump when tile order was finally declared incidental.
- **Versioned by model and prompt.** Bump `promptVersion` whenever a prompt
  change should invalidate history. Entries with a different token are swept at
  launch regardless of age.
- **Word class is in the key**, so reclassifying a word misses its stale entries
  rather than serving a sentence built under the old meaning.
- **A second, version-independent key** (`stableKey`) identifies caregiver
  overrides, so a hand-typed correction survives a model swap or a prompt bump.
  A caregiver's correction is about the words the child picked, not the
  machinery.

Eviction: 180 days unused, 2,000 unpinned entries max, least-recently-used
first.

### 5.5 Failure classification

`claudeBlast/Services/OpenAI/OpenAIFailure.swift` — the most portable file in
the repository, and the one most worth reading in full. Four conditions arrive
over two status codes, and the status alone does not separate them:

| Status | Signal | Meaning | Device behaviour |
|---|---|---|---|
| 401, 403 | anything else | Key is finished | Latch, fall back to single-word |
| 403 | `model_not_found` | Key fine, one model unavailable | **Never latch** |
| 429 | `insufficient_quota` | Money ran out | Latch, distinct message |
| 429 | anything else | Rate limited | Retry later |
| 400, 422 | message present | Request refused on merits | Show their message |

Three rules behind it:

- **Distinguish "revoked" from "out of credit".** They need different actions —
  a new key versus adding credit — and a caregiver told to paste a new key when
  the answer is "top up" goes looking for a problem that does not exist.
- **Never latch a capability refusal.** Allowlist changes propagate with a lag,
  so a remembered "this key cannot do images" keeps a newly-granted key broken
  until relaunch.
- **Never show the provider's own error text**, except for a content-policy
  refusal. Their copy is written for the account owner; it names projects and
  links to settings pages a parent cannot open. The one exception is a refusal
  about the specific request, where their message names what it objected to and
  no paraphrase is more useful.

### 5.6 Word moderation

`claudeBlast/Services/WordModerationService.swift`. Three layers, least to most
capable:

1. **A tiny offline blocklist** — unambiguous terms, works with no network. Not
   the primary gate.
2. **The moderation endpoint** — free, deterministic, catches explicit content.
3. **An age-appropriateness rubric via `gpt-4o-mini`** — the actual gate. This
   is what catches *categories* the other two cannot: weapons, drugs, alcohol,
   gambling. A lone "gun" is not a policy violation and no static list
   enumerates the space.

**The verdict type needs a fourth case: "not reviewed".** Originally there were
three — allowed, flagged, blocked — and a tier that failed to run produced
*allowed*. An exhausted key made the rubric throw, the error was swallowed, and
words were recorded as "checked and fine" when nothing had checked them. Under a
spend-capped key that is an expected state, not an edge case. Make "no judgement
was reached" its own value and treat it as flagged.

Flagging is not censorship. Anatomical terms are flagged precisely because a
caregiver may legitimately need them — the app makes sure a human saw the word,
then does what they say.

---

## 6. Prompts and the art pipeline

There are two paths to a picture, and confusing them is easy.

**Adding a word at runtime needs no prompt authoring and no source change.** A
caregiver types "unicorn", and the app composes:

```
<style prompt for the active set>  Subject: unicorn (animal).
```

That is the whole prompt. The style comes from
`claudeBlast/Resources/image_styles.json`; the subject is the word and its class,
where the class is a sense hint that disambiguates — "snack bar (food)" is a
granola bar, "snack bar (place)" is a building. See
`TileImageGenerator.prompt(displayName:wordClass:imageSet:detail:)`. An optional
free-text detail from the caregiver is appended if they supplied one.

**`tools/prompts.json` is for bulk-generating a whole set offline**, and is never
read at runtime. Its 504 entries are hand-tuned subject descriptions written once,
when producing 500+ images in a batch made it worth investing in each one — "a
warm clay figurine grandmother, half-body, white curly hair, reading glasses"
beats "grandma" when you are paying for the render and reviewing the result.

So: you need `image_styles.json` to add words. You need `prompts.json` only if
you are generating an entire style from scratch, and even then the generic
composition works — it is just less good per image.

### Refinement is the feature, in both paths

**In the app it is user-visible.** A caregiver who does not like the picture says
what is wrong in their own words and regenerates. That free-text instruction is
the `detail` argument appended to the prompt — the model revises rather than
rerolling blindly, which is the same shape as the sentence refine flow. Build
this. First-generation art is wrong often enough that an app without a refine
button is an app whose pictures a caregiver cannot fix.

**In bulk we found we needed exactly the same thing**, and the manual review pass
is where it happened: reject, say what was wrong, regenerate. The part worth
copying is what we did with those corrections. **A refinement that fixed a word
was written back into `tools/prompts.json` rather than used once and discarded**,
so it carries into every style generated afterwards. That is most of what those
504 entries are — not prompts written from scratch, but accumulated corrections
from reviewing thousands of images.

This is why the file is worth having even though runtime generation does not read
it. Each entry encodes "here is what this word has to show, learned the hard way",
and it is style-independent by construction, so the lesson is not re-learned per
art style.

On gpt-image-2 the bulk loop is `tools/generate_by_reference.py`, which draws
each tile from a frozen four-tile reference pack (~1.6¢ per image at low
quality, ~6¢ at medium; see `docs/guides/commissioning-an-image-set.md`).
`tools/generate_sets.py` is the text-only loop the gpt-image-1 sets were drawn
with: roughly $0.04 per image then, ~15s
between calls for rate limits, and a minimum byte size as a crude "did we get a
real image" check.

Supporting tools, all in `tools/`: coverage auditing, contact sheets for review,
tone-variant generation, outline and background checks, and a browser-based
approval interface so a human accepts or rejects each image.

### The tone-chain lesson

Skin-tone variants are produced by transforming the base art, and a single
instruction about hairline contrast leaked globally — flipping black and white
on *objects* that happened to sit next to skin. It shipped, and it was caught by
luck rather than by looking.

Two things came out of it. The instruction lived in two places and only one was
fixed first, so **any prompt change needs a repository-wide audit for the same
text**. And a deterministic checker (`tools/audit_tone_inversions.py`) now
catches the class of bug, because a human reviewing 560 images will not.

### Where a set lives

**A set is not a folder of PNGs.** It must carry its style prompt and its
subject overrides, or a word added on the device renders in the wrong style —
the app has to regenerate art in the *active* set, which means the style
description has to travel with the set. Build this in from the start; retrofit
is painful.

---

## 7. The eval harness

`claudeBlastTests/Eval/`. Developer-time only, network calls gated behind an
environment variable, so ordinary test runs stay free.

**Subject and judge are decoupled by construction** — both run through one
client, differing only by config, so the grader can be a different (stronger)
model than the thing being graded. Do this on day one even if both point at the
same model at first; retrofitting it is how you end up with a model grading
itself.

**Tier 1 is deterministic and cheap.** Pure functions over strings: did the
`(wordclass)` annotation leak into the output, is the text empty or a degenerate
echo of the input, does the escalation ladder go *backwards*. These run offline
against fixtures and on live output.

**Tier 2 is an LLM judge** for the qualitative questions Tier 1 cannot reach.

**The lesson that matters most: a green Tier 1 is not evidence that escalation
works.** The all-caps escalation ladder passed every check and produced audio in
which every rung sounded the same. Read the actual output, out loud, through
your actual TTS, before believing a score.

---

## 8. Interop — please implement OBF

`claudeBlast/Services/OBFExporter.swift`. Open Board Format is the interchange
format the AAC world already uses, and it is the single highest-value thing you
can implement early. If your app reads and writes OBF, boards move between your
platform and this one, and a family that switches devices does not rebuild their
child's vocabulary by hand.

One implementation note that cost real debugging: **board ids must be unique
across every board a user might import, not just within one export.** Cboard's
importer skips any board whose id it already holds. Page keys are generic and
repeat across scenes — `home`, `body_health` — so importing a second scene
silently dropped every page whose name had been seen before. No error; the
boards simply were not there. Qualify the id with the scene's identity.

Carry your own keys in an extension field so a round trip back into your app is
lossless.

---

## 9. What is genuinely iOS-specific

| Concern | Here | What you need |
|---|---|---|
| Speech | `AVSpeechSynthesizer` | Any TTS with selectable voices. Voice quality dominates perceived quality — steer users to enhanced voices. |
| Sync | CloudKit private database | Optional. The app is fully functional with none. |
| Secret storage | Keychain | Anything better than a plain config file. |
| Persistence | SwiftData | Anything. |
| Audio session | `.playback` + `.spokenAudio` | The equivalent "play even when muted" affordance. A silent switch must not silence a child's voice. |

**Everything in sections 2 through 8 is platform-independent.** That is the
part worth taking.

---

## Getting in touch

Questions are welcome — the interesting ones usually improve this document.
`support@blasterai.app`, or open an issue on
[GitHub](https://github.com/marklucovsky/blasterai).

If you build something from this, we would like to know. Not as a licence
condition — there isn't one — but because a Linux distro for special-needs
children is exactly what this vocabulary should be doing.
