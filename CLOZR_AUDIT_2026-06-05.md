# Clozr Comprehensive Audit Report

**Date:** 2025-06-05  
**Auditor:** Jarvis (AI assistant)  
**Version audited:** v0.2.x (FastAPI backend + Flutter web/mobile)  
**Prior reviews:** CLOZR_ASSESSMENT.md (v0.1), CLOZR_REVIEW.md (v0.1)

---

## Executive Summary

Since the v0.1 assessment, **massive improvements** have been made. The app has been rebuilt from scratch with a FastAPI + SQLite backend, JWT auth, provider proxying (keys server-side), input validation, and real Stripe integration. The previous critical issues (C1-C4, H1, H4, A1-A3) are **all resolved**. However, new code introduces new risks, and several product/UX gaps remain before this is ready for paying customers.

**Bottom line:** The app is now a credible MVP with real auth, real backend, real payments, and real transcription. It needs: (1) security hardening of remaining gaps, (2) mobile recording to actually work, (3) better error resilience for the meeting flow, and (4) competitive feature parity on basics before launch.

---

## 1. CRITICAL Issues (Must Fix Before Demo/Launch)

### C5 — Password Hashing is Weak (SHA-256 with salt)

**File:** `backend/main.py` → `hash_password()` / `verify_password()`

```python
salt = secrets.token_hex(16)
hashed = hashlib.sha256(f"{salt}:{password}".encode()).hexdigest()
```

SHA-256 is not suitable for password hashing — it's fast, making brute-force attacks trivial. An attacker who gets the DB can crack passwords at billions/second with a GPU.

**Fix:** Use `bcrypt` or `argon2-cffi`. These are deliberately slow (intentional) and are the industry standard. Adding `bcrypt` is a one-line change:
```python
import bcrypt
def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode(), bcrypt.gensalt()).decode()
def verify_password(password: str, stored_hash: str) -> bool:
    return bcrypt.checkpw(password.encode(), stored_hash.encode())
```

**Severity:** Critical — this is a real attack surface if the DB leaks.

---

### C6 — JWT Secret Has a Fallback Default

**File:** `backend/main.py` lines ~30-35

```python
JWT_SECRET = os.environ.get("CLOZR_JWT_SECRET", "")
# ...
def create_access_token(data: dict, expires_hours: int = 24) -> str:
    secret = JWT_SECRET or "dev-ephemeral-key-change-in-production"
```

The app refuses to start without `CLOZR_JWT_SECRET` (good — the startup check catches this). BUT inside `create_access_token` and `verify_token`, there's a fallback to `"dev-ephemeral-key-change-in-production"`. If the startup check is ever bypassed (e.g., someone comments it out for debugging), tokens are signed with a known string — full auth bypass.

**Fix:** Remove the fallback. If `JWT_SECRET` is empty, raise an exception:
```python
def create_access_token(data: dict, expires_hours: int = 24) -> str:
    if not JWT_SECRET:
        raise ValueError("CLOZR_JWT_SECRET not set")
    ...
```

Same for `verify_token`. The startup check is good defense-in-depth, but the fallback undermines it.

---

### C7 — Stripe Webhook Handler Opens Raw SQLite Connection (Inconsistent DB Access)

**File:** `backend/stripe_payments.py`

