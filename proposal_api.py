#!/usr/bin/env python3
"""
Jarvis Proposal Tracker API
- POST /api/proposals — create a shareable proposal
- GET /api/proposals/{id} — get proposal data
- POST /api/proposals/{id}/viewed — track when proposal is opened
- GET /api/proposals/{id}/views — get view history
"""

import json
import re
import uuid
import os
import urllib.request
import urllib.error
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

DATA_DIR = Path("/home/ron/.openclaw/workspace/apps/jarvis_meeting_app/proposals")
DATA_DIR.mkdir(parents=True, exist_ok=True)

# ⚠️ SECURITY: Telegram token MUST come from environment — no hardcoded fallback
# If TELEGRAM_BOT_TOKEN is not set, Telegram notifications are disabled.
TELEGRAM_BOT_TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN', '')
TELEGRAM_CHAT_ID = os.environ.get('TELEGRAM_CHAT_ID', '')

# Validate proposal IDs to prevent path traversal attacks
VALID_ID_PATTERN = re.compile(r'^[a-f0-9]{8,32}$')

def _validate_id(proposal_id: str) -> bool:
    """Ensure proposal ID is safe (hex, 8-32 chars) to prevent path traversal."""
    return bool(VALID_ID_PATTERN.match(proposal_id))

def proposal_path(proposal_id: str) -> Path:
    if not _validate_id(proposal_id):
        raise ValueError(f"Invalid proposal ID: {proposal_id}")
    return DATA_DIR / f"{proposal_id}.json"

def view_path(proposal_id: str) -> Path:
    if not _validate_id(proposal_id):
        raise ValueError(f"Invalid proposal ID: {proposal_id}")
    return DATA_DIR / f"{proposal_id}_views.json"

class ProposalHandler(BaseHTTPRequestHandler):
    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return json.loads(self.rfile.read(length)) if length else {}

    def do_OPTIONS(self):
        self._send_json({"ok": True})

    def do_GET(self):
        path = self.path.rstrip("/")
        
        # GET /api/proposals/{id} — get proposal data
        if path.startswith("/api/proposals/") and not path.endswith("/views"):
            proposal_id = path.split("/api/proposals/")[1]
            if not _validate_id(proposal_id):
                self._send_json({"error": "Invalid proposal ID"}, 400)
                return
            try:
                p = proposal_path(proposal_id)
            except ValueError:
                self._send_json({"error": "Invalid proposal ID"}, 400)
                return
            if not p.exists():
                self._send_json({"error": "Proposal not found"}, 404)
                return
            data = json.loads(p.read_text())
            # Remove internal fields
            data.pop("views", None)
            self._send_json(data)
            return
        
        # GET /api/proposals/{id}/views — get view history
        if path.startswith("/api/proposals/") and path.endswith("/views"):
            proposal_id = path.split("/api/proposals/")[1].replace("/views", "")
            if not _validate_id(proposal_id):
                self._send_json({"error": "Invalid proposal ID"}, 400)
                return
            try:
                v = view_path(proposal_id)
            except ValueError:
                self._send_json({"error": "Invalid proposal ID"}, 400)
                return
            views = json.loads(v.read_text()) if v.exists() else []
            self._send_json({"views": views})
            return
        
        self._send_json({"error": "Not found"}, 404)

    def do_POST(self):
        path = self.path.rstrip("/")
        
        # POST /api/proposals — create proposal
        if path == "/api/proposals":
            data = self._read_body()
            # SECURITY: Always generate server-side ID — never trust client-provided ID
            proposal_id = uuid.uuid4().hex[:8]
            data["id"] = proposal_id
            data["created_at"] = datetime.now(timezone.utc).isoformat()
            data["views"] = 0
            
            p = proposal_path(proposal_id)
            p.write_text(json.dumps(data, indent=2))
            
            # Create empty views file
            v = view_path(proposal_id)
            if not v.exists():
                v.write_text("[]")
            
            self._send_json({
                "id": proposal_id,
                "share_url": f"/jarvis/proposal/{proposal_id}",
                "created_at": data["created_at"],
            })
            return
        
        # POST /api/proposals/{id}/viewed — track a view
        if path.startswith("/api/proposals/") and path.endswith("/viewed"):
            proposal_id = path.split("/api/proposals/")[1].replace("/viewed", "")
            if not _validate_id(proposal_id):
                self._send_json({"error": "Invalid proposal ID"}, 400)
                return
            try:
                p = proposal_path(proposal_id)
            except ValueError:
                self._send_json({"error": "Invalid proposal ID"}, 400)
                return
            if not p.exists():
                self._send_json({"error": "Proposal not found"}, 404)
                return
            
            # Record the view
            view_data = self._read_body()
            view_record = {
                "timestamp": datetime.now(timezone.utc).isoformat(),
                "ip": self.client_address[0],
                "user_agent": self.headers.get("User-Agent", ""),
                "referrer": self.headers.get("Referer", ""),
            }
            view_record.update(view_data)  # merge any extra data
            
            v = view_path(proposal_id)
            views = json.loads(v.read_text()) if v.exists() else []
            views.append(view_record)
            v.write_text(json.dumps(views, indent=2))
            
            # Update view count on proposal
            proposal = json.loads(p.read_text())
            proposal["views"] = len(views)
            proposal["last_viewed_at"] = view_record["timestamp"]
            p.write_text(json.dumps(proposal, indent=2))
            
            # Send Telegram notification on first view
            if len(views) == 1:
                _send_telegram_notification(proposal, view_record)
            
            self._send_json({"ok": True, "total_views": len(views)})
            return
        
        self._send_json({"error": "Not found"}, 404)

    def log_message(self, format, *args):
        # Suppress default logging
        pass

def main():
    port = 8510
    server = HTTPServer(("0.0.0.0", port), ProposalHandler)
    print(f"Jarvis Proposal Tracker API running on port {port}")
    server.serve_forever()

if __name__ == "__main__":
    main()
def _send_telegram_notification(proposal: dict, view_record: dict):
    """Send a Telegram notification when a proposal is first viewed."""
    if not TELEGRAM_BOT_TOKEN or not TELEGRAM_CHAT_ID:
        return  # Telegram not configured — skip silently
    
    try:
        client_name = proposal.get("client_name", "Unknown")
        proposal_id = proposal.get("id", "?")
        total_views = proposal.get("views", 1)
        
        message = (
            f"🎯 Proposal Viewed!\n\n"
            f"{client_name} just opened your proposal\n"
            f"View #{total_views}"
        )
        
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        data = json.dumps({
            "chat_id": TELEGRAM_CHAT_ID,
            "text": message,
        }).encode()
        
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        urllib.request.urlopen(req, timeout=5)
    except Exception as e:
        print(f"Telegram notification failed: {e}")
