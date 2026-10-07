#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Bump, archive, export and upload a TestFlight build.

    Usage, and the recommended sequence is two commands rather than one:

        python3 tools/release.py --bump build      # archive + export, no upload
        # read the entitlement lines it prints, then:
        python3 tools/release.py --no-bump --upload --skip-preflight

        python3 tools/release.py --bump build --upload   # both at once
        python3 tools/release.py --version 1.0.0 --bump build

    Splitting buys a look at the shipped entitlements before a build number is
    spent, and a number is spent permanently — App Store Connect will not accept
    the same version+build pair twice, even for a build that was deleted.
    `--no-bump` keeps the number the first command set. See
    docs/release-runbook.md §4.

The difference between "we shipped build 1" and "we can ship build 7". Every
step is a command rather than a sequence of Xcode clicks, so the next one is a
repeat and not a recollection.

WHAT IT REFUSES TO DO
---------------------
Runs `preflight_release.py` first and stops if anything fails — clean tree on
main, Debug **and Release** both building, the full suite, gates 8 and 9, the
shared scheme, the retail icon. An archive from a dirty tree cannot be traced to
a commit, and every one of those checks is cheaper than an App Store round trip.

Upload is opt-in. Archive and export are repeatable; an upload spends a build
number permanently, and App Store Connect will not accept the same
version+build pair twice even for a build that was deleted.

BEFORE THE FIRST RUN
--------------------
1. **CloudKit must be promoted.** A TestFlight build always runs against the
   Production environment. Against an unpromoted schema it installs, launches,
   and syncs nothing. See `docs/cloudkit-promotion-runbook.md`.
2. **The App Store Connect app record must exist**, or the upload has nowhere to
   land. See `docs/release-runbook.md`.
3. **An App Store Connect API key**, for `--upload`:

       export ASC_KEY_ID=...        # the 10-char key id
       export ASC_ISSUER_ID=...     # the issuer UUID

   with the `.p8` in `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8`.
   Never in this repo: a key in git history is a key you cannot take back.

EVERY UPLOAD IS TAGGED
----------------------
A bug report names a build — "0.9.0 (5)" — and the question is what source
that was. Until build 6 the only answer was the bump commit's message, which is
a convention rather than a record: build 3's bump was a hand-written commit the
convention misses, and nothing proved the archived tree *was* that commit.

So an upload is refused unless the archive is exactly one commit: on main, and
differing from HEAD by nothing but the version bump. Once the upload is
accepted, the script commits that bump (`chore(release): 0.9.0 (6)`) and puts
an annotated tag on it — `v0.9.0-6` — so `git checkout v0.9.0-6` is the source
of build 6. The tag is checked for *before* the archive, because a collision
found after the upload would leave a spent build number with no name.

It does not push. Main and the tag are published by hand, with the command it
prints, because that is the outward step.

WHAT IT PRINTS AFTER EXPORT
---------------------------
The two entitlements that decide whether CloudKit works: `aps-environment` must
be `production`, and `com.apple.developer.icloud-container-environment` must be
`Production`. Both fail the same way and it is the worst way — the build
installs, launches, errors nothing, and never receives a change.

They are read off the signed app *inside* the ipa. Handing `codesign` the ipa
itself finds nothing, because an ipa is a zip archive — which this script did
until build 4, where it reported "NOT FOUND — check by hand" on an archive
whose entitlements were perfectly correct.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path

SCHEME = "claudeBlastRetail"
PROJECT = "claudeBlast.xcodeproj"
PBXPROJ = Path(PROJECT) / "project.pbxproj"
EXPORT_OPTIONS = Path("tools/ExportOptions-appstore.plist")
BUILD = Path("build")
EXPORT_DIR = BUILD / "export"

# Where Xcode's Organizer looks: it has no database, it scans this tree.
#
# Archiving into `build/` meant the Organizer never saw a scripted build, and —
# the part that actually costs something — each run overwrote the last. **The
# dSYMs live in the archive**, so a crash report from a TestFlight build whose
# archive had been clobbered could never be symbolicated. One archive per build,
# kept where Xcode already knows to look.
#
# What this does NOT do is mark the build as uploaded in the Organizer. That
# badge comes from Xcode writing its own record during its own distribution
# flow; `altool` from outside leaves no trace there. The archive is listed and
# distributable; it just does not know it has already been sent.
ARCHIVES_ROOT = Path.home() / "Library/Developer/Xcode/Archives"


