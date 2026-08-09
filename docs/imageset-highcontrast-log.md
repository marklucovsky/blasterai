# High Contrast v2 — generation log

A working record of commissioning one tile image set: what the style prompt
said, what the model actually produced, what changed between rounds, and why.

It exists for two reasons. The near one is that prompt iteration without
measurement is just taste, and taste does not survive 493 tiles. The far one is
that this log becomes the worked example in
`docs/guides/commissioning-an-image-set.md` — the answer to a clinician asking
for CVI-appropriate art is not "here is our set", it is "here is exactly how a
set gets made, go make one that matches your patient."

**Measurement:** `tools/analyze_set.py`, which scores every tile against its
set's declared style contract. It catches the failures that repeat
mechanically — frames, edge contamination, clutter, washed-out contrast,
undersized or off-centre subjects. It does not judge whether the picture means
the right word; that needs eyes, and the rubric for it is in
`docs/tile-audit-p3d.md`.

---

## Round 0 — baseline

The set as it stood before this work: generated April 2026, marked
`isShippable: false` in `TileImageResolver.swift` with the note "pending full
review + regen", and invisible in release builds.

**Coverage.** 472 of 493 vocabulary keys have art. The 23 with none are almost
entirely core words:

```
i, me, my, you, your, it, that, he, in, on, off, out, up, down, with, for,
all, here, all_done, how_are_you, i_love_it, toilet, backyard
```

That gap is not incidental. Core words are the highest-frequency tiles on any
board, and the set that exists specifically for children with low vision is the
one missing them — those tiles currently fall back to Playful-3D pastel clay.

**Scores.**

| set | clean | shippable |
|---|---|---|
| classic | 503 / 546 — **92%** | yes |
| playful_3d | 498 / 543 — **92%** | yes |
| **high_contrast** | **58 / 472 — 12%** | no |

Both shipping sets sit at 92% under the same machinery, which is the evidence
that the 12% is the set and not the analyzer. (Calibrating the analyzer against
known-good work before trusting it on new work is the step worth copying; see
the note on profiles below.)

Failure modes, by count:

```
multi=221  clutter=210  small=113  frame=87  edges=78
contrast=75  bgcolor=65  dense=17  offcenter=10  thin=2
```

**Root cause.** `tools/tile_sets/README.md` records a rule learned the hard way
during the Playful-3D work:

> Style prefix must NOT mention "AAC", "communication", "accessibility" —
> these trigger icon contamination.

The shipped `high_contrast` style in `claudeBlast/Resources/image_styles.json`
opens with:

> High-contrast **accessibility pictogram** for non-verbal children.

So the set violates our own documented rule in its first six words, and the
~60-word forbidden list that follows spends its length fighting that opening
instead of describing the picture we want. The model appears to read
"accessibility pictogram" as *icon set for an accessibility product* and
produces exactly that.

Three tiles, as evidence of what that means in practice:

- **`apple`** — a 5×5 grid of twenty-five unrelated UI glyphs (wifi arcs, a
  wheelchair symbol, a handbag, crosshairs, tablets, leaves) with a slightly
  larger apple in the middle. `components=13, flecks=44`.
- **`eat`** — a black rounded-rectangle panel with a drop shadow, floating on a
  **grey** background, containing a clay-styled face eating pizza flanked by
  wifi arcs, hearts and a wheelchair symbol. Every one of the style's named
  prohibitions, in one image. `bgcolor, frame, clutter, multi`.
- **`blocks`** — roughly forty tiny glyphs arranged in a block. `flecks=88`.

The tiles that *do* pass are the ones with a single concrete noun and no room
for improvisation — `chocolate` scores clean and looks it.

**Note on profiles.** Calibration turned up something worth recording
separately: Playful-3D's prompt promises "clean solid-color background", but
what the set actually ships is a lit gradient backdrop with a floor plane and a
cast shadow. Judging it against its written contract flagged 259 of 543 good
tiles. The analyzer therefore measures each set against what it really
promises, and `playful_3d`'s edge-uniformity check is off with a comment saying
why. A style prompt and a style contract are not the same document, and the
gap between them is worth knowing before you trust any automated score.

---

## The probe set

Sixteen keys, chosen to cover every documented failure class rather than to
flatter the prompt. A probe that only contains concrete nouns will pass
anything.

| Class | Keys | Why |
|---|---|---|
| Core words / pronouns | `i`, `you`, `my`, `up` | The 23-key gap, and the p3d audit's worst category — "pronouns need a directional convention, not a generic figure" |
| Abstract verbs | `want`, `need` | Lowest-scoring category in the p3d audit |
| Homonyms | `pool` | Billiards vs. swimming |
| Bare glyphs | `next_page`, `question` | The two `render_hc_basics.py` exists to work around |
| Contamination magnets | `hurt`, `toilet`, `home`, `food` | Medical/accessibility icon bait |
| Colour fidelity | `black` | Named-colour subjects fail in specific ways |
| Concrete control | `apple` | If this breaks, something is badly wrong |

`down` was added at round 3. All work ran at `--sleep 3` rather than the
default 15 (see "Rate limit" below).

---

## Round 1 — remove the two root causes

**Changed.** A new `high_contrast_v2` style rather than an edit in place, so the
old set stays comparable. Two changes, both root causes rather than symptoms:

