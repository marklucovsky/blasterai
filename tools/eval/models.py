# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Mark Lucovsky
"""What each model accepts, and what it costs.

The app's requests are written for gpt-4o-mini. Other models take different
parameters, so `adapt` rewrites a production request for the model under test
and records what it changed. The app builds the same rules in
`claudeBlast/Services/OpenAI/ChatRequest.swift` — keep the two in step. Every
GPT-6 model rejects `temperature` (only the default, 1, is allowed), and every
service states one.

Probed against the live API on 2026-10-19:
- GPT-6 (luna, sol, 6.1-sol, astra): `temperature` other than 1 → 400.
- Sol and Astra have no `reasoning_effort: "none"`; their lowest is "low".
- Luna at "none" and "low" used 0 reasoning tokens on our prompts.
- GPT-6 usage reports `prompt_tokens_details.cache_write_tokens`.

Prices are per 1M tokens, short context, from developers.openai.com/api/docs/
pricing (screenshot 2026-10-19). Long-context rates are not modelled; none of
our prompts come near it. Reconcile against the billing CSV with
`tools/diff_openai_costs.py` before trusting a total to the cent.
"""
from dataclasses import dataclass


@dataclass(frozen=True)
class Model:
    id: str
    accepts_temperature: bool
    efforts: tuple[str, ...]          # () = no reasoning_effort parameter
    default_effort: str | None
    input: float                       # $/1M
    cached_input: float
    cache_write: float | None          # None = not billed separately
    output: float

    @property
    def is_reasoning(self) -> bool:
        return bool(self.efforts)


MODELS: dict[str, Model] = {m.id: m for m in [
    Model("gpt-4o-mini", True, (), None, 0.15, 0.075, None, 0.60),
    Model("gpt-6-luna", False, ("none", "low", "medium", "high", "max"), "none", 0.10, 0.01, 0.125, 0.50),
    Model("gpt-6.1-sol", False, ("low", "medium", "high", "max"), "low", 2.00, 0.10, 2.50, 10.00),
    Model("gpt-6-astra", False, ("low", "medium", "high", "max"), "low", 10.00, 1.00, 12.50, 50.00),
]}


def get(model_id: str) -> Model:
    if model_id not in MODELS:
        raise SystemExit(f"unknown model {model_id!r}: add it to tools/eval/models.py (known: {', '.join(MODELS)})")
    return MODELS[model_id]


def adapt(body: dict, model_id: str, effort: str | None = None) -> tuple[dict, list[str]]:
    """Rewrite a production request for `model_id`. Returns the body to send and
    a list of the changes, which the run archive records beside every output."""
    m = get(model_id)
    out = dict(body)
    changes: list[str] = []
    if out.get("model") != model_id:
        changes.append(f"model {out.get('model')} → {model_id}")
        out["model"] = model_id
    if not m.accepts_temperature and "temperature" in out:
        changes.append(f"dropped temperature {out.pop('temperature')}")
    if m.is_reasoning:
        effort = effort or m.default_effort
        if effort not in m.efforts:
            raise SystemExit(f"{model_id} does not accept reasoning_effort {effort!r} (accepts {m.efforts})")
        out["reasoning_effort"] = effort
        changes.append(f"reasoning_effort {effort}")
        if "max_tokens" in out:
            # Reasoning tokens count against the completion budget, so a limit
            # sized for visible text alone would truncate at higher effort.
            limit = out.pop("max_tokens")
            scaled = limit if effort == "none" else limit * 4
            out["max_completion_tokens"] = scaled
            changes.append(f"max_tokens {limit} → max_completion_tokens {scaled}")
    elif effort:
        raise SystemExit(f"{model_id} takes no reasoning_effort")
    return out, changes


def cost(model_id: str, usage: dict) -> float:
    """Dollars for one call, from the response's `usage`."""
    m = get(model_id)
    prompt = usage.get("prompt_tokens", 0)
    details = usage.get("prompt_tokens_details") or {}
    cached = details.get("cached_tokens", 0) or 0
    written = (details.get("cache_write_tokens", 0) or 0) if m.cache_write is not None else 0
    plain = max(0, prompt - cached - written)
    dollars = (plain * m.input + cached * m.cached_input + written * (m.cache_write or 0)
               + usage.get("completion_tokens", 0) * m.output)
    return dollars / 1e6
