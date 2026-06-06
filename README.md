# Jarvis Meeting App

AI-powered meeting assistant for iOS — listens, transcribes, detects automatable workflows, and generates proposals in real-time.

## Features
- 🎙️ Real-time meeting transcription (Groq Whisper)
- 📝 Auto-extracted notes & action items
- 🔍 Workflow detection ("I check reviews every day" → automatable)
- 📊 Live business data (Local-Eye verification, SEO scores)
- 📋 One-tap proposal generation
- 🔑 Wake word: "Hey Jarvis" (Porcupine)
- 📅 Google Calendar integration

## Tech Stack
- **Flutter** (cross-platform, iOS-first)
- **Groq Whisper** (real-time STT)
- **OpenRouter/Groq LLM** (analysis & summaries)
- **Porcupine** (wake word detection)
- **Local-Eye API** (business verification)
- **Google Calendar API** (meeting context)

## Build & Deploy
iOS builds via Codemagic CI/CD (no Mac required).
TestFlight distribution.

## Architecture
```
lib/
├── main.dart              # App entry point
├── screens/
│   ├── home_screen.dart   # Meeting list & quick start
│   ├── meeting_screen.dart # Live transcription + analysis
│   ├── proposal_screen.dart # Generated proposals
│   └── settings_screen.dart # API keys, wake word config
├── services/
│   ├── audio_service.dart  # Mic capture & audio processing
│   ├── stt_service.dart    # Groq Whisper transcription
│   ├── llm_service.dart    # LLM analysis & summaries
│   ├── workflow_service.dart # Detect automatable workflows
│   ├── localeye_service.dart # Business verification lookups
│   └── calendar_service.dart # Google Calendar
├── models/
│   ├── meeting.dart        # Meeting data model
│   ├── workflow.dart       # Detected workflow model
│   └── proposal.dart       # Generated proposal model
└── widgets/
    ├── transcript_widget.dart # Real-time transcript display
    ├── workflow_card.dart    # Detected workflow card
    └── proposal_card.dart    # Proposal preview card
```