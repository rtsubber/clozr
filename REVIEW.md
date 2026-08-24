# Clozr Backend Code Review

**File:** `backend/main.py` (2,181 lines) + `backend/stripe_payments.py` (295 lines)  
**Date:** 2026-06-07  
**Reviewer:** Jarvis (automated review)

---

## Summary

The codebase is generally well-structured with good security practices (SSRF protection, rate limiting, Pydantic validation, prompt injection defenses). However, there are several bugs, security concerns, and code quality issues that should be addressed before production deployment.

**Critical:** 3 | **High:** 7 | **Medium:** 10 | **Low:** 8

---

## Critical Issues

### C1. Catalog price formatting bug — `/mo` duplicated or empty (Line 759)

```python
f"- {c.name} ({c.category}): {c.monthly_cost}/mo — {c.description}"
```

This line **always appends `/mo`** to `monthly_cost`, but:

- If `monthly_cost` is `"$149/mo"` → displays as `"$149/mo/mo"` (duplicated)
- If `monthly_cost` is `"$149"` → displays as `"$149/mo"` (correct)
- If `monthly_cost` is `""` (empty) → displays as `"/mo"` (nonsensical)

Since the LLM prompt explicitly says "USE THESE EXACT PRICES — DO NOT INVENT PRICES", feeding it `"/mo"` or `"$149/mo/mo"` will corrupt the proposal generation pricing.

**Fix:** Smart formatting:
```python
def _fmt_cost(cost: str) -> str:
    if not cost or cost.lower() in ("custom", "n/a"):
        return "Custom pricing"
    return cost if "/mo" in cost.lower() else f"{cost}/mo"

catalog_text = "\n".join([
    f"- {c.name} ({c.category}): {_fmt_cost(c.monthly_cost)} — {c.description}" + ...
])
```

---

### C2. `undefined` logger — `logger` never defined (Line 935)

```python
logger.warning("Groq timed out, falling back to OpenRouter")
```

The module uses `logging.error(...)`, `logging.info(...)`, `logging.warning(...)` throughout (lines 64, 1005, 1021, 1057, 1152, etc.), but line 935 uses `logger.warning(...)` where `logger` is never defined. This will raise a `NameError` at runtime, crashing the timeout fallback path silently (the outer `except` catches it, but the fallback never executes).

**Fix:** Change `logger.warning(...)` to `logging.warning(...)` on line 935.

---

### C3. Stripe payments references columns not in Account model (stripe_payments.py, Lines 225-227, 246, 253, 256, 289-290)

`stripe_payments.py` writes to `account.tier`, `account.stripe_customer_id`, `account.stripe_subscription_id`, and `account.subscription_status`, but the `Account` model in `main.py` (lines 128-147) **does not define any of these columns**. This will cause `AttributeError` at runtime when any Stripe webhook fires.

The `Account` model only has: `id`, `email`, `password_hash`, `name`, `company`, `created_at`, `is_active`, `brand_name`, `brand_color`, `accent_color`.

**Fix:** Add the missing columns to the `Account` model:
```python
tier = Column(String(20), default="free")
stripe_customer_id = Column(String(100), default="")
stripe_subscription_id = Column(String(100), default="")
subscription_status = Column(String(20), default="")
```

---

## High Issues

### H1. Timeout fallback logic for multi-stage LLM calls is broken (Lines 925-942)

The `httpx.TimeoutException` handler attempts to fall back to OpenRouter, but:

1. It only catches the timeout for the **simple (1-stage) path** — the `generate_proposal` and `generate_followup` tasks have their own try/except inside the main `async with httpx.AsyncClient` block, which won't be caught by this outer handler.
2. Even for the simple path, the fallback code **immediately raises `HTTPException(504)`** inside the `try` block, so the fallback never actually executes — the `except:` bare clause just re-raises 504.
3. The comment admits "This won't re-execute the full multi-stage logic."

**Fix:** Refactor LLM calls into a helper function that handles fallback per-request, and call it for each stage independently. The current structure needs a `call_llm(messages, temperature, max_tokens)` helper that tries provider[0], then provider[1] on failure.

---

### H2. SSRF redirect handler is defined but never connected (Lines 1793-1797)

