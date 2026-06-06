#!/usr/bin/env python3
"""Clozr Backend — systemd service runner

Secrets and paths are loaded from environment variables.
For local dev, copy .env.example to .env and fill in your keys.
For production, set env vars via systemd or your hosting platform.
"""

import os
import sys

# Defaults — override with environment variables in production
os.environ.setdefault("CLOZR_PORT", "8510")
os.environ.setdefault("CLOZR_ROOT_PATH", "/clozr")  # Deploy behind /clozr subpath

# Try loading secrets from .env file if present
_env_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".env")
if os.path.exists(_env_file):
    with open(_env_file) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                key, _, value = line.partition("=")
                key = key.strip()
                value = value.strip()
                if key and key not in os.environ:
                    os.environ[key] = value

# Validate required secrets
_REQUIRED = ["CLOZR_JWT_SECRET", "CLOZR_GROQ_API_KEY", "CLOZR_OPENROUTER_API_KEY"]
_missing = [k for k in _REQUIRED if not os.environ.get(k)]
if _missing:
    print(f"❌ Missing required env vars: {_missing}")
    print("Copy .env.example to .env and fill in your keys, or set them in your environment.")
    sys.exit(1)

from main import app
import uvicorn

if __name__ == "__main__":
    port = int(os.environ.get("CLOZR_PORT", "8510"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")