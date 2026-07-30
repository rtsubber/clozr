# Clozr

### AI that writes your proposal before you hang up.

Clozr listens to your meetings in real time, detects the moment a deal is being discussed, and generates a polished, client-ready proposal the second the call ends — no manual drafting, no copy-paste, no lost momentum.

---

## ✨ Features

- **Real-time transcription** — Live speech-to-text with Deepgram + Groq Whisper for ultra-low-latency capture
- **Workflow detection** — AI identifies when a conversation shifts to pricing, scope, or deal-making
- **One-tap proposal generation** — Generate a structured, professional proposal from the meeting transcript with a single click
- **Google Calendar integration** — Auto-import meeting context, attendees, and scheduling
- **Multi-platform** — Flutter web + mobile (iOS/Android) from a single codebase
- **Secure auth** — JWT-based authentication with bcrypt password hashing
- **Stripe payments** — Live subscription management with webhook idempotency and tier enforcement

---

## 🏗️ Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter (web + mobile) |
| Backend | FastAPI (Python) |
| Database | SQLite |
| Transcription | Deepgram + Groq Whisper |
| LLM | Llama-3.3-70b (via Groq) |
| Payments | Stripe (live) |
| Calendar | Google Calendar API |

---

## 💰 Pricing

| Plan | Price | Includes |
|------|-------|----------|
| **Free** | $0 | 5 meetings/month |
| **Pro** | $19/mo | Unlimited meetings, full proposal export |
| **Business** | $39/mo | Team accounts, branding, priority processing |
| **Self-Hosted** | $79/mo | Full source access, on-premise deployment |

Payments are processed live via Stripe. Subscription tiers are enforced server-side with fingerprint-based free-tier limits.

---

## 🚀 Quick Start

### Prerequisites

- Python 3.10+
- Flutter 3.x
- A Groq API key
- A Deepgram API key
- A Stripe account (for payments)

### Backend Setup

```bash
cd backend
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env with your API keys

# Run the server
python run.py
```

The FastAPI backend starts on `http://localhost:8000` with interactive docs at `/docs`.

### Frontend Setup

```bash
cd web
flutter pub get
flutter run -d chrome   # or: flutter run -d <device>
```

### Environment Variables

All secrets are loaded from environment variables — never hardcoded. Key variables:

| Variable | Description |
|----------|-------------|
| `GROQ_API_KEY` | Groq API key for LLM inference |
| `DEEPGRAM_API_KEY` | Deepgram API key for transcription |
| `STRIPE_SECRET_KEY` | Stripe secret key for payments |
| `STRIPE_WEBHOOK_SECRET` | Stripe webhook signing secret |
| `CLOZR_FREE_MEETING_LIMIT` | Max free-tier meetings (default: 5) |
| `CLOZR_LOCALEYE_FP_URL` | Fingerprint service URL (optional) |

---

## 📁 Project Structure

```
clozr/
├── backend/
│   ├── main.py              # FastAPI app, models, endpoints
│   ├── run.py               # Server entry point
│   ├── proposal_api.py      # Proposal generation logic
│   └── requirements.txt
├── web/
│   ├── lib/                 # Flutter Dart source
│   ├── fingerprint.js       # Device fingerprint client
│   └── pubspec.yaml
├── .env.example             # Template for environment variables
└── README.md
```

---

## 🔒 Security

- **Auth**: JWT tokens with 24-hour expiry, bcrypt password hashing
- **Rate limiting**: Bounded rate limiters on public endpoints
- **Input validation**: Pydantic models with strict field validation
- **GDPR compliance**: Audio files deleted when meetings are deleted
- **Webhook idempotency**: Stripe events deduplicated by event ID
- **No hardcoded secrets**: All credentials loaded from environment variables

---

## 🌐 Links

- **Website**: [clozr.brandbooststudio.co](https://clozr.brandbooststudio.co)
- **GitHub**: [github.com/rtsubber/clozr](https://github.com/rtsubber/clozr)

---

## 📄 License

Proprietary. All rights reserved. See [LICENSE](LICENSE) for details.

---

_Built with ⚡ by the Clozr team._