The `_ssrf_redirect_handler` function is defined but **never passed to the `httpx.AsyncClient`**. It's supposed to check redirect targets for private IPs, but without `event_hooks={"request": [_ssrf_redirect_handler]}` in the client constructor, it does nothing.

Furthermore, the function signature `async def _ssrf_redirect_handler(request) -> Response | None` returning `None` means "proceed with request" in httpx event hooks, but httpx doesn't use `event_hooks["request"]` for redirect interception — it uses `event_hooks["response"]` for that.

**Fix:** Either use httpx's `auth` or custom `transport` to intercept redirects, or check the final response URL after following redirects:
```python
resp = await client.get(url, ...)
if _is_private_url(str(resp.url)):
    raise HTTPException(400, "URL redirects to private address")
```

---

### H3. Rate limit race condition — non-atomic read-modify-write (Lines 371-396)

The `rate_limit()` function reads `_rate_limits[key]`, filters it, checks length, then appends. In an async context, multiple concurrent requests can all pass the check before any append, allowing bursts beyond the limit. With `await` points in the request handler, the GIL doesn't protect against interleaving.

**Fix:** Use `asyncio.Lock` for rate limit updates, or use an atomic sliding window (e.g., Redis with Lua scripts for distributed deployments).

---

### H4. Proposal view count race condition (Lines 1686-1688)

```python
proposal.views = (proposal.views or 0) + 1
proposal.last_viewed_at = datetime.now(timezone.utc)
db.commit()
```

Two concurrent view tracking requests can both read `views=0`, both write `views=1`, losing one count. This is a classic read-modify-write race.

**Fix:** Use SQL `UPDATE proposals SET views = views + 1 WHERE id = ?` via `db.execute()`.

---

### H5. Internal error details leaked in HTTP 500 responses (Lines 1058, 1269, 1918, 2087)

```python
raise HTTPException(500, f"Transcription failed: {str(e)}")
raise HTTPException(500, f"Import failed: {str(e)}")
raise HTTPException(500, f"Diarized transcription failed: {str(e)}")
```

These expose internal exception messages (file paths, library errors, etc.) to clients. An attacker can learn about the server's internal structure.

**Fix:** Log the full error server-side and return a generic message:
```python
logging.error(f"STT error: {e}", exc_info=True)
raise HTTPException(500, "Transcription failed. Please try again later.")
```

---

### H6. Catalog add endpoint uses raw `dict` — no validation (Lines 1728-1749)

```python
async def add_catalog_item(data: dict, ...):
    item = ServiceCatalogItem(
        id=data.get("id", uuid.uuid4().hex[:8]),
        name=data.get("name", ""),
        ...
    )
```

No Pydantic model, no field validation. Clients can inject arbitrary data, set `id` to predictable values (collision risk), or inject very long strings.

**Fix:** Create a Pydantic `CatalogItemCreate` model with field validation (max lengths, allowed characters for icon, etc.), similar to `ProposalCreate`.

---

### H7. `/api/catalog/import-url` and `/api/catalog/import-pdf` accept raw `dict` (Lines 1777, 1925)

Same issue as H6 — no Pydantic validation on the `data: dict` parameter for the URL import. While the URL is validated for SSRF, there's no max-length constraint on the URL string, no validation of other fields, etc.

**Fix:** Create Pydantic models for these endpoints.

---

## Medium Issues

### M1. JWT `exp` claim uses float timestamp instead of int (Line 337-338)

```python
expire = datetime.now(timezone.utc).timestamp() + (expires_hours * 3600)
to_encode.update({"exp": expire})
```

`python-jose` with the HS256 algorithm accepts float exp values, but some JWT libraries (and the JWT spec) expect integer timestamps. This could cause issues if tokens need to be verified by other systems.

**Fix:** Use `int(datetime.now(timezone.utc).timestamp()) + expires_hours * 3600`.

---

### M2. Fingerprint check endpoint not authenticated (Lines 1348-1385)

The `POST /api/fingerprint/check` endpoint requires `verify_token` (authenticated), but `GET /api/fingerprint/status` also requires it. The fingerprint hash (SHA-256, 64 chars) is validated, but the `action` field is only max_length=50 with no whitelist — any string is accepted and sent to Local-Eye.

