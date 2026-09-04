# Notes for 4E — the usage report

Raw material for the usage report, gathered before the work starts. Not a design;
the design waits on Brandi (`docs/final-countdown-plan.md` §4E).

---

## What CoughDrop's parent view actually shows

Observed 2026-09-02 from CoughDrop's supervisor dashboard. Worth studying because
it is the closest shipping thing to what 4E is for, and because its choices are
legible.

**The unit is a session, not a total.** The panel is headed "Recent Sessions for
supervisees" and each row is one sitting:

    an hour ago    4 buttons  - student   [home] [clear] [clear] … Yes, [vocalize] …
    3 hours ago   22 buttons  - student   [clear], not bad, [clear] … eat [open_boar…
    a day ago      0 buttons  - student
    2 days ago     2 buttons  - student   I e. [clear]

Three things fall out of that:

- **A session with zero buttons is still shown.** "0 buttons" is a real row. A
  device picked up and put down is data — arguably the most clinically
  interesting row on the page.
- **The raw sequence is previewed, including chrome.** `[clear]`, `[home]`,
  `[vocalize]` appear inline alongside words. It shows what the child *did*, not
  a tidied version of what they said. Noisy, and honest.
- **Counts are button presses**, not utterances. Ours would be tiles selected —
  and we additionally have the generated sentence, which CoughDrop has no
  equivalent of.

**Logging is off until switched on.** The dashboard reads "Logging is disabled"
with a reload link — the same posture we already take, and confirmation that an
opt-in default is the norm in this space rather than a limitation.

**The reader is a supervisor, not the device holder.** The page is "parent" with
a "supervisees" list and a home-board pointer per child. That is exactly 4E's
case — the report's recipient is usually not holding the device — and it is why
4E is a *share* rather than a screen in the Activity tab.

**Board changes are notified separately** from sessions: "student — home board was
changed, an hour ago". Editing and using are different events to a supervisor.

---

## What we have that they do not

`LoggedUtterance` records the generated sentence, not just the button sequence.
So our report can say what the child *said*, where CoughDrop can only say what
they pressed. That is the whole reason 4E crosses the privacy line `StorageExport`
refuses to cross, and why it must be an explicit, plainly-labelled, gated action.

---

## Open, still

The question held for Brandi: how much of the child's speech the readable report
carries — most-used words only, or full utterance history. The SLP wants more;
the privacy default wants less. See `docs/final-countdown-plan.md` §4E.
