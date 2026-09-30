#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Everything that must be true before an archive is worth making.

    Usage:
        python3 tools/preflight_release.py           # all checks
        python3 tools/preflight_release.py --fast    # skip the test suite
        python3 tools/preflight_release.py --quiet   # exit code only

Exits non-zero on the first failing check, and says what to do about it.

WHY THIS EXISTS
---------------
On 2026-09-17 the app did not compile in Release and nobody knew. Three
`@State` members were declared inside `#if DEBUG` while two tabs used them
unguarded, and it had presumably been that way for some time. Nothing in the
normal loop touches that configuration — `xcodebuild build` and `test` both
default to Debug — so the first thing that would have failed was the archive
for build 1, at the least convenient moment.

That is the shape of every check below: something true of a *shipping* build
that a development loop never looks at. Checks are cheap, an archive is slow,
and a TestFlight build with the wrong thing baked in costs a round trip through
Apple.

The gate assertions are the other half. `docs/final-countdown-plan.md` says to
re-confirm gates 8 and 9 "on the day, by looking at the schema" — because a
CloudKit Production schema is additive-only forever, so a field that should
exist must exist before promotion and a field that should not must be gone.
Looking is a thing a person forgets at 11pm. A grep is not.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

SCHEME = "claudeBlastRetail"
PROJECT = "claudeBlast.xcodeproj"
PBXPROJ = Path(PROJECT) / "project.pbxproj"
DESTINATION = "platform=iOS Simulator,name=iPad Pro 11-inch (M5),OS=26.2"

# Fields the synced schema must carry into CloudKit Production, and the one it
# must not. See `project_no_child_dob` and the gate table.
REQUIRED_PROFILE_FIELDS = ["languageRaw", "brownsStageRaw"]
FORBIDDEN_PROFILE_FIELDS = ["birthday", "ageGrade", "interactionModeRaw"]
CHILD_PROFILE = Path("claudeBlast/Models/ChildProfile.swift")


class Failure(Exception):
    """A check that failed, carrying what to do about it."""


def run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


# --- checks -----------------------------------------------------------------


def check_repo_state() -> str:
    """A build you cannot identify later is not a release."""
    dirty = run(["git", "status", "--porcelain"]).stdout.strip()
    if dirty:
        raise Failure("the working tree has uncommitted changes — an archive "
                      "from it cannot be traced back to a commit\n"
                      f"       {len(dirty.splitlines())} file(s) changed")
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"]).stdout.strip()
    sha = run(["git", "rev-parse", "--short", "HEAD"]).stdout.strip()
    if branch != "main":
        raise Failure(f"on branch '{branch}', not main — release from main")
    return f"main @ {sha}, clean"


def check_versions() -> str:
    """Marketing version and build number, read from where they actually live.

    Both are duplicated across the Debug and Release configurations in
    `project.pbxproj`, which is exactly why bumping them by hand goes wrong: it
    is four edits, and the one that matters is the Release pair.
    """
    body = PBXPROJ.read_text()
    marketing = set(re.findall(r"MARKETING_VERSION = ([^;]+);", body))
    build = set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", body))
    if not marketing or not build:
        raise Failure("could not read MARKETING_VERSION / CURRENT_PROJECT_VERSION "
                      f"from {PBXPROJ}")
    # The test target carries its own, so more than one value is normal; the
    # check is that each setting is internally consistent per target, which we
    # approximate by reporting them all rather than asserting one.
    return f"version {'/'.join(sorted(marketing))}, build {'/'.join(sorted(build))}"


def check_shared_scheme() -> str:
    """A release nobody else can reproduce is not automated, it is a habit."""
    path = Path(PROJECT) / "xcshareddata/xcschemes" / f"{SCHEME}.xcscheme"
    if not path.exists():
        raise Failure(f"{SCHEME} is not a shared scheme — Xcode → Product → "
                      "Scheme → Manage Schemes → tick Shared")
    tracked = run(["git", "ls-files", "--error-unmatch", str(path)])
    if tracked.returncode != 0:
        raise Failure(f"{path} exists but is not tracked in git — a scheme only "
                      "Xcode knows about cannot be built by anyone else")

    scheme = path.read_text()
    if "OPENAI" in scheme or "EnvironmentVariables" in scheme:
        raise Failure(f"{SCHEME} carries environment variables — the release "
                      "scheme must not, and a real key in a tracked scheme is a "
                      "leaked key")
    archive = re.search(r"<ArchiveAction\s+buildConfiguration = \"(\w+)\"", scheme)
    if not archive or archive.group(1) != "Release":
        raise Failure(f"{SCHEME} archives with "
                      f"{archive.group(1) if archive else 'no'} configuration, not Release")
    return f"{SCHEME} shared, tracked, archives Release"