def archive_path(marketing: str, build: int) -> Path:
    """A dated, named archive, the way Xcode names its own."""
    now = datetime.now()
    folder = ARCHIVES_ROOT / now.strftime("%Y-%m-%d")
    folder.mkdir(parents=True, exist_ok=True)
    stamp = now.strftime("%d-%m-%Y, %H.%M")
    return folder / f"claudeBlast {marketing} ({build}) {stamp}.xcarchive"

# The app target's two configurations, by identifier. The test target carries
# its own MARKETING_VERSION and CURRENT_PROJECT_VERSION, and bumping those would
# be meaningless noise — worse, a regex over the whole file would hit them.
APP_CONFIGS = ["56B216612F357AED00A89419 /* Debug */",
               "56B216622F357AED00A89419 /* Release */"]


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def git(*args: str) -> str:
    result = run(["git", *args])
    if result.returncode != 0:
        sys.exit(f"git {' '.join(args)} failed\n{result.stderr.strip()}")
    return result.stdout.strip()


def release_tag(marketing: str, build: int) -> str:
    """`v0.9.0-6`. One per uploaded build — never per archive."""
    return f"v{marketing}-{build}"


def dirty_paths() -> list[str]:
    """Every path `git status` reports: staged, unstaged or untracked."""
    out = run(["git", "status", "--porcelain"]).stdout
    return [line[3:].strip() for line in out.splitlines() if line.strip()]


def check_traceable(tag: str) -> None:
    """Refuse an upload that no commit could name afterwards.

    Runs before the archive, for the same reason preflight does: an upload
    spends a build number, so whatever would leave it untraceable has to stop
    the run while stopping is still free. The second command of the split runs
    with `--skip-preflight`, which skips preflight's clean-tree check — so this
    repeats the part of it the tag depends on.
    """
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    if branch != "main":
        sys.exit(f"on branch '{branch}', not main — uploads are tagged on main")
    stray = [p for p in dirty_paths() if p != str(PBXPROJ)]
    if stray:
        sys.exit("refusing to upload: the archive would include uncommitted changes,\n"
                 "so no commit could name it afterwards. Only the version bump may be\n"
                 "uncommitted:\n    " + "\n    ".join(stray[:10]))
    if run(["git", "rev-parse", "-q", "--verify", f"refs/tags/{tag}"]).returncode == 0:
        sys.exit(f"tag {tag} already exists — that build was already uploaded.\n"
                 "Bump instead; App Store Connect will not take the number twice.")


def record_release(marketing: str, build: int, tag: str) -> None:
    """Commit the bump if it is not committed yet, then tag the commit.

    The archive was HEAD plus the bump (`check_traceable` saw to that), so
    committing the bump produces exactly the tree that shipped. If the bump was
    already committed, the tree was clean and HEAD is the tree that shipped.
    """
    print("▸ tag")
    if str(PBXPROJ) in dirty_paths():
        git("add", str(PBXPROJ))
        git("commit", "-q", "-m", f"chore(release): {marketing} ({build})")
    if read_versions() != (marketing, build):
        sys.exit(f"HEAD carries {read_versions()}, not {marketing} ({build}). Tag the\n"
                 f"right commit by hand:  git tag -a {tag} -m 'BlasterAI {marketing} ({build})' <sha>")
    stamp = datetime.now().strftime("%Y-%m-%d")
    git("tag", "-a", tag, "-m",
        f"BlasterAI {marketing} ({build}), uploaded to App Store Connect {stamp}")
    print(f"    {tag} → {git('rev-parse', '--short', 'HEAD')}")
    print(f"\nPublish both:  git push origin main {tag}")


def config_span(lines: list[str], marker: str) -> tuple[int, int]:
    """The line range of one build configuration block."""
    start = next(n for n, l in enumerate(lines) if marker in l)
    for n in range(start, len(lines)):
        if lines[n].strip() == "};":
            return start, n
    raise SystemExit(f"could not find the end of {marker}")


def read_versions() -> tuple[str, int]:
    lines = PBXPROJ.read_text().splitlines()
    s, e = config_span(lines, APP_CONFIGS[1])           # Release is the one that ships
    body = "\n".join(lines[s:e])
    marketing = re.search(r"MARKETING_VERSION = ([^;]+);", body)
    build = re.search(r"CURRENT_PROJECT_VERSION = ([^;]+);", body)
    if not marketing or not build:
        sys.exit("could not read the app target's version settings")
    return marketing.group(1).strip(), int(build.group(1).strip())


