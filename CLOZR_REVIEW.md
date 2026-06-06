# The Clozr — Code Review Package for Claude Opus

## Overview
**The Clozr** (formerly Jarvis Meeting App) is a Flutter web app that acts as an AI-powered meeting assistant. It listens to meetings via browser speech recognition, transcribes them, detects automatable workflows using LLM analysis, and generates shareable business proposals.

**Stack:** Flutter (web), Dart, Python backend (proposal API), Groq/OpenRouter LLM, Web Speech API

**Current state:** v0.1.0 — functional prototype, web-first, deployed via Tailscale Funnel

---

## Files Included

### Core App (Dart/Flutter)
- `lib/main.dart` — App entry, routing, theme
- `lib/screens/home_screen.dart` — Home: meeting list, start button, catalog shortcut
- `lib/screens/meeting_screen.dart` — Live recording, transcript, workflow detection, summary
- `lib/screens/proposal_screen.dart` — AI-generated proposal viewer + share
- `lib/screens/settings_screen.dart` — API keys (Groq, OpenRouter, Local-Eye), wake word toggle
- `lib/screens/catalog_screen.dart` — Editable service catalog (what workflows to detect)

### Services
- `lib/services/stt_service.dart` — Browser Speech Recognition via JS interop
- `lib/services/llm_service.dart` — Groq/OpenRouter for meeting summary + proposal generation
- `lib/services/workflow_service.dart` — Detects automatable workflows from transcript via LLM
- `lib/services/localeye_service.dart` — Local-Eye business verification API
- `lib/services/api_keys.dart` — API key management (SharedPreferences)
- `lib/services/meeting_storage.dart` — Meeting persistence (SharedPreferences)
- `lib/services/catalog_storage.dart` — Service catalog persistence

### Models
- `lib/models/meeting.dart` — Meeting data model
- `lib/models/workflow.dart` — Detected workflow model
- `lib/models/proposal.dart` — Generated proposal model
- `lib/models/service_catalog.dart` — Service catalog model + BrandBoost defaults

### Widgets
- `lib/widgets/transcript_widget.dart` — Transcript display
- `lib/widgets/workflow_card.dart` — Workflow card UI

### Backend (Python)
- `proposal_api.py` — Proposal share API (create, track views, Telegram notifications)
- `serve_web.py` — Static file server + API proxy for the Flutter web build

### Web
- `web/index.html` — Includes JS bridge for browser Speech Recognition

### Config
- `pubspec.yaml` — Flutter dependencies
- `.env.example` — Environment variable template (real .env has placeholder keys)

---

## Review Focus Areas

### 1. Security
- API keys stored in SharedPreferences (localStorage on web) — how secure is this?
- `.env` file in Flutter assets — any risk of keys leaking in build?
- Proposal API: no auth on endpoints — anyone can create/track proposals
- Telegram bot token hardcoded in `proposal_api.py` — should this be env-only?
- CORS headers set to `*` — appropriate for production?
- Tailscale Funnel URL (`ron-system-product-name...`) exposed in code and proposals
- IP address and user agent logged on proposal views — privacy concerns?
- No rate limiting on proposal creation or view tracking

### 2. Architecture & Design
- SharedPreferences for all storage — appropriate? When to migrate to SQLite?
- JS interop for STT — is this the right approach vs native Flutter packages?
- LLM prompts hardcoded in `llm_service.dart` and `workflow_service.dart` — should these be configurable?
- Service catalog defaults are BrandBoost-specific — how to make this more generic?
- Meeting data model lacks audio recording (only transcript) — intentional?
- Proposal sharing via file-based JSON storage — scalability concerns?

### 3. Code Quality
- Error handling: many `catch (_) { return []; }` patterns — silently failing
- STT service uses singleton pattern for JS callbacks — thread safety?
- Workflow detection depends entirely on LLM — no fallback for offline
- UI state management: mixing `setState` with Riverpod providers inconsistently
- `proposal_screen.dart` has a hardcoded mock `_generateProposal()` fallback
- No tests beyond the default `widget_test.dart`

