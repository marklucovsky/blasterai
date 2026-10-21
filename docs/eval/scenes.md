<!-- SPDX-License-Identifier: Apache-2.0 -->
# Scenes: templates, word budgets, and how we evaluate them

Draft, 2026-10-20 (session 12). Source: four Yak Back multi-page templates
(Sesame Street, Holidays, Doctor and Hospital, The Life of Jesus) — 19 pages
read from screenshots. Topics only; nothing here is copied into the app.

## What the Yak Back pages show

**1. Half the grid is a frame, identical on every page of every scene.** The
grid is 10 × 6 = 60 cells.

| Frame | Cells | Where |
|---|---|---|
| Home + 8 sentence starters (I want, I like, I don't like, Favorite, Thoughts about, Let's, I feel, I see) + 1 blank | 10 | top row |
| clear, period, delete word, -s, back | 5 | left column |
| I, it, you · is · the, and | 6 | fixed cells (col 2, col 3, col 9) |
| Links to the scene's pages (4–6) + blanks | 9 | bottom row |

That leaves **30 topic cells (50%)** in a 4 × 9 block with six frame holes.
yes/no are *not* frame: they're topic words where a page wants them
(Sesame home, Help Me).

**2. The 30 cells are a ceiling, not a target.**

| Scene | Page | Topic words |
|---|---|---|
| Holidays | home · Winter · Spring/Summer · Fall · Greetings | 30 · 23 · 22 · 16 · 30 |
| Doctor | home · My Body · Hospital Stay · Help Me | 30 · 30 · 25 · 29 |
| Life of Jesus | home · Christmas · Ministry · Miracles · Parables | 19 · 19 · 19 · 17 · 18 |
| Sesame Street | home · Friends · Play Time | ~28 · ~28 · ~30 |

Sparse pages are normal: a third of these pages use under two thirds of the
budget. Nobody pads.

**3. The home page is a sampler; each linked page goes deep on one thing.**

- Holidays home: the people (me, mom, dad, family, friend, grandma, grandpa),
  the central verbs (celebrate, sing, eat, decorate, hug, give, open), feelings
  (fun, sad, excited, happy) and one tile per holiday. Winter Holidays then
  has Santa, wrap, ornament, latkes, dreidel, gelt…
- Doctor home: people (me, doctor, nurse, mom, dad), greetings (hello, my name
  is), the visit's things (waiting room, exam table, gown, scale, thermometer,
  stethoscope, shot, medicine, bandage, sticker) and the instructions the
  child will hear (sit, lie down, stand up, open wide, deep breath, look,
  wait). Linked: My Body, Hospital Stay, Help Me.
- Life of Jesus home: people, verbs (heal, teach, love, follow, pray),
  describing words (kind, powerful, amazing, holy), a few nouns.

So the home page is roughly **people + central core verbs + feelings/describe
+ a handful of topic nouns**, and the topic nouns grow on the linked pages.

**4. A word that repeats keeps its cell.** Jesus is r2c3 on home, Ministry and
Parables; Mary and Joseph hold their cells across home and Christmas; love,
kind, forgive and teach repeat in place; fireworks and flowers share a cell
between Winter and Spring. This is motor planning: the hand learns where a
word lives.

**5. Colour is Fitzgerald**: people yellow, verbs green, describe blue,
social pink, nouns orange, links red — the same scheme we use.

**6. Situation scenes use phrases.** Help Me is all phrases ("tell me first",
"is it almost done", "I need a break", "hold my hand", "can my mom stay",
"that hurts"); Hospital Stay has "I want my", "where is my", "when can I go
home"; My Body has "my __ hurts". Topic scenes (Holidays, Jesus) are single
words.

**7. Themed pages are specific.** Yak Back's library is 264 templates, 210 of
them WordPower 60, and by type mostly TV shows (82), places (65) and movies
(47), then games, sports, school, holidays, faith. The single-page ones show
what "specific" means:

- **Baby Shark**: the five sharks, every beat of the song a child joins in on,
  then the play-along words (swim, clap, jump, hide, bite, fast/slow,
  loud/quiet, happy, scared, again).
