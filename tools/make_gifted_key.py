#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Wrap an OpenAI key into a .blasterkey file an evaluator can tap to install.

The problem this solves is not typing. An evaluator could make their own key;
what stops them is being asked to put a credit card down to try a favour someone
asked them to look at. So the key is ours, and it arrives as a file.

    Usage:
        python3 tools/make_gifted_key.py --for Brandi
        python3 tools/make_gifted_key.py --for Brandi --out ~/Desktop
        python3 tools/make_gifted_key.py --for Brandi --expires 2026-12-31
        python3 tools/make_gifted_key.py --for Brandi --key sk-...   # scripting only

    Produces:  Brandi.blasterkey

The key is read from a prompt by default, and that is deliberate: a key passed as
--key lands in your shell history, where it outlives the evaluator. Pasting into
the prompt is the same gesture and leaves nothing behind. --key stays for
scripting.

THE WHOLE LOOP, including the parts no script can do
----------------------------------------------------
1. platform.openai.com, project **Blaster TestFlight** (not your default project,
   which is development spend and should stay separate).
2. Create a secret key and **name it after the evaluator**. The name is the whole
   ledger: the dashboard shows name, monthly spend and last-used per key, which
   answers "this key is burning money — whose is it?" without anything being
   written down here. Nothing in this repo records keys, and nothing should.
3. Confirm the project allows all three models the app calls: `gpt-4o-mini`,
   `omni-moderation-latest`, `gpt-image-2`. Withholding the moderation model
   silently removes a child-safety tier — the app keeps working and words stop
   being checked. `tools/audit_openai_models.py` lists what the code calls.
4. Run this script. Text the file.
5. To revoke: delete the key in the dashboard. That is the only revocation that
   works; nothing in the file or the app can take a key back.

A note on the spending limit: it enforces, but it lags. Measured 2026-09-16,
spend reached $1.44 against a $1 limit before the first refusal, so treat a cap
as a backstop with alerts rather than a fence. Images are essentially the entire
spend (~4.8c each; sentences need ~34,000 generations to reach a dollar), so a
cap is in practice a cap on art.