**Fix:** Add an `@validator("action")` that restricts to known actions like `["free_meeting"]`.

---

### M3. Proposal GET is unauthenticated — intentional but risky (Lines 1573-1597)

The proposal view endpoint is public by design ("anyone with the link"), but returns `pain_points`, `solutions`, `executive_summary`, and pricing. The 16-character hex ID acts as an access token (64 bits of entropy), which is reasonable but should be documented. There's no rate limiting on this endpoint either, allowing enumeration attempts.

**Fix:** Add rate limiting to the public proposal endpoint. Consider adding `@app.get("/api/proposals/{proposal_id}", dependencies=[Depends(rate_limit_dependency)])`.

---

### M4. Meeting deletion doesn't remove audio file (Lines 1510-1522)

When a meeting is deleted, the associated audio file on disk (`meeting.audio_path`) is not removed. This causes storage leaks over time.

**Fix:** Delete the audio file before deleting the database record:
```python
if meeting.audio_path and Path(meeting.audio_path).exists():
    Path(meeting.audio_path).unlink(missing_ok=True)
```

---

### M5. STT audio file saved before validation of meeting ownership (Lines 1022-1032)

In the `/api/stt` endpoint, the audio file is written to disk **before** checking if the meeting exists and belongs to the user. If the meeting doesn't exist, the orphan audio file remains on disk.

**Fix:** Move the file save after validating the meeting, or add a cleanup mechanism for orphan files.

---

### M6. Deepgram STT audio file saved before meeting validation (Lines 1239-1268)

Same as M5 — the diarized audio file is saved to disk before checking if the meeting_id belongs to the account.

---

### M7. Local-Eye verify endpoint sends unvalidated `data: dict` to external API (Lines 1067-1088)

The `localeye_verify` endpoint takes a raw `dict` and passes `data.get("phone", "")` and `data.get("business_name", "")` directly to the Local-Eye API with no sanitization. No Pydantic model validation.

**Fix:** Create a Pydantic model with phone number regex validation and max-length constraints for business_name.

---

### M8. `/api/localeye/verify` doesn't use `LOCALEYE_API_KEY` (Lines 1073-1088)

The endpoint checks `LOCALEYE_API_KEY` exists (line 1069), but **never uses it** in the actual API calls. It uses a playground token obtained without authentication, and the `/v1/playground/phone-vet` call doesn't include the API key. This means the `LOCALEYE_API_KEY` check is a false gate — the playground API works without it.

**Fix:** Either use `LOCALEYE_API_KEY` in the request headers, or remove the check if the playground API is intentionally unauthenticated.

---

### M9. `import httpx` inside function bodies (Lines 779, 991, 1071, 1133)

`httpx` is already imported at the top of the file (line 10), but is re-imported inside several function bodies. This is harmless but unnecessary and adds confusion.

**Fix:** Remove the `import httpx` statements inside function bodies.

---

### M10. Provider fallback only retries once on rate limit (Lines 783-845)

For the 2-stage proposal generation, if the first provider returns 429 on Stage 1, it falls back to the second provider for Stage 1. But if it also falls back for Stage 1, **Stage 2 still uses the first provider's URL/model/headers variables** which were updated by the fallback. This works by accident (the fallback overwrites the variables), but if Stage 1 succeeds on provider 1 and Stage 2 fails with 429, the fallback for Stage 2 updates the local `url`, `model`, `headers` variables — but the next request (if there were a Stage 3) would use the wrong provider.

More importantly, for the simple 1-stage path (summarize/detect_workflows), if the first provider returns 429, it retries with the second provider, which is correct. But the Stage 2 fallback code duplicates logic that should be in a helper.

**Fix:** Extract a `call_llm(messages, temp, max_tokens)` helper that handles provider fallback.

---

## Low Issues

### L1. `MeetingCreate` allows 200KB transcript but LLM max is 50KB (Lines 262-277, 303-309)

`MeetingCreate` allows `transcript` up to 200,000 chars, but `LLMRequest` caps `transcript` at 50,000 chars. A transcript saved via `POST /api/meetings` at 150K chars would be accepted, but when sent to `/api/llm` it would be rejected. Inconsistency, not a bug per se.