- **McDonald's Menu**: the real menu items by name, drinks and treats,
  ketchup and napkin, and the ordering words — plain, no pickles, small /
  medium / large, for here, to go, please, thank you. On an ordering page,
  manners are topic words.
- **Joshua Tree**: the park's own landmarks and animals by name, the ranger,
  gear (backpack, water bottle, map), feelings (amazing, tired) and safety
  words.

Their pitch: "Motivation drives AAC use… a child who can talk about what
they already care about has every reason" to reach for the board.

**8. The frame shrinks or grows with the grid.** Yak Back ships most
templates for WordPower 60, with separate versions for other sizes:

| Grid | Example | Frame | Topic words | Pages |
|---|---|---|---|---|
| WP25 (5 × 4 shown) | Sesame Street 25 | link row only (5 cells, 25%) | 15 per page | 5, one per category: people, play, feelings, snack, social |
| WP60 (10 × 6) | Sesame, Holidays, Doctor, Jesus | ~30 cells (50%) | ≤ 30 | 4–6 |
| WP140 (~14 × 10) | Bluey 140 | Home, pronouns, a few starters, grammar (is/are/a/the/that/not/-s/with/and/?/what/do you) — ~20% | ~100 | 1, no links |

On the small grid there is no Home, no starters, no grammar: the words are
split into sheets by category and the link row moves between them. On the
large grid everything is one page, in Fitzgerald bands (people, then
social/feelings, verbs, describe, nouns).

**So the word list can be grid-independent and the template does the rest.**
If the model returns a ranked list tagged by part of speech, the same list
can be laid out as one 12 × 5 home page (frame + 25), as three or four 4 × 5
phone sheets split by category (links + 15 each), or later as one large page.
That is Mark's "transform" idea: the phone either runs the full 12 × 5 board
and scrolls, or gets its own lighter template with two or three sheets.

## What this means for BlasterAI

1. **A scene starts as one home page built from a template.** More pages are
   added one at a time ("add a page: Christmas dinner"), each from the same
   template, each adding a link. We don't ask a model for a five-page scene.
2. **The template is ours, as data**: a grid size, fixed frame tiles in fixed
   cells, the link row, and N free cells. The model never sees layout.
3. **The model's job is words, within a budget.** It's told the topic, N (the
   free cells), and the frame's words. It returns a *ranked* list of up to N + a
   few words, each tagged `topic` or `core` (core words central to the topic:
   celebrate, open, give for Holidays; sit, wait, open wide for Doctor). Code
   drops frame duplicates and fills from the top. Fewer than N is fine.
4. **Placement is code**: group by part of speech, and a word already on
   another page of the scene takes the same cell.
5. **Overflow seeds the next page.** Words ranked past N are the first
   suggestions when the creator adds a page.

What we don't need from Yak Back's frame: clear, delete word, period, -s —
the tray and the sentence AI do those. The starters ("I see", "I want") would
help the sentence AI with intent ("I see" + cat settles see_cat), but they
wait for the SLPs (below).

## What we generate today

`prompt_scene_generate_system.txt` asks for ONE flat page of topical words
and explicitly **excludes core**: no pronouns, people/family, feelings,
generic food, needs or social words. Core comes later from the caregiver's
structure step (`core_sets.json`). New words must be concrete nouns — never
actions or describing words. So the model cannot produce the Yak Back home
page shape (people + central verbs + feelings + nouns) even if asked.

Words per scene in the v0 run (one sample each):

| Case | Words | | Case | Words |
|---|---|---|---|---|
| sensory_break | 4 | | morning_circle | 16 |
| bedtime | 5 | | swimming | 17 |
| potty_training | 7 | | farm_trip | 19 |
| dentist | 8 | | church | 19 |
| birthday_party | 9 | | shooting_range | 19 (refusal ignored, G3) |
| pancakes_long | 9 | | hospital_stay | 20 |
| zoo_terse | 15 | | grocery_store | 21 |

Median 16 against a budget of 25; the routines (bedtime, potty, dentist,
sensory break) are thinnest, because their vocabulary is mostly actions and
the prompt forbids new actions and leaves core out.

## Mark's calls (2026-10-20)

