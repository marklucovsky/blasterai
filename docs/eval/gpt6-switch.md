# Build 9: every chat job off gpt-4o-mini (2026-10-23)

gpt-4o-mini retires 2027-01-14. Build 9 moves each chat job to the GPT-6 model
its numbers support. One line per job in `ModelID` (ModelPricing.swift);
`ChatRequest` shapes the body (no temperature, a reasoning effort,
`max_completion_tokens`).

| Job | Was | Now | Evidence |
|---|---|---|---|
| Sentences + escalation | gpt-4o-mini | **gpt-6-luna** (none) | `luna.md`; Sol rejected on latency |
| Scene + page authoring | gpt-4o-mini | **gpt-6.1-sol** (low) | below |
| Tile suggest | gpt-4o-mini | **gpt-6.1-sol** (low) | below |
| Word audit (rubric, tier 3) | gpt-4o-mini | **gpt-6-luna** (none) | below |
| Skin check | gpt-4o-mini | **gpt-6-luna** (none) | below |
| Moderation (tier 2) | omni-moderation-latest | unchanged | free endpoint |
| Art | gpt-image-2 | unchanged | |

## Authoring, the app's own prompts

Runs `2026-10-23-1203-*-switch-{base,sol,luna}`, 3 samples, judge × 3. Sol is
judged by gpt-6-astra (a model doesn't grade itself), the others by gpt-6.1-sol,
so judge scores across columns are close but not identical yardsticks; Tier-1
is the same code for all.

| Surface | | gpt-4o-mini | Luna | Sol |
|---|---|---|---|---|
| scene_generate | Tier-1 | 8/42 | 12/42 | **27/42** |
| | ≤3 on any | 41/42 | 37/40 | **34/42** |
| | p50 / p95 | 5.6 s / 10.8 s | 6.9 s / 11.0 s | 15.8 s / 20.2 s |
| scene_refine | ≤3 on any | 15/18 | 8/18 | **3/18** |
| page_generate | Tier-1 | 8/12 | 9/12 | **12/12** |
| page_refine | Tier-1 | 9/9 | 9/9 | 9/9 |
| tile_suggest | ≤3 on any | 22/24 | 17/24 | **6/24** |
| | coverage / precision | 2.75 / 4.08 | 3.33 / 3.96 | **3.83 / 4.71** |
| | p50 | 2.7 s | 2.5 s | 5.4 s |

Sol for both, Mark 2026-10-23. A whole scene now takes ~16 s. Luna also wrote
malformed JSON (stray closing brackets) on 2 of 3 `zoo_terse` scenes — moot
while scenes are on Sol, but a reason not to move them to Luna for speed.

## Word audit

Same runs, 40 words × 3. Luna agrees with gpt-4o-mini on 26 of 40 words and
is more lenient on the rest:

- **blocked → flagged** (caregiver's choice): fight, punch, blood, hate — the
  M1 decision of 2026-10-19 (`WORKLIST.md`) — and stupid, dumb, crap, shut up,
  knife; toy gun 1 in 3.
- **flagged → allowed:** monster; penis, vagina, private parts 1 in 3.
- **unchanged, blocked:** beer, wine, gun, cigarette, vape, drugs, kill, sexy.

Tiers 1 and 2 (local lists, omni-moderation) still run first. Accepted as is,
Mark 2026-10-23.

## Skin check

`tools/eval/probe_skin_check.py` sends Classic tiles with the app's exact
request and compares with `tools/tile_sets/classic_skin_tiles.json`.

At the app's old limit of 3 tokens Luna answered **empty** on every tile: it
spends 4 completion tokens on "yes", and a truncated answer has no text. Empty
reads as "no", so every person would have kept the default skin tone, silently.
The limit is now 16. After that: gpt-4o-mini 40/40, Luna 40/40, and Luna 80/80
on a second sample (seed 11).