### 4. Product & UX
- Wake word "Hey Clozr" mentioned in UI but Porcupine integration not implemented
- Proposal screen says "340% ROI" in mock data — violates anti-fabrication policy
- No meeting duration tracking
- No way to edit/delete individual proposals
- No audio playback of recorded meetings
- Copy-to-clipboard as only export option — no PDF, email, etc.

### 5. Deployment
- `serve_web.py` uses Python's built-in HTTP server — not production-ready
- No HTTPS (relies on Tailscale Funnel for TLS)
- No health check endpoint
- Proposal API runs separately from web server — coordination issues?
- No database — JSON files for proposals (race conditions with concurrent access?)

### 6. Privacy & Compliance
- Full meeting transcripts stored in localStorage — no encryption
- Business verification queries send client phone numbers to Local-Eye API
- Proposal view tracking logs IP + user agent without visitor consent
- No privacy policy or terms of service in the app
- GDPR/CCPA considerations for storing meeting content?

---

## Specific Code Concerns

### `proposal_api.py` — Hardcoded secrets
```python
TELEGRAM_BOT_TOKEN = os.environ.get('TELEGRAM_BOT_TOKEN', '8708322997:AAHfLffsR0Xk8BmmOVjMktrZidPY4Z4ZsJs')
TELEGRAM_CHAT_ID = os.environ.get('TELEGRAM_CHAT_ID', '5176561592')
```
Real token is the DEFAULT VALUE — if env var is missing, it still sends to real Telegram.

### `llm_service.dart` — No input sanitization
Full transcript is injected into LLM prompt without sanitization. Could contain:
- Prompt injection attempts in meeting speech
- Very long transcripts that exceed token limits
- Sensitive business data being sent to Groq/OpenRouter

### `stt_service.dart` — Web-only
Uses `@JS()` annotations and `dart:js_interop` — completely web-specific. Native iOS/Android builds will fail.

### `localeye_service.dart` — Playground token
Gets a "playground token" before each verification call. This is meant for demos, not production use.

### `serve_web.py` — No auth proxy
API proxy forwards all requests without authentication. Anyone who finds the URL can create proposals and track views.

---

## Architecture Diagram

```
┌─────────────────────────────────────────┐
│            Flutter Web App               │
│  ┌─────────┐ ┌──────────┐ ┌───────────┐ │
│  │  STT    │ │   LLM    │ │ Local-Eye │ │
│  │(Browser │ │(Groq/    │ │   API     │ │
│  │ Speech) │ │OpenRouter│ │           │ │
│  └────┬────┘ └────┬─────┘ └─────┬─────┘ │
│       │           │              │       │
│  ┌────┴───────────┴──────────────┴─────┐ │
│  │       SharedPreferences              │ │
│  │  (meetings, API keys, catalog)      │ │
│  └─────────────────────────────────────┘ │
└──────────────────┬───────────────────────┘
                   │ HTTP
┌──────────────────┴───────────────────────┐
│       Python Backend (serve_web.py)       │
│  ┌─────────────────────────────────────┐ │
│  │   Proposal API (proposal_api.py)    │ │
│  │   - POST /api/proposals             │ │
│  │   - GET  /api/proposals/{id}        │ │
│  │   - POST /api/proposals/{id}/viewed │ │
│  └─────────────────────────────────────┘ │
│  ┌─────────────────────────────────────┐ │
│  │   JSON File Storage (proposals/)    │ │
│  └─────────────────────────────────────┘ │
│  ┌─────────────────────────────────────┐ │
│  │   Telegram Bot (notifications)      │ │
│  └─────────────────────────────────────┘ │
└─────────────────────────────────────────┘
        │
   Tailscale Funnel
        │
   Public Internet
```

---

## What We Want From Opus

1. **Security audit** — What's the highest-risk item? What needs fixing before any public launch?
2. **Architecture recommendations** — What would you change about the current design?
3. **Code quality feedback** — Patterns that should be improved or replaced
4. **Product suggestions** — Missing features, UX improvements, differentiation opportunities
5. **Deployment strategy** — How to move from "works on my Tailscale" to production
6. **Privacy framework** — What's needed for storing meeting transcripts responsibly

Please be direct. This is a v0.1 prototype — we know there are gaps. We want the honest assessment.