1. **No starters frame.** Leaf pages stay as they are today: topic words, or
   topic words plus links. Revisit when the SLPs weigh in.
2. **No phrase tiles** until we hear from the SLPs (two more signed up today).
3. **Budget 50%: about 25 topic words plus links.** Most of our AI-generated
   scenes today are far sparser than that.
4. **The frame is a best guess from us**, drafted below, as the starting
   point for the SLP discussion.

## Draft frame: scene home page, iPad 12 × 5

Our edge over Yak Back's frame: **put the frame's core words in the same cells
they hold on BlasterAI 60.** A child who has learned where "want" is on the
default board finds it in the same place on every scene's home page. Yak
Back's frame is consistent across its scenes but matches no core board.

The frame is BlasterAI 60's level-1 words (minus eat, drink and play, which
are folders on its home), each in its BlasterAI 60 cell, plus Home and the
link row:

```
     c1    c2    c3    c4    c5    c6    c7    c8    c9    c10   c11   c12
r1   Home  link  link  link  link  link  ·     ·     ·     ·     ·     ·
r2   I     ·     ·     ·     go    ·     ·     ·     ·     more  ·     ·
r3   ·     ·     ·     ·     want  ·     ·     ·     ·     ·     ·     stop
r4   you   ·     ·     help  ·     ·     ·     ·     ·     ·     ·     ·
r5   yes   done  no    ·     ·     ·     ·     ·     ·     ·     ·     ·
```

| | Cells |
|---|---|
| Home | 1 |
| Link row (the scene's leaf pages, up to 11; unused cells stay blank) | 11 |
| Core frame: I, you, want, more, go, stop, help, yes, no, all done | 10 |
| **Topic words** (model's ranked list; ≤ 25) | 38 free |

So the model is asked for at most 25 words for 38 free cells, which leaves
room for placement to group by part of speech. Its `core` tags are for core
words beyond the frame that are central to the topic (celebrate, give, open;
sit, wait, open wide).

**Leaf pages**: Home in cell 0, topic words (≤ 25), and links where the page
has them. No core frame, as today.

**iPad 12 × 5 is the main case** (Mark, 2026-10-20). Other grids, phone
included, come later.

## How we evaluate it

Surface `topic_words` (harness only — `tools/eval/candidates/`, not in the
app). One prompt for every page, per Mark: the words are the same kind for a
scene's home page and a leaf page; only the template differs, and the
template is code. Cases `cases/topic_words.json`: the 14 old scene
descriptions, Yak Back-shaped topics weighted like their library (shows,
movies, places, games, sports, a song, a real menu, a national park), and
four leaf pages. Each case has a best-guess list of required words (Claude's
draft, for Mark and the SLPs to correct).

| Check | How |
|---|---|
| Refusal | Tier-1: unsafe topic → `refused`, no words |
| Required words | Tier-1: on the page — a word that fell into the overflow is reported as such |
| Size | Tier-1: at least 15 on the page (10 for a narrow topic), at most 32 returned |
| Phrases, word classes | Tier-1 |
| coverage, precision, related_core, ranking, child_fit | judge, `rubrics/topic_words.txt` |

What code does, not the model (`scorers.score_topic_words`, the stand-in for
the Swift placer): match each word to the vocabulary (plurals, sense-marked
keys like `hot_`), drop frame words and duplicates, cut at 25, and keep a
floor of 5 actions and 3 describing/feeling words on the page by promoting
them from the overflow over the lowest-ranked nouns.

## Iteration log (2026-10-20, session 12)

| Run | Change | gpt-4o-mini judge pass | Notes |
|---|---|---|---|
| t1 | first draft: ranked words tagged pos/kind, "sampler" | 0/69 | generic filler on every page; refusal ignored 3/3; tags confused with word classes |
| t2 | refusal first; no padding; tags dropped (pos from `parts_of_speech.json`) | 0/72 | refusal fixed 3/3; volume 19–25 words, up from v0's median 16 |
| t3 | + 10 Yak Back-shaped cases; "be specific" | 0/102 | gpt-4o-mini leaves Elsa, Mario, Christmas unmarked as new — the app would drop them |
| t4 | the model writes words, code matches them to the vocabulary; 2–4 topic feelings allowed; ranking judged only at the cut | 0/102 | Tier-1 21 → 42 of 102 |
| t5 | four ranked lists merged by share | 0/102 | worse; feelings leaf page broke. Reverted |
| t6 | + one worked example (a fire station) | 0/102 | flat |
| t7 | + a second "review your draft" call | 0/102 | flat for gpt-4o-mini; Luna 8 → 11 |
| placer | floor of 5 actions + 3 describing/feelings | 0/102 | Luna 11 → 13; related_core 3.3 → 3.55 |

Same prompt, other models (judge pass, all scores ≥ 4):

| Subject | Judge pass | coverage | precision | related_core | ranking | child_fit | $ / page |
|---|---|---|---|---|---|---|---|
| gpt-4o-mini (t6) | 0/102 | 2.9 | 3.0 | 3.0 | 3.2 | 3.5 | $0.0005 |
| Luna, none (t4) | 9/102 | 3.0 | 3.5 | 3.2 | 2.6 | 4.0 | $0.0005 |
| Luna, low (t4) | 8/102 | 3.0 | 3.6 | 3.1 | 2.6 | 4.1 | — |
| Luna + review + placer (t7) | 13/102 | 3.3 | 3.8 | 3.6 | 3.1 | 4.1 | $0.001 |
| Luna, medium (t6) | 10/102 | 3.2 | 3.8 | 3.3 | 2.7 | 4.1 | $0.001 — 16 s/page (1,270 reasoning tokens), no better than none |
| Sol, low (t6) | 40/102 | 3.9 | 4.6 | 3.6 | 3.6 | 4.4 | $0.008 |

**Claude's read of the pages** (merged review `runs/2026-10-20-2354-merged-topic-models`, one
sample per model per case): approve gpt-4o-mini 13/34, Luna + review 30/34,
Sol 34/34. The judge orders the models the same way but its bar is far too
strict: against Claude's labels it agrees 42% at "every score ≥ 4" (57 too
strict, 0 too lenient) and 72% at "≥ 3" (Sol 97%, gpt-4o-mini 58% — too
lenient on its filler). It needs Mark's labels and a rubric pass, as the
sentence judge did (r1 → r2), before its pass rate means anything.