def check_builds(config: str) -> str:
    """The check that exists because Release silently stopped compiling."""
    result = run(["xcodebuild", "-scheme", SCHEME, "-configuration", config,
                  "-destination", DESTINATION, "build"])
    if "** BUILD SUCCEEDED **" not in result.stdout:
        errors = [ln for ln in result.stdout.splitlines() if "error:" in ln][:5]
        raise Failure(f"{config} does not build\n" +
                      "\n".join(f"       {e.strip()}" for e in errors))
    return f"{config} builds"


def check_tests() -> str:
    result = run(["xcodebuild", "-project", PROJECT, "-scheme", SCHEME,
                  "-destination", DESTINATION, "test"])
    if "** TEST SUCCEEDED **" not in result.stdout:
        failed = [ln for ln in result.stdout.splitlines() if "failed" in ln][:5]
        raise Failure("the test suite does not pass\n" +
                      "\n".join(f"       {f.strip()}" for f in failed))
    # Count, not just the exit status: CLAUDE.md records that a filter matching
    # nothing still prints TEST SUCCEEDED.
    cases = len(re.findall(r"Test case .* passed", result.stdout))
    if cases < 100:
        raise Failure(f"only {cases} tests ran — that is not the whole suite")
    return f"{cases} test cases passed"


def check_gates() -> str:
    """Gates 8 and 9, as assertions rather than as a reminder to look.

    A CloudKit Production schema is additive-only forever: after promotion you
    can add a field but never remove one. So everything that should exist must
    exist by then, and everything that should not must already be gone. Both
    become impossible the moment S6 promotes.
    """
    body = CHILD_PROFILE.read_text()
    missing = [f for f in REQUIRED_PROFILE_FIELDS
               if not re.search(rf"\bvar {f}\b", body)]
    if missing:
        raise Failure(f"gate 8: ChildProfile is missing {', '.join(missing)} — "
                      "these must exist BEFORE promotion, and can never be added "
                      "to a promoted schema as anything but new fields")
    present = [f for f in FORBIDDEN_PROFILE_FIELDS
               if re.search(rf"\bvar {f}\b", body)]
    if present:
        raise Failure(f"gate 9: ChildProfile still declares {', '.join(present)} "
                      "— a promoted schema can never drop a field, so a child's "
                      "date of birth would be in it permanently")
    return "gates 8 and 9: schema fields correct"


def check_private_cloudkit_only() -> str:
    """No public CloudKit database anywhere.

    CloudKit security roles govern the PUBLIC database. The defaults grant
    `_world` read on every record type, which is harmless here only because this
    app uses `.private(...)` exclusively — records in a user's private database
    belong to that user and no role gives anyone else access.

    That makes "private only" load-bearing and invisible. A future public-database
    feature would make `_world` read on `CD_LoggedUtterance` an instant leak of a
    child's speech, with nothing to warn anyone. This turns the assumption into a
    check.
    """
    hits = []
    for path in Path("claudeBlast").rglob("*.swift"):
        for n, line in enumerate(path.read_text().splitlines(), 1):
            if "cloudKitDatabase" in line and ".public" in line:
                hits.append(f"{path}:{n}")
    if hits:
        raise Failure("a PUBLIC CloudKit database appears in the sources — the "
                      "default `_world` read role would expose those records:\n" +
                      "\n".join(f"       {h}" for h in hits))
    return "CloudKit is private-database only"


