# Release runbook

How a TestFlight build gets made. Written so the next one is a checklist rather
than a memory, and so someone who is not Mark can produce one.

**Status:** scripted end to end. `tools/preflight_release.py` checks, then
`tools/release.py` bumps, archives, exports and (opt-in) uploads.

    python3 tools/release.py --bump build            # bump, archive, export
    python3 tools/release.py --bump build --upload   # …and send it

Upload is opt-in on purpose: archive and export are repeatable, but a build
number is spent permanently — App Store Connect will not take the same
version+build pair twice, even for a build that was deleted.

---

## 0. Before anything: is CloudKit promoted?

**A TestFlight build always uses the Production CloudKit environment.** Not the
Development one, whatever the scheme says — distribution builds get Production,
and that is the whole of gate 1.

Production currently has **no schema at all** (session 1 deferred phases 4–5), so
a build uploaded before promotion installs and runs but syncs nothing. If that
is not yet done, stop here and run `docs/cloudkit-promotion-runbook.md` first.

Promotion is irreversible in one direction: a Production schema is additive-only
forever. After it, a field can be added but never removed.

**A build that adds a synced field needs that field in Production first.**
Production does not grow its schema from client writes; a record carrying a
field Production lacks is rejected, and that record type stops syncing. Before
uploading such a build: run the schema exerciser from a Development build
(Admin → Device → Storage) so the field exists in Development, then CloudKit
Console → **Deploy Schema Changes** to Production, and tick the field off in
`docs/cloudkit-schema-checklist.md`. Fields added since promotion (2026-09-18):
`ChildProfile.linkColorModeRaw` (2026-09-27) and `BlasterScene.designedFor`
(session 8), both deployed 2026-10-06. The first shipped in build 4 a week
before its deploy, because nothing in the release loop asked. Before every
upload, compare `tools/expected_cloudkit_schema.py` against Production's
record types: a field it lists that Production lacks means deploy first.

---

## 1. Preflight

    python3 tools/preflight_release.py

Refuses rather than warns, and reports every problem in one run rather than one
per round trip — each of these checks takes minutes.

| Check | Why it is there |
|---|---|
| Working tree clean, on `main` | An archive you cannot trace to a commit is not a release |
| Versions readable | They live in `project.pbxproj`, duplicated per configuration |
| Shared scheme, tracked, archives Release | Without it, only a machine that has run Xcode can build |
| Scheme carries no environment variables | The dev scheme holds a live `OPENAI_API_KEY`; a tracked one would leak it |
| **Gates 8 and 9** | `languageRaw`/`brownsStageRaw` present, `birthday` gone — both become impossible to change after promotion |
| Privacy manifest, export compliance | Submission requires the first; without the second every upload asks |
| Tile-set drift, model list | The existing audits, so preflight is one command and not four |
| **Debug *and Release* build** | Release stopped compiling on 2026-09-17 and nothing noticed |
| No key override in Release | `OPENAI_API_KEY` is read only under `#if DEBUG`, and no copy naming it survives into the Release binary |
| Full test suite, with a count | A filter matching nothing still prints `TEST SUCCEEDED` |

`--fast` skips the suite; everything else still runs.

### The Release check earns its place

On 2026-09-17 the app did not compile in Release. Three `@State` members were
inside `#if DEBUG` while two tabs used them unguarded. Nothing in the normal loop
touches that configuration — `xcodebuild build` and `test` both default to Debug
— so the first thing that would have failed was the archive for build 1.

---

## 2. Schemes

Two, and the split matters.

- **`claudeBlast`** — development. Holds `OPENAI_API_KEY` as an environment
  variable, which is why it is in `.gitignore` by name and must stay there.
- **`claudeBlastRetail`** — shipping. Every action builds **Release**, so running
  it on a device exercises what ships: no provider picker, no Mock, no
  `OPENAI_API_KEY` override, no DEBUG-only surfaces. Tracked in git. This is what the release builds.

Running the retail scheme on a device is the only way to see the RELEASE-only
behaviour before an archive exists.

---

## 3. Version and build number

Both live in `claudeBlast.xcodeproj/project.pbxproj`, **duplicated across the
Debug and Release configurations** of each target:

    MARKETING_VERSION = 0.9.0;          # the version testers see
    CURRENT_PROJECT_VERSION = 1;        # the build number

Rules App Store Connect enforces:

- A build number may never be reused for a given version, even for a build that
  was rejected or deleted. Always increment.
