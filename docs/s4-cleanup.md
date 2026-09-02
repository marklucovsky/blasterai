# S4 cleanup list

Small defects found while building session 4, deliberately not fixed in the PR
that surfaced them. Cleared in a cleanup PR before the session closes.

Add to this list rather than derailing a feature branch; delete an entry when it
lands.

---

## 1. `p3d_bassketball.heic` ships and is unreachable

**Found:** 2026-09-01, during a tile-art coverage audit for the PDF renderer.

`bassketball` is a historical vocabulary typo — `tools/map_sclera.py:100` labels
it "typo in vocab", and `tools/prompts.json` still carries a prompt for it. The
vocabulary was corrected to `basketball`, which now has art in all five sets, but
the misspelled Playful-3D file was never removed. Nothing can reference it: no
vocabulary key, no pack, no scene.

**Fix:** delete `claudeBlast/TileImageSets/p3d_bassketball.heic`. Consider
whether the stale `prompts.json` / `sclera_mapping.json` entries should go too,
or stay as a record of the rename.

**Check for siblings** — this was found by diffing art filenames against
vocabulary keys. That audit is worth keeping:

    python3 - <<'EOF'
    import json, os
    vocab = {t['key'] for t in json.load(open('claudeBlast/Resources/vocabulary.json'))}
    packs = set()
    for f in os.listdir('claudeBlast/Resources'):
        if f.startswith('pack_') and f.endswith('.json'):
            packs |= {w['key'] for w in json.load(open(f'claudeBlast/Resources/{f}'))['words']}
    known = vocab | packs
    seen = set()
    for f in os.listdir('claudeBlast/TileImageSets'):
        if f.endswith('.heic'):
            seen.add(f[:-5].partition('_')[2])
    print('art with no word:', sorted(k for k in seen - known if not k.startswith('packcover_')))
    print('words with no art:', sorted(known - seen))
    EOF

---

## 2. `help` classic art has a drawn frame baked into the image

**Found:** 2026-09-01, visible on any printed board and in the app grid.

`cls_help` carries its own white box and thin black border inside the PNG, so the
tile renders a frame within a frame. Every other tile in the set is a subject on a
clean background. It is most obvious in print, where the surrounding card border
makes the doubling explicit, but it is wrong on screen too.

**This is our own generated art, not inherited.** ARASAAC was demoted to legacy
and removed; the shipped sets are all OpenAI-generated. So the fix is a
regeneration, not a substitution — per the standing preference, never swap a
generated tile for a third-party one.

**Fix:** re-audit the classic set for baked-in frames or borders (there may be
more than one — `help` was found by eye, not by search), then regenerate the
offenders from `tools/prompts.json` with the background requirement stated
explicitly.

---

## 3. Long tile labels truncate in print

**Found:** 2026-09-01, on a 9-across core board: "graham crac…".

At core-board density the label band is ~1 inch wide, which a few of the longer
vocabulary words overrun. The board is still usable — the picture carries the
word, and the label is a hint — but a caregiver reading the sheet gets nothing
from an ellipsis.

**Fix:** shrink to fit down to a floor before truncating, the way `TileView` does
with `minimumScaleFactor(0.6)`. Its comment applies verbatim to paper: a whole
word slightly smaller beats half a word at the size asked for.

---

## 4. The "not vocabulary" predicate is copy-pasted in five places

**Found:** 2026-09-01, while fixing page-link tiles travelling inside a pack.

`wordClass != "navigation" && wordClass != PageLink.wordClass` appears inline in
`SceneRefinerService:139`, `SceneGeneratorService:176`, `PageGeneratorService:222`
and `CollectionSource:154`. Pack export needed the same rule and was written
without it, which is how `body_health` shipped as a word and got moderated as one.

It now has a name — `TileModel.isStructuralChrome` — but only pack export uses it.

**Fix:** point the other four at the named predicate, so the next surface that
treats a page's tiles as a word list inherits the rule instead of forgetting it.

---

## 5. `NOTICE` describes art the app no longer ships — **S5, not this session**

**Found:** 2026-09-02, while deciding what licence an exported `.obz` should
assert.

`NOTICE` still says most tile images are ARASAAC pictograms under CC BY-NC-SA
4.0, "FREE for NON-COMMERCIAL use only", and that "Commercial use (e.g. App Store
distribution) requires replacement with commercially-licensed imagery."