def check_release_icon() -> str:
    """The shipping build must not wear the development icon.

    Debug and Release point at different icon sets so a home screen with both
    installed says which is which — hot pink and a DEV badge versus the
    Fitzgerald green card. The check exists because that is a build setting, and
    a build setting that silently reverts costs an App Store round trip to
    notice.
    """
    body = PBXPROJ.read_text()
    names = re.findall(r"ASSETCATALOG_COMPILER_APPICON_NAME = (\w+);", body)
    if "AppIconRetail" not in names:
        raise Failure("no configuration uses AppIconRetail — the Release build "
                      "would ship the development icon")
    iconset = Path("claudeBlast/Assets.xcassets/AppIconRetail.appiconset/AppIcon.png")
    if not iconset.exists():
        raise Failure(f"{iconset} is missing — regenerate with "
                      "`python3 tools/make_app_icon.py --word speak --install`")
    return "Release uses AppIconRetail"


def check_privacy() -> str:
    manifest = list(Path(".").rglob("PrivacyInfo.xcprivacy"))
    if not manifest:
        raise Failure("no PrivacyInfo.xcprivacy — App Store submission requires one")
    plist = Path("Info.plist").read_text()
    if "ITSAppUsesNonExemptEncryption" not in plist:
        raise Failure("Info.plist does not declare ITSAppUsesNonExemptEncryption — "
                      "without it every upload asks, and the answer has to be "
                      "given by hand every time")
    return "privacy manifest present, export compliance declared"


def check_sibling_audits() -> str:
    """The audits that already exist, so preflight is one command and not four."""
    for script, what in [("tools/check_tileset_drift.py", "tile-set drift"),
                         ("tools/audit_openai_models.py", "OpenAI model list")]:
        result = run([sys.executable, script, "--quiet"])
        if result.returncode != 0:
            raise Failure(f"{what} check failed — run `python3 {script}` to see why")
    return "tile-set drift and model list clean"


ENV_KEY_ACCESSOR = Path("claudeBlast/Services/OpenAIKeyVault.swift")
# Copy that exists only to describe the override. Each is longer than 15 bytes
# on purpose — see `check_no_env_key_in_release` for why the name itself is not
# on this list.
ENV_KEY_COPY = [b"OpenAI (env override)", b"Set via environment",
                b"`OPENAI_API_KEY` environment "]


def built_app(config: str) -> Path:
    """The .app bundle the last build of `config` produced, from its own settings."""
    result = run(["xcodebuild", "-scheme", SCHEME, "-configuration", config,
                  "-destination", DESTINATION, "-showBuildSettings"])
    settings = dict(re.findall(r"^\s*(TARGET_BUILD_DIR|WRAPPER_NAME) = (.+)$",
                               result.stdout, re.MULTILINE))
    if "TARGET_BUILD_DIR" not in settings or "WRAPPER_NAME" not in settings:
        raise Failure(f"could not read the {config} build location from "
                      "xcodebuild -showBuildSettings — the bundle was not examined")
    return Path(settings["TARGET_BUILD_DIR"]) / settings["WRAPPER_NAME"]


def bundle_mentions(app: Path, needle: bytes) -> list[str]:
    """Every file in the bundle containing `needle`. Fails if there is no bundle."""
    if not app.is_dir():
        raise Failure(f"{app} does not exist — the build it names has not run, "
                      "so nothing was examined")
    return [str(f.relative_to(app)) for f in app.rglob("*")
            if f.is_file() and needle in f.read_bytes()]


def debug_only_lines(path: Path) -> set[int]:
    """Line numbers inside an `#if DEBUG` branch (before its #else / #endif)."""
    inside, depth, lines = False, 0, set()
    for n, line in enumerate(path.read_text().splitlines(), 1):
        t = line.strip()
        if t.startswith("#if"):
            depth += 1
            if t == "#if DEBUG" and depth == 1:
                inside = True
            continue
        if t.startswith("#else") or t.startswith("#elseif"):
            if depth == 1:
                inside = False
            continue
        if t.startswith("#endif"):
            depth -= 1
            if depth == 0:
                inside = False
            continue
        if inside:
            lines.add(n)
    return lines


