# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""Chat-completions calls for the eval harness: retries, timing, cost.

Reads the key from OPENAI_API_KEY. The key needs a project that allows every
model a run names; a model the project blocks comes back as a 403/404 and is
recorded as an error, never retried.
"""
import os
import random
import time

import requests  # bundles its own CA certs; avoids system-cert SSL issues

import models

URL = "https://api.openai.com/v1/chat/completions"
RETRYABLE = {408, 409, 429, 500, 502, 503, 504}


def call(body: dict, attempts: int = 4, timeout: float = 180) -> dict:
    """Send `body` as-is. Returns {"text", "usage", "latency_s", "cost",
    "finish_reason", "error"}; `error` is None on success."""
    key = os.environ.get("OPENAI_API_KEY")
    if not key:
        raise SystemExit("OPENAI_API_KEY is not set")
    last_error = None
    for attempt in range(attempts):
        start = time.monotonic()
        try:
            r = requests.post(URL, json=body, timeout=timeout,
                              headers={"Authorization": f"Bearer {key}"})
        except requests.RequestException as e:
            last_error = f"network: {e}"
        else:
            latency = time.monotonic() - start
            if r.status_code == 200:
                d = r.json()
                choice = d["choices"][0]
                usage = d.get("usage", {})
                return {"text": choice["message"].get("content") or "", "usage": usage,
                        "latency_s": round(latency, 3), "cost": models.cost(body["model"], usage),
                        "finish_reason": choice.get("finish_reason"), "error": None}
            last_error = f"HTTP {r.status_code}: {r.text[:300]}"
            if r.status_code not in RETRYABLE:
                break
        time.sleep(min(30, 2 ** attempt + random.random()))
    return {"text": "", "usage": {}, "latency_s": None, "cost": 0.0, "finish_reason": None,
            "error": last_error}
