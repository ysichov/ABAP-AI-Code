#!/usr/bin/env python3
"""
Concept check: does GET /v1/models work for each provider?

Run this from your machine to confirm whether the endpoint itself is fine
(isolating the problem from the SAP SM59 destination / proxy).

Usage:
    set ANTHROPIC_API_KEY=sk-ant-...   (Windows: set, Linux/mac: export)
    set OPENAI_API_KEY=sk-...
    set MISTRAL_API_KEY=...
    python check_models.py

Only providers whose key is present are tested.
Uses only the standard library (urllib) - no pip install needed.
"""

import json
import os
import urllib.request
import urllib.error

# provider -> (base_url, headers builder)
PROVIDERS = {
    "anthropic": {
        "url": "https://api.anthropic.com/v1/models",
        "env": "ANTHROPIC_API_KEY",
        "headers": lambda key: {
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
    },
    "openai": {
        "url": "https://api.openai.com/v1/models",
        "env": "OPENAI_API_KEY",
        "headers": lambda key: {
            "Authorization": f"Bearer {key}",
        },
    },
    "mistral": {
        "url": "https://api.mistral.ai/v1/models",
        "env": "MISTRAL_API_KEY",
        "headers": lambda key: {
            "Authorization": f"Bearer {key}",
        },
    },
}


def check(name, cfg):
    key = os.environ.get(cfg["env"])
    if not key:
        print(f"[{name}] skipped - {cfg['env']} not set")
        return

    req = urllib.request.Request(cfg["url"], headers=cfg["headers"](key), method="GET")
    print(f"[{name}] GET {cfg['url']}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:
        print(f"[{name}] HTTP {e.code}: {e.read().decode()[:300]}")
        return
    except Exception as e:  # noqa: BLE001
        print(f"[{name}] ERROR: {e}")
        return

    # Both Anthropic and OpenAI-compatible APIs return the list under "data".
    models = body.get("data", [])
    print(f"[{name}] OK - {len(models)} models:")
    for m in models:
        mid = m.get("id", "?")
        name_extra = m.get("display_name") or m.get("owned_by") or ""
        print(f"    {mid:40} {name_extra}")
    print()


if __name__ == "__main__":
    for name, cfg in PROVIDERS.items():
        check(name, cfg)
