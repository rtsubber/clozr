#!/usr/bin/env python3
"""Clozr Backend — systemd service runner"""

import os
import sys

# Set required env vars if not already set
os.environ.setdefault("CLOZR_JWT_SECRET", "dev-key-change-for-production")
os.environ.setdefault("CLOZR_DATA_DIR", "/home/ron/.openclaw/workspace/apps/jarvis_meeting_app/data")
os.environ.setdefault("CLOZR_PORT", "8510")
os.environ.setdefault("CLOZR_STATIC_DIR", "/home/ron/.openclaw/workspace/apps/jarvis_meeting_app/build/web")
os.environ.setdefault("CLOZR_ALLOWED_ORIGINS", "http://localhost:*,https://*.tail38a93d.ts.net")
os.environ.setdefault("CLOZR_ROOT_PATH", "/clozr")  # Deploy behind /clozr subpath

# Import secrets from existing files
def load_secret(filepath, env_name):
    try:
        with open(filepath) as f:
            os.environ[env_name] = f.read().strip()
    except FileNotFoundError:
        pass

load_secret("/home/ron/.openclaw/workspace/.groq_key", "CLOZR_GROQ_API_KEY")
load_secret("/home/ron/.openclaw/workspace/.openrouter_key", "CLOZR_OPENROUTER_API_KEY")

# Stripe key from env file
if not os.environ.get("STRIPE_SECRET_KEY"):
    load_secret("/home/ron/.openclaw/workspace/apps/jarvis_meeting_app/.clozr_env", "STRIPE_SECRET_KEY")

# Telegram from existing config
try:
    import json
    with open("/home/ron/.openclaw/workspace/.telegram_config.json") as f:
        tg = json.load(f)
        if tg.get("bot_token"):
            os.environ["CLOZR_TELEGRAM_BOT_TOKEN"] = tg["bot_token"]
        if tg.get("chat_id"):
            os.environ["CLOZR_TELEGRAM_CHAT_ID"] = str(tg["chat_id"])
except:
    pass

from main import app
import uvicorn

if __name__ == "__main__":
    port = int(os.environ.get("CLOZR_PORT", "8510"))
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")