None of that is true any more. All 2,743 shipped images across the five sets are
OpenAI-generated; "ARASAAC" survives only as a *style description* inside a
generation prompt (`Resources/image_styles.json` — "in the ARASAAC style") and in
one comment listing AAC apps. No ARASAAC asset ships.

This is not cosmetic. It is a standing claim that the app cannot be distributed
commercially without replacing its art, which is exactly the kind of statement
the S5 claims refresh exists to catch — and it is the file a reviewer or
contributor reads first.

**Fix:** rewrite `NOTICE` for the art that actually ships, as part of the S5
claims refresh (`docs/claims-audit-2026-07-20.md` discipline) rather than here.
Mark's intent, confirmed 2026-09-02: **repo and app images are Apache-2.0 with no
additional constraints.**

Related and already handled: OBF/OBZ export reports Apache-2.0 for bundled art
and attributes caregiver-generated art to its author without asserting a licence
on their behalf. See `docs/obf-interop.md`.

---

## 6. A test that references a `private` symbol can vanish without failing

**Found:** 2026-09-02, while adding coverage for the `bundleImage` alias bug.

A new test in `BoardPrintTests` referenced `PrintImageCache`, which is
file-private in `BoardPDFRenderer.swift`. Rather than failing the build,
`xcodebuild` printed `** TEST SUCCEEDED **` and ran the previous test bundle: 21
tests, the new one simply absent. Nothing in the summary said so.

This is the same trap `CLAUDE.md` documents for a wrong `-only-testing` path —
"a wrong path is not an error" — wearing a different disguise. The counter-measure
is the same: **check the test names, not just the count or the exit status.**

    xcrun xcresulttool get test-results tests --path <bundle>.xcresult \
      | grep -o '<newTestName>'

**Fix:** consider whether `CLAUDE.md`'s testing section should say this more
generally — verify that the test you just wrote appears in the results, by name,
before believing a green run.

---

## 7. No question words in the vocabulary at all

**Found:** 2026-09-02, from Brandi asking how we assure a child has the core
words they need.

Coverage against a standard core list is broadly good — verbs 29/30,
prepositions 12/13, pronouns 13/17, descriptors 16/19 — with one hole:

**Question words: 0 of 7.** No `what`, `where`, `who`, `why`, `when`, `how`,
`which`. The `question` wordClass contains exactly one word, and it is the
literal word `question` (a page-link cover). The nearest entries are `whats_up`
and `how_are_you`, which are social phrases, not question words.

This matters clinically rather than cosmetically: wh-words are how a child *asks*
rather than requests, and every published core board carries them. Without them
the board caps out at requesting and commenting.

**Also missing, from the same audit:** `do`, `to`, `mad`, `some`, `done`, `him`,
`her`, `them`, `us`, `hi`, `bye`, `dont`.

**Fix:** add the words, generate art for each in every shipped set, and place
them on the Core-First board. Non-trivial: it is a vocabulary change, an
image-generation run across five sets, and a revisit of the default board's
layout. Mark's call, 2026-09-02: **its own pass this session, not folded into the
export PR.**

---

## 8. A part-of-speech axis is for discovery, not for the generator

**Raised:** 2026-09-02, alongside item 7.

`wordClass` is **not** a board-organisation taxonomy and should not be made into
one. It exists for the sentence generator: `SentencePromptBuilder:68` injects
`"\(value) (\(wordClass))"` so the model can tell `snack_bar` the place from
`snack_bar` the food, and it also participates in the cache key. It serves that
customer well, and pages — arranged by the caregiver — are what organise a board.

What is genuinely missing is a *second, independent* axis: part of speech. Its
consumers are all caregiver- or therapist-facing:

1. **Tile picker filtering** — "show me verbs" while building a page.
2. **Coverage auditing** — the report that answers item 7's question for any board.
3. **Generation prompts** — "include eight core verbs" instead of hoping.

**It need not be a stored field.** `TileModel.key` is a language-neutral concept
id that never changes, so part of speech can ship as a static lookup in
`Resources/` over the bundled vocabulary — no `TileModel` property, no synced
schema change, and therefore **no S6 promotion deadline**. Caregiver-added words
are absent from such a table, which is acceptable: they are overwhelmingly
concrete nouns a family invented, and coverage auditing is about core words.

**Fix:** design with Brandi before building — part of speech and Fitzgerald-key
colour grouping are different axes, and which one a therapist actually filters and
teaches on decides the shape. See [[project_wordclass_taxonomy_review]].
