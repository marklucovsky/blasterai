# Sentences on GPT-6 Luna (session 12, 2026-10-21)

gpt-4o-mini retires 2027-01-14. This is the first measurement of GPT-6 Luna on
the sentence and escalation surfaces, and the prompt work that followed. Same
cases, same calibrated judge (gpt-6.1-sol × 3), five samples per case.

## Which model

| | Sentences pass | Ladders pass | Latency p50 / p95 | $ / sentence |
|---|---|---|---|---|
| gpt-4o-mini, prompt p4 (shipping) | 329/350 | 65/65 | 0.77 s / 1.06 s | $0.00013 |
| Luna none, p4 | 285/350 | 35/65 | 1.06 s / 1.55 s | $0.00002 |
| Luna low, p4 | ~same as none | — | 1.16 s / 2.55 s | $0.00004 |
| Sol low, p4 (judge Astra) | 346/350 Tier-1 | 64/65 Tier-1 | 1.50 s / 3.12 s; one 24 s rung | $0.0004 |

Sol gets the hard cases right but **latency rules it out** (Mark): the child
waits on every new tile combination. Luna at `low` effort buys nothing and is
slower. **Plan: Luna at effort `none`, with the prompt tuned for it.** Pass =
Tier-1 and every judge median ≥ 4.

## Why Luna failed on p4

The prompt contradicted itself and Luna obeyed the louder rule. Tiles arrive
as `no (social)`, `her (people)`, `bed (object)`; the word-class rule said
social words open the sentence, people are who you speak to, objects are things
to be given — and a separate rule called the class "AUTHORITATIVE … MOST
IMPORTANT". gpt-4o-mini resolved this by sense; Luna followed it literally:
"No, I want the bed.", "Her, can I go to the pool?", "Yes, no."

Also found: GPT-6 writes typographic apostrophes ("don’t"), and every Tier-1
regex used the plain one, so "No, I don’t want to go home" scored as a request
to go home. `scorers.plain_quotes` normalises before checking.

## Prompt l1 → l5

| Rev | Change | Luna sent. | Luna ladders | 4o-mini sent. | 4o-mini ladders |
|---|---|---|---|---|---|
| p4 | shipping prompt | 285 | 35 | 329 | 65 |
| l1 | the exceptions written INTO the word-class rule: a pronoun marked (people) is the subject; yes/no are answers and no + a thing refuses it; bed/bath/nap are routines; the "authoritative" rule names them as part of the class's meaning | (fails only: 47 → 74 of 105) | | | |
| l2 | stop + an action tells someone to stop; an action + an activity says what to do with it; a person + a question word is who the question is about | 316 | 38 | 331 | 61 |
| l3 | question example moved to the (question) role; bed and hurt spelled out; escalation note "climb exactly ONE step"; question ladder never "I can't wait" | 328 | 46 | 331 | 65 |
| l4 | every rung keeps the first sentence's own words ("to go to bed", never "my bed"); no stalls below the top; question rung 1 is a reason, not a second question; a report of being hurt takes the hurt ladder; see/hear/fall are reports; a pronoun + a place says where | 317 | 57 | 335 | 62 |
| l4 again | identical prompt | 308 | 58 | | |
| **l5** | routines named up front (bed, bath, potty); stop + a thing turns it off; a last every-tile check, a selected "you" is the person asked | **320** | 49 | **338** | 63 |

**Noise**: the same prompt twice moved Luna 317 → 308 sentences. A difference
under ~10 is not a result. gpt-4o-mini's answer to a byte-identical request
("i, bus, school") flipped from 5/5 "I ride the bus to school" to 6/6 "I want
the bus to school" within two hours.

**Escalation** swings 49–58 on Luna from run to run; the failures are stalls (a
rung repeated before the top) and statement ladders drifting. Mark: not a
priority — repetition is escalation, prosody can make repeats sound different,
and a stall retry would add latency. The work is single sentences: the first
few a caregiver sees decide whether they keep the feature.

## Labelled (Mark agreed with Claude on all 140)

`runs/2026-10-21-1757-merged-sentence-l5-luna-vs-4o`, sample 0 per case, l5:
**Luna 63/70, gpt-4o-mini 67/70**. Judge agreement with the labels: 98%
(Luna 97%, gpt-4o-mini 99%) — the sentence judge's calibration holds on Luna.

Luna's misses on l5: tired + bed → "I want the bed" (twice); no + wash → "No!
Don't wash!"; dog + in + car → "I want a dog in the car."; find + ball → "I want
to play ball."; refine-shorter still 12 words; history-more doesn't name the
juice (gpt-4o-mini misses that too). Luna is better on stop + TV ("Can you
turn off the TV?") and i + bus + school.

## Shipping l5

l5 is better on gpt-4o-mini than p4 (338 vs 329 sentences, ladders 63 vs 65
within noise), so it ships now on gpt-4o-mini and is the base for Luna.
`CacheKeyPolicy.promptVersion` 6 → 7 so sentences cached under p4 are
regenerated; prompt fixtures re-recorded (parity 14/14).

## Prompt l6 (2026-10-21, after Mark's labels)

New case from Mark: "i, iced tea, all done" → both models said "I am all done.
Can I have iced tea?" (10/10). l6 adds: all done with a thing means finished
with it (gpt-4o-mini needed the close example "i, juice, all done" → "I'm all
done with my juice.", not "… Can I have juice?" — the rule alone got 3/10);
a feeling with the routine it calls for; no + an action refuses doing it; a
thing and where it is (in, on, under) is a statement; the every-tile check
says a chosen action is the verb. A first draft said "(not replaced by play)"
and gpt-4o-mini wrote "I don't want to play with milk." — naming a word in a
prohibition can plant it; removed.

| | Sentences (of 355) | Ladders | Latency p50 / p95 |
|---|---|---|---|
| gpt-4o-mini l6 | **351** (l5 338/350) | **65/65** | 0.81 s / 1.17 s |
| Luna none l6 | 342 Tier-1; judge pass within noise of l5 | 58/65 (l5 49) | 1.07 s / 1.99 s |

Luna's labelled misses: no + wash, dog + in + car, iced tea fixed (5/5);
tired + bed 4/5. Still open on Luna: find + ball ("I want to play ball", 0/5),
stop + tv ("Stop watching TV."), bowl as an action (2/5 "can I have a bowl").
`CacheKeyPolicy.promptVersion` 7 → 8.

## Next

- Luna polish before the switch: find + ball, stop + tv, bowl (actions).
- The Luna switch itself: per-model capability table (GPT-6 rejects
  `temperature`; `reasoning_effort: none`), and the app's price table needs
  GPT-6 cache-write pricing — a first-seen prompt is billed as a cache write
  (1.25× input), confirmed against the 2026-10-21 bill, where the harness's
  own accounting matched to the cent.
