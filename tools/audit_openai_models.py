#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""List every OpenAI model the app calls, so a project allowlist can't miss one.

    Usage:
        python3 tools/audit_openai_models.py          # list, and check for drift
        python3 tools/audit_openai_models.py --quiet  # exit code only

Why this exists
---------------
Gifted evaluator keys live in an OpenAI project with a **model allowlist**, and a
model the code calls but the project does not permit fails with a 403
`model_not_found`. That is survivable for art — the caregiver is told, and the
key is not condemned — but it is not survivable for `omni-moderation-latest`:
tier 2 of word moderation would stop running while the app kept working, and a
tier-3 verdict would still come back, so nothing anywhere would look wrong. A
child-safety layer would be off and silent.

So before minting keys, the allowlist has to be checked against what the code
actually calls, and that list has to come from the code rather than from memory.

`ModelID` in claudeBlast/Services/OpenAI/ModelPricing.swift says it is "the one
place model ids are written down". It is not, quite: several services still
inline their own string literal. That is exactly the drift this catches — a new
service added with a new model would be invisible until an evaluator hit it.

Exits non-zero when a model literal appears in the sources without a matching
`ModelID` constant.
"""

import argparse
import re
import sys
from pathlib import Path

SOURCE_DIR = Path("claudeBlast")
PRICING = SOURCE_DIR / "Services/OpenAI/ModelPricing.swift"

# Model ids as they appear in a request body. Broad on the families rather than
# an exact list, so a model nobody here anticipated is still caught.
#
# The hyphen is required, and it is load-bearing: without it this matched
# `"tts.done"`, a TileScript notification name, and reported a missing model that
# does not exist. Every real OpenAI model id contains one (`gpt-4o-mini`,
# `omni-moderation-latest`, `tts-1`), so requiring it costs no coverage.
MODEL_PATTERN = re.compile(
    r'"((?:gpt|o\d|dall-e|text-embedding|omni-moderation|whisper|tts)-[A-Za-z0-9._-]*)"')

# Literals that name a family in prose or match a price-table prefix rather than
# naming a model a request is sent to.
#
# gpt-4o-mini is retired: build 9 moved every job to GPT-6 (62b87651). It stays
# in `ModelPricing.rates` and `ModelCapabilities.table` only so usage rows
# recorded before build 9 still price; no request names it, and a gifted key's
# allowlist does not need it.
IGNORE = {"gpt-4o", "gpt-4o-mini"}


def declared_ids() -> dict[str, str]:
    """`ModelID` constants: name -> model id."""
    if not PRICING.exists():
        sys.exit(f"missing {PRICING} — run from the repo root")
    body = PRICING.read_text()
    block = re.search(r"enum ModelID \{(.*?)\n\}", body, re.S)
    if not block:
        sys.exit(f"could not find `enum ModelID` in {PRICING}")
    return dict(re.findall(r'static let (\w+)\s*=\s*"([^"]+)"', block.group(1)))


def literals() -> dict[str, list[str]]:
    """Model id -> the files that name it, excluding comments."""
    found: dict[str, list[str]] = {}
    for path in sorted(SOURCE_DIR.rglob("*.swift")):
        for n, line in enumerate(path.read_text().splitlines(), 1):
            stripped = line.lstrip()
            if stripped.startswith("//") or stripped.startswith("///"):
                continue
            for model in MODEL_PATTERN.findall(line):
                if model in IGNORE:
                    continue
                found.setdefault(model, []).append(f"{path}:{n}")
    return found


def main() -> int:
    ap = argparse.ArgumentParser(
        description="List the OpenAI models this app calls; flag any not in ModelID.")
    ap.add_argument("--quiet", action="store_true", help="exit code only")
    args = ap.parse_args()

    declared = declared_ids()
    used = literals()
    # The allowlist is the union: a ModelID constant is a model the app intends
    # to call even if every call site currently goes through the constant.
    allowlist = sorted(set(declared.values()) | set(used))
    undeclared = {m: where for m, where in used.items() if m not in declared.values()}

    if not args.quiet:
        print("Allow these models on any project holding a Blaster key:\n")
        for model in allowlist:
            names = [n for n, v in declared.items() if v == model]
            label = f"ModelID.{'/'.join(names)}" if names else "NOT IN ModelID"
            print(f"  {model:<28} {label}")
        print()
        if undeclared:
            print("Model literals with no ModelID constant:\n")
            for model, where in sorted(undeclared.items()):
                print(f"  {model}")
                for w in where:
                    print(f"      {w}")
            print()
            print("Add a `ModelID` constant and use it, so the price table and the")
            print("request bodies cannot name different models.")
        else:
            print("✓ every model literal has a ModelID constant")

    return 1 if undeclared else 0


if __name__ == "__main__":
    sys.exit(main())