def write_versions(marketing: str, build: int) -> None:
    """Write both app configurations, and only those.

    Debug and Release each carry their own copy, which is exactly why doing this
    by hand goes wrong: it is four edits and only one of them is the one that
    ships, so a Debug-only bump looks right in Xcode and uploads the old number.
    """
    lines = PBXPROJ.read_text().splitlines(keepends=True)
    for marker in APP_CONFIGS:
        s, e = config_span(lines, marker)
        for n in range(s, e):
            lines[n] = re.sub(r"(MARKETING_VERSION = )[^;]+;", rf"\g<1>{marketing};", lines[n])
            lines[n] = re.sub(r"(CURRENT_PROJECT_VERSION = )[^;]+;", rf"\g<1>{build};", lines[n])
    PBXPROJ.write_text("".join(lines))


def bumped(marketing: str, build: int, how: str, override: str | None) -> tuple[str, int]:
    if override:
        marketing = override
    major, minor, patch = (list(map(int, marketing.split("."))) + [0, 0])[:3]
    if how == "build":
        build += 1
    elif how == "patch":
        patch += 1
        build += 1
    elif how == "minor":
        minor, patch = minor + 1, 0
        build += 1
    return f"{major}.{minor}.{patch}", build


# --- steps ------------------------------------------------------------------


def preflight() -> None:
    print("▸ preflight")
    result = subprocess.run([sys.executable, "tools/preflight_release.py"])
    if result.returncode != 0:
        sys.exit("\npreflight failed — nothing was archived.")


def archive(marketing: str, build: int) -> Path:
    print("▸ archive")
    BUILD.mkdir(exist_ok=True)
    path = archive_path(marketing, build)
    result = run(["xcodebuild", "-scheme", SCHEME, "-configuration", "Release",
                  "-destination", "generic/platform=iOS",
                  "-archivePath", str(path), "archive"])
    if "** ARCHIVE SUCCEEDED **" not in result.stdout:
        errors = [l for l in result.stdout.splitlines() if "error:" in l][:8]
        sys.exit("archive failed\n" + "\n".join(errors) or result.stderr[-2000:])
    print(f"    {path}")
    print("    (visible in Xcode → Window → Organizer)")
    return path


def export(archive: Path) -> Path:
    print("▸ export")
    if EXPORT_DIR.exists():
        shutil.rmtree(EXPORT_DIR)
    result = run(["xcodebuild", "-exportArchive", "-archivePath", str(archive),
                  "-exportOptionsPlist", str(EXPORT_OPTIONS),
                  "-exportPath", str(EXPORT_DIR)])
    if "** EXPORT SUCCEEDED **" not in result.stdout:
        blob = result.stdout + result.stderr
        # The first-run failure, named rather than left as raw xcodebuild text.
        # Archiving needs only a development certificate, which any machine that
        # has run on a device already has; exporting for the App Store needs a
        # *distribution* certificate and an App Store provisioning profile, and
        # Xcode will not mint a profile for an app that does not exist in App
        # Store Connect. So this is the step that first requires the console
        # work, and the message should say so.
        if "No profiles for" in blob or "no valid" in blob.lower():
            sys.exit(
                "export failed: no App Store provisioning profile.\n\n"
                "  The archive is fine — this is signing. Two things must exist,\n"
                "  both outside this repo:\n\n"
                "    1. An Apple *Distribution* certificate. Check with:\n"
                "         security find-identity -v -p codesigning\n"
                "       A machine that has only ever run on a device has an Apple\n"
                "       Development certificate and no distribution one.\n\n"
                "    2. The App Store Connect app record for app.blasterai.ios.\n"
                "       Xcode will not create an App Store profile for an app that\n"
                "       App Store Connect has never heard of.\n\n"
                "  Both are console work — see docs/release-runbook.md. The archive\n"
                f"  is kept at {archive}; re-run with --no-bump once they exist.")
        sys.exit("export failed\n" + blob[-2000:])
    ipas = list(EXPORT_DIR.glob("*.ipa"))
    if not ipas:
        sys.exit(f"export produced no .ipa in {EXPORT_DIR}")
    return ipas[0]


# Entitlements that decide whether CloudKit works, and the value each must have.
#
# Both fail the same way and it is the worst way: the build installs, launches,
# errors nothing, and simply never receives a change. Neither is visible from
# the outside, so they are read off the signed binary rather than assumed.
REQUIRED_ENTITLEMENTS = {
    # CloudKit syncs over silent push, and a TestFlight build runs against
    # production APS.
    "aps-environment": "production",
    # The container the build talks to. A development container against a
    # promoted schema is empty, which looks exactly like sync being broken.
    "com.apple.developer.icloud-container-environment": "Production",
}