OBFUSCATION, NOT ENCRYPTION
---------------------------
The file is scrambled with a keystream derived from the app's bundle identifier,
which is public. This stops a casual reader and keeps the key out of `sk-`
pattern scanners and out of the evaluator's own hands in usable form. It stops
nobody who tries. That is the intended trade — see the long note in
`claudeBlast/Services/GiftedKeyTransfer.swift`, and do not "upgrade" one side
without the other.
"""

import argparse
import base64
import getpass
import hashlib
import json
import re
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

# Must match `GiftedKeyObfuscation.bundleID` in
# claudeBlast/Services/GiftedKeyTransfer.swift. The golden fixture in
# claudeBlastTests/Fixtures is what catches these two drifting apart.
BUNDLE_ID = "app.blasterai.ios"

MEDIA_TYPE = "application/vnd.claudeblast.giftedkey+json"
VERSION = "1.0.0"
NONCE_LENGTH = 16


def keystream(nonce: bytes, count: int) -> bytes:
    """Block i is SHA256(SHA256(bundle_id) || nonce || big-endian uint64 i).

    Big-endian and 8 bytes. This is the seam where the two implementations agree
    or silently do not, so both sides state it and a test pins the first block.
    """
    seed = hashlib.sha256(BUNDLE_ID.encode()).digest()
    out = bytearray()
    block = 0
    while len(out) < count:
        out += hashlib.sha256(seed + nonce + struct.pack(">Q", block)).digest()
        block += 1
    return bytes(out[:count])


def scramble(data: bytes, nonce: bytes) -> bytes:
    return bytes(a ^ b for a, b in zip(data, keystream(nonce, len(data))))


def seal(payload: dict, nonce: bytes) -> dict:
    # Compact separators so the plaintext is stable for the fixture; the app
    # re-parses it as JSON, so only validity matters, not byte-equality.
    plaintext = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode()
    return {
        "@type": MEDIA_TYPE,
        "version": VERSION,
        "_comment": (
            f"A Blaster API key for {payload['label']}, from {payload['issuer']}. "
            "The contents are obfuscated, not encrypted — treat this file as you "
            "would the key itself."
        ),
        "label": payload["label"],
        "nonce": base64.b64encode(nonce).decode(),
        "payload": base64.b64encode(scramble(plaintext, nonce)).decode(),
        "checksum": hashlib.sha256(plaintext).hexdigest(),
    }


def read_key(supplied: str | None) -> str:
    if supplied:
        return supplied.strip()
    # getpass so a shoulder-surfer and a screen recording both see nothing.
    key = getpass.getpass("Paste the OpenAI key (input hidden): ").strip()
    if not key:
        sys.exit("No key given.")
    # Say that something arrived, and enough of it to recognise.
    #
    # Hidden input means a paste that silently failed — a terminal that swallowed
    # it, a clipboard holding the wrong thing — looks exactly like one that
    # worked, right up until an evaluator taps a file containing nothing. The
    # length and last four are enough to check against the dashboard without
    # putting the key on screen.
    print(f"  got {len(key)} characters, ending …{key[-4:]}", file=sys.stderr)
    return key


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Wrap an OpenAI key into a .blasterkey file for one evaluator.")
    ap.add_argument("--for", dest="recipient", required=True,
                    help="Who the key is for. Names the file and shows in the app.")
    ap.add_argument("--key", default=None,
                    help="The OpenAI key. Omit to be prompted, which keeps it out "
                         "of shell history.")
    ap.add_argument("--from", dest="issuer", default="Mark Lucovsky",
                    help="Who is sending it (shown to the evaluator).")
    ap.add_argument("--expires", default=None,
                    help="YYYY-MM-DD, display only — nothing enforces it. Revoke "
                         "in the OpenAI dashboard instead.")
    ap.add_argument("--out", default=".", type=Path,
                    help="Directory to write into (default: here).")
    ap.add_argument("--self-test", action="store_true",
                    help="Write the deterministic golden fixture used by the "
                         "Swift tests, with a fake key. Ignores --key/--for.")
    args = ap.parse_args()

    if args.self_test:
        return write_fixture(args.out)

    recipient = args.recipient.strip()
    if not recipient:
        sys.exit("--for cannot be empty.")

    key = read_key(args.key)
    if not key.startswith("sk-"):
        # A warning rather than a refusal: OpenAI has changed key prefixes before
        # and a script that refuses the future is worse than one that asks.
        print(f"warning: that doesn't look like an OpenAI key (no 'sk-' prefix)",
              file=sys.stderr)

    if args.expires:
        try:
            datetime.strptime(args.expires, "%Y-%m-%d")
        except ValueError:
            sys.exit("--expires must be YYYY-MM-DD.")

    payload = {
        "key": key,
        "label": recipient,
        "issuer": args.issuer,
        "issuedAt": datetime.now(timezone.utc).isoformat(),
        "expiresAt": f"{args.expires}T00:00:00Z" if args.expires else None,
    }

    import secrets
    sealed = seal(payload, secrets.token_bytes(NONCE_LENGTH))

    # Filename is what the evaluator sees in Messages before they open anything,
    # so it carries the name and nothing else.
    safe = re.sub(r"[^A-Za-z0-9 _-]", "", recipient).strip() or "key"
    args.out.mkdir(parents=True, exist_ok=True)
    path = args.out / f"{safe}.blasterkey"
    path.write_text(json.dumps(sealed, indent=2, sort_keys=True) + "\n")

    print(f"wrote {path}")
    print(f"  for      {recipient}")
    print(f"  key      sk-…{key[-4:]}")
    print(f"  expires  {args.expires or 'never (revoke in the dashboard)'}")
    print()
    print("Text the file. Nothing else needs to travel with it — there is no")
    print("passcode, and the app installs it on a tap.")
    return 0


def write_fixture(out: Path) -> int:
    """The golden fixture: fixed nonce, fake key, checked into the test bundle.

    Two implementations of one format is the only real risk left in this feature,
    and this is what catches them drifting. The key inside is not real.
    """
    payload = {
        "key": "sk-golden-fixture-not-a-real-key-0000",
        "label": "Golden Fixture",
        "issuer": "Blaster Tests",
        "issuedAt": "2026-09-16T00:00:00+00:00",
        "expiresAt": None,
    }
    nonce = bytes(range(NONCE_LENGTH))   # 00 01 02 … 0f, deterministic
    out.mkdir(parents=True, exist_ok=True)
    path = out / "gifted-key-golden.blasterkey"
    path.write_text(json.dumps(seal(payload, nonce), indent=2, sort_keys=True) + "\n")
    print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
