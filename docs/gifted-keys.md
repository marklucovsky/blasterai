# Gifted evaluator keys

Handing a TestFlight evaluator an OpenAI key without making them buy one.

The friction being removed is not typing a long string. An evaluator *could* make
their own key; what stops them is being asked to put a credit card down to try a
favour someone asked them to look at. So the key is ours, and it arrives as a file
they tap.

---

## Minting a key

1. **platform.openai.com → project `Blaster TestFlight`.** Not the default
   project, which is development spend and stays separate.
2. **Create a secret key and name it after the evaluator.** The name is the whole
   ledger. The dashboard shows name, monthly spend and last-used per key, which
   answers *"this key is burning money — whose is it?"* without anything being
   written down in this repo. **Nothing here records keys, and nothing should.**
3. **Confirm the project's model allowlist.** Run:

       python3 tools/audit_openai_models.py

   It reads the models out of the sources and prints what the project must permit.
   Today: `gpt-4o-mini`, `omni-moderation-latest`, `gpt-image-2` (gpt-image-1 until 1.0.0 — it shuts down 2026-10-23).

4. **Mint the file:**

       python3 tools/make_gifted_key.py --for Brandi --out ~/Desktop

   It prompts for the key with hidden input. `--key` exists for scripting, but a
   key passed as an argument lands in shell history where it outlives the
   evaluator.

5. **Send the file.** Nothing else travels with it — there is no passcode.

   **Text is the short path**: the attachment opens straight into BlasterAI.

   **By email it depends on the client, not on the account.** Both verified
   2026-09-19 on iPad, both against Gmail accounts:

   - **Apple Mail** honours the file-type association. Tapping the attachment
     opens BlasterAI directly — nothing else to do.
   - **The Gmail app** does not. It neither strips nor previews the file; it
     *downloads* it and stops there. The recipient then opens **Files →
     Downloads** and taps it, and that is what hands it to the app.

   The covering note has to describe both, because you cannot know which client
   is on the recipient's iPad, and someone in Gmail waiting for the mail app to
   do something will conclude the file is broken.

## Revoking

Delete the key in the dashboard. That is the only revocation that works: nothing
in the file or in the app can take a key back, and the `expiresAt` field is
display-only.

The evaluator's device will start reporting *"OpenAI refused this key"* and fall
back to speaking each word as it is tapped. Nothing else about their install
changes.

---

## Two things the dashboard does not tell you

**The spend limit enforces, but it lags.** Measured 2026-09-16: spend reached
**$1.44 against a $1 limit** with calls still succeeding, before the first 429.
Reconciliation is asynchronous and the overshoot has no documented bound. Treat a
cap as a backstop with alerts, not a fence. To trip one deliberately, set the cap
*below* current spend rather than burning more calls.

**Images are essentially the entire spend.** ~4.8¢ per image against ~30 calls for
$1.44 on gpt-image-1 (gpt-image-2, from October 2026, is ~6¢ per picture); `gpt-4o-mini` needs on the order of 34,000 generated sentences to reach a
dollar. A cap is in practice a cap on art generation.

**All evaluators share one project**, so they share its cap: one runaway key
stops everyone at once. Per-key monthly spend still says who, so attribution
survives — it is the blast radius that is pooled.

---

## What happens on the evaluator's device

| Situation | What they see |
|---|---|
| Key installed | Admin → Device shows "Gifted key — Brandi · sk-…8toA" |
| A key is already on the device | Refused before installing, with *"This device already has a key"* and the route to swap it — **Admin → Device → Remove API Key** |
| Key revoked | "OpenAI refused this key", device speaks each word as tapped |
| Project out of credit | "This key is out of credit", same fallback, plus *close and reopen once the limit is raised* |
| A model not allowed | Art generation says so by name; sentences and moderation unaffected |

The refusal is a design decision, not a failure, and it is checked when the file
loads rather than at Install so nobody agrees to something that was never going
to happen: the Keychain holds exactly one key, so installing over a caregiver's
own would silently redirect their spending to our account and leave the old key
unrecoverable. See `GiftedKeyImportSheet.swift`. An evaluator following the
tester walk skips the key step at onboarding and never meets it.

The quota state does not clear on its own — the flag is in memory and nothing on
the device can observe a limit being raised at OpenAI. Authoring surfaces recover
by themselves; only the child's tile-tap → sentence path latches. See the note in
`AdminView+DeviceTab.swift`.

---

## The file format

`.blasterkey`, `application/vnd.claudeblast.giftedkey+json`. A JSON envelope
carrying the key, the recipient's name, the sender, an issue date and an optional
display-only expiry.

**It is obfuscated, not encrypted, and the code says so in those words.** The
keystream is derived from the app's bundle identifier, which is printed in the
App Store listing and sits in the Info.plist of any downloaded build. Anyone who
wants the key inside one of these files can have it.

That is deliberate. The repo is Apache-2.0 on GitHub, so a random constant in
source would be exactly as public while *looking* like a secret to every
contributor who reads it — there is no such thing as an embedded secret in an
open-source app. Keeping it honest also keeps `ITSAppUsesNonExemptEncryption =
false` true, since a hash is not encryption and an XOR against a non-secret
keystream is not a cryptographic algorithm for export purposes.

What it buys is **non-possession**: the evaluator never holds the key in usable
form, so they cannot paste it somewhere, forward it to a colleague who also wants
a look, or have it lifted out of an iCloud backup by an `sk-`-pattern scanner. A
raw key in a text message loses all three.

The long version is in `claudeBlast/Services/GiftedKeyTransfer.swift`. **Do not
change one side of the format without the other** —
`claudeBlastTests/Fixtures/gifted-key-golden.blasterkey` is minted by the Python
tool (`--self-test`) and opened by a Swift test, and that pairing is the only
thing that catches the two implementations drifting.
