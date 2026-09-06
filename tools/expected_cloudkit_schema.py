#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Print the CloudKit record types and fields the app's schema should produce.

CloudKit's Development schema is built from what the app has *written*, so the
console can only ever show you what happened — never what was supposed to. This
derives the expectation from the Swift sources instead, and prints it in the
shape the console shows, so the two can be compared line by line.

    python3 tools/expected_cloudkit_schema.py            # the expected schema
    python3 tools/expected_cloudkit_schema.py --names    # record types only

**Read it as a checklist, not as truth.** It parses `@Model` classes with regex,
which is enough for this codebase's plain `var name: Type = default` style and
would not survive anything cleverer. If a model ever grows a property this
cannot see, the answer is to make the parse fail loudly rather than to trust a
short list — hence the assertion that every synced model was found.

Why the field names matter as much as the type names: `retiredReason` was absent
from the dev schema purely because nothing had been auto-hidden yet, and a field
that never appears in Development does not exist after promotion.
"""

import re
import sys
from pathlib import Path

MODELS = Path("claudeBlast/Models")
SCHEMA = MODELS / "SchemaVersions.swift"

# Properties SwiftData does not persist, so they never become fields.
SKIP_KEYWORDS = ("@Transient", "static", "computed")

# SwiftData stamps this on every record itself — it is not a Swift property, and
# leaving it out makes every count read one short of the console.
ENTITY_NAME = "entityName"

# createdTimestamp, createdUserRecordName, ___etag, modifiedTimestamp,
# modifiedUserRecordName, recordName. CloudKit's own, on every record type.
METADATA_FIELDS = 6


def synced_model_names() -> list[str]:
    """The `syncedModels` list, in declaration order."""
    text = SCHEMA.read_text()
    start = text.find("static var syncedModels")
    assert start != -1, "could not find syncedModels in SchemaVersions.swift"
    # Up to the close of the computed property. The type annotation contains a
    # `[` of its own, so bracket-matching from the declaration is not enough.
    block = text[start:text.index("\n    }", start)]
    names = re.findall(r"(\w+)\.self", block)
    assert names, "parsed syncedModels but found no models — the parse is stale"
    return names


def stored_properties(class_name: str) -> list[str]:
    """`var` declarations with a stored shape, in declaration order.

    Deliberately narrow: `var name: Type = value` or `var name: Type` with no
    following `{`. A computed property (`var x: T { … }`) is not stored and
    never becomes a CloudKit field.
    """
    for path in MODELS.glob("*.swift"):
        text = path.read_text()
        match = re.search(rf"(?:final\s+)?class\s+{class_name}\b", text)
        if not match:
            continue
        body = text[match.end():]
        names, depth, started = [], 0, False
        for line in body.split("\n"):
            depth += line.count("{") - line.count("}")
            if not started and "{" in line:
                started = True
                continue
            if started and depth <= 0:
                break
            stripped = line.strip()
            if any(k in stripped for k in SKIP_KEYWORDS):
                continue
            # A stored var: no trailing `{`, and not a getter/setter pair.
            m = re.match(r"(?:private\s+|@\w+(?:\([^)]*\)\s*)?)*var\s+(\w+)\s*:\s*[^{=]+(=|$)",
                         stripped)
            if m and not stripped.rstrip().endswith("{"):
                names.append(m.group(1))
        return names
    return []


def main() -> int:
    models = synced_model_names()
    missing = [m for m in models if not stored_properties(m)]
    assert not missing, (
        f"no stored properties parsed for {missing} — the parse is stale, "
        "fix it rather than trusting a short list"
    )

    if "--names" in sys.argv:
        for name in sorted(models):
            print(f"CD_{name}")
        return 0

    print(f"{len(models)} record types expected in CloudKit Development "
          "(plus the built-in `Users`):\n")
    for name in sorted(models):
        fields = sorted(stored_properties(name) + [ENTITY_NAME])
        # The console's "N fields" counts record fields AND the six metadata
        # rows together, so match that or every number looks wrong by six.
        print(f"CD_{name}  ({len(fields)} record fields + {METADATA_FIELDS} metadata "
              f"= {len(fields) + METADATA_FIELDS} fields in the console)")
        for field in fields:
            print(f"    CD_{field}")
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
