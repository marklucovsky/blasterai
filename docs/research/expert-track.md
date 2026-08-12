# Expert track — conversations with AAC leaders and influencers

**Status:** Active as of 2026-08-09
**Owner:** markl
**Companion:** `docs/objection-register.md` (the standing agenda)

---

## Why this exists separately

`docs/research/plan.md` is a generative discovery study, approved May 18. It
opens: *"Blaster has been built without direct input from its intended
users… This study is generative: we are not testing Blaster's current design."*
It cold-recruits SLPs and BCBAs, gates them behind an NDA, runs 30 minutes, and
treats concept reactions as an optional closing section — verbally, with **no
visuals**.

That was right for May. It is wrong for now, for two reasons.

**The product changed.** It is feature-complete against `docs/prd.md` v1 and
four sessions from a TestFlight build. We are no longer learning whether to
build; we are learning whether what we built survives contact with clinicians.

**The prospects changed.** The people who actually engage are not a random
sample of practitioners. They are trainers, group hosts, board members, and
faculty — people with an audience, strong existing opinions, and a reason to
care. The first such contact reviewed the site unprompted and sent four
specific design critiques (CVI art, prediction vs. teaching, growth over time,
word flexibility) without being asked a single question. Reading the discovery
script at that person would have wasted their time and signalled that we did
not know what we had built.

Mark's framing: we will get engagement from **decision-makers and influencers**,
much less from people who feel powerless but interested. Design for the former.

The discovery study is not wrong, it is **early-stage and differently
scoped** — and it remains the right instrument for a later family and caregiver
study, which is the population this track does *not* reach.

---

## What changes

| | Discovery track (`plan.md`) | Expert track (this doc) |
|---|---|---|
| Premise | Learn the problem space | Pressure-test what exists |
| Recruiting | Cold, screened, by cohort | Warm, individual, by reputation |
| NDA | Required | None — a handshake |
| Length | 30 min | 45–60 min |
| Demo | None ("no visuals") | **First, and central** |
| Structure | Fixed script, warm-up → workflow → pain points | Standing objection list, they lead |
| Success | Themes for an affinity map | A resolved objection, or a named advisor |
| Output | Insight report | Updates to `docs/objection-register.md` |

---

## Who

People with standing in the AAC community: trainers and CEU providers, AAC
group hosts, NGO and association board members, university clinical faculty,
AAC-specialist SLPs with a following, and adult AAC users who mentor.

The qualifying signal is not credentials, it is **whether they will argue with
you**. Someone who says "looks great" is not useful here; someone who opens
with four objections is exactly the person this track is for.

**P1 — Brandi Lee Wentland, M.A., CCC-SLP.** AAC trainer, hosts an Out & About
group and is expanding them to other states, Nika Project board member,
building an online AAC Academy and mentor program. Stated interest in free,
open-source, culturally-responsive AAC. Already reviewed the site and sent
substantive critique; offered to sign an NDA, which Mark declined in favour of a
handshake. Rows 1–4 of the objection register are hers.

---

## Format

**Before.** Send nothing to read. If they have already looked at the site, ask
what they remember — first impressions from marketing copy are data.

**Open (5 min).** Who you are, what it is, and why them specifically. Say the
part that earns candour: this is early, it is free and open source, and the
useful version of this conversation is the one where they tell you what is
wrong. No recording unless they offer; take notes.

**Demo (15 min).** Screen share, or the build in hand if they have it. Drive it
live — do not narrate slides. Lead with:

1. Tiles → sentence, and the word-flexibility case (`like` + `chocolate` vs.
   `don't` + `like` + `chocolate`). This is the strongest true thing we have.
2. Repetition → escalation. The idea most likely to be new to them.
3. Single-word mode. The trust beat for a skeptical clinician: AI is optional.
4. Caregiver refine / hand-type / suppress. The answer to "what if it's wrong."
5. Scene generation from a plain-language goal, **and** the no-AI, no-key
   Build-from-Collections path.

**Objections (30 min).** They will already be talking. Do not run a script —
use `docs/objection-register.md` as a checklist of what to make sure got
covered, and let order follow their interest. The discipline that matters:

- When a row says **Answered**, show it rather than assert it.
- When a row says **Gap**, say "you're right, we don't have that" and ask what
  good would look like. Do not argue a Gap into a Partly. The register exists
  so this is a decision made in advance, not under social pressure.
- Anything not in the register is the most valuable thing in the call. Write it
  down verbatim and add a row.

**Ask (10 min).** One or more of: join the pilot; be an informal clinical
advisor; introduce us to two people; tell us who would hate this and why.

**After.** Update the register the same day — new rows, and verdicts that
moved. Note anything that changes the roadmap and raise it before it gets
buried.

---

## What we are honest about, unprompted

Volunteering the limits is what makes the rest credible, and these will be found
anyway:

- No CVI support today; High Contrast is not shippable as it stands.
- No teaching or modeling mode. Single-word mode is AI off, not AI that teaches.
- No question words in the vocabulary.
- Sentence length does not scale with age.
- The child cannot modify a generated sentence; only a caregiver can.
- Zero families outside the author's own have used it.
- The cost figure is unverified until the token ledger ships.

---

## Scheduling reality

`docs/plan-2026-08-06.md` recommends internal testers only for TestFlight round
1, and internal testers need App Store Connect team accounts. An outside
clinician requires **external** testing and therefore Beta App Review. Promise
a build only against that timeline.

---

## Related

- `docs/objection-register.md` — the standing agenda and source of truth
- `docs/research/plan.md` — the discovery study; still right for families later
- `docs/claims-audit-2026-07-20.md` — the discipline this track inherits
- `docs/guides/` — what a pilot participant is given