1. **Dropped the "accessibility pictogram for non-verbal children" opening**
   and rewrote the prompt to lead with a positive description of the picture.
   Cut the forbidden list from ~60 words to ~35 — a long list of prohibitions
   reads as a list of suggestions.
2. **Fixed a second, independent bug in `tools/generate_sets.py`.** Subjects in
   `prompts.json` were authored for Playful-3D and bake in clay wording ("A 3D
   clay figurine child…"). `strip_clay_words()` was applied to `classic` and
   `arasaac` but **not** to `high_contrast` — so every HC prompt had been asking
   a flat white-on-black style to render a 3D clay figurine. That is why `eat`
   came back as a clay face. Now every style except `playful_3d` strips it.

**Result: 3 → 8 of 16 clean.** (Baseline on the same 16 keys: 3 clean, and 5 of
the 16 had no art at all.)

The two headline tiles:

- `apple` — was a 5×5 grid of twenty-five UI glyphs. Now one giant apple, pure
  black to every edge, red highlight and green leaf.
- `eat` — was a framed clay panel on grey. Now flat white line art on true black.

And the strongest single signal: **`next_page` and `question` both generated
cleanly.** Those are the tiles the pipeline had given up on —
`render_hc_basics.py` exists specifically because gpt-image-1 kept surrounding
them with grids of wheelchair and payment icons. A bold white arrow and a white
question mark with an orange dot. The deterministic workaround is probably
obsolete for v2, which should be confirmed on the full run before deleting it.

Remaining: `multi=6`, `edges=2`, `contrast=1`.

## Round 2 — accent discipline and internal detail

**Changed.** Two clauses:

- "Most of the subject is white. One small part of it may be picked out in a
  single bright saturated colour… never colored all over." `up` had come back
  as a wholly blue arrow, which measures at contrast 5.4 against white-on-black's
  ~20 and is materially harder to see with low vision.
- "with as few internal lines as possible", targeting the `multi` flag — figures
  drawn with heavy black internal linework fragment into many white regions,
  which is both a measurement artefact and a real complexity cost for CVI.

**Result: 8 → 11 of 16 clean.** Fixed `my`, `need`, `toilet`, `want`. Regressed
`pool`, `up`, `you`.

## Round 3 — arrows, and two miscalibrated thresholds

**Changed.** Added "If the subject is one simple shape with no distinct parts,
such as an arrow, draw it entirely in white." Added `down` to the probe.

Also recalibrated two thresholds after inspecting what they were actually
catching. `you` — a child pointing at the viewer, a genuinely good tile — was
flagged `clutter` for seven flecks, which were its eyes, nose and mouth. The
observed separation is wide enough to be unambiguous: legitimate v2 figures run
2–9 components and 0–7 flecks; contaminated baseline tiles run 13–24 and
41–124. Thresholds moved into the empty space between (10 and 12).

**Result: 11 → 15 of 17 clean.** `multi` and `clutter` to zero.

## Round 4 — when the subject beats the style

`up` and `down` were still solid blue, ignoring an explicit instruction. The
cause was not the style prompt at all:

```
up → AAC pictogram: A single bold 3D clay arrow pointing straight upward,
     bright blue color, …
```

The subject names the colour. `strip_clay_words()` removes clay wording but
deliberately not colours, because most subjects need theirs ("a red apple").
**A colour named in the subject beats a global rule in the style, every time.**

**Changed.** Per-key `HC_SUBJECT_OVERRIDES` for `up` and `down` specifying solid
white. This is the right tool for a small closed class; it would be the wrong
tool for a systemic problem.

**Result: 16 of 17 clean.**

The one remaining flag is benign. `down` has a perfect black field (Δ0.01,
uniformity 1.00), a contrast ratio of **20.86 against a theoretical maximum of
21**, one component, zero flecks, dead centre. It fails only `bbox_frac`
(0.386 vs. 0.42) because a vertical arrow is narrow — a limitation of measuring
subject size by bounding box, not a defect in the tile.

---

## Where it stands

| | clean | of |
|---|---|---|
| Baseline HC, full set | 58 | 472 (12%) |
| Baseline HC, probe keys | 3 | 16 |
| **v2, probe keys** | **16** | **17** |

Cost so far: 44 images, roughly $1.80. Elapsed: about 25 minutes of generation.

**Rate limit.** `SLEEP_SECONDS = 15` in `generate_sets.py` is a DALL-E-3 Tier-1
number (5 images/minute) carried forward to gpt-image-1 unexamined. All of the
above ran at `--sleep 3` with no throttling. On a full 493-key set that is the
difference between roughly two hours of pure sleep and twenty-five minutes, so
the new `--sleep` flag is worth using deliberately.

## What the full run still has to prove

The probe was chosen to be hard, so a high score on it is evidence the prompt is
sound, not that the set is done. Open questions:

1. Does it hold across 493 keys, including the 23 core words that have never had
   HC art?
2. Can `render_hc_basics.py` be retired, or do `next_page`/`question` fail
   intermittently across repeated draws?
3. How many other subjects name a colour that fights the white-dominant rule?
   `left` specifies "bright glowing YELLOW arrow"; that class needs a sweep.
4. Unrelated but worth noting for the semantic pass: the subject for `right` is
   *"a bold green checkmark showing the correct right answer"* — the wrong sense
   of the word, in every set, not just this one.

## Round 5 — full set: pending

