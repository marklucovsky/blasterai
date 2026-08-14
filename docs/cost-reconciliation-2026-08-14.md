# Cost Reconciliation — 2026-08-14

**Purpose:** verify that the app's computed API costs match what OpenAI actually bills, closing
gate 4 of `docs/plan-2026-08-06.md` ("no token/cost accounting — the $0.10–0.50/month claim is
unverified"). Same discipline as `docs/claims-audit-2026-07-20.md`.

**Method:** a clean simulator install, a scripted session (TileScript "First Look" ×2, an
AI-generated scene, a page, an add-word, one art refine), then OpenAI's own usage and cost
exports pulled for the same window and compared line by line.

**Sources:** `cost_2026-08-13_2026-08-14.csv`, `completions_usage_2026-08-14_2026-08-14.csv`,
`images_usage_2026-08-14_2026-08-14.csv`, `moderations_usage_2026-08-14_2026-08-14.csv`.

---

## Result: every rate confirmed to the cent

Rates implied by dividing OpenAI's billed amount by their billed quantity, against
`ModelPricing`:

| Line item | Quantity | Billed | Implied rate | `ModelPricing` |
|---|---|---|---|---|
| `gpt-4o-mini` input | 30,346 tok | $0.0045519 | **$0.150 / 1M** | $0.15 ✓ |
| `gpt-4o-mini` output | 1,637 tok | $0.0009822 | **$0.600 / 1M** | $0.60 ✓ |
| `gpt-image-1` text input | 4,567 tok | $0.022835 | **$5.00 / 1M** | $5.00 ✓ |
| `gpt-image-1` image input | 194 tok | $0.00194 | **$10.00 / 1M** | $10.00 ✓ |
| `gpt-image-1` image output | 42,240 tok | $1.6896 | **$40.00 / 1M** | $40.00 ✓ |
| `omni-moderation-latest` | 453 tok | $0 | free | free ✓ |

**Six for six.** The two line items carrying essentially all the money — image output and chat
input — are exact.

### The single most convincing detail

The bill shows **194 image-input tokens** for the whole day. The app recorded exactly one
image-to-image call (`Art refines`, `/v1/images/edits`, `img-in 194`). A rate that only one
call in the entire day exercises, matched precisely — that is not a coincidence surviving a
wrong implementation.

### Volume reconciles

42,240 image-output tokens ÷ 1,056 per image = **40 images**, which is 23 (current install) +
11 (pre-wipe run) + 6 (previous evening, same UTC day).

Within the clean-install run: 23 images → $0.9715 predicted; app reported $0.94 (tile art) +
$0.04 (refine) = **$0.98**.

### What could not be compared directly

The app's month-to-date total ($0.99) against the export's day total ($1.72). The app's store
was wiped before the final run, so it holds only that run, while the CSV covers all of
2026-08-14 **UTC** — which includes the prior evening in local time plus two earlier runs. Not
a discrepancy; different windows.

---

## Open item: cached input tokens

**The app recorded cached prompt tokens that OpenAI's exports do not show.**

Two scene-generation calls reported `cached 2304` and `cached 1024` in their API responses, and
the app applied the half-rate cached discount accordingly. But summing
`input_cached_tokens` across all 37 `gpt-4o-mini` requests in the completions export gives
**0**, and the cost export's `gpt-4o-mini-2024-07-18, cached input` line shows **0 tokens**.

So one of:

1. **The exports haven't settled.** Most likely. OpenAI's two exports **disagree with each
   other**: the cost file reports 42,240 image-output tokens (40 images) while the completions
   file reports 40,128 (38). A two-image gap between OpenAI's own files means neither was final
   when pulled.
2. **The API reports `cached_tokens` without billing them at the cached rate**, in which case
   we credit a discount that was never given.

**Exposure if we're wrong:** 3,328 tokens × $0.075/1M = **$0.00025** on this data set.
Immaterial to any claim, but under-reporting is the wrong direction to be wrong in — telling a
caregiver something costs less than it does is exactly the failure this system exists to
prevent.

**Decision: leave the code unchanged for now.** It implements OpenAI's published pricing, and
changing it on evidence that contradicts itself would be worse than waiting. **Re-pull the
export after 24h; if `input_cached_tokens` is still zero once billing has settled, stop
applying the cached discount.**

---

## What this establishes about the product

| | Calls | Cost |
|---|---|---|
| **Talking** (sentences, escalations, refines) | 13 | **$0.0012** |
| **Authoring** (art, scene/page generation, word audit) | 31 | **$0.99** |

A ratio of roughly **800×**. Two complete TileScript runs cost a tenth of a cent; one
AI-generated scene with art cost about a dollar.

Two effects worth keeping in mind when quoting numbers:

- **Prompt caching materially discounts authoring.** One scene-generation call came back 97%
  cached (2,304 of 2,385 input tokens). Repeat authoring against similar prompts is cheaper
  than a naive token count suggests — subject to the open item above.
- **Art is the entire cost story.** At ~$0.043 per image, cost scales with the number of tiles
  a caregiver generates art for, and with nothing else that matters.

### The GTM claim

`docs/gtm.md` currently says **$0.10–0.50/month**. That is wrong in both directions: it
overstates talking by roughly an order of magnitude, and omits authoring entirely, which is
where all the money goes.

**Evidenced replacement:**

> Talking costs about a penny a month. Building a new board with AI art costs about a dollar,
> once.

Still a devastating comparison to $300/yr for a dedicated device, and every part of it is now
backed by a line item. Updating `docs/gtm.md`, the site, and the deck is a follow-up to this
document.

---

## How to repeat this

1. Wipe and reinstall so the ledger holds only the session being measured.
2. Run a representative session; note the local start/end times.
3. Export from OpenAI: **Usage → Export** (completions, images, moderations) and **Cost →
   Export**, for the UTC day covering the run.
4. Compare *rates* (billed ÷ quantity) rather than totals — rates are robust to window
   mismatches, totals are not.
5. Check the exports against **each other** before trusting either against the app.

A `tools/` script against the Admin `/v1/organization/costs` endpoint would automate steps 3–5.
That endpoint returns actually-billed dollars and reconciles to the invoice, but requires an
**Admin API key created by an org owner** — org-wide and far more privileged than the project
key a caregiver supplies. **It must never be requested from a user or wired into the app.** See
`docs/design-remote-config.md`.