**Fix:** Document this in API docs or add truncation in the LLM endpoint.

---

### L2. `uuid.uuid4().hex[:8]` for catalog items is only 8 hex chars (32 bits) (Line 1732)

```python
id=data.get("id", uuid.uuid4().hex[:8]),
```

8 hex characters = 32 bits of entropy ≈ 4 billion possibilities. For a low-volume catalog this is fine, but collision risk is non-zero at scale. Proposal IDs use 16 chars (64 bits).

**Fix:** Use at least 12 characters (48 bits) for better collision resistance, or use the full UUID.

---

### L3. `VALID_ID` regex allows 8-40 hex chars but proposals are 16 chars (Line 211)

```python
VALID_ID = re.compile(r"^[a-f0-9\-]{8,40}$")
```

This accepts any hex string 8-40 chars, including strings with hyphens in any position. It would match `abc----def` which isn't a valid UUID format. It's permissive enough to not break anything, but it's worth tightening.

**Fix:** If only UUIDs are expected: `r"^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$|^[a-f0-9]{16}$"`. Otherwise, leave as-is since it's just input validation.

---

### L4. `AccountCreate` doesn't validate email format (Lines 255-261)

The `AccountCreate` Pydantic model accepts any string as `email` with no format validation. A user could register with `email: "notanemail"`.

**Fix:** Use `EmailStr` from `pydantic[email]` or add a regex validator.

---

### L5. Password hashing uses bcrypt directly — no deprecation concern but no Argon2 option (Lines 329-341)

The code uses bcrypt directly, which is fine. However, the legacy SHA-256 fallback (lines 338-340) could be a security risk if an attacker downgrades the hash format. Since new passwords always use bcrypt, this is low risk.

**Fix:** Consider adding a migration path that upgrades legacy hashes on next successful login.

---

### L6. `/api/llm` response_format `json_object` may not be supported by all providers (Lines 792, 823, 860, 878, 900)

`response_format: {"type": "json_object"}` is an OpenAI/Groq feature. If falling back to OpenRouter with a model that doesn't support it, the request may fail.

**Fix:** Check provider/model capabilities before setting `response_format`, or handle the error gracefully.

---

### L7. `send_telegram_notification` uses `urllib.request` instead of `httpx` (Lines 575-584)

The function uses `urllib.request.urlopen` with a 5-second timeout. This is a synchronous call that blocks the event loop. In an async FastAPI handler, this blocks the server thread.

**Fix:** Use `httpx.AsyncClient` for the Telegram notification, or run it in a thread pool with `asyncio.to_thread()`.

---

### L8. No CORS origin validation for subdomains (Line 693)

```python
ALLOWED_ORIGINS = os.environ.get("CLOZR_ALLOWED_ORIGINS", 
    "http://localhost:8510,https://brandbooststudio.co,https://clozr.brandbooststudio.co").split(",")
```

This doesn't allow `www.brandbooststudio.co` or other subdomains. Also, if deploying to a different domain, the env var must be updated.

**Fix:** Consider using `CORSMiddleware` with `allow_origin_regex` for subdomain matching.

---

## Additional Notes

1. **Good patterns observed:** Prompt injection defense with `<transcript>` tags and system prompts, SSRF protection function, Pydantic validators for field injection prevention, JWT auth, rate limiting, WAL mode for SQLite, path traversal prevention in filenames.

2. **The SSRF `_is_private_url()` function (lines 56-82) is solid** — it resolves DNS and checks both IPv4 and IPv6 against private ranges. Good.

3. **The 2-stage proposal generation (Stage 1: extract, Stage 2: write)** is a good pattern for reducing hallucination, but the duplicated fallback logic makes maintenance hard. Refactor into a helper.

4. **Stripe webhook handler has no idempotency** — if a `checkout.session.completed` event is delivered twice, it writes the same data twice. This is mostly safe (idempotent writes) but should be verified.

5. **The `/api/proposals/{proposal_id}/viewed` endpoint (line 1666) has no rate limiting**, allowing view count inflation. Add `rate_limit(request, max_requests=10, window_seconds=60)`.

---

*Review complete. Prioritize C1 (catalog formatting), C2 (undefined logger), and C3 (missing DB columns) as they will cause runtime errors.*