**What the prompt can't fix in gpt-4o-mini**: filler (fun, together,
adventure, teamwork), abstractions on faith pages (peace, joy, kindness),
missing the specific things (the song's verses, the park's landmarks, the
menu's sizes). Four prompt variants and a review pass left it flat.

## Still open

- ~~Model for authoring~~ **Decided (Mark, 2026-10-21): gpt-6.1-sol is the plan
  of record for page and scene authoring.** gpt-4o-mini is retired as a
  benchmark — fine for the early demos (dinos, farm), too weak to score
  against. Cost is not a driver next to tile art; quality and latency are.
  Sol at low effort: ~10 s a page (p90 14 s); low is its minimum effort, and
  it spends ~0 reasoning tokens there, so that is its floor. Pages of one
  scene can be generated in parallel. Sentences stay on the small model.
  Baseline for further prompt work: `runs/2026-10-20-2347-gpt-6.1-sol-low-topic-t6-sol`
  (judge Astra, since the judge must not be the subject). Luna is tracked
  alongside each round to see whether it can catch up.
- ~~Judge calibration~~ **Done 2026-10-21.** Mark labelled the merged page
  and agreed with Claude on all 102. Rubric r2 (`rubrics/topic_words.txt`:
  a 4 is "usable after swapping a word or two"; coverage and ranking score
  down only for missing the central things or filler beating a needed word;
  synonyms like potty / toilet are not a fault) took agreement 42% → **80%**
  (Sol 97%, Luna + review 70%, gpt-4o-mini 73%), rejudge
  `runs/2026-10-21-1414-merged-topic-models-rejudge`, judge Astra. Of the 15
  still too strict, most name a real gap (morning circle without the days of
  the week, snack time without cup or plate); the 5 too lenient are filler and
  phrase tiles from the weaker models. r2's examples come from these labels,
  so it needs a held-out check on new pages before it is trusted further.
- **Required words** per case: Claude's drafts, for Mark and the SLPs.
- **Existing scene code**: how today's scene and page generation maps onto
  "one home page from a template, then add pages" — to read before any code
  change.

### Sol, 2026-10-21 (plan of record)

| Run | Change | Judge (r2) pass | Tier-1 | Notes |
|---|---|---|---|---|
| t6 | baseline, rejudged with r2 | 94/102 | 94/102 | after correcting the required-word lists (below) |
| t8 | + every word the request names gets a tile ("we wear helmets" → helmet); one tile per thing (no generic copy of a specific word) | 94/102 | 89/102 | pancakes now has "turn"; generic copies (xylophone beside Magic Xylophone) persist; level with t6 |
| t8 held out | 12 new topics never used for tuning: Paw Patrol, Chuck E. Cheese, Disney World, Minecraft, soccer, Easter, camping, haircut, The Very Hungry Caterpillar, Old MacDonald, taco night, weather leaf | **36/36** | 27/36 | Claude approves 36/36; Tier-1 misses are list matching (`easter_egg`, `ground_beef`, a play pass for tokens) |

Judge r2 on Sol pages it was not calibrated on (t6 samples 1–2, Claude's labels):
62/66 agree, 4 too strict, 0 too lenient (94%).

**Required-word lists corrected** where they contradicted the prompt's own rules
(play as a Bluey requirement; love on a Bible page; celebrate/party; McDonald's
sizes) or missed a valid alternative (basketball for ball, shopping cart, wash
hands, walk/trail for hike, Chicken McNuggets).

**Matcher bug fixed**: "shorts" (clothing) resolved to the adjective "short" as
if it were a plural. A plural now resolves only onto a noun
(`scorers.resolve_key`). The Swift placer needs the same rule.

**What prompting will not fix:**
- *Holidays is a scene, not a page.* Six holidays don't fit in 25 words;
  fireworks lose to birthday words on every sample. Yak Back makes it five
  pages, which is our home + leaves.
- *Turn-taking.* For "playing with my brother" Sol picks share and wait over
  "turn": ambiguous in our vocabulary, and there is no "my turn". For the SLPs.
- *Named characters.* 7 of 45 Sol pages carry named characters, all shows,
  films, games and theme parks: Mario 7, Paw Patrol 7, Disney World 6, Frozen 5,
  Bluey 4, Chuck E. Cheese 2, Minecraft 2 (Sol classifier). Those tiles need a
  caregiver's picture (next section), so a show page arrives about a quarter
  without art.

## Art for named words (2026-10-21)

Mark's Bluey tile was refused by the image safety system. Probe
(`tools/eval/probe_art_refusals.py`, run `runs/2026-10-21-1402-art-refusals`,
the app's own reference-pack request, 3 attempts per word):

- **Refused**: Mario, Yoshi, Peppa Pig, Mickey Mouse, Elmo, Spider-Man,
  Pikachu, Mr. Rogers on every attempt; Elsa 2 of 3; Mario's mushroom 2 of 3.
- **Drawn but wrong** — worse, because nothing flags it: Bluey (people) → a
  generic girl, Olaf → a boy, Bingo → a bingo card, Target → a globe, Keepy
  Uppy → a boy kicking a ball, Ms. Rachel and Taylor Swift → generic women.
- **Fine**: brands and products (McDonald's with its arches, Happy Meal, Lego,
  Switch), landmarks, faith and holiday figures (Jesus, Noah's ark, Santa),
  Baby Shark, Chase (Paw Patrol).

So the line is **named characters and real people**, not trademarks in
general. Detection at moderation time (prototype: the rubric plus an `art`
field, "named" | "drawable", 28 named / 36 not, 3 runs each):

| Model | Named caught | False flags | Note |
|---|---|---|---|
| gpt-4o-mini | 25–27/28 | 5/36 | flags Jesus, Santa, Tooth Fairy; the extra question made it rate Abraham Lincoln and Taylor Swift *inappropriate* |
| Luna, none | 27–28/28 | 3/36 | flags Keepy Uppy and Magic Xylophone — which drew wrong anyway |
| Sol, low | 28/28 | 1/36 | Cinderella, arguably right |

Plan (Mark): a "named" word is flagged — "we may not be able to draw this;
add your own picture" — and the tile is created for a caregiver photo. No
attempts to describe a character so the image model draws it anyway. Scene
generation can mark named words itself, since the authoring model wrote them.

## Layout prototype (2026-10-21)

`tools/eval/build_layouts.py` places Sol's words on the 12 × 5 grid
(`tools/eval/layouts.json` lists the scenes). Mark's calls on the first look:

- **Row 1 stays reserved for links, even on a single-page scene.** An SLP may
  fill it with BlasterAI links (question, actions, social, time, describe), or
  with one link to a page of links, as Groups does.
- **Leaf pages: sparse across the grid** for the first pass.
- **Frame: core words stay in their BlasterAI 60 cells.**
- Multi-page scenes will be rarer than single pages.

Found in the prototype: 9–17 new pictures per page; a character name can land
on a same-spelled vocabulary word of another sense (Bluey's Bingo → the bingo
game tile), so the matcher must check sense, as with shorts / short; colour
bands separate pairs a song page may want together (cow / moo).

## Adding a page to a scene: scene context (2026-10-21)

Mark: a page added to a model-made scene should take what its short topic
leaves unsaid from the scene ("Holiday songs" in a Christmas scene). Today the
app's add-page prompt sends the scene's pages and tiles but not its name or
summary. The caregiver's raw prompt is not on the scene by design (since #77
it is logged on the device only: it can name the child or describe them, and
scenes sync and are shared). The scene does carry the model's own summary
(`descriptionText`).

Test (`group addpage` vs `addpage_bare`, run
`runs/2026-10-21-1514-gpt-6.1-sol-low-topic-t8-sol-addpage`): eight short page
topics inside real Sol scenes, with the scene's name, summary and home-page
words (`candidates/prompt_topic_scene_context.txt`) and without.

| Page | With scene context | Without |
|---|---|---|
| Christmas → Holiday songs | Rudolph, Frosty, sleigh, jingle | adds dreidel, menorah, candle |
| Bluey → Characters | Bandit, Chilli, Muffin, Socks, Nana… | Elmo, Peppa Pig, Paw Patrol, Daniel Tiger… |
| McDonald's → Desserts | McFlurry, cone, sundae, apple pie | cake, brownie, cupcake |
| Yellowstone → Animals | bison, elk, wolf, moose, pronghorn | dog, cat, cow, lion, monkey |
| Frozen → Characters | Elsa, Anna, Olaf, Kristoff, Sven, Oaken | every kids' show |
| Disney World → Rides | Dumbo, Mad Tea Party, Peter Pan's Flight | carousel, Ferris wheel, bumper cars |
| Hungry Caterpillar → Foods | the book's foods | a lunch menu |
| Mario → Power-ups | Super Mushroom, Fire Flower, Super Star | star, heart, shield, magnet |

Required words: **19/24 with context, 2/24 without**. The scene's name and
summary are enough; the raw prompt is not needed. Misses: Disney ride names are
titles ("The Many Adventures of Winnie the Pooh"), which need a short name a
child would say; 1-Up on one Mario sample. A characters page is nearly all
names (Bluey: 23), so nearly all photos.

App change this implies (later PR): the add-page user prompt gets the scene's
name and `descriptionText`.

**Re-creating a scene from its summary** (Mark's experiment,
`tools/eval/recreate_from_summary.py`, table in
`runs/2026-10-21-1425-gpt-6.1-sol-low-topic-t8-sol/recreate_from_summary.md`):
Sol's page asked for again with its own summary as the topic keeps a median
**67%** of the original words; asking the original prompt twice keeps **79%**.
What drops is the specifics the caregiver typed that the summary left out (mom,
dad and the iPad from the hospital stay; the goomba from Mario; the feelings page
drifted to "feelings and body needs"). Enough context for adding a page; not a
substitute for the prompt if a scene ever has to be regenerated. If that
matters, the summary can be asked to keep the named specifics.