The Stripe webhook handler and portal endpoint open raw `sqlite3.connect()` connections instead of using the SQLAlchemy `SessionLocal` that the rest of the app uses. This:
- Bypasses WAL mode pragma (set in the main app's event listener)
- Bypasses foreign key enforcement
- Creates connection management inconsistencies
- Could cause database locking issues under concurrent access

```python
import sqlite3
db_path = os.path.join(os.path.dirname(__file__), "clozr.db")
conn = sqlite3.connect(db_path)
```

**Fix:** Refactor Stripe handlers to use `get_db()` dependency injection like every other endpoint, or at minimum create a shared DB utility.

---

### C8 — Proposal View Endpoint is Unauthenticated (Intentional, but Lacks Rate Limiting)

**File:** `backend/main.py` → `GET /api/proposals/{proposal_id}`

The proposal view endpoint is intentionally public (shareable links), which is correct. However:
- 8-character hex IDs (`uuid4()[:8]`) provide only ~4 billion possible IDs. This is scrapable.
- No rate limiting on the public view endpoint.
- The `/viewed` tracking endpoint also lacks rate limiting.

**Fix:** 
- Increase proposal ID length to at least 16 characters.
- Add rate limiting to the public proposal view endpoint.
- Consider adding a slug or UUID prefix for better entropy.

---

### C9 — Meeting Create/Update Accepts Unvalidated Dict Input

**File:** `backend/main.py` → `POST /api/meetings`

```python
@app.post("/api/meetings")
async def create_meeting(data: dict, ...):
```

The meeting creation endpoint accepts a raw `dict` with no Pydantic validation. While it only uses known keys (`title`, `transcript`, etc.), this is inconsistent with the validated `ProposalCreate` model and leaves the door open for field injection or unexpected data.

**Fix:** Create a `MeetingCreate` Pydantic model with validated fields, matching the pattern used for proposals.

---

### C10 — Audio File Path Not Validated (Potential Path Traversal)

**File:** `backend/main.py` → `POST /api/meetings`

```python
audio_filename = data.get("audio_filename")
if audio_filename:
    audio_path = AUDIO_DIR / audio_filename
    if audio_path.exists():
        meeting.audio_path = str(audio_path)
```

The `audio_filename` comes from client input and is used directly in a path. While `AUDIO_DIR / audio_filename` limits the scope somewhat, a crafted filename like `../../../etc/passwd` could potentially escape `AUDIO_DIR` on some Python versions.

**Fix:** Validate the filename: ensure it matches `^[a-zA-Z0-9_\-\.]+$` and doesn't contain path separators.

---

## 2. HIGH Priority Issues (Should Fix Soon)

### H5 — No Password Reset or Email Verification

Users register with email + password but there's no:
- Password reset flow
- Email verification
- Account lockout after failed attempts (only rate limiting at 5/5min)
- Password strength requirements beyond "min 8 chars"

**Fix:** Add password reset (send token via email), email verification on signup, and account lockout after N failures.

---

### H6 — No Token Refresh or Logout Endpoint

- JWT tokens expire after 24 hours with no refresh mechanism.
- No logout endpoint (tokens remain valid until expiry).
- No token revocation mechanism.

If a token is compromised, there's no way to invalidate it.

**Fix:** Add a `/api/auth/refresh` endpoint and consider a token blacklist for logout.

---

### H7 — Flutter Web Audio Recording is Fragile

**Files:** `stt_recorder.dart`, `js_interop_web.dart`

The web recording implementation:
- Uses polling (100ms intervals × up to 15 seconds) to check if `getUserMedia` succeeded. This is brittle.
- Uses `btoa(String.fromCharCode.apply(null, new Uint8Array(...)))` for binary data transfer, which fails for bytes ≥ 128 in some browsers (WebM/Opus uses full 0-255 range).
- The `base64` approach is correct but the `String.fromCharCode` path is unreliable for binary audio.
- `MediaRecorder.isTypeSupported()` check exists but falls back to empty options silently.
- No pause/resume support for recording.

**Fix:**
- Use `FileReader.readAsDataURL()` or `Array.from()` + `Uint8Array` for reliable binary transfer.
- Add pause/resume buttons to the UI.
- Consider using a proper audio library for web (e.g., `Record` package) that handles these edge cases.

---

### H8 — No Offline/Error State Handling in Flutter

Multiple screens assume the backend is always reachable:
- `MeetingStorage.loadAll()` silently returns `[]` on error — the home screen shows "No meetings yet" instead of "Can't connect to server."
- `CatalogStorage.load()` falls back to defaults on any error, even auth errors.
- `LLMService` throws exceptions that are caught with generic error messages.
- No retry logic, no exponential backoff, no "retry" button on failure states.

**Fix:** Add proper error states to each screen:
- Home screen: show "Connection error" with retry button
- Meeting screen: show specific errors (auth expired, network, server)
- Proposal screen: add retry on LLM failure

---

### H9 — Rate Limiter is In-Memory and Per-Process

**File:** `backend/main.py` → `_rate_limits`

```python
_rate_limits: dict[str, list] = {}
```

This is a simple in-memory dict that:
- Resets on every server restart
- Doesn't work across multiple worker processes (uvicorn with `--workers > 1`)
- Could grow unbounded (no cleanup of old IPs)

**Fix:** Use a proper rate limiting solution:
- `slowapi` (uses in-memory + supports Redis)
- Or at minimum, add periodic cleanup and consider file-based persistence

---

### H10 — Stripe Integration Has Edge Cases

**File:** `backend/stripe_payments.py`

Issues:
- Portal endpoint creates a new `sqlite3` connection per call (see C7).
- No idempotency handling for webhook events (duplicate `checkout.session.completed` could double-update).
- `invoice.payment_failed` is a no-op — should at minimum log and potentially notify the user.
- No handling for `customer.subscription.trial_will_end` — should notify user.
- Price IDs are hardcoded as defaults — fragile if Stripe products change.

**Fix:** Add idempotency keys (store processed event IDs), handle all subscription lifecycle events, and move price IDs to environment variables only (no defaults).

---

### H11 — Proposal Screen Sends Raw `current_pain_points` as List (Type Mismatch)

**File:** `proposal_screen.dart` → `_shareProposal()`

```dart
'current_pain_points': _proposal!.painPoints.map((p) => p.description).toList(),
```

This sends pain points as a `List<String>` (just descriptions), but the backend `ProposalCreate` Pydantic model expects `pain_points: list[str]` — which matches. However, `proposed_solutions` is sent as a list of maps, and the backend validates each solution dict with specific fields. If the LLM generates unexpected fields, they get silently truncated by the validator (which is correct), but the client doesn't get feedback about truncation.

**Minor issue** — works correctly as-is, but worth noting for consistency.

---

### H12 — `ApiKeys` Class Still Exists (Legacy)

**File:** `lib/services/api_keys.dart`

This class stores Groq, OpenRouter, and Local-Eye API keys in SharedPreferences. While the app now proxies through the backend (so these keys aren't used), the class still exists and could confuse future development. It's dead code.

**Fix:** Remove `api_keys.dart` and any references to it.

---

## 3. MEDIUM Priority (UX Improvements, Polish)

### M5 — No Pause/Resume During Recording

The meeting screen has a single Start/Stop button. There's no way to:
- Pause recording (e.g., for a break)
- Resume after pausing
- Mark sections of the meeting

This is a significant UX gap. Competitors like Otter.ai support pause/resume.

**Fix:** Add a pause button that stops the MediaRecorder and a resume button that restarts it, appending to the existing recording.

---

### M6 — No Manual Transcript Entry

Users can only create meetings by recording. There's no way to:
- Paste a transcript from an external source (e.g., Zoom, Teams)
- Import a transcript from a file
- Edit a transcript after recording

This limits the product to live in-person meetings only.

**Fix:** Add a "Paste Transcript" option on the meeting screen and a way to import from file.

---

### M7 — No Meeting Search or Filter

The home screen shows the last 50 meetings with no search or filter. As users accumulate meetings, finding a specific one becomes difficult.

**Fix:** Add a search bar (by title/transcript content) and date/category filters.

---

### M8 — No Calendar Integration

The app has no calendar integration. Users can't:
- See upcoming meetings
- Auto-join scheduled meetings
- Link meeting records to calendar events

This is table-stakes for competitors (Otter, Fireflies, Fathom all do this).

**Fix:** Add CalDAV/Google Calendar integration for meeting scheduling and linking.

---

### M9 — Follow-Up Email Has No Edit/Send Capability

The follow-up email screen generates an email but only offers "Copy to Clipboard." There's no:
- Edit capability for the generated email
- Direct send via email client
- Template customization
- History of sent emails

**Fix:** Add an editable text field and a "Open in Mail" button that launches the device email client with pre-filled content.

---

### M10 — Proposal View is Read-Only (No Edit Before Sharing)

Proposals are generated by the LLM and shared immediately. Users can't:
- Edit the generated proposal before sharing
- Adjust pricing or timelines
- Remove sections they don't want
- Change the client name

The "Review Before Sending" section flags open questions, but there's no UI to resolve them.

**Fix:** Make the proposal editable before publishing. Add an "Edit" mode with text fields for each section.

---

### M11 — Audio Playback Doesn't Work Reliably on Mobile

**File:** `meeting_screen.dart` → `_toggleAudioPlayback()`

The audio playback code has two paths:
- **Web:** Uses `evalJs()` to inject an HTML5 audio player that fetches with auth headers. This works but is fragile — it creates DOM elements that are never cleaned up, and there's no progress indicator.
- **Mobile:** Downloads the entire audio file to a temp path and plays it with `audioplayers`. This could use significant storage for long meetings.

**Fix:** Use a proper streaming audio solution. For mobile, consider using a cached audio player. For web, add proper audio element management with cleanup.

---

### M12 — Home Screen Calls `_loadMeetings()` on Every Build

**File:** `home_screen.dart`

```dart
WidgetsBinding.instance.addPostFrameCallback((_) => _loadMeetings());
```

This is inside `build()`, so `_loadMeetings()` is called on EVERY rebuild (e.g., when returning from a meeting, or any state change). This causes unnecessary network requests.

**Fix:** Use `initState()` or a more targeted refresh approach (e.g., only reload when explicitly needed).

---

### M13 — Settings Screen Shows "Backend: " When Backend URL is Empty

**File:** `settings_screen.dart`

```dart
_infoRow(Icons.dns_outlined, 'Backend', AppConfig.backendUrl),
```

When `backendUrl` is empty (same-origin deployment), this shows "Backend: " with nothing after it. Not helpful.

**Fix:** Show "Same origin" or the detected base path when the URL is empty.

---

### M14 — Seed Script Has Hardcoded Default Password

**File:** `backend/seed.py`

```python
password = os.environ.get("CLOZR_ADMIN_PASSWORD", "changeme123")
```

The default password is weak and predictable. If someone runs the seed script without setting the env var, they get an insecure admin account.

**Fix:** Generate a random password if not provided, and print it to stdout.

---

### M15 — No CORS Preflight Handling for Multipart Endpoints

The `POST /api/stt` and `POST /api/stt/diarize` endpoints accept multipart form data. If the Flutter app is running on a different origin than the backend (dev mode), CORS preflight requests may fail for multipart content types.

The FastAPI CORSMiddleware should handle this, but it's worth verifying that `allow_headers=["Authorization", "Content-Type"]` is sufficient for multipart uploads. Some browsers send a preflight with an `Access-Control-Request-Headers` that includes additional headers.

**Fix:** Test cross-origin STT uploads in development and ensure the CORS middleware allows the necessary headers.

---

## 4. Competitive Feature Gaps

Based on comparison with Otter.ai, Fireflies.ai, Fathom, and tl;dv:

### Must-Have for Launch (Table Stakes)

| Feature | Clozr | Otter | Fireflies | Fathom |
|---------|-------|-------|-----------|--------|
| Speaker Diarization | ✅ Deepgram | ✅ | ✅ | ✅ |
| Meeting Recording | ✅ (browser) | ✅ | ✅ | ✅ |
| AI Summary | ✅ | ✅ | ✅ | ✅ |
| Calendar Integration | ❌ | ✅ | ✅ | ✅ |
| Zoom/Meet/Teams Bot | ❌ | ✅ | ✅ | ✅ |
| Transcript Search | ❌ | ✅ | ✅ | ✅ |
| Transcript Editing | ❌ | ✅ | ✅ | ✅ |
| Mobile App (native) | ⚠️ Flutter | ✅ | ✅ | ✅ |
| Pause/Resume Recording | ❌ | ✅ | ✅ | ✅ |

### Differentiators (Where Clozr Wins)

| Feature | Clozr | Competitors |
|---------|-------|-------------|
| **Auto-Proposals from Meetings** | ✅ Best-in-class | ❌ None do this |
| **Service Catalog Integration** | ✅ Matches proposals to your services | ❌ |
| **Branded Proposals** | ✅ Per-tenant branding | ❌ |
| **ROI Calculator** | ✅ Data-driven from catalog | ❌ |
| **Follow-Up Email Generation** | ✅ Context-aware | ❌ Partial |
| **Speaker Renaming** | ✅ Edit speaker labels | ✅ (some) |
| **Custom Service Detection** | ✅ Detects from your catalog | ❌ |

### Should-Have for Growth

| Feature | Priority | Notes |
|---------|----------|-------|
| **CRM Integration** (HubSpot, Salesforce) | High | Natural fit for proposal tool |
| **Meeting Templates** | Medium | Reusable meeting types |
| **Team Features** | Medium | Multi-user accounts, shared proposals |
| **Action Items / Task Extraction** | Medium | AI-detected tasks with assignments |
| **Proposal Analytics** | Medium | View counts, time spent, section engagement |
| **Export (PDF, Email)** | Medium | Currently clipboard-only |
| **Transcript Import** | High | Paste or upload transcripts |
| **Meeting Notes** | Medium | Manual annotations during recording |
| **Keyword/Topic Search** | Medium | Search across all meetings |
| **Video Meeting Bot** | High | Auto-join Zoom/Meet/Teams |

---

## 5. Architecture Assessment

### What's Working Well

1. **Server-side API keys** — The A1 fix is properly implemented. All LLM/STT calls go through the backend with JWT auth. No keys in the browser.

2. **SQLAlchemy + SQLite with WAL** — Proper database with foreign keys, WAL mode for concurrent reads, and proper ORM models.

3. **Pydantic validation** — Proposal endpoints use validated models with field constraints.

4. **Rate limiting** — Present on all endpoints (though in-memory, see H9).

5. **Prompt injection defense** — Transcripts are wrapped in `<transcript>` tags with explicit system instructions to ignore embedded commands. Two-stage proposal generation (extract → generate) provides additional isolation.

6. **Stripe integration** — Proper checkout flow, customer portal, and webhook handling.

7. **2-stage proposal generation** — The extraction-then-generation pipeline produces better proposals than single-prompt approaches.

8. **Diarization via Deepgram** — Speaker labeling is a real differentiator, well-implemented with rename capability.

9. **Per-tenant branding** — Each account has brand_name, brand_color, accent_color.

10. **Privacy-conscious view tracking** — Only device_type and referrer_domain are tracked (no IP/UA).

### What Needs Improvement

1. **Database access consistency** — Stripe handlers use raw sqlite3 instead of SQLAlchemy.

2. **Error propagation** — Frontend still has too many `catch (_) {}` silent failures.

3. **State management** — Still mixing `setState` with Riverpod. Some state (like the auth provider) is in Riverpod, but most screen state is local `setState`.

4. **Test coverage** — Zero tests beyond the default Flutter widget test. No backend tests either.

5. **Logging** — Backend has request logging but minimal error logging. Frontend has none.

---

## 6. Security Summary

| Issue | From v0.1 | Status |
|-------|-----------|--------|
| C1: Telegram token in source | CRITICAL | ✅ Fixed (env var, no fallback) |
| C2: Unauth Proposal API | CRITICAL | ✅ Fixed (JWT auth on all endpoints) |
| C3: Path traversal | CRITICAL | ✅ Fixed (regex validation on IDs) |
| C4: Field injection | CRITICAL | ✅ Fixed (Pydantic whitelist models) |
| H1: API keys in localStorage | HIGH | ✅ Fixed (server-side proxy) |
| H2: Prompt injection | HIGH | ✅ Mitigated (delimiters + system instructions) |
| H3: Data to 3rd parties no consent | HIGH | ⚠️ Partial (no consent UI yet) |
| H4: Race conditions | HIGH | ✅ Fixed (SQLite WAL + ORM) |
| C5: Weak password hashing | NEW | 🔴 Must fix |
| C6: JWT fallback secret | NEW | 🔴 Must fix |
| C7: Raw SQLite in Stripe | NEW | 🟡 Should fix |
| C8: Short proposal IDs | NEW | 🟡 Should fix |
| C9: Unvalidated meeting create | NEW | 🟡 Should fix |
| C10: Audio path traversal | NEW | 🟡 Should fix |

**Overall security posture: Vastly improved from v0.1.** The critical issues from the first audit are all resolved. The new issues (C5, C6) are important but straightforward fixes.

---

## 7. Priority Fix Order

### Before Any Customer Demo
1. ✅ C5: Switch to bcrypt password hashing
2. ✅ C6: Remove JWT secret fallback
3. ✅ C10: Validate audio filenames
4. ✅ C9: Add Pydantic model for meeting creation
5. ✅ H8: Add proper error states to Flutter screens

### Before Paid Launch
6. H5: Password reset + email verification
7. H6: Token refresh mechanism
8. C7: Refactor Stripe handlers to use SQLAlchemy
9. C8: Increase proposal ID length to 16+ chars
10. H10: Stripe idempotency and event handling
11. H7: Fix web audio binary transfer
12. M5: Add pause/resume recording

### Before Scale
13. H9: Proper rate limiting (Redis-backed)
14. M6: Transcript import (paste/file)
15. M7: Meeting search
16. M10: Editable proposals
17. M9: Editable follow-up emails
18. M14: Remove default password from seed script

---

## 8. Feature Roadmap Recommendations

### Phase 1: Launch-Ready (2-3 weeks)
- Fix C5, C6, C9, C10 (security)
- Add pause/resume recording
- Add transcript import (paste)
- Add proposal editing before sharing
- Add "Open in Mail" for follow-up emails
- Add password reset flow
- Add error/retry states to all screens

### Phase 2: Competitive Parity (4-6 weeks)
- Calendar integration (Google Calendar via CalDAV)
- Transcript search across meetings
- Transcript editing after recording
- PDF export for proposals
- Mobile-native audio recording (not just web)
- Meeting notes / annotations
- CRM integration (HubSpot first)

### Phase 3: Growth (8-12 weeks)
- Zoom/Meet/Teams bot for auto-join
- Team features (shared workspace, proposals)
- Action items extraction
- Proposal analytics dashboard
- Custom proposal templates
- Branded proposal pages (custom domains)
- White-label / reseller functionality

---

## 9. Code Quality Notes

### Good Patterns
- Proper separation of concerns (services, models, screens)
- Backend proxy pattern eliminates client-side API keys
- Two-stage LLM prompts for better proposal quality
- Pydantic validation on sensitive endpoints
- Proper auth flow with JWT
- Rate limiting on all endpoints
- Privacy-conscious view tracking

### Patterns to Improve
- **Silent error swallowing** — Multiple `catch (_) { return []; }` and `catch (_) {}` patterns. At minimum, log errors. Ideally, surface them to users.
- **Inconsistent state management** — Mix of Riverpod providers and local `setState`. Should standardize on Riverpod for shared state.
- **Dead code** — `ApiKeys` class, `wakeWordEnabled` toggle (not functional), old `GroqSTTService` references
- **Hardcoded strings** — Brand name "The Clozr" appears in multiple places instead of using the account's `brand_name`
- **No loading states on some operations** — Some API calls have no visual feedback during loading
- **Meeting storage double-write** — `_saveMeetingToBackend()` and `MeetingStorage.save()` both save the same meeting, potentially creating duplicates

---

## 10. Testing Recommendations

### Backend Tests Needed
- Auth flow (register, login, token expiry)
- Proposal CRUD (create, read, update, delete, publish)
- Meeting CRUD with auth isolation
- Stripe webhook handling
- Rate limiting
- Input validation (path traversal, XSS, injection)
- LLM proxy with mock responses

### Frontend Tests Needed
- Auth flow (login, logout, token refresh)
- Meeting recording lifecycle
- Proposal generation and sharing
- Error states (network failure, auth expiry, server error)
- Offline behavior

### Integration Tests
- Full meeting flow: record → transcribe → summarize → detect workflows → generate proposal → share
- Stripe checkout → webhook → subscription update flow
- Proposal share → view tracking → notification

---

*End of audit report. This represents a thorough review of the Clozr codebase as of 2026-06-05.*