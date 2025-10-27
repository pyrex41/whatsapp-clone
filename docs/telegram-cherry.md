# Telegram Bridge Integration via Cherry-Pick

## Product Requirements Document (PRD)

**Document Version:** 1.0
**Date:** October 26, 2025
**Status:** Ready for Implementation
**Estimated Effort:** 4-6 hours
**Risk Level:** Medium

---

## Executive Summary

This document provides detailed instructions for integrating the Telegram bridge functionality from the `telegram` branch (PR #5) into the `happy` branch using a selective cherry-pick strategy. This approach preserves all AI/translation work on `happy` while adding the production-ready bridge infrastructure.

### Why Cherry-Pick Strategy?

- **Complementary Features**: The branches don't compete - they enhance different platform areas
- **Preserve AI Work**: 45+ commits of AI/translation development on `happy` remain intact
- **Production-Ready Code**: Telegram bridge has comprehensive testing, error handling, and documentation
- **Minimal Conflicts**: Most files are net-new additions, not modifications to existing code

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Overview of Changes](#overview-of-changes)
3. [Step-by-Step Integration](#step-by-step-integration)
4. [File-by-File Guide](#file-by-file-guide)
5. [Manual Merge Instructions](#manual-merge-instructions)
6. [Testing Checklist](#testing-checklist)
7. [Rollback Procedure](#rollback-procedure)
8. [Success Criteria](#success-criteria)

---

## Prerequisites

### Required

- [ ] Clean working directory on `happy` branch
- [ ] All uncommitted changes stashed or committed
- [ ] Git version 2.23+ (for `git restore` commands)
- [ ] Elixir 1.14+, Phoenix 1.7+
- [ ] Xcode 15+ (for iOS build verification)
- [ ] Node 18+ (for React Native)

### Recommended

- [ ] Create backup branch: `git branch happy-backup happy`
- [ ] Review PR #5 description: https://github.com/pyrex41/whatsapp-clone/pull/5
- [ ] Verify all tests pass on `happy`: `cd globalbridge_backend && mix test`
- [ ] Verify iOS app builds on `happy`

---

## Overview of Changes

### Files to Cherry-Pick (Net New)

These files don't exist on `happy` and can be copied directly:

#### Backend - Bridge Infrastructure (17 files)
```
globalbridge_backend/lib/globalbridge_backend/bridges/
  ├── message_router.ex          # Message format conversion (Telegram ↔ GlobalBridge)
  ├── process.ex                 # GenServer for individual bridge instances
  ├── registry.ex                # Process lifecycle management with ETS tracking
  ├── supervisor.ex              # OTP supervision tree for bridges
  ├── telemetry.ex               # Metrics and monitoring
  ├── user_mapper.ex             # External platform user mapping
  └── telegram/
      ├── api.ex                 # Telegram Bot API HTTP client
      └── server.ex              # GenServer with polling & webhook support

globalbridge_backend/lib/globalbridge_backend/contexts/
  └── bridges.ex                 # Context for bridge CRUD operations

globalbridge_backend/lib/globalbridge_backend_web/controllers/
  ├── bridge_controller.ex       # REST API endpoints
  ├── bridge_json.ex             # JSON serialization
  ├── health_controller.ex       # Health check endpoints
  └── telegram_webhook_controller.ex  # Telegram webhook handler

globalbridge_backend/test/
  ├── globalbridge_backend/bridges/message_router_test.exs
  ├── globalbridge_backend_web/channels/user_channel_bridge_test.exs
  ├── globalbridge_backend_web/controllers/bridge_controller_test.exs
  └── integration/bridge_genserver_integration_test.exs
```

#### Backend - Bridge Schema Updates
```
globalbridge_backend/lib/globalbridge_backend/schemas/bridge.ex  # Enhanced with status tracking
```

#### iOS - Bridge Support (3 files)
```
clients/ios/GlobalBridge/Core/Models/Bridge.swift
clients/ios/GlobalBridge/Core/Networking/REST/BridgeService.swift
clients/ios/GlobalBridge/UI/Views/ThreadSettingsView.swift
clients/ios/GlobalBridge/Tests/BridgeTests.swift
clients/ios/GlobalBridge/Tests/BridgeSetupUITests.swift
clients/ios/GlobalBridge/Tests/Phoenix/PhoenixStateManagerBridgeTests.swift
```

#### React Native - Bridge UI (6 files)
```
clients/globalbridge-expo/app/(tabs)/bridge-setup.tsx
clients/globalbridge-expo/src/hooks/use-bridges.ts
clients/globalbridge-expo/src/hooks/use-thread-bridges.ts
clients/globalbridge-expo/src/services/notification-service.ts
clients/globalbridge-expo/src/services/realtime-service.ts
clients/globalbridge-expo/src/providers/notification-provider.tsx
```

#### Infrastructure
```
.github/workflows/ci.yml         # CI/CD workflow
LOAD_TESTING_README.md          # Load testing guide
load-test.js                    # k6 load test script
```

### Files Requiring Manual Merge (6 files)

These files exist on both branches and need careful merging:

1. **globalbridge_backend/lib/globalbridge_backend/application.ex**
   - Add: Bridge.Registry, Bridge.Supervisor, Bridge.Telemetry to supervision tree
   - Keep: All existing AI components (ConversationMonitor, EmbeddingCache, etc.)
   - Keep: validate_production_security() function from telegram

2. **globalbridge_backend/lib/globalbridge_backend_web/router.ex**
   - Add: Bridge API routes (`/api/v1/bridges/*`)
   - Add: Telegram webhook route (`/api/webhooks/telegram`)
   - Add: Health check route (`/api/health`)
   - Keep: All existing AI routes

3. **globalbridge_backend/config/runtime.exs**
   - Add: Bridge configuration (poll_interval, max_failures, health_check_interval)
   - Keep: All existing AI configuration

4. **globalbridge_backend/.env.example**
   - Add: TELEGRAM_BOT_TOKEN, bridge configuration
   - Keep: All existing environment variables

5. **clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixStateManager.swift**
   - Add: Bridge event handling
   - Keep: All existing AI event handling

6. **clients/globalbridge-expo/src/api/endpoints.ts & schemas.ts**
   - Add: Bridge API endpoints and schemas
   - Keep: All existing endpoints

---

## Step-by-Step Integration

### Phase 1: Preparation (15 minutes)

```bash
# 1. Ensure you're on happy branch with clean state
git checkout happy
git status  # Should show "nothing to commit, working tree clean"

# 2. Create backup branch
git branch happy-backup-$(date +%Y%m%d)

# 3. Create integration branch
git checkout -b telegram-integration

# 4. Verify telegram branch is accessible
git branch -a | grep telegram
# Should show: remotes/origin/telegram

# 5. Create tracking directory for cherry-picked files
mkdir -p .integration-tracking
echo "# Files cherry-picked from telegram branch" > .integration-tracking/MANIFEST.md
```

### Phase 2: Backend Bridge Infrastructure (45 minutes)

```bash
# Navigate to backend
cd globalbridge_backend

# Cherry-pick entire bridges directory (new code)
git checkout telegram -- lib/globalbridge_backend/bridges/

# Cherry-pick bridge context
git checkout telegram -- lib/globalbridge_backend/contexts/bridges.ex

# Cherry-pick bridge controllers
git checkout telegram -- \
  lib/globalbridge_backend_web/controllers/bridge_controller.ex \
  lib/globalbridge_backend_web/controllers/bridge_json.ex \
  lib/globalbridge_backend_web/controllers/health_controller.ex \
  lib/globalbridge_backend_web/controllers/telegram_webhook_controller.ex

# Cherry-pick enhanced bridge schema
git checkout telegram -- lib/globalbridge_backend/schemas/bridge.ex

# Cherry-pick bridge tests
git checkout telegram -- \
  test/globalbridge_backend/bridges/ \
  test/globalbridge_backend_web/channels/user_channel_bridge_test.exs \
  test/globalbridge_backend_web/controllers/bridge_controller_test.exs \
  test/integration/bridge_genserver_integration_test.exs

# Stage these new files
git add lib/globalbridge_backend/bridges/
git add lib/globalbridge_backend/contexts/bridges.ex
git add lib/globalbridge_backend_web/controllers/bridge*.ex
git add lib/globalbridge_backend_web/controllers/health_controller.ex
git add lib/globalbridge_backend_web/controllers/telegram_webhook_controller.ex
git add lib/globalbridge_backend/schemas/bridge.ex
git add test/globalbridge_backend/bridges/
git add test/globalbridge_backend_web/channels/user_channel_bridge_test.exs
git add test/globalbridge_backend_web/controllers/bridge_controller_test.exs
git add test/integration/bridge_genserver_integration_test.exs

# Commit
git commit -m "feat(backend): add Telegram bridge infrastructure from PR #5

- Add Bridge Registry, Supervisor, Process, Telemetry modules
- Add Telegram API client and server with circuit breaker
- Add message router and user mapper
- Add bridge REST API controllers
- Add bridge context for CRUD operations
- Add comprehensive test suite for bridge functionality

Cherry-picked from telegram branch (PR #5)"

cd ..
```

### Phase 3: Backend Configuration & Routes (30 minutes)

**MANUAL MERGE REQUIRED** - See [Manual Merge Instructions](#manual-merge-instructions) section below.

```bash
cd globalbridge_backend

# DO NOT use git checkout for these files - we'll merge manually
# See detailed merge instructions in next section for:
# - lib/globalbridge_backend/application.ex
# - lib/globalbridge_backend_web/router.ex
# - config/runtime.exs
# - .env.example
```

### Phase 4: iOS Bridge Support (30 minutes)

```bash
# Navigate to iOS directory
cd clients/ios/GlobalBridge

# Cherry-pick Bridge model
git checkout telegram -- Core/Models/Bridge.swift

# Cherry-pick BridgeService
git checkout telegram -- Core/Networking/REST/BridgeService.swift

# Cherry-pick ThreadSettingsView
git checkout telegram -- UI/Views/ThreadSettingsView.swift

# Cherry-pick tests
git checkout telegram -- \
  Tests/BridgeTests.swift \
  Tests/BridgeSetupUITests.swift \
  Tests/Phoenix/PhoenixStateManagerBridgeTests.swift

# Note: PhoenixStateManager.swift requires manual merge (see below)

# Stage files
git add Core/Models/Bridge.swift
git add Core/Networking/REST/BridgeService.swift
git add UI/Views/ThreadSettingsView.swift
git add Tests/BridgeTests.swift
git add Tests/BridgeSetupUITests.swift
git add Tests/Phoenix/PhoenixStateManagerBridgeTests.swift

# Commit
git commit -m "feat(ios): add bridge management UI and services from PR #5

- Add Bridge model with status tracking
- Add BridgeService for REST API integration
- Add ThreadSettingsView for bridge management UI
- Add comprehensive bridge test suite
- Add PhoenixStateManager bridge event handling tests

Cherry-picked from telegram branch (PR #5)"

cd ../../..
```

### Phase 5: React Native Bridge UI (30 minutes)

```bash
cd clients/globalbridge-expo

# Cherry-pick bridge setup screen
git checkout telegram -- app/\(tabs\)/bridge-setup.tsx

# Cherry-pick bridge hooks
git checkout telegram -- \
  src/hooks/use-bridges.ts \
  src/hooks/use-thread-bridges.ts

# Cherry-pick services (if they don't conflict with existing)
git checkout telegram -- \
  src/services/notification-service.ts \
  src/services/realtime-service.ts

# Cherry-pick provider
git checkout telegram -- src/providers/notification-provider.tsx

# Note: src/api/endpoints.ts and schemas.ts require manual merge

# Stage files
git add app/\(tabs\)/bridge-setup.tsx
git add src/hooks/use-bridges.ts
git add src/hooks/use-thread-bridges.ts
git add src/services/notification-service.ts
git add src/services/realtime-service.ts
git add src/providers/notification-provider.tsx

# Commit
git commit -m "feat(expo): add bridge setup UI and hooks from PR #5

- Add bridge setup screen with create/delete functionality
- Add use-bridges hook for bridge state management
- Add use-thread-bridges hook for thread-specific queries
- Add notification and realtime services for bridge events
- Add notification provider integration

Cherry-picked from telegram branch (PR #5)"

cd ../..
```

### Phase 6: Infrastructure & Documentation (15 minutes)

```bash
# Cherry-pick CI/CD workflow
git checkout telegram -- .github/workflows/ci.yml

# Cherry-pick load testing infrastructure
git checkout telegram -- LOAD_TESTING_README.md load-test.js

# Stage files
git add .github/workflows/ci.yml
git add LOAD_TESTING_README.md
git add load-test.js

# Commit
git commit -m "feat(infra): add CI/CD workflow and load testing from PR #5

- Add GitHub Actions workflow for backend, frontend, and iOS
- Add k6-based load testing infrastructure
- Add load testing documentation

Cherry-picked from telegram branch (PR #5)"
```

### Phase 7: Manual Merges (60 minutes)

See detailed instructions in [Manual Merge Instructions](#manual-merge-instructions) section.

### Phase 8: Testing & Validation (45 minutes)

See [Testing Checklist](#testing-checklist) section.

---

## Manual Merge Instructions

### File 1: globalbridge_backend/lib/globalbridge_backend/application.ex

**Goal**: Merge supervision trees from both branches.

```bash
# Open file for editing
code globalbridge_backend/lib/globalbridge_backend/application.ex
```

**Current state (happy branch):**
```elixir
children =
  [
    GlobalbridgeBackend.Repo,
    # ... other children ...
    # AI Cache (ETS-based) for translations and embeddings
    GlobalbridgeBackend.AI.Cache,
    # Embedding Cache for eager query embedding generation
    GlobalbridgeBackend.AI.EmbeddingCache,
    # Task supervisor for async operations
    {Task.Supervisor, name: GlobalbridgeBackend.TaskSupervisor},
    # Dynamic supervisor for per-thread database repos
    {DynamicSupervisor, name: GlobalbridgeBackend.DynamicRepoSupervisor, strategy: :one_for_one},
    # Agens Multi-Agent Framework Supervisor
    Agens.Supervisor
  ] ++ oban_children ++ [
    # AI Components Setup
    Supervisor.child_spec({Task, fn -> ... end}, id: :ai_components_setup_task),
    # AI Cost Tracking
    GlobalbridgeBackend.AI.CostTracker,
    GlobalbridgeBackend.AI.BudgetMonitor,
    # AI Rate Limit Monitoring
    GlobalbridgeBackend.Monitoring.RateLimitMonitor,
    # AI Conversation Monitor
    GlobalbridgeBackend.AI.ConversationMonitor,
    GlobalbridgeBackendWeb.Endpoint
  ]
```

**Target state (after merge):**
```elixir
children =
  [
    GlobalbridgeBackend.Repo,
    GlobalbridgeBackendWeb.Telemetry,
    {DNSCluster, query: Application.get_env(:globalbridge_backend, :dns_cluster_query) || :ignore},
    {Phoenix.PubSub, name: GlobalbridgeBackend.PubSub},
    # Phoenix Presence for online/offline tracking
    GlobalbridgeBackendWeb.Presence,
    # JWKS cache for Auth0 JWT verification
    GlobalbridgeBackend.Auth.JWKSCache,
    # Participant cache for thread authorization
    GlobalbridgeBackend.Cache.ParticipantCache,
    # AI Cache (ETS-based) for translations and embeddings
    GlobalbridgeBackend.AI.Cache,
    # Embedding Cache for eager query embedding generation
    GlobalbridgeBackend.AI.EmbeddingCache,
    # Task supervisor for async operations (message persistence, read receipts, notifications)
    {Task.Supervisor, name: GlobalbridgeBackend.TaskSupervisor},
    # Dynamic supervisor for per-thread database repos
    {DynamicSupervisor, name: GlobalbridgeBackend.DynamicRepoSupervisor, strategy: :one_for_one},
    # Agens Multi-Agent Framework Supervisor
    Agens.Supervisor
  ] ++ oban_children ++ [
    # AI Components Setup (runs after other supervisors are started)
    Supervisor.child_spec(
      {Task, fn ->
        GlobalbridgeBackend.AI.AgensSetup.start_components()
        GlobalbridgeBackend.AI.Telemetry.setup()
        GlobalbridgeBackend.Bridges.Telemetry.setup()  # <-- ADD THIS LINE
      end},
      id: :ai_components_setup_task
    ),
    # AI Cost Tracking and Budget Monitoring
    GlobalbridgeBackend.AI.CostTracker,
    GlobalbridgeBackend.AI.BudgetMonitor,
    # AI Rate Limit Monitoring
    GlobalbridgeBackend.Monitoring.RateLimitMonitor,
    # AI Conversation Monitor for real-time suggestions
    GlobalbridgeBackend.AI.ConversationMonitor,
    # Bridge Registry and Supervisor for managing bridge processes   # <-- ADD THESE 2 LINES
    GlobalbridgeBackend.Bridges.Registry,                             # <-- ADD
    GlobalbridgeBackend.Bridges.Supervisor,                           # <-- ADD
    # Start to serve requests, typically the last entry
    GlobalbridgeBackendWeb.Endpoint
  ]
```

**Also add the validate_production_security function at the end of the file:**

```elixir
# After validate_vec_path! function, add:

defp validate_production_security do
  require Logger

  if Application.get_env(:globalbridge_backend, :env) == :prod do
    # Ensure SSL verification is enabled in production
    ssl_verify = Application.get_env(:globalbridge_backend, :ssl_verify_peer, true)

    unless ssl_verify do
      raise """
      CRITICAL SECURITY ERROR: SSL verification is disabled in production.
      This creates a severe security vulnerability to MITM attacks.
      Set SSL_VERIFY_PEER=true in your production environment.
      """
    end

    Logger.info("Production security validation passed: SSL verification enabled")
  end
end
```

**Then call it in the start function:**

```elixir
def start(_type, _args) do
  # Validate sqlite-vec extension before starting
  validate_sqlite_vec()

  # Validate production security settings  # <-- ADD THIS LINE
  validate_production_security()           # <-- ADD THIS LINE

  # Background job processing with Oban (not in test)
  children = ...
```

**Commit:**
```bash
git add globalbridge_backend/lib/globalbridge_backend/application.ex
git commit -m "feat(backend): integrate bridge supervision with AI components

- Add Bridge.Registry and Bridge.Supervisor to supervision tree
- Add Bridge.Telemetry setup alongside AI telemetry
- Add production security validation for SSL verification
- Maintain all existing AI components (Cache, EmbeddingCache, ConversationMonitor)"
```

---

### File 2: globalbridge_backend/lib/globalbridge_backend_web/router.ex

**Goal**: Add bridge API routes while keeping all existing routes.

```bash
code globalbridge_backend/lib/globalbridge_backend_web/router.ex
```

**Add these routes in the `/api/v1` scope (after existing AI routes):**

```elixir
scope "/api/v1", GlobalbridgeBackendWeb do
  pipe_through [:api, :auth]

  # Existing AI routes...
  post "/ai/translate", AIController, :translate
  post "/ai/smart-reply", AIController, :smart_reply
  # ... other AI routes ...

  # Bridge Management Routes (ADD THESE)
  resources "/bridges", BridgeController, only: [:index, :create, :update, :delete]
  get "/threads/:thread_id/bridges", BridgeController, :thread_bridges
end
```

**Add webhook routes in the `/api/webhooks` scope:**

```elixir
# Add this new scope if it doesn't exist
scope "/api/webhooks", GlobalbridgeBackendWeb do
  pipe_through :api

  post "/telegram", TelegramWebhookController, :webhook
end
```

**Add health check route (public, no auth):**

```elixir
# Add this new scope for health checks
scope "/api", GlobalbridgeBackendWeb do
  pipe_through :api

  get "/health", HealthController, :index
  get "/health/bridges", HealthController, :bridges
end
```

**Full router.ex structure should look like:**

```elixir
defmodule GlobalbridgeBackendWeb.Router do
  use GlobalbridgeBackendWeb, :router

  # ... existing pipelines ...

  # Health check (public)
  scope "/api", GlobalbridgeBackendWeb do
    pipe_through :api

    get "/health", HealthController, :index
    get "/health/bridges", HealthController, :bridges
  end

  # Authenticated API routes
  scope "/api/v1", GlobalbridgeBackendWeb do
    pipe_through [:api, :auth]

    # ... existing routes ...

    # Bridge Management
    resources "/bridges", BridgeController, only: [:index, :create, :update, :delete]
    get "/threads/:thread_id/bridges", BridgeController, :thread_bridges
  end

  # Webhooks (public but validated)
  scope "/api/webhooks", GlobalbridgeBackendWeb do
    pipe_through :api

    post "/telegram", TelegramWebhookController, :webhook
  end

  # ... rest of router ...
end
```

**Commit:**
```bash
git add globalbridge_backend/lib/globalbridge_backend_web/router.ex
git commit -m "feat(router): add bridge and webhook API routes

- Add /api/v1/bridges/* endpoints for bridge management
- Add /api/webhooks/telegram for Telegram webhook handling
- Add /api/health endpoints for monitoring
- Maintain all existing AI and thread routes"
```

---

### File 3: globalbridge_backend/config/runtime.exs

**Goal**: Add bridge configuration while preserving AI config.

```bash
code globalbridge_backend/config/runtime.exs
```

**Add this section after the AI configuration:**

```elixir
# ... existing AI configuration ...

# Bridge Configuration
config :globalbridge_backend, :bridges,
  # Telegram polling interval (milliseconds)
  telegram_poll_interval: System.get_env("TELEGRAM_POLL_INTERVAL", "1000") |> String.to_integer(),
  # Maximum consecutive failures before circuit breaker opens
  max_consecutive_failures: System.get_env("BRIDGE_MAX_FAILURES", "5") |> String.to_integer(),
  # Health check interval (milliseconds)
  health_check_interval: System.get_env("BRIDGE_HEALTH_CHECK_INTERVAL", "30000") |> String.to_integer(),
  # Circuit breaker timeout (milliseconds)
  circuit_breaker_timeout: System.get_env("BRIDGE_CIRCUIT_BREAKER_TIMEOUT", "300000") |> String.to_integer()

# SSL Verification (Production Security)
config :globalbridge_backend,
  ssl_verify_peer: System.get_env("SSL_VERIFY_PEER", "true") == "true"
```

**Commit:**
```bash
git add globalbridge_backend/config/runtime.exs
git commit -m "feat(config): add bridge and security configuration

- Add Telegram polling and health check intervals
- Add circuit breaker configuration for bridge resilience
- Add SSL verification flag for production security
- Maintain all existing AI configuration"
```

---

### File 4: globalbridge_backend/.env.example

**Goal**: Add bridge environment variables.

```bash
code globalbridge_backend/.env.example
```

**Add these variables to the file:**

```bash
# ... existing variables ...

# ============================================
# Telegram Bridge Configuration
# ============================================

# Telegram Bot Token (get from @BotFather)
TELEGRAM_BOT_TOKEN=your_telegram_bot_token_here

# Bridge Polling & Health
TELEGRAM_POLL_INTERVAL=1000              # Polling interval in ms
BRIDGE_MAX_FAILURES=5                     # Max failures before circuit breaker opens
BRIDGE_HEALTH_CHECK_INTERVAL=30000       # Health check interval in ms
BRIDGE_CIRCUIT_BREAKER_TIMEOUT=300000    # Circuit breaker reset timeout in ms

# Production Security
SSL_VERIFY_PEER=true                     # MUST be true in production
```

**Commit:**
```bash
git add globalbridge_backend/.env.example
git commit -m "feat(env): add bridge and security environment variables

- Add TELEGRAM_BOT_TOKEN for bot authentication
- Add bridge polling and health check configuration
- Add circuit breaker configuration
- Add SSL verification flag with security warning"
```

---

### File 5: clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixStateManager.swift

**Goal**: Add bridge event handling to Phoenix state manager.

```bash
code clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixStateManager.swift
```

**Find the message handling section and add bridge events:**

```swift
// In the handleMessage function or equivalent message routing logic

private func handleMessage(_ message: PhoenixMessage) {
    // ... existing message handling ...

    // Add bridge event handling
    if message.event == "bridge_status_changed" {
        handleBridgeStatusChanged(message)
    } else if message.event == "bridge_message" {
        handleBridgeMessage(message)
    }

    // ... rest of existing logic ...
}

// Add these new handler methods
private func handleBridgeStatusChanged(_ message: PhoenixMessage) {
    guard let payload = message.payload,
          let bridgeId = payload["bridge_id"] as? String,
          let statusString = payload["status"] as? String,
          let status = Bridge.Status(rawValue: statusString) else {
        return
    }

    // Update bridge status in app state
    // This will be handled by the Store when bridge state is added
    print("Bridge \(bridgeId) status changed to \(status)")
}

private func handleBridgeMessage(_ message: PhoenixMessage) {
    guard let payload = message.payload,
          let messageId = payload["message_id"] as? String else {
        return
    }

    print("Received message from bridge: \(messageId)")
    // Forward to message handling pipeline
}
```

**Commit:**
```bash
git add clients/ios/GlobalBridge/Core/Networking/Phoenix/PhoenixStateManager.swift
git commit -m "feat(ios): add bridge event handling to PhoenixStateManager

- Add bridge_status_changed event handler
- Add bridge_message event handler
- Integrate with existing Phoenix message routing"
```

---

### File 6: clients/globalbridge-expo/src/api/endpoints.ts & schemas.ts

**Goal**: Add bridge API endpoints and schemas.

```bash
code clients/globalbridge-expo/src/api/endpoints.ts
```

**Add bridge endpoints:**

```typescript
// ... existing endpoints ...

// Bridge endpoints
export const bridges = {
  list: () => api.get<Bridge[]>('/bridges'),
  create: (data: { bridge_type: string; phone_number: string }) =>
    api.post<Bridge>('/bridges', data),
  update: (id: string, data: { is_active: boolean }) =>
    api.patch<Bridge>(`/bridges/${id}`, data),
  delete: (id: string) => api.delete(`/bridges/${id}`),
  forThread: (threadId: string, bridgeType?: string) =>
    api.get<Bridge[]>(`/threads/${threadId}/bridges`, {
      params: bridgeType ? { bridge_type: bridgeType } : {}
    }),
};
```

**Add bridge schemas in schemas.ts:**

```typescript
import { z } from 'zod';

// ... existing schemas ...

// Bridge schemas
export const BridgeStatusSchema = z.enum([
  'active',
  'inactive',
  'error',
  'connecting'
]);

export const BridgeSchema = z.object({
  id: z.string(),
  bridge_type: z.string(),
  phone_number: z.string(),
  status: BridgeStatusSchema,
  is_active: z.boolean(),
  error_message: z.string().nullable(),
  last_active_at: z.string().nullable(),
  created_at: z.string(),
  updated_at: z.string(),
});

export type Bridge = z.infer<typeof BridgeSchema>;
export type BridgeStatus = z.infer<typeof BridgeStatusSchema>;
```

**Commit:**
```bash
git add clients/globalbridge-expo/src/api/endpoints.ts
git add clients/globalbridge-expo/src/api/schemas.ts
git commit -m "feat(expo): add bridge API endpoints and schemas

- Add bridge CRUD endpoints
- Add bridge Zod schemas for type safety
- Integrate with existing API client"
```

---

### File 7: Update package.json files

**React Native:**
```bash
cd clients/globalbridge-expo
git checkout telegram -- package.json
git add package.json
npm install
cd ../..
```

**Backend (if dependencies changed):**
```bash
cd globalbridge_backend
git checkout telegram -- mix.exs
git add mix.exs
mix deps.get
cd ..
```

**Commit:**
```bash
git commit -m "feat(deps): add bridge-related dependencies

- Add Expo notification dependencies
- Add any new Elixir dependencies for bridges"
```

---

## Testing Checklist

### Backend Tests

```bash
cd globalbridge_backend

# 1. Compile check
mix compile
# Expected: No errors, only warnings acceptable

# 2. Run all tests
mix test
# Expected: All tests pass (ignore bridge tests if TELEGRAM_BOT_TOKEN not set)

# 3. Run bridge-specific tests (with mocked token)
TELEGRAM_BOT_TOKEN=test_token mix test test/globalbridge_backend/bridges/
# Expected: Bridge unit tests pass

# 4. Check database migrations
mix ecto.migrations
# Expected: No pending migrations

# 5. Start development server
iex -S mix phx.server
# Expected: Server starts without errors
# Check logs for: "Bridge.Registry started" and "AI components initialized"

# 6. Test health endpoint
curl http://localhost:4000/api/health
# Expected: {"status": "healthy", "timestamp": "..."}

cd ..
```

### iOS Tests

```bash
cd clients/ios/GlobalBridge

# 1. Build check
xcodebuild -scheme GlobalBridge -destination 'platform=iOS Simulator,name=iPhone 15' build
# Expected: Build succeeds

# 2. Run tests (if configured)
xcodebuild test -scheme GlobalBridge -destination 'platform=iOS Simulator,name=iPhone 15'
# Expected: Tests pass (or skip if test target not configured)

# 3. Manual app launch
# Open in Xcode and run on simulator
# Verify:
# - App launches without crashes
# - AI features work (Smart Reply, Translation)
# - No bridge-related crashes (bridge UI may not be visible yet)

cd ../../..
```

### React Native Tests

```bash
cd clients/globalbridge-expo

# 1. TypeScript check
npm run typecheck
# Expected: No type errors

# 2. Lint check
npm run lint
# Expected: No lint errors (or only warnings)

# 3. Start Metro bundler
npm start
# Expected: Metro starts, no errors in bundle

# 4. Manual testing (in separate terminal)
# Press 'i' for iOS simulator or 'a' for Android
# Verify:
# - App loads
# - No bridge-related errors in console
# - Existing features work

cd ../..
```

### Integration Tests

```bash
# 1. Start backend server
cd globalbridge_backend
iex -S mix phx.server

# In another terminal:
# 2. Test bridge creation API (with valid auth token)
curl -X POST http://localhost:4000/api/v1/bridges \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"bridge_type": "telegram", "phone_number": "+1234567890"}'
# Expected: Bridge created (or error if no TELEGRAM_BOT_TOKEN)

# 3. Test bridge list
curl http://localhost:4000/api/v1/bridges \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN"
# Expected: JSON array of bridges

# 4. Verify AI endpoints still work
curl -X POST http://localhost:4000/api/v1/ai/translate \
  -H "Authorization: Bearer YOUR_AUTH_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello", "target_language": "es"}'
# Expected: Translation response
```

### Smoke Test Checklist

- [ ] Backend compiles without errors
- [ ] All backend tests pass
- [ ] Backend server starts successfully
- [ ] Health endpoint responds
- [ ] Bridge API endpoints respond (401 without auth is OK)
- [ ] AI API endpoints still work
- [ ] iOS app builds successfully
- [ ] iOS app launches without crashes
- [ ] React Native app builds successfully
- [ ] React Native app launches without crashes
- [ ] No TypeScript errors in React Native
- [ ] Git history is clean (no merge conflicts)

---

## Rollback Procedure

If integration fails or tests don't pass:

### Option 1: Reset to happy branch

```bash
# Delete integration branch
git checkout happy
git branch -D telegram-integration

# Restore from backup
git checkout happy-backup-$(date +%Y%m%d)
```

### Option 2: Rollback specific commits

```bash
# List recent commits
git log --oneline -10

# Revert specific commit
git revert <commit-hash>

# Or reset to before integration
git reset --hard happy
```

### Option 3: Create fix commits

If only small issues exist, create fix commits rather than rolling back:

```bash
# Fix the issue
# Edit files...

git add <files>
git commit -m "fix: resolve integration issue with ..."
```

---

## Success Criteria

### Must Have (Blocking)

- [ ] ✅ All backend tests pass
- [ ] ✅ Backend compiles without errors
- [ ] ✅ iOS app builds successfully
- [ ] ✅ React Native app builds successfully
- [ ] ✅ No regressions in AI features (translation, smart reply still work)
- [ ] ✅ Health endpoint responds correctly
- [ ] ✅ Git history is clean (all commits have proper messages)

### Should Have (Non-blocking but important)

- [ ] ✅ Bridge API endpoints are accessible (even if not functional without tokens)
- [ ] ✅ iOS BridgeService compiles
- [ ] ✅ React Native bridge screens are accessible
- [ ] ✅ Load testing infrastructure is in place
- [ ] ✅ CI/CD workflow file is valid

### Nice to Have (Future work)

- [ ] Bridge functionality tested end-to-end with real Telegram bot
- [ ] iOS bridge UI fully integrated with settings
- [ ] React Native bridge setup flow tested
- [ ] Load tests run successfully

---

## Post-Integration Tasks

After successful integration:

### 1. Update Documentation

```bash
# Create integration summary
cat > docs/telegram-integration-summary.md << 'EOF'
# Telegram Bridge Integration Summary

**Date**: $(date +%Y-%m-%d)
**Integration Method**: Cherry-pick from telegram branch (PR #5)
**Status**: ✅ Complete

## What Was Integrated

- Backend bridge infrastructure (Registry, Supervisor, Process, Telemetry)
- Telegram API client with circuit breaker pattern
- Bridge REST API and webhook handlers
- iOS bridge models, services, and UI
- React Native bridge setup screens and hooks
- CI/CD workflow and load testing infrastructure

## What Was Preserved

- All AI/translation features from happy branch
- Smart Reply functionality
- ConversationMonitor and AI caching
- All 45+ commits of AI development work

## Next Steps

1. Configure TELEGRAM_BOT_TOKEN in environment
2. Test bridge creation with real Telegram bot
3. Test message routing between platforms
4. Run load tests to verify performance
5. Deploy to staging for integration testing

## Known Issues

None at this time.
EOF

git add docs/telegram-integration-summary.md
git commit -m "docs: add telegram integration summary"
```

### 2. Push Integration Branch

```bash
# Push integration branch for review
git push origin telegram-integration

# Create PR from telegram-integration to happy
gh pr create \
  --base happy \
  --head telegram-integration \
  --title "Integrate Telegram Bridge from PR #5" \
  --body "This PR integrates the Telegram bridge functionality from PR #5 (telegram branch) into the happy branch using a selective cherry-pick strategy.

## Integration Method
- Cherry-picked bridge infrastructure files
- Manually merged configuration and routing files
- Preserved all AI/translation work from happy branch

## Testing
- ✅ All backend tests pass
- ✅ Backend compiles successfully
- ✅ iOS app builds successfully
- ✅ React Native app builds successfully
- ✅ No regressions in AI features

## Files Changed
- Backend: Added bridge infrastructure, updated application.ex, router.ex, runtime.exs
- iOS: Added Bridge model, BridgeService, ThreadSettingsView
- React Native: Added bridge setup screen and hooks
- Infrastructure: Added CI/CD workflow and load testing

See docs/telegram-cherry.md for detailed integration steps.
"
```

### 3. Close Original PR #5

```bash
# Add comment to PR #5 explaining integration
gh pr comment 5 --body "This PR has been integrated into the \`happy\` branch via cherry-pick strategy.

See the new PR #[number] for the integration.

The cherry-pick approach was chosen to preserve all AI/translation work on \`happy\` while adding the bridge functionality.

Closing this PR as superseded by the integration PR."

# Close PR #5
gh pr close 5
```

### 4. Merge to happy and Deploy

```bash
# After PR review and approval, merge to happy
git checkout happy
git merge telegram-integration --no-ff

# Tag the integration
git tag -a v1.0.0-bridge-integration -m "Integrate Telegram bridge with AI features"

# Push to remote
git push origin happy
git push origin v1.0.0-bridge-integration
```

---

## Troubleshooting

### Issue: "Module GlobalbridgeBackend.Bridges not found"

**Solution**: Ensure all bridge files were cherry-picked:
```bash
ls -la globalbridge_backend/lib/globalbridge_backend/bridges/
# Should show: message_router.ex, process.ex, registry.ex, supervisor.ex, telemetry.ex, user_mapper.ex, telegram/
```

### Issue: "Can't find BridgeController"

**Solution**: Ensure controller was cherry-picked and router was updated:
```bash
ls globalbridge_backend/lib/globalbridge_backend_web/controllers/bridge*.ex
# Should show: bridge_controller.ex, bridge_json.ex

grep "BridgeController" globalbridge_backend/lib/globalbridge_backend_web/router.ex
# Should show route definitions
```

### Issue: Tests fail with "TELEGRAM_BOT_TOKEN not set"

**Solution**: This is expected. Set test token or skip bridge tests:
```bash
# Option 1: Set test token
TELEGRAM_BOT_TOKEN=test_token mix test

# Option 2: Skip bridge tests
mix test --exclude bridge
```

### Issue: iOS build fails with "Type 'Bridge' not found"

**Solution**: Ensure Bridge.swift was added to Xcode project:
```bash
# Verify file exists
ls clients/ios/GlobalBridge/Core/Models/Bridge.swift

# Open Xcode and ensure Bridge.swift is in project navigator
# If not, add it: Right-click Core/Models → Add Files → Select Bridge.swift
```

### Issue: React Native fails with "Module not found: use-bridges"

**Solution**: Ensure hooks were cherry-picked and dependencies installed:
```bash
ls clients/globalbridge-expo/src/hooks/use-bridges.ts
cd clients/globalbridge-expo
npm install
cd ../..
```

---

## Appendix A: File Manifest

Complete list of files changed in integration:

### Backend (27 files)
```
globalbridge_backend/
├── lib/globalbridge_backend/
│   ├── application.ex (MODIFIED)
│   ├── bridges/ (NEW)
│   │   ├── message_router.ex
│   │   ├── process.ex
│   │   ├── registry.ex
│   │   ├── supervisor.ex
│   │   ├── telemetry.ex
│   │   ├── user_mapper.ex
│   │   └── telegram/
│   │       ├── api.ex
│   │       └── server.ex
│   ├── contexts/
│   │   └── bridges.ex (NEW)
│   └── schemas/
│       └── bridge.ex (MODIFIED)
├── lib/globalbridge_backend_web/
│   ├── controllers/
│   │   ├── bridge_controller.ex (NEW)
│   │   ├── bridge_json.ex (NEW)
│   │   ├── health_controller.ex (NEW)
│   │   └── telegram_webhook_controller.ex (NEW)
│   └── router.ex (MODIFIED)
├── config/
│   └── runtime.exs (MODIFIED)
├── .env.example (MODIFIED)
└── test/
    ├── globalbridge_backend/bridges/ (NEW)
    │   └── message_router_test.exs
    ├── globalbridge_backend_web/
    │   ├── channels/
    │   │   └── user_channel_bridge_test.exs (NEW)
    │   └── controllers/
    │       └── bridge_controller_test.exs (NEW)
    └── integration/
        └── bridge_genserver_integration_test.exs (NEW)
```

### iOS (6 files)
```
clients/ios/GlobalBridge/
├── Core/
│   ├── Models/
│   │   └── Bridge.swift (NEW)
│   └── Networking/
│       ├── Phoenix/
│       │   └── PhoenixStateManager.swift (MODIFIED)
│       └── REST/
│           └── BridgeService.swift (NEW)
├── UI/Views/
│   └── ThreadSettingsView.swift (NEW)
└── Tests/
    ├── BridgeTests.swift (NEW)
    ├── BridgeSetupUITests.swift (NEW)
    └── Phoenix/
        └── PhoenixStateManagerBridgeTests.swift (NEW)
```

### React Native (8 files)
```
clients/globalbridge-expo/
├── app/(tabs)/
│   └── bridge-setup.tsx (NEW)
├── src/
│   ├── api/
│   │   ├── endpoints.ts (MODIFIED)
│   │   └── schemas.ts (MODIFIED)
│   ├── hooks/
│   │   ├── use-bridges.ts (NEW)
│   │   └── use-thread-bridges.ts (NEW)
│   ├── providers/
│   │   └── notification-provider.tsx (NEW)
│   └── services/
│       ├── notification-service.ts (NEW)
│       └── realtime-service.ts (NEW)
└── package.json (MODIFIED)
```

### Infrastructure (3 files)
```
.github/workflows/ci.yml (NEW)
LOAD_TESTING_README.md (NEW)
load-test.js (NEW)
```

**Total**: 44 files (30 new, 14 modified)

---

## Appendix B: Commit Message Template

Use this template for integration commits:

```
<type>(<scope>): <subject>

<body>

Cherry-picked from telegram branch (PR #5)

<footer>
```

**Example:**
```
feat(backend): add Telegram bridge infrastructure

- Add Bridge Registry, Supervisor, Process, Telemetry modules
- Add Telegram API client and server with circuit breaker
- Add message router and user mapper
- Add bridge REST API controllers
- Add comprehensive test suite

Cherry-picked from telegram branch (PR #5)

Co-authored-by: Claude <noreply@anthropic.com>
```

---

## Appendix C: Time Estimates

| Phase | Task | Estimated Time | Notes |
|-------|------|----------------|-------|
| 1 | Preparation | 15 min | Branch setup, backup |
| 2 | Backend Infrastructure | 45 min | Cherry-pick bridge files |
| 3 | Backend Config/Routes | 30 min | Manual merges |
| 4 | iOS Integration | 30 min | Cherry-pick + manual merge |
| 5 | React Native | 30 min | Cherry-pick + manual merge |
| 6 | Infrastructure | 15 min | CI/CD, load testing |
| 7 | Manual Merges | 60 min | application.ex, router.ex, etc. |
| 8 | Testing | 45 min | Backend, iOS, RN tests |
| **Total** | | **4h 30m** | Plus 30min buffer = **5 hours** |

---

## Support

If you encounter issues during integration:

1. **Check this document** for troubleshooting section
2. **Review PR #5** for original implementation details
3. **Git log** on telegram branch for context: `git log telegram --oneline`
4. **Rollback** if necessary using procedures above
5. **Document the issue** for future reference

---

**Document End**

Last Updated: October 26, 2025
Integration Status: Ready for Implementation
Estimated Duration: 4-6 hours
Risk Level: Medium
Success Rate: High (complementary features, minimal conflicts)
