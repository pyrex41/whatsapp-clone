# GlobalBridge (WhatsApp‑style Messaging) – Monorepo

Realtime chat with AI assistance. This repository contains:

- A Phoenix/Elixir backend with Channels, offline‑first sync, and AI features.
- A cross‑platform Expo (React Native) client wired to the backend. Status: MVP stub, WIP.
- A native iOS Swift app (production ready).
- An Elm client previously experimented with has been scrapped (kept only for historical reference).
- An F# client effort exists as an MVP stub and is WIP (tracked separately from this folder layout).
- Extensive docs and Task Master AI project automation.

The codebase has been evolving under the “GlobalBridge” name; the repository origin reflects an earlier WhatsApp‑clone effort. This README ties the moving pieces together and gives you a single, reliable starting point.

---

## Contents

- Overview
- Architecture
- Prerequisites
- Quick Start (2 terminals)
- Environment Variables
- Project Structure
- Development Tasks (tests, lint, e2e)
- AI Features
- Troubleshooting
- Useful Docs

---

## Overview

GlobalBridge is a WhatsApp‑style messaging platform featuring:

- Realtime messaging over Phoenix Channels with presence, typing, read receipts, edits, deletes, and attachments.
- Offline‑first sync via change data capture (CDC) with websocket fallback to REST.
- AI capabilities: translation with cultural context, conversation summarization (RAG), semantic search, and task extraction.
- Authentication via email/password and optional Auth0 SSO.

Primary components:

- Backend (Phoenix/Elixir): `globalbridge_backend`
- Expo client (React Native): `clients/globalbridge-expo` (MVP stub, WIP)
- Native iOS client (Swift): `clients/ios/GlobalBridge`
- Elm client: previously explored and now scrapped (`clients/elm-client` remains for reference only)
- F# client: MVP stub, WIP (lives outside this directory layout)

---

## Architecture

- Phoenix Channels provide realtime topics: `thread:*` and `user:*`.
- REST API lives under `/api` (client default base: `http://localhost:4000/api`).
- Per‑thread SQLite databases for message storage and vector search; sqlite‑vec powers semantic search.
- AI subsystem uses a multi‑agent orchestration (Agens) with provider routing (OpenAI/Groq/XAI) and caching.

See also:

- Backend overview: `BACKEND_OVERVIEW.md`
- Backend README: `globalbridge_backend/README.md`
- Expo client README: `clients/globalbridge-expo/README.md`

---

## Prerequisites

- Elixir ≥ 1.15 and Erlang/OTP suitable for Phoenix 1.8
- Node.js 18+ and npm (Expo client)
- Xcode (iOS) and/or Android SDKs (optional, for device simulators)
- SQLite with sqlite‑vec extension for AI vector search

Install sqlite‑vec and set `SQLITE_VEC_PATH` per `docs/SQLITE_VEC_SETUP.md`.

---

## Quick Start (2 terminals)

This launches the backend on port 4000 and the Expo app pointing at it.

1) Terminal A – Backend

```bash
# From repo root
./start_backend.sh
# or manual
cd globalbridge_backend && mix setup && mix phx.server
```

2) Terminal B – Expo client

```bash
cd clients/globalbridge-expo
npm install --legacy-peer-deps

# Choose one depending on your simulator/device
npm run dev:ios       # iOS Simulator on same Mac (API → 127.0.0.1:4000)
npm run dev:android   # Android emulator (API → 10.0.2.2:4000)
npm run dev:tunnel    # Physical device via Expo tunnel
```

Expo uses `EXPO_PUBLIC_API_URL` at runtime (see `clients/globalbridge-expo/app.config.ts`). Defaults to `http://localhost:4000/api`.

Auth0 SSO is optional; without it you can use the legacy email/password flow. To enable SSO, set the Expo `EXPO_PUBLIC_AUTH0_*` variables and configure callbacks as described in the client README.

---

## Environment Variables

Top‑level example: `.env.example` (provider keys, Auth0). Component‑specific samples:

- Backend: `globalbridge_backend/.env.example`
- Expo: `clients/globalbridge-expo/.env.example`

Key settings (backend):

```bash
# Required for vector search (see docs/SQLITE_VEC_SETUP.md)
SQLITE_VEC_PATH=/opt/homebrew/lib/vec0.dylib   # macOS path example

# AI provider keys (enable what you use)
OPENAI_API_KEY=...
GROQ_API_KEY=...
XAI_API_KEY=...
ANTHROPIC_API_KEY=...

# Optional model hints
OPENAI_MODEL=llama-3.1-70b-versatile
TRANSLATION_MODEL=llama-3.1-8b-instant
SUMMARIZER_MODEL=grok-4-fast-non-reasoning
```

