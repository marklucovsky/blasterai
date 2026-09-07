#!/usr/bin/env python3
"""Build deliberately-damaged .blasterscene files to exercise SceneActivation.

Hand-editing the SwiftData store is not a practical way to test §9: the store is
in a UUID-named container, it is open under WAL, and on a Designed-for-iPad Mac
it is awkward to reach at all. A scene *file* reaches the same code by the route
a caregiver actually uses — AirDrop or Messages, import, activate — and it works
on every device.

Not every fault can travel this way. `SceneImporter` refuses `pages: []` before
activation ever sees it (SceneImporter.swift, `SceneImportError.noPages`), which
is correct defence-in-depth and is why there is no fixture for the refusal path:
a page-less scene is only reachable by deleting the last page of a scene that is
already installed.

Usage:  python3 tools/make_damaged_scenes.py [outdir]
"""
import json
import sys
import uuid
from pathlib import Path

MEDIA_TYPE = "application/vnd.claudeblast.scene+json"


def tile(key, *, link="", audible=True, concealed=None):
    entry = {"key": key, "isAudible": audible, "link": link}
    if concealed is not None:
        entry["isConcealed"] = concealed
    return entry


def scene(name, description, home, pages):
    return {
        "@type": MEDIA_TYPE,
        "_comment": "Deliberately damaged fixture — see tools/make_damaged_scenes.py",
        "version": "1.0.0",
        "name": name,
        "description": description,
        "homePageKey": home,
        "id": str(uuid.uuid4()),
        "pages": pages,
    }


FIXTURES = {
    # Repair. homePageKey names a page that is not in the file, which is exactly
    # what an importer assigning fields in field order produces. Activation
    # should adopt "kitchen" and SAY so — the silent version of this repair is
    # the whole reason §9 exists.
    "damaged-dangling-home": scene(
        "Damaged — Dangling Home",
        "homePageKey names no page. Expect: activates, notice names the adopted page.",
        "no_such_page",
        [{"key": "kitchen", "tiles": [tile("eat"), tile("drink"), tile("more")]}],
    ),

    # Warning. Two words this device does not have and the file does not carry.
    # Populated in the editor, missing on the board — the second live lockout.
    "damaged-missing-words": scene(
        "Damaged — Missing Words",
        "References words not in the vocabulary. Expect: activates, notice names them.",
        "home",
        [{"key": "home", "tiles": [
            tile("eat"),
            tile("zzz_not_a_word"),
            tile("zzz_also_missing"),
        ]}],
    ),

    # Warning. Every tile concealed: the board draws empty for the child. May
    # well be deliberate under the reveal approach, so it warns, never refuses.
    "damaged-all-concealed": scene(
        "Damaged — All Concealed",
        "Every tile concealed. Expect: activates, notice says nothing is pressable.",
        "home",
        [{"key": "home", "tiles": [
            tile("eat", concealed=True),
            tile("drink", concealed=True),
            tile("more", concealed=True),
        ]}],
    ),

    # Warning. A page of nothing but gaps names no words at all, so it must warn
    # that nothing is reachable WITHOUT also reporting the spacers as missing.
    "damaged-only-spacers": scene(
        "Damaged — Only Spacers",
        "A page of gaps. Expect: nothing-pressable warning, and NO missing-word list.",
        "home",
        [{"key": "home", "tiles": [
            tile("<spacer>#aaaaaaaa", audible=False),
            tile("<spacer>#bbbbbbbb", audible=False),
        ]}],
    ),
}


def main():
    outdir = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    outdir.mkdir(parents=True, exist_ok=True)
    for stem, body in FIXTURES.items():
        path = outdir / f"{stem}.blasterscene"
        path.write_text(json.dumps(body, indent=2) + "\n")
        print(f"{path}  —  {body['description']}")


if __name__ == "__main__":
    main()
