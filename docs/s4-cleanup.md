# S4 cleanup list

Small defects found while building session 4, deliberately not fixed in the PR
that surfaced them. Cleared in a cleanup PR before the session closes.

Add to this list rather than derailing a feature branch.

**Entries are kept after they land, marked `**Landed:**` with the date and PR,
rather than deleted.** The original rule was to delete them; in practice the
reasoning in an entry outlives the fix and is what the next person needs. Every
entry below now carries a status — if one does not, that is a bug in this file,
not an item still open.

---

## 1. `p3d_bassketball.heic` ships and is unreachable

**Landed:** 2026-09-05, S5 PR 1 (#64).

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

**Landed:** 2026-09-05, S5 PR 1 (#64).

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

**Landed:** 2026-09-05, S5 PR 1 (#64).

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

**Landed:** 2026-09-05, S5 PR 1 (#64).

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

**Landed:** 2026-09-05, S5 PR 1 (#64).

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

**Landed:** 2026-09-05, S5 PR 1 (#64).

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

**Landed:** S4, `43ce69b`.

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

**Landed:** S4, `43ce69b`.

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

---

## 9. Validate a scene before letting it become active

**Raised:** 2026-09-03, out of two live lockouts on the iPad mini.

**Landed:** 2026-09-07, S5 PR 4. `SceneActivation` + `activate` returning its
outcome; all four call sites now report instead of `try?`.

Right now anything can be activated, and a scene with a structural fault takes
the device with it. Two ways in were hit within an hour:

1. **No resolvable home page.** A hand-built scene whose `homePageKey` named no
   page rendered `No Active Scene` — with no board, and therefore no Home cell to
   long-press, and therefore no route into Admin.
2. **Pages with no tiles.** A scene imported from a file whose words had been
   dropped by the export bug (see the `BundledVocabulary` fix) had four empty
   leaf pages. An empty page produced no chunks, so no Home cell, same dead end.

Both are patched, and the patches are the right ones to keep — the empty state
now carries an **Open Admin** button, the `pages` setter and `activate()` hold
the home-page invariant, and an empty page still draws its Home cell. But every
one of those is a *repair after the fact*. Nothing yet stops a scene in a known
bad state from going live.

**The question to settle:** should `activate(context:)` refuse, or repair, or
warn?

Arguments for refusing:

- A scene with no pages at all cannot be repaired into something usable. Adopting
  a first page is not available; there is nothing to adopt.
- Activation is a deliberate caregiver action with an obvious place to put an
  error, unlike the silent repairs which happen with nobody watching.
- "Why is my board empty" is a much worse question than "this scene isn't ready
  yet, here's what's missing".

Arguments for repairing, as now:

- A repair keeps a caregiver moving; a refusal in the wrong place strands them
  with a scene they cannot activate and may not know how to fix.
- The repair rules are cheap and obvious (first page becomes home).

Likely answer: **repair what is unambiguous, refuse what is not, and never
silently do either.** A scene with pages but a dangling home key repairs and says
so. A scene with no pages, or one whose every page is empty, refuses with a
message naming the fault. Worth deciding alongside Mark's related observation
rather than in isolation.

**Cases to enumerate when this is picked up:**

- No pages at all.
- Pages, but every page empty of vocabulary.
- Home page deleted while the scene was inactive — is it homeless, or repaired?
- Home page deleted while the scene was ACTIVE, which is the same fault arriving
  with a child holding the device.
- A page whose tiles all resolve to missing `TileModel`s (the export bug's
  signature), which looks populated in the editor and empty on the board.
- Scene arriving by import or sync in any of the above states, where no
  caregiver was present at the moment it became invalid.

Recorded so the two shipped patches are understood as containment, not as the
fix. The containment landed; the enumeration above is what `SceneActivation` was
written against.

---

## 10. Consequential toggles have no gate, and an unresponsive UI aims taps for you

**Raised:** 2026-09-03, from the Mac install after a large load run. Same class
as item 9.

**Landed:** 2026-09-07, S5 PR 4. The iCloud toggle confirms in both directions
and says what actually happens.

The Mac install came back with `icloud_enabled = true`, which nobody meant to
set. DEBUG registers it `false` and onboarding seeds its toggle from that, so a
stored `true` is an explicit write — and the likeliest author is a tap that
queued during one of the long unresponsive stretches after the load and landed on
whatever was under the finger when the run loop caught up.

**The mechanism is the point, not the mishap.** A UI that stops answering does
not stop accepting. Touches queue, and they are delivered against the layout that
exists when processing resumes — which after a list has grown, or a sheet has
settled, is not the layout the finger was aimed at. Every control in reach
becomes a control that can fire on its own.

**Why this one matters.** Flipping iCloud sync is not a preference, it is a
storage decision: the `ModelContainer` is rebuilt at next launch against a
different configuration, which store is authoritative changes, and turning it ON
can pull a large sync down onto a device that was deliberately local. It is one
tap, unconfirmed, in a scrolling list.

Related to item 9 because both are the same shape: **a consequential state change
with no gate, discovered only once the app is already in the bad state.**

**Do not dismiss this as a DEBUG-only artefact.** The load scripts that caused
the unresponsiveness are DEBUG-only; the unconfirmed toggle is not, and neither
is the general case. A first CloudKit sync on a real device with a large store
produces the same stalls in a RELEASE build, and Storage is exactly the screen a
caregiver would be on while waiting for it.

**Candidate fixes, in rough order of value:**

1. **Confirm the iCloud toggle**, both directions, naming what happens — "sync
   will begin at next launch and may download your existing data" / "this device
   will stop syncing; data already in iCloud is kept". Cheap, and it defeats the
   queued-tap case outright because a stray tap cannot also confirm.
2. **Make long operations own the screen.** The load runs leave the list live and
   tappable while blocking the main thread in bursts. A modal progress state that
   ignores input is more honest about what is happening — and this is exactly the
   fix already applied to tile-image export, which had the same "is it hung?"
   problem.
3. **Audit for siblings.** Anything else that is one unconfirmed tap from a
   structural change: factory reset (already confirmed), Flush All on the cache,
   scene activation and deletion, Remove PIN.


---

## 11. Profile names are visible now, and "Legacy" is on the report

**Raised:** 2026-09-04, from the first usage-report PDF. Next session.

**Landed:** 2026-09-07, S5 PR 5. Legacy deleted outright; Sandbox became the
caregiver's own profile; the report no longer titles itself with a profile that
is not a child.

The report's title is the `ChildProfile.displayName`, so the first PDF built on
Mark's iPad is headed **"Legacy"** — the name `ProfileMigration` gives the profile
it seeds from prior UserDefaults. That was an internal label back when nothing
displayed it. It is now the largest word on a document intended for a therapist.

Two questions, and the second is the real one:

1. **What should the seeded profiles be called?** "Legacy" describes where the
   record came from, not who it is about. Whatever replaces it has to work for a
   caregiver who never chose it and may never rename it.
2. **Do `Legacy` and `Sandbox` both need to exist?** They arrived for different
   reasons — `Legacy` is a migration artefact, `Sandbox` is
   `ChildProfileResolver`'s undeletable fallback so the engine never sees nil —
   and on a fresh install a caregiver can end up looking at both in the Profiles
   list with no way to tell why either is there. If one can cover both jobs, it
   should.

**Do this as an audit rather than a rename.** The names leak into the report
title, the Profiles list, the caregiver menu and any future scheduled digest, so
the question is which surfaces show a profile name at all — and whether an
unnamed profile should show *something else* rather than a placeholder that reads
as a real child's name.


---

## 12. The new activity screens have not been seen on a phone

**Raised:** 2026-09-04. Next session.

**Landed:** 2026-09-07, S5 PR 5. Heatmap scrolls with a pinned weekday gutter;
coverage rows protect the count; the coverage grid stopped claiming a layout
reflow does not preserve. The most-used strip was replaced by a list.

Coverage, Patterns and the coverage grid were built and reviewed on iPad and Mac.
None has been looked at in a compact width, and each has a shape that compact
width is unkind to:

- **The Patterns heatmap** is a `weekday × hour` grid whose columns come from the
  data. A board used from 7am to 8pm gives fourteen columns plus a day label
  gutter; on a phone those cells get very small, and nothing currently caps them
  or offers a scroll.
- **Coverage rows** carry a ring, a two-line label, a count and a percentage on
  one line. That is four things competing for ~350pt.
- **The coverage grid** uses `GridItem(.adaptive(minimum: 68))`, which will
  simply give fewer columns — probably fine, but it means a page's layout shape
  reads differently on a phone than the board the child actually uses, which
  undercuts the whole point of showing position.
- **The summary strips** are three-cell `HStack`s with numbers and labels; the
  Patterns one additionally carries a change indicator under each.

Related to the S3 finding that SwiftUI toolbars silently *drop* items at narrow
widths rather than collapsing them — the failure mode here is likely to be quiet
truncation rather than an obvious break.