- The marketing version may repeat across builds; the pair must be unique.

Bump the **Release** pair of the app target. Missing that is the failure mode,
because a Debug-only bump looks right in Xcode and ships the old number.

---

## 4. Archive, export, upload

**Two commands, not one.** This is the recommended sequence:

    python3 tools/release.py --bump build                    # archive + export, no upload
    # read the entitlement lines it prints
    python3 tools/release.py --no-bump --upload --skip-preflight

### Why split it

An upload spends a build number **permanently** — App Store Connect will not
accept the same version+build pair twice, even for a build that was deleted. The
entitlements are only observable *after* export, and the way they fail is the
worst way this pipeline has: the build installs, launches, errors nothing, and
CloudKit simply never receives a change. So the split buys the one thing worth
buying — a look at the shipped entitlements before the number is spent.

`--no-bump` keeps the number the first command set, so one build number covers
both runs. `--skip-preflight` is safe *here specifically*, because preflight has
just passed on this exact commit and it is the expensive part (Debug build,
Release build, the full suite). Do not carry that flag anywhere else.

The honest caveat: `--no-bump` re-archives, so the ipa you inspected is not
literally the one sent. Same commit and same configuration, so it is the same
build — but if you would rather ship exactly what you looked at, run the single
combined command and accept that the entitlement lines arrive after the upload
rather than before.

Export options live in `tools/ExportOptions-appstore.plist`, checked in so two
archives a year apart export the same way. Upload is `xcrun altool --upload-app`,
confirmed present on Xcode 26.3.

### Archives land where Xcode looks

`release.py` writes to `~/Library/Developer/Xcode/Archives/<date>/`, so a
scripted build appears in **Xcode → Window → Organizer** like any other. It used
to archive into `build/`, where the Organizer never saw it and — the part that
actually cost something — each run overwrote the last.

**The dSYMs live in the archive.** A crash report from a TestFlight build whose
archive had been clobbered can never be symbolicated, which is precisely when
you need it: a tester reports something odd and the report is addresses.

What the Organizer will *not* show is that the build was uploaded. That badge
comes from Xcode writing its own record during its own distribution flow;
`altool` from outside leaves no trace there. The archive is listed and
distributable, it just does not know it has already been sent.

### What must exist outside this repo, first

The archive needs nothing special — a machine that has run on a device can make
one. **Export is where the console work first bites**, and its failure is
opaque unless you know what it means:

    error: exportArchive No profiles for 'app.blasterai.ios' were found

Two things, both in Apple's consoles:

1. **An Apple _Distribution_ certificate.** `security find-identity -v -p
   codesigning` on a machine that has only ever built to a device shows an
   Apple *Development* certificate and nothing else. Xcode mints the
   distribution one on a first Organizer distribution, or create it in the
   portal.
2. **The App Store Connect app record.** Xcode will not create an App Store
   provisioning profile for an app App Store Connect has never heard of.

`release.py` names both when export fails this way, and keeps the archive, so
`--no-bump` re-exports once they exist rather than rebuilding.

### Never choose "TestFlight Internal Only"

Xcode's Distribute dialog offers it and it looks like the modest choice for a
first build. **It is a dead end.** A build uploaded that way reaches internal
testers and can never be given to external ones or submitted — there is no
promote path, and the only fix is to upload again as **App Store Connect**.

Found on 2026-09-18: build 2 went up internal-only, and re-uploading the same
archive as App Store Connect produced **0.9.0 (3)**, because App Store Connect
had already spent build number 2. The project file had to be hand-corrected to 3
so the next `--bump build` lands on 4.

`tools/ExportOptions-appstore.plist` specifies `app-store-connect`, so
`release.py` cannot make this mistake. Only the manual bootstrap below offers the
choice, and the answer is always **App Store Connect** — it covers internal
testing too.

**If App Store Connect and the project file ever disagree about the build
number**, App Store Connect wins: it will not accept a number it has already
seen, whatever the reason. Edit `CURRENT_PROJECT_VERSION` on the app target's two
configurations to match, and commit it.

### The first distribution must be manual, once per machine

This is a genuine bootstrap, not a gap in the script. `xcodebuild -exportArchive`
*uses* a distribution certificate; it cannot create one, because issuing a
certificate requires generating a private key and an interactive identity. Only
Xcode's Organizer flow can do that on your behalf — or you generate a CSR in
Keychain Access and request the certificate in the portal by hand, which is the
same clicking with less discoverability.