def check_no_env_key_in_release() -> str:
    """The developer key override is DEBUG only, in the source and in the binary.

    `OPENAI_API_KEY` lets a developer scheme inject a key. A family can never
    set a scheme variable, so in a shipping build the path is dead code — and
    dead code that describes a way to inject a key, with copy naming it, is not
    something to hand App Review.

    **The binary cannot be searched for the name itself.** Swift stores a string
    of 15 bytes or fewer inline, in the instructions that build it, and
    `OPENAI_API_KEY` is 14 — it never appears contiguously in any binary, Debug
    or Release. A first version of this check scanned for it, passed, and went
    on passing with the `#if DEBUG` removed. So the two halves check what each
    can actually see:

    - **Source:** the literal is read in exactly one file, and only inside an
      `#if DEBUG` branch there.
    - **Binary:** the copy that names the override is long enough to be stored
      as bytes. The Debug bundle MUST contain it — the known-good input that
      proves the scan works — and the Release bundle must not. A missing bundle
      is "could not look", never "clean".

    The source half is the load-bearing one. With the accessor guarded, Release
    sees `environmentOverride()` return a constant nil, and the optimizer drops
    every branch behind it — copy included — even if a view forgets its own
    `#if DEBUG`. The binary half catches the copy that the optimizer *cannot*
    drop: text on a path Release can actually reach. Both were confirmed by
    removing the guards and watching each half fail.
    """
    stray = [str(p) for p in Path("claudeBlast").rglob("*.swift")
             if p != ENV_KEY_ACCESSOR and b'"OPENAI_API_KEY"' in p.read_bytes()]
    if stray:
        raise Failure("the key override is read outside OpenAIKeyVault — route "
                      "it through `environmentOverride`:\n" +
                      "\n".join(f"       {s}" for s in stray))
    guarded = debug_only_lines(ENV_KEY_ACCESSOR)
    reads = [n for n, line in enumerate(ENV_KEY_ACCESSOR.read_text().splitlines(), 1)
             if '"OPENAI_API_KEY"' in line]
    if not reads:
        raise Failure(f"{ENV_KEY_ACCESSOR} no longer reads OPENAI_API_KEY — this "
                      "check is looking in the wrong place")
    unguarded = [n for n in reads if n not in guarded]
    if unguarded:
        raise Failure("OPENAI_API_KEY is read outside `#if DEBUG` at "
                      + ", ".join(f"{ENV_KEY_ACCESSOR}:{n}" for n in unguarded))

    debug_app, release_app = built_app("Debug"), built_app("Release")
    for marker in ENV_KEY_COPY:
        if not bundle_mentions(debug_app, marker):
            raise Failure(f"the Debug bundle does not contain {marker.decode()!r}, "
                          "so this scan cannot see it — the check is broken, "
                          "not passed")
        hits = bundle_mentions(release_app, marker)
        if hits:
            raise Failure(f"the Release bundle contains {marker.decode()!r} — "
                          "override copy outside `#if DEBUG`:\n" +
                          "\n".join(f"       {h}" for h in hits))
    return "override read only under #if DEBUG; its copy is absent from Release"


# --- driver -----------------------------------------------------------------


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Check everything that must be true before archiving.")
    ap.add_argument("--fast", action="store_true",
                    help="skip the test suite (minutes); everything else still runs")
    ap.add_argument("--quiet", action="store_true", help="exit code only")
    args = ap.parse_args()

    checks = [
        ("repo state", check_repo_state),
        ("versions", check_versions),
        ("shared scheme", check_shared_scheme),
        ("gates 8 & 9", check_gates),
        ("privacy & compliance", check_privacy),
        ("cloudkit scope", check_private_cloudkit_only),
        ("release icon", check_release_icon),
        ("audits", check_sibling_audits),
        ("Debug build", lambda: check_builds("Debug")),
        ("Release build", lambda: check_builds("Release")),
        # After both builds: it reads the bundles they produced.
        ("no env key in Release", check_no_env_key_in_release),
    ]
    if not args.fast:
        checks.append(("test suite", check_tests))

    failures = 0
    for name, check in checks:
        try:
            detail = check()
            if not args.quiet:
                print(f"  ✓ {name:<22} {detail}")
        except Failure as e:
            failures += 1
            if not args.quiet:
                print(f"  ✗ {name:<22} {e}")
            # Keep going. One run should name every problem, not send someone
            # round the loop once per failure — each of these takes minutes.
        except Exception as e:  # noqa: BLE001 — a broken check is a failed check
            failures += 1
            if not args.quiet:
                print(f"  ✗ {name:<22} check itself failed: {e}")

    if not args.quiet:
        print()
        if failures:
            print(f"{failures} check(s) failed — not ready to archive.")
        elif args.fast:
            print("Ready to archive, but the test suite was skipped (--fast).")
        else:
            print("Ready to archive.")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
