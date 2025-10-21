# Elm Web Client Feature PRD

## Background & Problem Statement
- The current primary client is the native front-end (mobile-first) that interacts with the Phoenix backend. This setup slows down functional testing and onboarding because each backend change requires rebuilding or simulating the mobile stack.
- A browser-accessible client will give the engineering swarm a quicker feedback loop, improve QA efficiency, and provide a cross-platform entry point for early adopters.
- Elm is chosen to guarantee maintainable, type-safe front-end code with predictable state transitions, aligning with the backend’s emphasis on correctness and the PRD’s focus on bridge reliability.

## Goals
1. Deliver a production-quality Elm single-page web client that mirrors the native client’s core capabilities (auth, thread list, real-time chat, bridge visibility).
2. Provide a developer-focused experience that makes manual regression testing of backend features trivial (fast startup, mock/test data hooks).
3. Establish a reusable Elm/Phoenix integration pattern (channels + REST) that future web surfaces can build on.

## Non-Goals
- Implement advanced E2EE tooling or multi-tenant theming within this phase.
- Replace the native front-end; the Elm client complements it.
- Build rich admin dashboards beyond the views needed to exercise chat/bridge behavior.

## User Segments
- **Developers / QA (Primary):** Need instant access to new features and logs while iterating on bridges, messaging flows, and auth.
- **Early Adopters / Internal Stakeholders (Secondary):** Want a lightweight way to try messaging without installing native builds.

## Core Experience & Flows
1. **Authentication**
   - Login via email + password (Guardian token exchange).
   - Optional “developer mode” credential presets for quick QA.
   - Persist session via local storage; support token refresh.
2. **Thread Overview**
   - List personal and bridged threads (Slack/Telegram badges).
   - Indicators for unread messages, bridge status, and sync health.
3. **Conversation View**
   - Real-time message stream with Phoenix Channels.
   - Compose box with optimistic send, attachment stubs, and delivery receipts.
   - Message metadata display (bridge origin, encrypted/not).
4. **Bridge Insights**
   - Per-thread bridge status pane (connected, syncing, errors).
   - Ability to trigger bridge reconnect or re-auth flows, powered by existing backend endpoints.
5. **Developer Utilities**
   - Toggle to show raw payloads / CDC logs.
   - Sandbox controls to seed demo threads, replay message timelines, and inspect websocket events.

## Functional Requirements
- Use Elm 0.19 SPA architecture (single bundle compiled via elm-live or Vite integration).
- Integrate with Phoenix Channels through JavaScript interop:
  - Shared `phoenix.js` socket client exposed to Elm via ports.
  - Maintain per-thread subscriptions; reconnect automatically on token refresh.
- REST endpoints consumed for auth, initial data hydration, and bridge commands.
- State management in Elm follows The Elm Architecture with union types for page states (Loading, Ready, Error).
- Responsive layout for desktop/tablet widths; mobile-friendly is “nice to have”.

## System & Architecture Notes
- **Build Pipeline:** Use Vite (preferred) or esbuild to bundle Elm, `phoenix.js`, and CSS. Output served by Phoenix’s static endpoint.
- **Session Handling:** Guardian tokens stored in secure cookies (httpOnly) when possible; Elm obtains CSRF token through initial boot payload.
- **Data Layer:**
  - Initial hydration via `/api/bootstrap` delivering threads, user profile, bridge summary.
  - Real-time updates via channels broadcasting message events and bridge status changes.
- **Testing Hooks:**
  - QA mode exposes `window.Globalbridge.debug` functions to insert canned events.
  - Provide Elm fuzzer tests for core state transitions and integration tests with Cypress (smoke suite).

## UX & Visual Guidance
- Clean dashboard layout inspired by native client: left nav for threads, main panel for messages, right panel (collapsible) for bridge insights.
- Dark mode parity with native client palette.
- Accessibility: keyboard navigation for thread switching, ARIA labels on controls, focus management for modals.

## Telemetry & Observability
- Emit Phoenix telemetry events when the web client subscribes/unsubscribes from threads.
- Front-end: capture key interactions (login success/failure, send message, bridge retry) via a lightweight analytics adapter (console logging in dev, configurable provider in prod).

## Security Considerations
- Respect existing auth flows; never expose raw tokens in local storage if avoidable (prefer cookies).
- Ensure socket connection upgrades validate Guardian tokens and enforce per-thread authorization.
- Prepare for future E2EE by abstracting message rendering to accept decrypted payloads from backend/native clients when available.

## Dependencies
- Requires stabilized backend endpoints for:
  - `/api/auth/login`, `/api/auth/refresh`
  - `/api/threads`, `/api/threads/:id/messages`
  - `/api/bridges/:id/actions` (connect/disconnect/retry)
  - Phoenix channels namespace `thread:*`
- Requires bridging services to emit status updates through existing telemetry bus.

## Milestones & Deliverables
1. **Scaffolding (Week 1)**
   - Repo setup, Elm/Vite build, Phoenix static integration.
   - Auth flow working against staging backend.
2. **Messaging Core (Week 2)**
   - Thread list + conversation view with real-time updates.
   - Optimistic sending and receipt handling.
3. **Bridge Panel & QA Tooling (Week 3)**
   - Bridge status UI, reconnect actions, developer debug panel.
   - Cypress smoke tests + Elm state tests.
4. **Polish & Launch (Week 4)**
   - Accessibility sweep, responsive layout tuning, docs.
   - Rollout plan + telemetry dashboards.

## Risks & Mitigations
- **Elm ↔ Phoenix Interop Complexity:** Mitigate with a thin JS adapter module with unit tests and typed Elm ports.
- **Auth Token Handling in Browser:** Lean on Phoenix session cookies and refresh endpoints; document fallback local-storage usage with encryption.
- **Feature Divergence from Native Client:** Establish shared UX checklist and weekly parity reviews between squads.

