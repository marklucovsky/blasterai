<!-- SPDX-License-Identifier: Apache-2.0 -->
# Testing backlog

Test coverage worth having that isn't built yet. Each entry says what it would
prove, what it would **not** prove, and roughly what it costs — because the
recurring mistake is reaching for the expensive kind of test when a cheap one
covers the same failure.

See also [architecture-backlog.md](architecture-backlog.md).

---

## The two kinds of art bug, and which tests catch which

Everything below is shaped by a distinction the 2B art work made concrete. Bugs
in the tile-art pipeline come in two flavours, and they need different tools:

**Plumbing** — did the right calls happen, in the right order, the right number
of times? Deterministic, cheap to assert, and now partly covered by
`ArtPlanTests`.

**Art** — is the picture any good? Not assertable. Every art bug found in 2B was
caught by a human looking at tiles:

- the two-image exemplar edit composing a *new* picture, so one word came out as
  three different swimmers
- Medium landing well past its target tone
- the tone prompt inventing a child eating dinner when handed a picture of the
  White House, because the prompt asserts a figure exists

A mock returning a fixed PNG sails through all three. **No amount of unit testing
substitutes for adding a word and looking at it**, and a suite that implied
otherwise would be worse than none. What tests can do is stop a fixed bug from
coming back, and pin the plumbing so review attention goes to the pictures.

---

## 1. HTTP-level stub for the art pipeline  · medium value, ~250 lines

**Status:** deferred 2026-08-17. `ArtPlanTests` took the high-value part for
~130 lines and no new infrastructure, which is most of why this is still a
backlog item.

`OpenAIClient.send` already accepts `session: URLSession = .shared` — the seam
exists. `TileImageGenerator` never passes one, so it always reaches the real API.
Building this means a `URLProtocol` stub plus threading `session:` through
`generate`, `fillMissingVariants`, `generateBase`, `transform`, `depictsSkin`.

**Would prove** — the failure modes, which is the part `ArtPlanTests` cannot
reach, since they depend on what comes *back*:

| Scripted response | Assertion |
|---|---|
| classify → "no" | 0 edits, variants byte-identical to the base |
| classify → "yes" | edits run in order, each prompt naming the right origin→target hex |
| classify → 500 | **fails closed** — copies rather than transforming |
| second edit → 500 | Light + Medium stored, Dark **absent** — never the wrong tone |
| base generation → 500 | that style contributes nothing, other styles still land |
| catch-up, existing = {Light} | 2 edits; existing = {Light, Medium} → 1 edit, Dark only |
| any of the above | the expected `APIUsageEvent` rows and causes |

**Would not prove** anything about the art itself. See the note above.

**Worth doing when** a third caller of `TileImageGenerator` appears, or the first
time one of those failure paths is edited without confidence. The
`transform`-failure-leaves-it-absent rule in particular is a deliberate choice
that currently nothing defends.

---

## 2. Tile-art eval harness  · high value, unknown cost

The natural extension of the sentence [eval harness], and the only thing on this
page that addresses **art** rather than plumbing. Generate art for a fixed word
list across styles, then score it — programmatically where possible (measured
skin tone against the set's `ToneTarget`, outline weight, background fill; the
`tools/measure_skin_tone.py` and `tools/check_*.py` scripts already do versions
of this offline), and with a judge rubric where not.

Would have caught: Medium landing past its target (measurable), and plausibly the
different-swimmers bug via an image-similarity check between a style's variants.

Note the asymmetry this exploits: variants of one style are *supposed* to be
near-identical outside the skin, so pixel-level comparison between them is a
legitimate assertion in a way it never is for independently generated art.

Related: scene-generation eval (Tier-1 structural + judge rubric) is the same
shape of missing coverage on a different surface.

---

## 3. `SceneImageBatchController` state machine  · low value

Pause / resume / cancel / background-and-return, and the `Mode` split between
drawing new art and filling variants. No network needed if the per-word call is
injected. Low value because the states are simple and a break would be immediately
visible, but it is the kind of thing that quietly rots as modes are added — it
grew its second mode in 2B.

---

## 4. Onboarding → active set → generation, end to end  · medium value

The single worst bug of 2B was a chain of small ones: a non-failable
`init(rawValue:)` made `?? .defaultSet` dead code, which produced
`ImageSetID("")`, which matched no card in onboarding, which persisted an empty
string, which left the resolver on Classic — so a word added on Medium-Dark was
generated in Classic. Every link was individually plausible.

`ImageSetCatalog.resolved(_:)` and its tests now cover the first link. Nothing
covers the path from "caregiver taps a card" to "art is generated in that style".
A test that drives the onboarding commit and then asserts what `ArtPlan` produces
would close it.

---

## 5. Bundled-art coverage per style  · already covered, do not duplicate

`ImageSetCoverageTests` asserts every shippable set has real art for the whole
vocabulary and for starter/pack words. This is the test that catches a missing
sync or a wrong `bundlePrefix`. Listed here only so it isn't rebuilt: if a
question is "does this set have art for this word", it already has an answer.

[eval harness]: plan-2026-06-16.md
