# Remote Config from blasterai.app — the shared download pipe

**Written:** 2026-08-14, during session 2A (cost accounting).
**Status:** design agreed, **implementation deferred to 2B**, where the same machinery is
needed for installable image sets.
**Related:** `docs/design-installable-image-sets.md`, `docs/plan-2026-08-06.md` (session 2),
`claudeBlast/Services/OpenAI/ModelPricing.swift`.

---

## The problem this solves

`ModelPricing` is a hand-transcribed snapshot of OpenAI's published prices. **There is no
pricing API** — `/v1/models` carries no rates, so the numbers are read off a human-readable
page and typed in.

The defect isn't staleness itself; a wrong price harms nothing operationally, since we bill
nobody and it only affects a figure in an admin panel. **The defect is that correcting a price
currently requires an App Store release.** Coupling the accuracy of a number to our release
cadence is the thing worth fixing.

## The decision

Publish a small static JSON payload at `blasterai.app` (e.g. `/api/pricing.json`), refreshed by
a scheduled GitHub Action in `~/src/blasterai-site`. The app fetches it, validates it, and uses
it in preference to its built-in table.

**This is not a backend.** It is a static artifact on Cloudflare Pages — no code, no database,
no request handling. That's a feature: the endpoint's entire attack surface is "serves a wrong
file," which the client-side validation below contains.

Mark's precedent is a far more capable `/info` endpoint at a previous startup, served by real
code. The distinction matters and is deliberate: this one cannot make decisions, and doesn't
need to.

## Privacy — the objection that had to clear first

The app today **never phones home to us**. "No external backend" is load-bearing in
`docs/prd.md`, on the site, and in the deck. A pricing fetch means Cloudflare logs an IP from
every install that asks.

**It clears because we are already crossing that boundary for image-set downloads from the
same domain.** Pricing rides an existing pipe at no *additional* privacy cost. Had installable
sets not been on the roadmap, this would be a much harder call for a number in an admin panel.

Conditions, non-negotiable:

- Unauthenticated static `GET`. No query parameters, no headers carrying device, child, or
  install identifiers. Nothing that could turn a fetch into a analytics signal.
- Disclosed in the privacy copy and the App Store nutrition labels alongside the set downloads.
- Check Cloudflare log retention on that zone and turn it down if it isn't already minimal.

## Two corrections to the first sketch

### Not at boot

The initial idea was "fetch at boot if `daysSinceVerified > N`." Boot is the worst available
moment — it's when launch latency is most visible and when a child may be waiting on the grid.
And there is no urgency whatsoever: prices change rarely, and a stale price costs nothing.

**Fetch when Admin → AI Usage is opened**, with a long cache. The child-facing launch path stays
completely untouched, which is worth more than freshness here. The only person who benefits
from a fresh price is the person looking at the report, so fetch when they look.

### Prefer a structured source over scraping HTML

A GitHub Action parsing OpenAI's pricing page is the same fragility relocated — and relocating
it makes failures **quieter**, since a CI job failing overnight is less visible than a person
noticing a wrong number.

- Prefer a maintained structured source (LiteLLM's `model_prices_and_context_window.json` is
  the obvious candidate) over parsing markup. It adds a third-party trust dependency, which the
  validation below is sized to contain.
- **The Action must fail loudly and must never publish a partial or empty parse.** "No update"
  always beats "wrong update" — the whole point of this system is to make a claim we can stand
  behind, and a confidently wrong number is worse than an admittedly old one.

## The client contract — advisory, never authoritative

The built-in `ModelPricing` table remains the floor and the fallback. A garbled, stale, or
hostile payload must not be able to make reported costs nonsense.

1. **Reject unknown model ids.** Only ids present in `ModelID` are accepted.
2. **Sanity-check magnitudes.** A rate off by orders of magnitude is a parse failure, not a
   price cut. Bound each rate to a plausible range.
3. **Only accept a payload whose `asOf` is newer** than the built-in table's.
4. **Payload carries a schema version.** An unrecognized version is ignored, not guessed at.
5. **Never blocks, never crashes.** Any failure silently falls back to the built-in table.
6. Cache the accepted payload locally with its `asOf`, so the fetch is occasional rather than
   per-view.

Every ledger row already stamps `priceTableAsOf` (`APIUsageEvent`), so whichever table produced
a figure stays identifiable after the fact — including retrospectively distinguishing rows
priced by a remote payload from rows priced by the built-in table.

## Why this waits for 2B

The machinery — *fetch a file from blasterai.app, validate it, cache it, fall back gracefully,
tell the user nothing when it fails* — is **exactly** what installable image sets need. Same
pipe, same validation shape, same failure modes, same privacy disclosure. Building it twice
would be the mistake.

So 2A ships the built-in table plus `ModelPricing.daysSinceVerified()`, which surfaces "prices
last verified N days ago" in the Activity detail view. That makes the staleness *visible*
rather than assumed away, which is the honest interim position while no API exists to check it
for us.

## Verification, unrelated to any of the above

Worth recording because it was discovered alongside: OpenAI's Admin
**`/v1/organization/costs`** endpoint returns *actually billed dollars* and reconciles to the
invoice — a far stronger check than reading the dashboard.

It requires an **Admin API key created by an org Owner**, which is org-wide and far more
privileged than the project key a caregiver supplies. **It must never be requested from a user
or wired into the app.** It is a development-time tool, run against our own org, for confirming
that the app's computed totals match reality. A `tools/` script for that is the natural home.