Key settings (expo client):

```bash
EXPO_PUBLIC_API_URL=http://localhost:4000/api
EXPO_PUBLIC_AUTH0_DOMAIN=your-tenant.us.auth0.com
EXPO_PUBLIC_AUTH0_CLIENT_ID=your-client-id
EXPO_PUBLIC_AUTH0_AUDIENCE=https://globalbridge-api
```

---

## Project Structure

```
.
├── globalbridge_backend/            # Phoenix backend (Channels, REST, AI)
│   ├── lib/globalbridge_backend_web/channels/thread_channel.ex
│   ├── README.md
│   └── docs/                        # Backend docs (AI, caching, rate limits, etc.)
├── clients/
│   ├── globalbridge-expo/           # Expo RN app (typed routes)
│   │   ├── app/ (expo-router)
│   │   ├── src/api/ (REST client, schemas)
│   │   ├── src/services/realtime-service.ts (Phoenix Channels client)
│   │   └── README.md
│   ├── ios/GlobalBridge/            # Native iOS app (Swift, production ready)
│   └── elm-client/                  # Experimental Elm client
├── docs/                            # Cross-cutting docs (Auth0, sync, AI, etc.)
└── start_backend.sh                 # Convenience launcher for the backend
```

---

## Development Tasks

Backend (from `globalbridge_backend`):

- Install deps: `mix setup`
- Run: `mix phx.server`
- Tests: `mix test` (see `globalbridge_backend/test`)
- Format/Lint: `mix format`, `mix credo`, `mix dialyzer`
- Seed sample data: `elixir seed_test_data.exs`

Expo client (from `clients/globalbridge-expo`):

- Install deps: `npm install --legacy-peer-deps`
- Type check: `npm run typecheck`
- Lint: `npm run lint`
- Unit tests (Vitest): `npm test`
- E2E (Detox): `npm run e2e:ios` or `npm run e2e:android`

Native iOS (from `clients/ios/GlobalBridge`): open the Xcode project and follow docs under `clients/ios/docs`.

---

## AI Features

The backend exposes validated AI endpoints under `/api/ai/*`, including:

- `POST /api/ai/translate` – cultural‑aware translation with confidence
- `POST /api/ai/analyze_tone`
- `POST /api/ai/summarize_thread` – RAG with sqlite‑vec
- `POST /api/ai/search_semantic` – semantic search
- `POST /api/ai/extract_tasks` – tasks, deadlines, decisions extraction
- `POST /api/ai/vec_health` – vector health check per thread

Notes:

- sqlite‑vec is required for vector operations. Set `SQLITE_VEC_PATH` before starting the backend.
- Provider routing and cost controls are documented in `globalbridge_backend/docs/AI_MODEL_CONFIGURATION.md` and `.../COST_TRACKING.md`.

---

## Troubleshooting

- Expo app can’t reach API:
  - Ensure backend is running on `http://localhost:4000`.
  - For Android emulator use `http://10.0.2.2:4000/api`.
  - For physical devices use your LAN IP or `npm run dev:tunnel`.
- Websocket auth failures:
  - Confirm your JWT or Auth0 settings. See `docs/AUTH0_*` and `test_auth0_backend.sh`.
- Vector errors:
  - Verify `SQLITE_VEC_PATH` and follow `docs/SQLITE_VEC_SETUP.md`.

---

## Useful Docs

- Root docs index: `docs/README.md` and `docs/README_START_HERE.md`
- Backend deep‑dive: `BACKEND_OVERVIEW.md`
- Backend README: `globalbridge_backend/README.md`
- Expo client README: `clients/globalbridge-expo/README.md`
- Auth0 integration: files under `docs/` prefixed `AUTH0_*.md`
- SQLite vec setup: `docs/SQLITE_VEC_SETUP.md`
- Sync API contract: `docs/sync-api-contract.md`

---

## Task Master AI (optional)

This repo includes Task Master AI configuration to drive multi‑step dev workflows. See `AGENTS.md` and `.taskmaster/` for commands like `task-master next`, `task-master set-status`, and research‑assisted task expansion.

---

## License

No explicit license is provided; assume private/internal use unless stated otherwise.
