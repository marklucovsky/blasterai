# Commissioning a tile image set

BlasterAI ships a few tile art styles. None of them will be right for every
child.

A child with cortical visual impairment may need a single high-saturation shape
on a black field with no competing detail. A child who reads photographs but not
symbols may need something else entirely. A child in a classroom in another
country may need art that looks like their world rather than ours. We cannot
guess our way to those sets from here, and shipping one compromise for everybody
is how AAC art usually goes wrong.

So the tooling is the deliverable. Everything used to build the shipped sets is
in this repo, and this guide walks it end to end. A set is roughly **$20 of
compute and an afternoon**, most of which is waiting.

**Who this is for.** Someone comfortable with a terminal and a git clone,
working with Claude Code or similar. The division of labour that works: **you
commission and you approve; the assistant does the mechanical work.** You decide
what the set is for and which tiles are good enough for a child to rely on. You
should not be hand-editing 493 filenames.

**What you get.** A folder of 493 PNGs, measured against your own style
contract and reviewed tile by tile, that installs into the app as a selectable
art style.

---

## Before you start

```bash
git clone https://github.com/marklucovsky/blasterai && cd blasterai
git lfs install && git lfs pull          # master art is LFS; app PNGs are not
pip install requests Pillow numpy scipy
export OPENAI_API_KEY=sk-...             # a funded Platform account
```

Every tool assumes the **repo root** as the working directory, not `tools/`.

Budget roughly **$20–25** for a 493-tile set at gpt-image-1 `quality: medium`,
plus a few dollars of iteration. Wall-clock depends on sharding — see step 6.

---

## Step 1 — Decide what the set is *for*

Write this down before you write a prompt. It is the thing you will measure
against, and vague intent produces a vague set.

A useful spec answers:

- **Who is it for, specifically?** "Low vision" is not a spec. "A child who
  needs one large high-contrast shape and cannot filter background detail" is.
- **What is the background?** One flat colour? Which one exactly? A gradient?
- **How much of the frame does the subject fill?**
- **How much colour, and where?** Is colour carrying meaning, or decoration?
- **What must never appear?** Text, frames, secondary objects, fine detail.
- **How will you know a tile failed?** If you cannot say, you cannot measure.

If you are building for a specific child, this step is a conversation with the
people who know them — a clinician, a teacher, a parent. That conversation is
worth more than anything in the rest of this guide.

## Step 2 — Register the set

Five places. Do all five before generating anything.

| File | Add |
|---|---|
| `claudeBlast/Resources/image_styles.json` | `"your_set": "<style prompt>"` |
| `tools/generate_sets.py` → `SET_STYLES` | `"your_set": "your_set"` |
| `tools/sync_to_app.py` → `SET_PREFIX` | `"your_set": "ys"` (short, unique) |
| `tools/optimize_tiles.py` → `--set` choices | `"your_set"` |
| `.gitattributes` | `tools/tile_sets/your_set/*.png filter=lfs diff=lfs merge=lfs -text` |

> **The `.gitattributes` line must exist before you commit a single PNG.** The
> pattern is non-recursive (`*.png`, not `**/*.png`), so a new folder without
> its own line puts several hundred megabytes into regular git, and getting it
> back out means rewriting history.

Generate into a **new** set folder rather than overwriting an existing one. You
want the old set intact to compare against, and you may decide the new one is
worse.

## Step 3 — Write the style prompt

`image_styles.json` is read by both the offline tool and the in-app "generate
with AI" path, so it is one string with two consumers. (If you change it, mirror
the change into `TileImageGenerator.swift`'s `fallbackStyle(for:)`, which
hardcodes its own copy for when the bundle file is missing.)

Four rules, each learned the expensive way:

**1. Never name the use case.** Do not write "accessibility", "AAC",
"communication aid", or "for non-verbal children" in a style prefix. The model
does not read those as constraints on rendering; it reads them as a *subject
domain* and starts drawing accessibility products — wheelchair symbols, wifi
arcs, medical clipboards, app UI. The old High Contrast prompt opened with
"High-contrast accessibility pictogram for non-verbal children" and its `apple`
tile came back as a 5×5 grid of twenty-five UI glyphs with an apple in the
middle.

**2. Lead with the picture you want.** Describe the image positively and
concretely first. Prohibitions come last and briefly.