So, once per machine:

    Xcode → Product → Archive
    Organizer → select the archive → Distribute App → App Store Connect

That mints the Apple Distribution certificate and the App Store provisioning
profile. Both persist in the keychain afterwards, and every later build goes
through `release.py` without touching Xcode.

Done on Mark's machine 2026-09-18, producing 0.9.0 (2) — the first TestFlight
build. A second machine, or a rotated certificate, needs this again.

### Creating the app record

App Store Connect → Apps → **+** → New App:

| Field | Value |
|---|---|
| Platform | iOS |
| Name | **BlasterAI** — must be unique across the store; you find out here |
| Bundle ID | `app.blasterai.ios` |
| Primary category | **Education** — decided 2026-08-09, never Kids |
| SKU | anything stable, e.g. `blasterai-ios` |

The Kids Category is deliberately not used: its parental-gate rule forbids
leaving the app without a gate, which would break the in-flow "Get a key" link
that BYOK onboarding depends on.

### Check the exported entitlements, once

`claudeBlast.entitlements` declares `aps-environment` as **development**. CloudKit drives
sync with silent pushes, and a TestFlight build runs against the *production* APS
environment — so if that value survives into the exported build rather than being replaced
by the distribution profile, sync would be quiet in exactly the way that is hardest to
diagnose: everything installs, nothing errors, changes simply do not arrive.

Xcode normally substitutes it during an App Store export. `release.py` prints both
entitlements after exporting, so this is read rather than assumed on every build — it
cannot go in `preflight_release.py`, because it is only observable after export.

To check by hand:

    unzip -q build/export/claudeBlast.ipa -d /tmp/ipa
    codesign -d --entitlements :- /tmp/ipa/Payload/claudeBlast.app

**Not `codesign … claudeBlast.ipa`.** An ipa is a zip archive and `codesign`
cannot read one, so that command finds nothing and says so — which is
indistinguishable from the entitlement genuinely being absent. This runbook
carried that command, `release.py` copied it, and on build 4 the script duly
reported `aps-environment: NOT FOUND — check by hand` on an archive whose
entitlements were perfectly correct. A check that cries wolf is worse than no
check: the next person to see it assumes the checker is wrong again.

Two values matter, and both fail the same silent way:

| entitlement | must be |
|---|---|
| `aps-environment` | `production` |
| `com.apple.developer.icloud-container-environment` | `Production` |

The first is the silent push CloudKit syncs over. The second is the container it
talks to — a development container against a promoted schema is simply empty,
which looks exactly like sync being broken.

**The App Store Connect API key is a secret.** The `.p8` goes in
`~/.appstoreconnect/private_keys/`, never in the repo — same discipline as the
OpenAI keys, and for the same reason: a key in git history is a key you cannot
take back.

---

## 5. What no script can do

These are in App Store Connect, in a browser, and they are part of the loop:

- **What to Test** — the tester-facing notes for this build. Tell people what
  changed and what to look at, not what was refactored.
- **Tester group** — internal testers need App Store Connect accounts, which is
  why round 1 is Mark and Kurt and needs no Beta App Review. External testers
  do need review; see the external-invite prerequisites in
  `docs/final-countdown-plan.md`.
- **Export compliance** — answered from `ITSAppUsesNonExemptEncryption` in
  `Info.plist`, which is `false` and stays true: the gifted-key format uses a
  SHA-256 keystream, and a hash is not encryption.
- **Gifted evaluator keys** — before the first external invite, not before
  round 1. See `docs/gifted-keys.md`.

---

## 6. After the build is up

- Install from TestFlight on iPad, iPhone and Mac.
- Confirm **three-way Production CloudKit sync** between them. This is the thing
  build 1 exists to prove; everything else has already been proven in the
  simulator.
- Check the Activity tab reports usage and cost as expected on a real device.

---

## What is proven, and what is not

Written and exercised on 2026-09-18, the session that produces build 1 — the
point being that every line runs the day it is written rather than sitting
unverified.

- **Version bump** — verified against the real project file, including that it
  touches only the app target's two configurations and leaves the test target's
  own `MARKETING_VERSION` alone. That is the failure mode of doing it by hand:
  four edits, one of which is the one that ships.
- **Archive** — run for real. Succeeds.
- **Export** — reached and failed on signing, which is the expected state before
  the console work. Its error message was rewritten to say so.
- **Upload** — not yet run. It is five lines and cannot be tested without
  spending a build number against a real app record.
