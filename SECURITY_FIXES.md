# Clozr Security Fix Tracker

Based on Opus assessment (CLOZR_ASSESSMENT.md)

## ✅ Fixed (June 3, 2026)

### Critical
- [x] **C1 — Telegram token hardcoded** → Removed default fallback, env-only with empty string
- [x] **C2 — Unauthenticated API exposed** → Stopped + disabled both systemd services (jarvis-proposal-api, jarvis-app)
- [x] **C3 — Path traversal** → Added `_validate_id()` with `^[a-f0-9]{8,32}$` regex, server-generated IDs only
- [x] **C3 — Client-controlled proposal IDs** → Changed to `uuid.uuid4().hex[:8]` (server-generated, never from client)
- [x] **Fake "340% ROI"** → Removed mock data, replaced with empty placeholder
- [x] **Tailscale hostname in code** → Removed from proposal_api.py and proposal_screen.dart
- [x] **Telegram notification leaking URLs** → Simplified notification, removed user agent/device info from message

### Medium
- [x] **M3 — Dev path in DATA_DIR** → Still hardcoded path but no longer in public-facing URLs

## 🔲 Still Needs Fix

### Critical (before any public use)
- [ ] **C4 — Unvalidated field injection** → `view_record.update(view_data)` blindly merges client JSON
- [ ] **C1 follow-up** → Revoke Telegram bot token in BotFather (Ron needs to do this manually)

### High (before paid customers)
- [ ] **H1 — API keys in localStorage** → Move all provider calls behind authenticated backend
- [ ] **H2 — Prompt injection** → Add transcript delimiters, system/user separation, JSON validation
- [ ] **H3 — No consent/disclosure** → Privacy policy, data processing disclosure
- [ ] **H4 — Race conditions on JSON** → Migrate to SQLite with WAL

### Architecture (A1-A6)
- [ ] **A1 — Backend proxy for provider calls** → Keys server-side, auth, rate limiting
- [ ] **A2 — Replace stdlib HTTP with FastAPI** → One app, proper routing, validation, middleware
- [ ] **A3 — SQLite datastore** → meetings, transcripts, workflows, proposals, views, users
- [ ] **A4 — Per-tenant branding** → Decouple from BrandBoost, make catalog/identity configurable
- [ ] **A5 — Consistent state management** → Pick Riverpod, move setState code to providers
- [ ] **A6 — STT engine interface** → Abstract behind interface for server-side engine swap

### Code Quality
- [ ] Stop silent failures (`catch (_)` everywhere) → surface errors to UI
- [ ] Wire proposal generation to real LLM (delete mock `_generateProposal()`)
- [ ] Fix STT singleton fragility (hot-reload + multi-screen issues)
- [ ] Add transcript length bounds/truncation before LLM calls
- [ ] Add unit tests (JSON parsing, ID validation, proposal flow)

### Product
- [ ] Real STT engine (not browser Web Speech API) — no diarization, flaky on iOS
- [ ] Meeting capture integration (Zoom/Meet/Teams, calendar-driven)
- [ ] Audio recording + playback
- [ ] Edit/delete proposals and transcripts
- [ ] Approval workflow before share (draft → review → publish)
- [ ] Branded PDF export
- [ ] Remove "Hey Clozr" toggle until Porcupine is actually integrated
- [ ] Accounts/login, multi-tenant isolation
- [ ] Stripe billing

### Deployment
- [ ] FastAPI + Caddy/nginx (not Python stdlib HTTP server)
- [ ] Environment-only secrets, fail-closed on missing
- [ ] `.env` confirmed in `.gitignore`
- [ ] CI: flutter analyze + flutter test + secret scanner (gitleaks)
- [ ] Real hosting (Fly.io/Render for backend, Cloudflare Pages for Flutter)

### Privacy
- [ ] Privacy policy + ToS in app
- [ ] Recording consent indicator in-meeting
- [ ] Data minimization (don't log IP/UA unless needed)
- [ ] Verify sub-processor data-use terms (Groq vs OpenRouter training policies)
- [ ] Encrypt transcripts at rest
- [ ] Deletion path (right to be forgotten)