**3. Keep the forbidden list short.** A sixty-word list of things not to draw
reads as a list of things to consider drawing. The rewritten High Contrast
prompt cut its prohibitions roughly in half and got dramatically cleaner
results. State the handful that actually recur.

**4. Be specific where it matters.** "Pure black background" is weaker than
"solid #000000, filling the whole square, running off all four edges and into
every corner."

## Step 4 — Choose a probe set

Fifteen or so keys that you will regenerate on every iteration. **Choose them to
break the prompt, not to flatter it.** A probe of concrete nouns will pass
anything and teach you nothing.

Cover, at minimum:

| Class | Why | Examples |
|---|---|---|
| Pronouns and core words | Highest-frequency tiles, and the hardest to draw. A generic figure does not distinguish *I* from *you* — these need a directional convention | `i`, `you`, `my`, `up` |
| Abstract verbs | The worst-scoring category in every audit we have run | `want`, `need` |
| Homonyms | The model picks a sense and it may not be yours | `pool`, `right` |
| Bare glyphs | Arrows and marks attract framing and icon clutter | `next_page`, `question` |
| Contamination magnets | Anything medical, navigational, or institutional | `hurt`, `toilet`, `home` |
| A concrete control | If this breaks, something is badly wrong | `apple` |

## Step 5 — Iterate, with measurement

```bash
# generate the probe
python3 tools/generate_sets.py --set your_set --sleep 3 \
  --key i --key you --key want --key pool --key next_page --key apple

# measure it
python3 tools/analyze_set.py --set your_set --out tools/tile_sets/analysis/r1.json
```

`analyze_set.py` scores each tile against a **profile** — a machine-readable
version of your step-1 spec, in `PROFILES` at the top of the file. Add one for
your set: declared background and tolerance, edge uniformity, subject size,
contrast, component and fleck limits, centroid drift.

It measures what repeats mechanically: frames and insets, background
contamination, clutter, washed-out contrast, undersized or off-centre subjects.
It does **not** know whether the picture means the right word. That needs eyes,
and the rubric is in `docs/tile-audit-p3d.md` (clarity / match / size, 1–5).

> **Calibrate before you trust it.** Run the analyzer against a set you already
> consider good and see what it flags. If a known-good set scores badly, your
> profile is wrong, not the art. This is not hypothetical: judging Playful-3D
> against a flat-background rule flagged 259 of 543 perfectly good tiles,
> because its prompt promises "clean solid-color background" while what it
> actually ships is a lit gradient with a cast shadow. **A style prompt and a
> style contract are different documents.** Both shipping sets now score 92%,
> which is what makes a 12% score on a third set meaningful.

Then loop: change one thing, regenerate the probe, compare.

```bash
python3 tools/analyze_set.py --set your_set \
  --out tools/tile_sets/analysis/r2.json \
  --compare tools/tile_sets/analysis/r1.json
```

`--compare` prints what got fixed and, more importantly, **what regressed**. A
change that fixes four tiles and breaks three is not progress, and without the
diff you will not notice.

**Keep a log.** One entry per round: what you changed, what it was meant to fix,
the score, and the verdict. `docs/imageset-highcontrast-log.md` is a real one —
four rounds, 3/16 clean to 16/17. The log is what makes the set reproducible by
someone else, and it is most of this guide's evidence.

**Two levers, and knowing which to reach for:**

- **The style prompt** fixes systemic problems — everything is framed,
  everything is too small, colour is everywhere.
- **`HC_SUBJECT_OVERRIDES` in `generate_sets.py`** fixes a small closed class of
  keys, without disturbing the shared subjects that other sets use.

The distinction matters because subject text and style text compete, and
**subject text usually wins.** The `up` tile stayed solid blue through two
prompt revisions and an explicit "draw arrows entirely in white" instruction,
because its subject in `prompts.json` says *"bright blue color"* — authored for
Playful-3D years earlier. No amount of style wording beat it; a four-line
per-key override did. If a rule you stated globally is being ignored by a
handful of tiles, read their subjects before rewriting the prompt again.

## Step 6 — Generate the full set

```bash
python3 tools/generate_sets.py --set your_set --sleep 5
```

Generation is serial and `SLEEP_SECONDS` defaults to 15 — a DALL-E-3 Tier-1
number (5 images/minute) that predates gpt-image-1 and was never revisited. At
the default, 493 tiles is two hours of pure sleep. Use `--sleep` deliberately.

To go faster, shard across processes on disjoint key lists:

