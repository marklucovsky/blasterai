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