def show_entitlements(ipa: Path) -> None:
    """Read the shipped entitlements off the signed app inside the ipa.

    **It used to hand `codesign` the ipa itself**, which is a zip archive — so
    it found nothing and printed "NOT FOUND — check by hand" on a build whose
    entitlements were perfectly correct. That is worse than no check at all: it
    cried wolf on the one build it was asked about, and the next person to see
    it would reasonably assume the checker was wrong again.

    The app has to come out of the archive first. It is the *exported* ipa
    rather than the one in the .xcarchive because export re-signs for
    distribution, and re-signing is exactly when these can change.
    """
    print("▸ entitlements")
    with tempfile.TemporaryDirectory() as tmp:
        try:
            with zipfile.ZipFile(ipa) as z:
                z.extractall(tmp)
        except (zipfile.BadZipFile, OSError) as err:
            print(f"    could not open {ipa.name}: {err}")
            return
        apps = list(Path(tmp).glob("Payload/*.app"))
        if not apps:
            print(f"    no Payload/*.app inside {ipa.name}")
            return

        result = run(["codesign", "-d", "--entitlements", ":-", str(apps[0])])
        blob = result.stdout or result.stderr

    ok = True
    for key, want in REQUIRED_ENTITLEMENTS.items():
        m = re.search(rf"<key>{re.escape(key)}</key>\s*<string>([^<]+)</string>", blob)
        got = m.group(1) if m else None
        if got == want:
            print(f"    {key}: {got} ✓")
            continue
        ok = False
        found = got or "not present"
        print(f"    {key}: {found}  ⚠️  needs {want}")
    if not ok:
        print("    CloudKit syncs over silent push against the production")
        print("    container; a build with these wrong installs, errors")
        print("    nothing, and never receives a change.")


def upload(ipa: Path, key_id: str, issuer: str) -> None:
    print("▸ upload")
    result = run(["xcrun", "altool", "--upload-app", "-f", str(ipa), "-t", "ios",
                  "--apiKey", key_id, "--apiIssuer", issuer])
    out = result.stdout + result.stderr
    if result.returncode != 0:
        sys.exit(f"upload failed\n{out[-2000:]}")
    print("    accepted. Processing in App Store Connect takes a few minutes.")


def main() -> int:
    ap = argparse.ArgumentParser(description="Produce a TestFlight build.")
    ap.add_argument("--bump", choices=["build", "patch", "minor"], default="build",
                    help="what to increment (default: %(default)s)")
    ap.add_argument("--no-bump", action="store_true",
                    help="re-archive the current version, e.g. after a failed export")
    ap.add_argument("--version", help="set the marketing version explicitly")
    ap.add_argument("--upload", action="store_true",
                    help="send it. Opt-in: a build number is spent permanently")
    ap.add_argument("--skip-preflight", action="store_true",
                    help="for iterating on this script only, never for a real build")
    args = ap.parse_args()

    if not args.skip_preflight:
        preflight()

    marketing, build = read_versions()
    if args.no_bump:
        print(f"▸ version   {marketing} ({build}), unchanged")
    else:
        marketing, build = bumped(marketing, build, args.bump, args.version)
        write_versions(marketing, build)
        print(f"▸ version   {marketing} ({build})")

    tag = release_tag(marketing, build)
    if args.upload:
        # Before the archive rather than after the upload: both can only be
        # answered cheaply while no build number has been spent.
        key_id = os.environ.get("ASC_KEY_ID", "").strip()
        issuer = os.environ.get("ASC_ISSUER_ID", "").strip()
        if not key_id or not issuer:
            sys.exit("--upload needs ASC_KEY_ID and ASC_ISSUER_ID set, with the "
                     ".p8 in ~/.appstoreconnect/private_keys/")
        check_traceable(tag)

    xcarchive = archive(marketing, build)
    ipa = export(xcarchive)
    show_entitlements(ipa)
    print(f"    {ipa}")

    if args.upload:
        upload(ipa, key_id, issuer)
        record_release(marketing, build, tag)
    else:
        print("\nNot uploaded. When the build looks right:")
        print("    python3 tools/release.py --no-bump --upload --skip-preflight")
        print(f"That run commits the bump and tags it {tag}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