```bash
python3 - <<'PY'
import json, pathlib
keys = [t["key"] for t in json.loads(open("claudeBlast/Resources/vocabulary.json").read())]
d = pathlib.Path("/tmp/shards"); d.mkdir(exist_ok=True)
for i in range(4):
    (d / f"{i}.txt").write_text("\n".join(keys[i::4]) + "\n")
PY

for i in 0 1 2 3; do
  python3 tools/generate_sets.py --set your_set --sleep 5 --keys-file /tmp/shards/$i.txt &
done; wait
```

Each process writes distinct files, so they cannot collide. Failures are printed
with OpenAI's error body and collected in `tools/tile_sets/your_set_failed.txt`;
re-run those keys with `--key`.

Generate the **whole** set with the final prompt, including tiles you made
during iteration. A set generated across three prompt revisions is not one set.

## Step 7 — Review and approve

This is the step that cannot be automated, and the reason the previous steps
exist: to make sure a human only looks at work worth looking at.

```bash
python3 tools/build_review_page.py --set your_set
```

A self-contained page, one card per tile, showing **Playful-3D | Classic | your
new tile** side by side, with ✓ / ✗ and a comment box on each. Filter by word
class, by pack, or by status; approve everything visible in one click when a
category is clean.

Verdicts persist in `localStorage` and carry a fingerprint of the exact image
they were given for. When a tile is regenerated, the two verdicts behave
differently on purpose:

- **Approved → cleared.** An approval is permission to ship, and it must never
  carry over to art nobody has looked at.
- **Rejected → stays rejected**, marked *redone — re-review* in orange. A
  rejection is a to-do item, and clearing it would destroy the one filter you
  need in order to check the fixes. A rejected tile ships nothing, so there is
  no risk in keeping it. Judging it again clears the marker.

That asymmetry is what makes the loop tractable:

1. Review, then **Export Rejects** → paste into
   `tools/tile_sets/your_set/rejected.json`
2. `python3 tools/review_tiles.py regen --set your_set` — or fix the subject
   and regenerate by hand, which is usually the better answer when the
   rejection had a reason
3. Rebuild the page, filter to **Rejected → fixed, needs re-review**, and look
   only at those

`rejected.json` also seeds the page: any key listed there that the browser has
no opinion on comes back as an outstanding reject, with its original reason.
So a review survives being continued on another machine, or a cleared browser
store.

When you are done, **Export Full Review** downloads the verdict manifest. Keep
it — the next step needs it.

## Step 8 — Ship it

```bash
python3 tools/optimize_tiles.py --set your_set                       # 1024² → 512², ~80% smaller
python3 tools/sync_to_app.py --set your_set --review review_your_set.json
```

`--review` syncs only the tiles you approved and reports how many were withheld.
Without it, every tile ships regardless of verdict — which is what the review
tool's export used to allow, since nothing read it.

Then build and run the test target. `ImageSetCoverageTests` enforces that any
set marked `isShippable` has real art for every vocabulary key, and prints a
notice when a set that is *not* marked shippable has become complete:

```
[eval] your_set now has full coverage — consider marking it isShippable.
```

That is your completion signal. Flip `isShippable` in
`ImageSetID` (`claudeBlast/Services/TileImageResolver.swift`) and the coverage
test starts enforcing it from then on.

---

## What transfers

The specific failures were ours. These are not:

1. **Naming the use case in a style prompt poisons it.** The model draws the
   domain, not in the style.
2. **Subject text beats style text.** A colour named in a subject overrides a
   global rule about colour, every time.
3. **Calibrate against known-good work first.** An analyzer that flags a set you
   already shipped is measuring the wrong contract.
4. **A probe set should be adversarial.** Hard keys, chosen to break things.
5. **Diff every round.** Count regressions, not just fixes.
6. **Prompt changes for systemic problems, per-key overrides for small closed
   classes.** Using the wrong one wastes a round.
7. **Measurement exists to protect human attention**, not replace it. Nobody
   should review 493 tiles that a script could have told you were broken.

## The worked example

`docs/imageset-highcontrast-log.md` is the full record of rebuilding High
Contrast: the baseline evidence, four iteration rounds with what changed and
why, the two root-cause bugs, and the final numbers. Read it alongside this
guide — it is the same process with the details left in.

## If you build one

Open a PR, or just tell us it exists. A set tuned for a real child, with the
spec that produced it, is more useful to the next family than anything we would
have guessed at from here.
