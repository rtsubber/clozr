# Jarvis Meeting App

## Setup (Development)

```bash
# 1. Install Flutter (if not already)
export PATH="$HOME/flutter/bin:$PATH"

# 2. Get dependencies
cd apps/jarvis_meeting_app
flutter pub get

# 3. Copy env file and add your API keys
cp .env.example .env

# 4. Run on simulator/device
flutter run
```

## iOS Build (No Mac Required)

This project uses **Codemagic** for cloud iOS builds:

1. Push code to GitHub
2. Connect repo to [codemagic.io](https://codemagic.io)
3. Codemagic builds the IPA in the cloud
4. Distribute via TestFlight

### Codemagic Setup
- Sign up at codemagic.io
- Connect your GitHub repo
- Add environment variables: GROQ_API_KEY, OPENROUTER_API_KEY
- Set iOS provisioning profile
- Build & distribute to TestFlight

## Architecture

```
User taps "Start Meeting"
    ↓
Audio recorded → Groq Whisper (real-time STT)
    ↓
Transcript streams to UI
    ↓
Every 10s: transcript chunk → LLM analysis
    ↓
LLM detects workflows → matched against automation catalog
    ↓
"Hey Jarvis, prepare the proposal"
    ↓
LLM generates one-page proposal from meeting data
    ↓
Share via AirDrop / email / text
```

## API Keys Needed

| Service | Purpose | Free Tier |
|---------|---------|-----------|
| Groq | Real-time STT (Whisper) + LLM | Yes (generous limits) |
| OpenRouter | Fallback LLM | Yes |
| Local-Eye | Business verification | Yes (5 checks/tokens) |
| Porcupine | "Hey Jarvis" wake word | Yes (100/month) |