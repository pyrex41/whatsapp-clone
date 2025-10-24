# Product Requirements Document: GlobalBridge Messenger

**Version:** 2.1
**Last Updated:** October 24, 2025  
**Document Type:** Technical Product Requirements  
**Status:** Planning Phase

---

## Executive Summary

GlobalBridge Messenger is a privacy-first, AI-ready messaging application designed to unify fragmented communication workflows for global collaborators—freelancers, NGO workers, and distributed teams who juggle multiple platforms like Slack and Telegram. The platform serves as a "meta-messaging" hub that bridges disparate communication tools with a foundation built to support intelligent translation, cultural adaptation, and workflow automation.

**Core Problem:** International remote workers waste up to 23 hours weekly switching between communication platforms, face language and cultural barriers, and lack tools that unify cross-platform conversations without compromising privacy.

**Solution Architecture:** An Elixir/Phoenix backend with Swift/iOS frontend, leveraging SQLite-based sync (Turso), manual CDC for control, E2EE-ready encryption, and an extensible AI abstraction layer that supports both on-device and server-side processing without architectural changes.

**Target Users:**
- Freelancers managing cross-border projects
- NGO workers coordinating international aid efforts  
- Small distributed teams across time zones
- Digital nomads navigating multilingual collaboration

**Key Technical Differentiators:**
- Per-thread bridge activation (not workspace-wide) for granular control
- AI abstraction layer supporting on-device (MLX) and cloud processing without rebuild
- Feature flag architecture enabling tiered functionality
- Manual CDC providing full sync control and offline-first capability
- E2EE-ready design with client-side encryption (stretch goal)

---

## 1. Problem Statement & Technical Context

### 1.1 Core Problem

Global collaborators (freelancers, NGO workers, distributed teams) face fragmented communication across multiple platforms:

- **Tool Silos:** Slack for structured workflows, Telegram for informal updates, native apps for personal chats—no unified view
- **Context Loss:** Switching platforms causes information fragmentation; users manually copy-paste between tools
- **Language Barriers:** Multilingual teams lack integrated translation with cultural context
- **Privacy Concerns:** Existing solutions require cloud processing of sensitive data

**Technical Challenge:** Build a system that unifies these platforms while maintaining:
- Offline-first architecture with reliable sync
- Extensible AI processing (on-device or cloud) without architectural rebuild
- Per-thread granular bridge control (not workspace-wide)

### 1.2 Technical Requirements

The solution must:
- Handle real-time messaging with <100ms latency for native messages
- Support bi-directional sync with external platforms (Slack, Telegram) via bridges
- Enable AI features to be added post-MVP without refactoring core architecture
- Provide offline capability with conflict resolution
- Scale to support 1M+ concurrent connections (Elixir/Phoenix baseline)
- E2EE capability (stretch goal - not required for MVP)

---

## 2. User Personas & Core Use Cases

### 2.1 Primary Persona: Global Collaborator

**Profile:**
- Age: 25-45
- Occupation: Freelance professionals, NGO coordinators, remote consultants
- Technical Proficiency: High (comfortable with OAuth, API integrations, multiple platforms)
- Work Pattern: 2-4 time zones, 3-5 communication tools daily

**Technical Pain Points:**
- Context switching between Slack (client channels), Telegram (vendor groups), native apps
- Manual synchronization of information across platforms
- Language barriers requiring copy-paste to translation tools
- Privacy concerns with enterprise platforms processing sensitive client data
- Offline gaps when traveling (need local-first sync)

**Usage Patterns:**
- Creates project-specific threads
- Activates bridges per conversation (not workspace-wide)
- Requires offline capability for unreliable connectivity
- Values privacy and data control
- Needs AI processing without cloud dependency (on-device option)

### 2.2 Core Use Cases

#### Use Case 1: Freelancer Managing Cross-Platform Project

**Scenario:** US-based designer coordinates with Indian developers (Telegram) and European clients (Slack)

**Technical Flow:**
1. Create thread in GlobalBridge Messenger
2. Activate Slack bridge → OAuth flow → bot joins client channel
3. Activate Telegram bridge → bot invitation → developers join group
4. Messages flow bi-directionally: Slack ↔ GlobalBridge ↔ Telegram
5. All messages encrypted locally before storage
6. AI translation layer (when enabled) processes inline without blocking message flow
7. Offline work queued in CDC log, syncs on reconnect

**Technical Requirements:**
- Per-thread bridge configuration stored in `bridges` table
- Real-time sync via Phoenix Channels (<100ms latency)
- Conflict resolution: last-write-wins with timestamp ordering
- Bridge failures degrade gracefully (show "disconnected" UI, queue messages)

#### Use Case 2: NGO Worker with Intermittent Connectivity

**Scenario:** Field coordinator syncs updates from offline locations

**Technical Flow:**
1. Compose messages while offline (queued in local SQLite)
2. CDC log tracks all local changes with sequence numbers
3. On reconnect, client pushes CDC deltas to server
4. Server reconciles conflicts (timestamp-based merge)
5. Server pushes remote changes back to client
6. Bridge imports (Slack/Telegram) also queued during offline periods

**Technical Requirements:**
- Write-ahead log (WAL) for SQLite to handle offline writes
- CDC sequence tracking to maintain message order
- Background sync process that doesn't block UI
- Retry logic with exponential backoff for network failures

---

## 3. Product Architecture

### 3.1 Technology Stack

**Backend:**
- **Framework:** Elixir/Phoenix (handles 1M+ concurrent connections)
- **Database:** Turso (SQLite-based, global replication, mobile sync)
- **Real-Time:** Phoenix Channels (WebSocket for <100ms latency)
- **Sync:** Turso Sync (automatic mobile-server CDC) OR LiteSync (manual CDC alternative)

**Frontend:**
- **Platform:** iOS (Swift 6 with strict concurrency)
- **State Management:** Swiftea (TEA/MVU pattern on Combine, ~200 LOC)
- **Real-Time Client:** SwiftPhoenixClient (WebSocket wrapper)
- **UI Framework:** SwiftUI with async/await actors

**AI Infrastructure:**
- **On-Device:** MLX framework (3B models, 20+ tokens/sec on iPhone 16)
- **Server-Side:** LangChain + Grok-3-mini (fallback for complex queries)
- **Privacy Toggle:** User selects on-device vs. server processing

**Security:**
- **Encryption:** Transport security with TLS 1.3
- **Storage:** Encrypted SQLite with per-thread keys
- **Bridge Security:** OAuth scopes limited to specific channels

### 3.2 System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                       iOS Client (Swift)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  SwiftUI     │  │  Swiftea     │  │  Turso       │      │
│  │  Views       │──│  State       │──│  SQLite      │      │
│  │              │  │  (TEA/MVU)   │  │  Local DB    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                  │                  │              │
│         │                  │                  │              │
│  ┌──────▼──────────────────▼──────────────────▼───────┐    │
│  │           Phoenix Channel Client                    │    │
│  │           (WebSocket + E2EE)                        │    │
│  └──────────────────────────────────────────────────────┘    │
└────────────────────────────┬────────────────────────────────┘
                             │ WSS + Signal Protocol
                             │
┌────────────────────────────▼────────────────────────────────┐
│                 Phoenix Backend (Elixir)                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Channels    │  │  AI          │  │  Bridges     │      │
│  │  (Real-Time) │  │  Controller  │  │  (GenServer) │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                  │                  │              │
│  ┌──────▼──────────────────▼──────────────────▼───────┐    │
│  │              Turso Database                         │    │
│  │          (SQLite + Global Sync)                     │    │
│  └──────────────────────────────────────────────────────┘    │
└────────────────────────────┬────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
    ┌─────────▼─────────┐        ┌─────────▼─────────┐
    │  Slack API        │        │  Telegram Bot API │
    │  (OAuth Webhooks) │        │  (Polling/Webhook)│
    └───────────────────┘        └───────────────────┘
```

### 3.3 Data Model

**Core Tables:**

```sql
-- Users
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  -- public_key BLOB,  -- For future E2EE (stretch goal)
  created_at INTEGER NOT NULL
);

-- Threads (Chat Groups)
CREATE TABLE threads (
  id TEXT PRIMARY KEY,
  name TEXT,
  -- encrypted_key BLOB,  -- Per-thread E2EE key (stretch goal)
  bridge_config TEXT,            -- JSON: {slack: {channel_id, token}, telegram: {chat_id}}
  created_at INTEGER NOT NULL
);

-- Messages
CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  content TEXT NOT NULL,
  -- encrypted_content BLOB,  -- E2EE stretch goal - not implemented in MVP
  timestamp INTEGER NOT NULL,
  source TEXT,                       -- "native", "slack", "telegram"
  FOREIGN KEY (thread_id) REFERENCES threads(id),
  FOREIGN KEY (sender_id) REFERENCES users(id)
);

-- Bridges
CREATE TABLE bridges (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  platform TEXT NOT NULL,           -- "slack" | "telegram"
  config TEXT NOT NULL,              -- JSON: OAuth tokens, webhook URLs
  status TEXT DEFAULT 'active',     -- "active", "paused", "error"
  FOREIGN KEY (thread_id) REFERENCES threads(id)
);

-- AI Context (Optional: for caching summaries)
CREATE TABLE ai_cache (
  thread_id TEXT PRIMARY KEY,
  summary TEXT,
  last_updated INTEGER,
  FOREIGN KEY (thread_id) REFERENCES threads(id)
);
```

---

## 3. Core Features & Technical Architecture

### 3.1 Architecture Overview: AI-Ready from Day 1

The system is designed to support AI features without architectural changes. MVP ships without AI, but the infrastructure accommodates future integration:

```
┌─────────────────────────────────────────────────────────────┐
│                    iOS Client (Swift 6)                      │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  SwiftUI     │  │  Swiftea     │  │  SQLite      │      │
│  │  Views       │──│  State       │──│  Local DB    │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                  │                  │              │
│  ┌──────▼──────────────────▼──────────────────▼───────┐    │
│  │        AI Abstraction Layer (Protocol)             │    │
│  │   • On-device: MLX (Llama/Gemma) - Future          │    │
│  │   • Server: LangChain/Grok - Future                │    │
│  │   • Feature Flag: Enabled/Disabled by tier         │    │
│  └────────────────────────────────────────────────────┘    │
│         │                                                    │
│  ┌──────▼──────────────────────────────────────────────┐   │
│  │   Phoenix Channel Client (WebSocket + E2EE)        │   │
│  └────────────────────────────────────────────────────┘   │
└────────────────────────────┬───────────────────────────────┘
                             │ WSS + Signal Protocol
┌────────────────────────────▼───────────────────────────────┐
│              Phoenix Backend (Elixir/OTP)                   │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Channels    │  │  Bridge      │  │  AI Service  │     │
│  │  (Real-Time) │  │  GenServers  │  │  (Future)    │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
│         │                  │                  │             │
│  ┌──────▼──────────────────▼──────────────────▼──────┐    │
│  │         Turso/SQLite (sharded per-thread)         │    │
│  └───────────────────────────────────────────────────┘    │
└────────────────────────────┬───────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │                             │
    ┌─────────▼─────────┐        ┌─────────▼─────────┐
    │  Slack API        │        │  Telegram Bot API │
    │  (OAuth/Webhooks) │        │  (Polling/Webhook)│
    └───────────────────┘        └───────────────────┘
```

### 3.2 MVP Feature Set (No AI Required)

#### F1: Core Messaging Infrastructure

**Requirements:**
- Real-time 1:1 and group messaging via Phoenix Channels
- Message delivery confirmation and read receipts
- Typing indicators
- Offline message queuing with automatic sync on reconnect
- Media support: images (files/voice in future releases)

**Data Model:**
```sql
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  -- public_key BLOB,  -- For future E2EE (stretch goal)
  created_at INTEGER NOT NULL
);

CREATE TABLE threads (
  id TEXT PRIMARY KEY,
  name TEXT,
  -- encrypted_key BLOB,  -- Per-thread E2EE key (stretch goal)
  created_at INTEGER NOT NULL
);

CREATE TABLE messages (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  content TEXT NOT NULL,
  -- encrypted_content BLOB,  -- E2EE stretch goal - not implemented in MVP
  timestamp INTEGER NOT NULL,
  source TEXT DEFAULT 'native',  -- "native", "slack", "telegram"
  metadata TEXT,  -- JSON: reply_to, attachments, etc.
  FOREIGN KEY (thread_id) REFERENCES threads(id),
  FOREIGN KEY (sender_id) REFERENCES users(id)
);

CREATE TABLE cdc_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  operation TEXT NOT NULL,  -- "INSERT", "UPDATE", "DELETE"
  record_id TEXT NOT NULL,
  changes TEXT,  -- JSON of changed fields
  timestamp INTEGER NOT NULL,
  synced BOOLEAN DEFAULT FALSE
);
```

**Technical Implementation:**
- Phoenix Channels for WebSocket communication
- SwiftUI + Swiftea (TEA/MVU) for state management
- Optimistic UI updates with rollback on failure
- Background sync with exponential backoff

#### F2: Change Data Capture (CDC) Sync

**Requirements:**
- Manual CDC using SQLite triggers
- Bi-directional sync: client ↔ server
- Conflict resolution: last-write-wins by timestamp
- Offline queue with automatic retry
- Option to integrate Turso for distributed sync (toggle)

**Implementation Strategy:**
```elixir
# Backend: CDC endpoint
defmodule MessagingWeb.SyncController do
  def pull_changes(conn, %{"since" => timestamp}) do
    changes = CDC.get_changes_since(timestamp)
    json(conn, %{changes: changes, server_timestamp: now()})
  end

  def push_changes(conn, %{"changes" => changes}) do
    Enum.each(changes, &CDC.apply_change/1)
    json(conn, %{status: :ok})
  end
end
```

```swift
// iOS: Background sync actor
actor SyncManager {
  func syncChanges() async {
    let localChanges = await db.getCDCLog(since: lastSyncTime)
    
    // Push local changes
    await api.pushChanges(localChanges)
    
    // Pull remote changes
    let remoteChanges = await api.pullChanges(since: lastSyncTime)
    await db.applyChanges(remoteChanges)
    
    lastSyncTime = Date()
  }
}
```

**Turso Integration Option:**
- Feature flag: `USE_TURSO_SYNC=true`
- Automatic replication when enabled
- Falls back to manual CDC if disabled
- Allows evaluation without commitment

#### F3: Slack Bridge (Per-Thread)

**Requirements:**
- Per-thread activation (not workspace-wide)
- OAuth 2.0 flow for user authorization
- Bot creation and channel joining
- Bi-directional message sync: Slack ↔ GlobalBridge
- Webhook listener + polling fallback
- Rate limiting compliance (1 req/sec Slack API limit)

**User Flow:**
1. User taps "Connect Slack" in thread settings
2. Backend generates OAuth URL, returns to client
3. User authorizes → Slack redirects with code
4. Backend exchanges code for token, creates bot
5. User selects Slack channel to bridge
6. GenServer starts, begins polling/webhook subscription
7. Messages flow bi-directionally with author attribution

**Data Model:**
```sql
CREATE TABLE bridges (
  id TEXT PRIMARY KEY,
  thread_id TEXT NOT NULL,
  platform TEXT NOT NULL,  -- "slack" | "telegram"
  config TEXT NOT NULL,  -- JSON: {token, channel_id, webhook_url}
  status TEXT DEFAULT 'active',  -- "active" | "paused" | "error"
  rate_limit_config TEXT,  -- JSON: {max_per_sec, burst_size}
  created_at INTEGER NOT NULL,
  FOREIGN KEY (thread_id) REFERENCES threads(id)
);

CREATE TABLE bridge_messages (
  id TEXT PRIMARY KEY,
  bridge_id TEXT NOT NULL,
  external_id TEXT NOT NULL,  -- Slack/Telegram message ID
  internal_message_id TEXT NOT NULL,  -- GlobalBridge message ID
  direction TEXT NOT NULL,  -- "inbound" | "outbound"
  synced_at INTEGER NOT NULL,
  FOREIGN KEY (bridge_id) REFERENCES bridges(id),
  FOREIGN KEY (internal_message_id) REFERENCES messages(id)
);
```

**Implementation:**
```elixir
# Backend: Slack bridge GenServer
defmodule Bridge.SlackServer do
  use GenServer

  def handle_info(:poll, state) do
    # Poll conversations.history every 5 seconds
    messages = Slack.Api.get_history(state.channel_id, since: state.last_poll)
    
    Enum.each(messages, fn msg ->
      forward_to_thread(%{
        content: msg.text,
        sender: msg.user,
        source: "slack",
        external_id: msg.ts
      }, state.thread_id)
    end)
    
    schedule_next_poll()
    {:noreply, %{state | last_poll: now()}}
  end

  def handle_info({:webhook, payload}, state) do
    # Webhook from Slack Events API
    case verify_signature(payload) do
      :ok ->
        process_event(payload["event"], state.thread_id)
        {:noreply, state}
      :error ->
        Logger.warn("Invalid Slack webhook signature")
        {:noreply, state}
    end
  end

  defp forward_to_thread(message, thread_id) do
    # Broadcast to Phoenix Channel
    MessagingWeb.Endpoint.broadcast(
      "thread:#{thread_id}",
      "message:new",
      message
    )
  end
end
```

**Bridge Sharing Flow:**
- "Add to Slack" button generates invite link
- New users install app to workspace → bot auto-adds to bridged channel
- Permissions: `channels:read`, `channels:history`, `chat:write`

#### F4: Telegram Bridge (Per-Thread)

**📋 Detailed Implementation:** See `docs/telegram-bridge-prd.md` for complete technical specification.

**Requirements:**
- Bot creation via BotFather with webhook/polling support
- Per-thread bridge activation with granular permissions
- Bi-directional message synchronization with deduplication
- Rate limiting compliance (30 req/sec Telegram API limit)
- Automatic error recovery and health monitoring
- User mapping and attribution for cross-platform messages
- Message format conversion between Telegram and GlobalBridge
- Webhook signature verification (optional security enhancement)

**User Flow:**
1. User navigates to thread settings → "Add Bridge" → "Telegram"
2. User provides bot token from @BotFather
3. Backend validates token and creates bridge configuration
4. User adds bot to Telegram group via generated invite link
5. Bridge establishes connection via webhooks (primary) + polling (fallback)
6. Messages flow bi-directionally with real-time synchronization
7. Bridge status shown in UI with error handling and reconnection

**Technical Architecture:**
- **Backend:** GenServer per bridge with supervision tree
- **Sync Strategy:** Webhook-first with polling fallback
- **Database:** Dedicated bridge tables with message deduplication
- **Security:** Encrypted bot tokens, access control validation
- **Monitoring:** Health checks, error tracking, performance metrics

**Implementation Overview:**
```elixir
# Production-ready GenServer with comprehensive error handling
defmodule GlobalbridgeBackend.Bridges.TelegramServer do
  use GenServer
  require Logger

  @poll_interval 5000  # 5 seconds
  @max_retry_attempts 3
  @health_check_interval 300_000  # 5 minutes

  def init({bridge_id, config}) do
    # Webhook setup with fallback to polling
    case setup_webhook(config) do
      :ok -> schedule_poll()
      :error -> Logger.warn("Webhook setup failed, using polling only")
    end

    schedule_health_check()

    {:ok, %{
      bridge_id: bridge_id,
      config: config,
      offset: config.last_telegram_update_id || 0,
      consecutive_failures: 0,
      webhook_active: true
    }}
  end

  def handle_info(:poll, state) do
    case poll_updates(state) do
      {:ok, new_offset, updates_processed} ->
        update_bridge_offset(state.bridge_id, new_offset)
        schedule_poll()
        {:noreply, %{state | offset: new_offset, consecutive_failures: 0}}

      {:error, reason} ->
        handle_poll_error(state, reason)
    end
  end

  def handle_cast({:webhook_update, update}, state) do
    # Process real-time webhook updates
    process_update(update, state.config.thread_id, state.bridge_id)
    {:noreply, state}
  end

  # Message processing with deduplication
  defp process_update(update, thread_id, bridge_id) do
    telegram_message_id = update["message"]["message_id"]

    unless message_already_processed?(bridge_id, telegram_message_id) do
      message_attrs = convert_telegram_to_globalbridge(update["message"], thread_id)
      create_globalbridge_message(message_attrs)
      record_message_mapping(bridge_id, telegram_message_id)
      broadcast_to_thread(thread_id, message_attrs)
    end
  end
end
```

**Database Schema:**
```sql
-- Bridge configuration
ALTER TABLE bridges ADD COLUMN telegram_chat_id TEXT;
ALTER TABLE bridges ADD COLUMN telegram_webhook_url TEXT;
ALTER TABLE bridges ADD COLUMN last_telegram_update_id INTEGER DEFAULT 0;

-- Message deduplication
CREATE TABLE bridge_messages (
  bridge_id TEXT,
  telegram_message_id INTEGER,
  globalbridge_message_id TEXT,
  direction TEXT,
  synced_at TIMESTAMP
);
```

**API Endpoints:**
- `POST /api/v1/bridges/telegram` - Create bridge
- `GET /api/v1/bridges/{thread_id}/telegram` - Get status
- `DELETE /api/v1/bridges/{bridge_id}` - Remove bridge
- `POST /api/webhooks/telegram/{bridge_id}` - Webhook receiver

**Bridge Sharing Flow:**
- **Bot Setup:** User creates bot via @BotFather, provides token to GlobalBridge
- **Group Invitation:** App generates `t.me/{bot_username}?start={thread_id}` link
- **Permission Model:** Bot requires read/write access to group messages
- **User Verification:** Bot validates thread access before joining group
- **Multi-User Support:** Any thread participant can add/remove bridges

**Error Handling & Recovery:**
- Automatic webhook → polling fallback on network issues
- Exponential backoff for rate limit violations
- Health monitoring with status indicators
- Graceful degradation with user notifications
- Automatic reconnection attempts

**Performance Characteristics:**
- **Latency:** <5 seconds average message delivery
- **Throughput:** 30 messages/second per bridge (Telegram limit)
- **Reliability:** >99.5% uptime with automatic recovery
- **Scalability:** Support for 100+ concurrent bridges

**Security Considerations:**
- Bot tokens encrypted at rest using application secrets
- Webhook endpoints protected by bridge ID randomization
- Access control ensures only thread participants can manage bridges
- Message content sanitization prevents malicious payload injection
- Optional webhook signature verification for enhanced security

### 3.3 Future Features (Post-MVP) - Architecture Ready

#### AI Translation & Cultural Context

**Design (Not Implemented in MVP):**

```swift
// iOS: AI abstraction layer (ready to plug in)
protocol AIProvider {
  func translate(_ text: String, to language: String) async -> TranslationResult
  func analyzeTone(_ text: String) async -> ToneAnalysis
  func summarize(_ messages: [Message]) async -> String
}

class OnDeviceProvider: AIProvider {
  let model = MLXModel(name: "llama-3b")  // MLX Swift
  
  func translate(_ text: String, to language: String) async -> TranslationResult {
    let prompt = "Translate to \(language) with cultural context: \(text)"
    let result = await model.generate(prompt, maxTokens: 200)
    return TranslationResult(
      translatedText: extractTranslation(result),
      culturalNotes: extractNotes(result)
    )
  }
}

class ServerProvider: AIProvider {
  func translate(_ text: String, to language: String) async -> TranslationResult {
    let request = AIRequest(prompt: "translate", text: text, targetLang: language)
    return try await api.post("/ai/translate", body: request)
  }
}

// Feature flag determines which provider to use
class AIService {
  let provider: AIProvider
  
  init(tier: UserTier, privacyMode: Bool) {
    switch (tier, privacyMode) {
    case (.free, _):
      provider = OnDeviceProvider()  // Free: on-device only
    case (.pro, true):
      provider = OnDeviceProvider()
    case (.pro, false):
      provider = ServerProvider()  // Pro: user choice
    case (.enterprise, _):
      provider = ServerProvider()  // Enterprise: cloud processing
    }
  }
}
```

**Backend Endpoint (Future):**
```elixir
defmodule MessagingWeb.AIController do
  def translate(conn, %{"text" => text, "target_lang" => lang}) do
    # Check tier authorization
    if Accounts.has_feature?(conn.assigns.user, :ai_translation) do
      result = AI.translate(text, lang)  # LangChain + Grok
      json(conn, result)
    else
      conn
      |> put_status(403)
      |> json(%{error: "Upgrade to Pro for server-side AI"})
    end
  end
end
```

**Features (When Enabled):**
- Real-time inline translation with language auto-detection
- Cultural context hints (e.g., "In Japanese business culture, this phrase implies...")
- Formality adjustment suggestions
- Slang/idiom explanations in tooltips
- Multi-step agents: extract tasks → translate → sync to external calendars

#### Advanced Workflow Automation

**Future Capabilities:**
- Extract deadlines, action items from conversations
- Generate thread summaries on-demand
- Detect meeting scheduling attempts, propose times
- Export structured data to Notion, Trello, Google Calendar

**Architecture:**
- Pluggable agent system using LangChain on backend
- On-device inference for simple tasks (classification, entity extraction)
- Server-side for complex multi-step workflows

### 3.4 Feature Flag & Tier System

**Architecture Requirement:**

All features must be gated by a feature flag system to support multiple tiers:

```elixir
# Backend: Feature flag module
defmodule Accounts.Features do
  @features %{
    free: [:native_messaging, :one_bridge, :on_device_ai],
    pro: [:native_messaging, :unlimited_bridges, :on_device_ai, :server_ai, :advanced_ai],
    enterprise: [:all]
  }

  def has_feature?(user, feature) do
    tier = user.subscription_tier
    feature in @features[tier] or :all in @features[tier]
  end
end
```

```swift
// iOS: Feature flag check
class FeatureFlags {
  static func canUseFeature(_ feature: Feature) -> Bool {
    switch (currentTier, feature) {
    case (.free, .bridgeActivation):
      return activeBridges.count < 1  // Free: 1 bridge
    case (.pro, .bridgeActivation):
      return true  // Pro: unlimited
    case (_, .aiTranslation):
      return currentTier != .free  // AI requires Pro+
    default:
      return false
    }
  }
}
```

**Feature Matrix:**

| Feature | Free | Pro | Enterprise |
|---------|------|-----|------------|
| Native Messaging | ✅ | ✅ | ✅ |
| Bridges | 1 | Unlimited | Unlimited |
| On-Device AI | ✅ | ✅ | ✅ |
| Server-Side AI | ❌ | ✅ | ✅ |
| Advanced Workflows | ❌ | ❌ | ✅ |
| Audit Logs | ❌ | ❌ | ✅ |


#### F2: Change Data Capture (CDC) Sync

**Requirements:**
- Manual CDC using SQLite triggers
- Bi-directional sync: client ↔ server
- Conflict resolution: last-write-wins by timestamp
- Offline queue with automatic retry
- Option to integrate Turso for distributed sync (toggle)

**Acceptance Criteria:**
- Changes sync within 5 seconds on active connections
- Offline changes sync when connectivity restores
- No data loss during conflicts (timestamp-based merge)
- CDC logs pruned after 7 days

#### F3: Slack Bridge (Per-Thread)
**Description:** Bi-directional message sync between app thread and Slack channel

**User Flow:**
1. User taps "Add Slack Bridge" in thread settings
2. Backend creates Slack App, returns OAuth `install_url`
3. User authorizes, Slack installs bot to chosen channel
4. Backend stores OAuth token, starts GenServer to poll/webhook
5. Share "Add to Slack" button: new users join workspace, bot auto-adds to channel
6. Messages flow both ways with author attribution

**Requirements:**
- OAuth 2.0 for Slack App installation (scopes: `channels:read`, `chat:write`)
- Webhook listener at `/slack/events` with signature verification
- Poll `conversations.history` every 5s as fallback
- Forward Slack messages to Phoenix Channel as `message:new` events
- Forward app messages to Slack via `chat.postMessage` API
- Offline: queue outbound messages, retry on reconnect
- E2EE: encrypt Slack imports before storing locally (stretch goal)

**Acceptance Criteria:**
- User can authorize Slack in <3 taps
- Messages appear in both platforms within 5s (webhook) or 10s (polling)
- Encrypted payloads never leak to Slack (metadata only)
- Bridge survives app/server restarts (GenServer supervision)
- Graceful degradation: show "Bridge Disconnected" UI on errors

**Implementation Notes:**
```elixir
# lib/bridge/slack_server.ex
defmodule Bridge.SlackServer do
  use GenServer

  def handle_info({:webhook, payload}, state) do
    case payload["event"]["type"] do
      "message" ->
        event = payload["event"]
        forward_to_channel(%{
          content: event["text"],
          sender: event["user"],
          source: "slack"
        }, state.thread_id)
    end
    {:noreply, state}
  end

  defp forward_to_channel(payload, thread_id) do
    MessagingAppWeb.Endpoint.broadcast(
      "thread:#{thread_id}",
      "message:new",
      payload
    )
  end
end
```

#### F4: Telegram Bridge (Per-Thread)
**Description:** Bi-directional sync with Telegram groups

**User Flow:**
1. User taps "Add Telegram Bridge"
2. Backend creates bot via Telegram API, returns invite link (`t.me/yourbot?start=thread123`)
3. User adds bot to Telegram group, shares `chat_id`
4. Backend starts GenServer to poll `getUpdates` or webhook
5. Share bot invite: new users message bot with code to opt-in
6. Messages sync both ways

**Requirements:**
- Create bot via BotFather, store token in backend config
- Webhook at `/telegram/webhook` OR poll `getUpdates` every 5s
- Extract `chat_id` from first message, link to thread
- Forward messages both directions with author mapping
- Handle media (files, images) with CDN URLs
- E2EE: encrypt Telegram imports locally (stretch goal)

**Acceptance Criteria:**
- Bot responds to `/start thread123` with confirmation
- Messages sync within 5-10s
- Supports text + file attachments
- Bridge config stored in `bridges` table
- UI shows online/offline bridge status

**Implementation Notes:**
```elixir
# lib/bridge/telegram_server.ex
defmodule Bridge.TelegramServer do
  use GenServer

  def handle_info(:poll, state) do
    updates = Telegram.Api.get_updates(offset: state.offset)
    Enum.each(updates, fn update ->
      if update.message && update.message.chat.id == state.chat_id do
        forward_to_channel(%{
          content: update.message.text,
          sender: update.message.from.id,
          source: "telegram"
        }, state.thread_id)
      end
    end)
    {:noreply, %{state | offset: last_update_offset(updates)}}
  end
end
```

### 4.2 Post-MVP Features (AI & Advanced Capabilities)

#### F5: AI Translation & Cultural Context
**Description:** Intelligent translation with cultural adaptation for multilingual threads

**Requirements:**
- On-Device Option: MLX framework (3B model, 20+ tokens/sec)
- Server Option: LangChain + Grok-3-mini for complex queries
- Privacy toggle in settings (default: on-device)
- Detect language automatically (langdetect library)
- Translate messages with cultural notes (e.g., "ASAP in Indian culture may allow flexibility")
- Cache translations per message to avoid re-processing

**User Flow:**
1. User enables translation in thread settings
2. Foreign language messages auto-translate inline
3. Tap translated text to see original + cultural context
4. AI flags potential tone mismatches ("This might sound formal in Japanese")

**Acceptance Criteria:**
- Translations complete within 2s (on-device) or 5s (server)
- Accuracy: 85%+ for common languages (ES, FR, DE, HI, JA)
- Cultural notes appear for idioms/urgency markers
- User can switch between on-device/server in <2 taps

**Implementation:**
```swift
// iOS: AI Adapter with privacy toggle
class AIAdapter {
  let provider: AIProvider
  init(privacyMode: Bool) {
    provider = privacyMode ? OnDeviceProvider() : ServerProvider()
  }

  func translate(_ text: String, to language: String) async -> TranslationResult {
    let prompt = "Translate to \(language) with cultural context: \(text)"
    let result = await provider.process(prompt, context: [])
    return TranslationResult(text: result, culturalNotes: extractNotes(result))
  }
}
```

#### F6: AI Thread Summarization
**Description:** Generate concise summaries of long threads for quick catchup

**Requirements:**
- Summarize threads on-demand (button in thread header)
- Extract key action items, deadlines, decisions
- Highlight unresolved questions
- Privacy: process encrypted content locally or on server (user choice)

**Acceptance Criteria:**
- Summaries generated in <10s for 100-message threads
- Accuracy: captures 90%+ of action items
- UI shows "Last Summarized: 2h ago" timestamp

#### F7: Smart Workflow Extraction
**Description:** Auto-detect and extract tasks, deadlines, decisions from conversations

**Requirements:**
- Regex + LLM parsing for phrases like "by Friday", "need to", "action item"
- Create structured task list from extracted items
- Link tasks back to source messages
- Export to external tools (future: Trello, Notion integration)

**Acceptance Criteria:**
- Detects 80%+ of explicit deadlines/tasks
- False positive rate <10%
- User can edit/confirm extracted tasks

### 4.3 Enhanced Security & Privacy (Future)

#### F8: End-to-End Encryption (Stretch Goal - Post-MVP)
- Per-message encryption with Signal Protocol
- Perfect forward secrecy with ratcheting keys
- Per-thread disappearing timer
- Screenshot detection warnings
- Audit logs for bridge activity

---

## 4. Technical Stack & Implementation

### 4.1 Technology Stack

**Backend:**
- **Framework:** Elixir/Phoenix 1.7+ (handles 1M+ concurrent connections)
- **Database:** SQLite (sharded per-thread) with option for Turso (libSQL)
- **Real-Time:** Phoenix Channels (WebSocket)
- **Sync:** Manual CDC with SQLite triggers OR Turso Sync (configurable)
- **Process Management:** OTP GenServers for bridge workers

**Frontend:**
- **Platform:** iOS (Swift 6 with strict concurrency)
- **State Management:** Swiftea (TEA/MVU on Combine, ~200 LOC)
- **Real-Time Client:** SwiftPhoenixClient (WebSocket wrapper)
- **UI Framework:** SwiftUI with async/await actors
- **Local Storage:** SQLite.swift

**AI Infrastructure (Post-MVP):**
- **On-Device:** MLX framework (3B models, 20+ tokens/sec on iPhone 16)
- **Server-Side:** LangChain Elixir + Grok-3-mini/OpenAI
- **Privacy Toggle:** User controls on-device vs. server processing

**Security:**
- **Encryption:** Signal Protocol (E2EE), CryptoKit/libsodium for key management
- **Storage:** Encrypted SQLite with per-thread keys
- **Bridge Security:** OAuth scopes limited to specific channels

### 4.2 Data Architecture

**Database Sharding Strategy:**
- Each thread gets its own SQLite database file
- Path structure: `~/Library/Application Support/GlobalBridge/threads/{thread_id}.db`
- Enables granular backup, sharing, and E2EE (each thread has own encryption key)
- Shared databases: `users.db`, `bridges.db`, `sync_state.db`

**CDC Log Structure:**
```sql
CREATE TABLE cdc_log (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  table_name TEXT NOT NULL,
  operation TEXT NOT NULL,  -- INSERT, UPDATE, DELETE
  record_id TEXT NOT NULL,
  changes TEXT,  -- JSON snapshot of changed fields
  timestamp INTEGER NOT NULL,
  synced BOOLEAN DEFAULT FALSE,
  sync_attempts INTEGER DEFAULT 0
);

CREATE INDEX idx_cdc_unsynced ON cdc_log(synced, timestamp) 
WHERE synced = FALSE;
```

**Conflict Resolution:**
- Strategy: Last-write-wins (LWW) based on timestamp
- Server timestamp is authoritative
- Client includes local timestamp + server_timestamp from last sync
- Server reconciles: if client's server_timestamp < current, conflict exists
- Resolution: keep entry with higher timestamp, log conflict for debugging

### 4.3 Synchronization Architecture

**Manual CDC Approach:**

```elixir
# Backend: Sync controller
defmodule MessagingWeb.SyncController do
  def pull_changes(conn, %{"thread_id" => thread_id, "since" => timestamp}) do
    user_id = conn.assigns.user.id
    
    # Verify user has access to thread
    with :ok <- Threads.verify_access(thread_id, user_id),
         changes <- CDC.get_changes_since(thread_id, timestamp) do
      json(conn, %{
        changes: changes,
        server_timestamp: System.system_time(:millisecond)
      })
    end
  end

  def push_changes(conn, %{"thread_id" => thread_id, "changes" => changes}) do
    user_id = conn.assigns.user.id
    
    with :ok <- Threads.verify_access(thread_id, user_id),
         {:ok, conflicts} <- CDC.apply_changes(thread_id, changes) do
      json(conn, %{
        status: :ok,
        conflicts: conflicts,
        server_timestamp: System.system_time(:millisecond)
      })
    end
  end
end
```

```swift
// iOS: Sync actor
actor SyncManager {
  private var lastSyncTime: [String: Date] = [:]  // thread_id -> timestamp
  private let syncInterval: TimeInterval = 30
  
  func startPeriodicSync(for threadId: String) {
    Task {
      while !Task.isCancelled {
        await syncThread(threadId)
        try await Task.sleep(for: .seconds(syncInterval))
      }
    }
  }
  
  private func syncThread(_ threadId: String) async {
    // Push local changes first
    let localChanges = await db.getCDCLog(
      threadId: threadId,
      since: lastSyncTime[threadId]
    )
    
    if !localChanges.isEmpty {
      let pushResult = await api.pushChanges(threadId: threadId, changes: localChanges)
      await handleConflicts(pushResult.conflicts)
    }
    
    // Pull remote changes
    let pullResult = await api.pullChanges(
      threadId: threadId,
      since: lastSyncTime[threadId]
    )
    
    await db.applyChanges(pullResult.changes)
    lastSyncTime[threadId] = pullResult.serverTimestamp
  }
}
```

**Turso Integration (Optional):**
- Feature flag: `USE_TURSO_SYNC=true` in backend config
- When enabled, Turso handles replication automatically
- Client uses Turso iOS SDK instead of manual CDC
- Fallback: if Turso unavailable, graceful degradation to manual CDC
- Trade-off: Less control, but simpler implementation

### 4.4 Bridge Architecture

**GenServer Pool Design:**

```elixir
# Supervisor tree for bridge workers
defmodule Bridge.Supervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def start_bridge(platform, thread_id, config) do
    spec = bridge_spec(platform, thread_id, config)
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  defp bridge_spec("slack", thread_id, config) do
    {Bridge.SlackServer, {thread_id, config}}
  end

  defp bridge_spec("telegram", thread_id, config) do
    {Bridge.TelegramServer, {thread_id, config}}
  end
end
```

**Rate Limiting:**
- Token bucket algorithm per bridge
- Slack: 1 req/sec, burst of 5
- Telegram: 30 req/sec, burst of 100
- Queue excess messages, process at max rate
- Exponential backoff on rate limit errors

```elixir
defmodule Bridge.RateLimiter do
  use GenServer

  def init({max_per_sec, burst_size}) do
    {:ok, %{
      tokens: burst_size,
      max_tokens: burst_size,
      refill_rate: max_per_sec,
      last_refill: System.monotonic_time(:millisecond)
    }}
  end

  def handle_call(:acquire, _from, state) do
    state = refill_tokens(state)
    
    if state.tokens >= 1 do
      {:reply, :ok, %{state | tokens: state.tokens - 1}}
    else
      {:reply, {:error, :rate_limited}, state}
    end
  end

  defp refill_tokens(state) do
    now = System.monotonic_time(:millisecond)
    elapsed = now - state.last_refill
    new_tokens = min(
      state.tokens + (elapsed * state.refill_rate / 1000),
      state.max_tokens
    )
    %{state | tokens: new_tokens, last_refill: now}
  end
end
```

### 4.5 AI Abstraction Layer

**Protocol Design (Ready for Future Use):**

```swift
// iOS: AI provider protocol
protocol AIProvider {
  func translate(_ text: String, to language: String) async throws -> TranslationResult
  func analyzeTone(_ text: String) async throws -> ToneAnalysis
  func summarize(_ messages: [Message], length: SummaryLength) async throws -> Summary
  func extractTasks(_ messages: [Message]) async throws -> [Task]
}

struct TranslationResult {
  let translatedText: String
  let originalText: String
  let culturalNotes: [CulturalNote]?
  let confidence: Double
}

struct CulturalNote {
  let type: NoteType  // .idiom, .formality, .urgency
  let originalPhrase: String
  let explanation: String
  let suggestion: String?
}

// On-device implementation (future)
class OnDeviceAIProvider: AIProvider {
  private let model: MLXModel
  
  init() throws {
    self.model = try MLXModel.load(name: "llama-3b-instruct")
  }
  
  func translate(_ text: String, to language: String) async throws -> TranslationResult {
    let prompt = """
    Translate the following text to \(language). Provide cultural context if needed.
    
    Text: \(text)
    
    Format your response as JSON:
    {
      "translation": "...",
      "cultural_notes": [{"type": "...", "phrase": "...", "explanation": "..."}]
    }
    """
    
    let response = try await model.generate(prompt, maxTokens: 300)
    return try JSONDecoder().decode(TranslationResult.self, from: response.data(using: .utf8)!)
  }
}

// Server implementation
class ServerAIProvider: AIProvider {
  private let apiClient: APIClient
  
  func translate(_ text: String, to language: String) async throws -> TranslationResult {
    let request = TranslationRequest(text: text, targetLanguage: language)
    return try await apiClient.post("/ai/translate", body: request)
  }
}

// Factory with feature flag support
class AIService {
  static func createProvider(for tier: SubscriptionTier, privacyMode: Bool) -> AIProvider? {
    switch (tier, privacyMode) {
    case (.free, _):
      return try? OnDeviceAIProvider()  // Free tier: on-device only
    case (.pro, true):
      return try? OnDeviceAIProvider()  // Pro with privacy: on-device
    case (.pro, false), (.enterprise, _):
      return ServerAIProvider(apiClient: .shared)  // Pro/Enterprise: server
    }
  }
}
```

**Backend AI Endpoint (Future):**
```elixir
defmodule MessagingWeb.AIController do
  use MessagingWeb, :controller
  
  def translate(conn, %{"text" => text, "target_lang" => target_lang}) do
    user = conn.assigns.user
    
    # Feature flag check
    unless Accounts.has_feature?(user, :ai_translation) do
      conn
      |> put_status(403)
      |> json(%{error: "AI translation requires Pro tier"})
    else
      result = AI.Service.translate(text, target_lang)
      json(conn, result)
    end
  end
end

defmodule AI.Service do
  @llm Application.compile_env(:messaging, :llm_provider)
  
  def translate(text, target_lang) do
    prompt = """
    Translate to #{target_lang} with cultural context: #{text}
    Respond in JSON format with translation and cultural_notes.
    """
    
    {:ok, chain} = LLMChain.new(llm: @llm)
    |> LLMChain.add_message(Message.new_user!(prompt))
    |> LLMChain.run()
    
    parse_translation_response(chain)
  end
end
```

---

## 5. Project Structure & Development Guidelines

### 5.1 Repository Organization

```
globalbridge-messenger/
├── backend/                    # Phoenix API
│   ├── lib/
│   │   ├── messaging/          # Domain logic (contexts)
│   │   │   ├── accounts.ex     # User management
│   │   │   ├── threads.ex      # Thread operations
│   │   │   ├── messages.ex     # Message CRUD
│   │   │   └── bridges.ex      # Bridge management
│   │   └── messaging_web/      # Web layer
│   │       ├── channels/
│   │       │   └── thread_channel.ex
│   │       ├── controllers/
│   │       │   ├── auth_controller.ex
│   │       │   ├── sync_controller.ex
│   │       │   ├── slack_controller.ex
│   │       │   ├── telegram_controller.ex
│   │       │   └── ai_controller.ex  # Future
│   │       └── live/           # Future: LiveView admin
│   ├── priv/
│   │   ├── repo/
│   │   │   ├── migrations/
│   │   │   └── seeds.exs
│   │   └── static/
│   └── test/                   # Tests mirror lib/ structure
│       ├── messaging/
│       ├── messaging_web/
│       └── integration/
│
├── clients/ios/
│   ├── App/
│   │   ├── GlobalBridgeApp.swift
│   │   └── AppDelegate.swift
│   ├── Core/
│   │   ├── Models/
│   │   │   ├── User.swift
│   │   │   ├── Thread.swift
│   │   │   ├── Message.swift
│   │   │   └── Bridge.swift
│   │   ├── Networking/
│   │   │   ├── APIClient.swift
│   │   │   └── WebSocketClient.swift
│   │   ├── Realtime/
│   │   │   └── PhoenixChannelManager.swift
│   │   ├── Storage/
│   │   │   ├── DatabaseManager.swift
│   │   │   └── CDCManager.swift
│   │   └── Crypto/
│   │       └── EncryptionManager.swift
│   ├── Features/
│   │   ├── Threads/
│   │   │   ├── ThreadListView.swift
│   │   │   ├── ThreadListState.swift
│   │   │   └── ThreadCreationView.swift
│   │   ├── Chat/
│   │   │   ├── ChatView.swift
│   │   │   ├── ChatState.swift
│   │   │   ├── MessageRow.swift
│   │   │   └── MessageComposer.swift
│   │   ├── Bridges/
│   │   │   ├── BridgeSetupView.swift
│   │   │   ├── SlackAuthView.swift
│   │   │   ├── TelegramAuthView.swift
│   │   │   └── BridgeStatusView.swift
│   │   └── AI/              # Future
│   │       ├── AIProvider.swift
│   │       └── TranslationView.swift
│   ├── Shared/
│   │   ├── Extensions/
│   │   ├── Utilities/
│   │   └── Components/
│   └── Tests/
│       ├── Unit/
│       ├── Integration/
│       └── UI/
│
├── shared/
│   └── contracts/              # API schemas
│       ├── message.json
│       ├── thread.json
│       ├── bridge.json
│       └── sync.json
│
├── services/                   # Bridge configuration
│   ├── bridges/
│   │   ├── slack/
│   │   │   ├── manifest.json   # Slack app manifest
│   │   │   └── README.md
│   │   └── telegram/
│   │       └── bot_config.md
│   └── ai/                     # Future
│       └── prompts/
│
└── docs/
    ├── prd.md                  # This document
    ├── architecture.md
    ├── api-spec.md
    └── deployment.md
```

### 5.2 Development Commands

**Backend:**
```bash
# Setup
cd backend
mix deps.get
mix ecto.create && mix ecto.migrate

# Development
mix phx.server                  # Start server on port 4000
iex -S mix phx.server          # Start with interactive console

# Testing
MIX_ENV=test mix test          # Run all tests
MIX_ENV=test mix test --cover  # With coverage report
mix test test/messaging_web/channels/thread_channel_test.exs  # Single file

# Code quality
mix format                      # Format code
mix credo                       # Static analysis
mix dialyzer                    # Type checking
```

**iOS:**
```bash
cd clients/ios

# Build and run
xcodebuild -scheme GlobalBridge \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build

# Test
xcodebuild -scheme GlobalBridge \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test

# Specific test
xcodebuild -scheme GlobalBridge \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -only-testing:GlobalBridgeTests/SyncManagerTests \
  test

# Sync preview app (for testing CDC)
swift run SyncPreview
```

### 5.3 Coding Standards

**Elixir/Phoenix:**
- Run `mix format` before every commit (enforce with pre-commit hook)
- Use pattern matching over conditionals where possible
- Keep contexts under `Messaging.*` namespace
- Follow Phoenix context conventions: `Messaging.Threads.create_thread/2`
- Test files mirror source: `lib/messaging/threads.ex` → `test/messaging/threads_test.exs`
- Use `{:ok, result}` | `{:error, reason}` tuples for functions that can fail
- Document public functions with `@doc` and `@spec`
- Target ≥85% test coverage

Example:
```elixir
defmodule Messaging.Threads do
  @moduledoc """
  Context for managing threads and thread membership.
  """

  alias Messaging.{Repo, Thread, User}

  @doc """
  Creates a new thread with the given attributes.
  """
  @spec create_thread(User.t(), map()) :: {:ok, Thread.t()} | {:error, Ecto.Changeset.t()}
  def create_thread(%User{} = creator, attrs) do
    %Thread{}
    |> Thread.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:creator, creator)
    |> Repo.insert()
  end
end
```

**Swift/iOS:**
- Swift 6 strict concurrency mode enabled
- Use actors for shared mutable state (especially sync logic)
- 4-space indentation
- PascalCase for types/protocols: `ChatThreadView`, `AIProvider`
- camelCase for properties/functions: `syncManager`, `translateMessage()`
- Use async/await over callbacks/closures where possible
- Prefer value types (struct) over reference types (class) unless actor needed
- Mark classes as `final` unless inheritance intended

Example:
```swift
actor SyncManager {
    private var lastSyncTime: Date = .distantPast
    private let database: DatabaseManager
    private let api: APIClient
    
    init(database: DatabaseManager, api: APIClient) {
        self.database = database
        self.api = api
    }
    
    func syncChanges() async throws {
        let localChanges = try await database.getUnsyncedChanges()
        
        // Push to server
        try await api.pushChanges(localChanges)
        
        // Pull from server
        let remoteChanges = try await api.pullChanges(since: lastSyncTime)
        try await database.applyChanges(remoteChanges)
        
        lastSyncTime = Date()
    }
}
```

**Shared Contracts:**
- Use snake_case for JSON keys to match Phoenix serializers
- Version all API endpoints: `/api/v1/...`
- Document schemas in `shared/contracts/` with JSON Schema

Example contract:
```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "Message",
  "type": "object",
  "properties": {
    "id": {"type": "string", "format": "uuid"},
    "thread_id": {"type": "string", "format": "uuid"},
    "sender_id": {"type": "string", "format": "uuid"},
    "content": {"type": "string"},
    "timestamp": {"type": "integer"},
    "source": {"type": "string", "enum": ["native", "slack", "telegram"]}
  },
  "required": ["id", "thread_id", "sender_id", "content", "timestamp", "source"]
}
```

### 5.4 Testing Strategy

**Backend Testing:**
- **Unit tests:** Test contexts in isolation with mocked dependencies
- **Integration tests:** Test full request/response cycles
- **Channel tests:** Test Phoenix Channel interactions with `Phoenix.ChannelTest`
- **Bridge tests:** Test GenServers with mock Slack/Telegram APIs
- Target: ≥85% code coverage

Test organization:
```
test/
├── messaging/                  # Context tests
│   ├── accounts_test.exs
│   ├── threads_test.exs
│   └── bridges_test.exs
├── messaging_web/
│   ├── channels/
│   │   └── thread_channel_test.exs
│   ├── controllers/
│   │   └── sync_controller_test.exs
│   └── integration/
│       └── end_to_end_sync_test.exs
└── support/
    ├── fixtures.ex
    ├── factory.ex
    └── mocks/
        ├── slack_api_mock.ex
        └── telegram_api_mock.ex
```

**iOS Testing:**
- **Unit tests:** Test business logic, state management, data models
- **Integration tests:** Test sync flows with mock backend
- **UI tests:** Test critical user flows (thread creation, message sending, bridge setup)
- Name test suites: `<Feature>Tests` (e.g., `ThreadsTests`, `SyncManagerTests`)

Test organization:
```
Tests/
├── Unit/
│   ├── SyncManagerTests.swift
│   ├── MessageModelTests.swift
│   └── AIProviderTests.swift
├── Integration/
│   ├── PhoenixChannelTests.swift
│   └── BridgeSyncTests.swift
└── UI/
    ├── ThreadCreationTests.swift
    └── MessageComposerTests.swift
```

**Cross-Platform Integration Tests:**
- Document test scenarios in `docs/integration-tests.md`
- Examples:
  - "Slack message → Phoenix Channel → iOS notification"
  - "iOS offline message → CDC queue → server sync → Telegram bridge"
  - "Concurrent edits from multiple clients → conflict resolution"

### 5.5 Security Configuration

**Environment Variables:**

Backend `.env.local`:
```bash
# Phoenix
SECRET_KEY_BASE=<generate with: mix phx.gen.secret>
PHX_HOST=localhost
PORT=4000

# Database
DATABASE_PATH=priv/db/
USE_TURSO_SYNC=false  # Toggle for Turso integration

# Turso (if enabled)
TURSO_AUTH_TOKEN=<from turso.tech console>
TURSO_DATABASE_URL=libsql://your-db.turso.io

# Slack
SLACK_CLIENT_ID=<from api.slack.com/apps>
SLACK_CLIENT_SECRET=<secret>
SLACK_SIGNING_SECRET=<for webhook verification>
SLACK_REDIRECT_URI=http://localhost:4000/auth/slack/callback

# Telegram
TELEGRAM_BOT_TOKEN=<from @BotFather>
TELEGRAM_WEBHOOK_SECRET=<random string for webhook verification>

# AI (Future)
AI_PROVIDER=langchain  # langchain | openai | anthropic
GROK_API_KEY=<optional: for server-side AI>
```

iOS configuration (Xcode schemes):
- Development: Points to `localhost:4000`
- Staging: Points to staging server
- Production: Points to production server
- Store secrets in `Config.plist` (gitignored)
- Never commit API keys or tokens

**Security Best Practices:**
- **Rate Limiting:** 100 requests/minute per user on API endpoints
- **OAuth Scopes:** Minimize Slack/Telegram permissions
  - Slack: `channels:read`, `channels:history`, `chat:write` only
  - Telegram: Bot can only read messages it's mentioned in or group messages
- **Webhook Verification:** Always verify signatures from Slack/Telegram
- **Audit Logging:** Log all bridge activations, user additions, permission changes
- **Secret Rotation:** Rotate API keys/secrets quarterly
- **HTTPS Only:** Enforce TLS for all API communication (App Transport Security on iOS)

---

## 6. Non-Functional Requirements

### 6.1 Performance Requirements

**Latency:**
- Native message delivery: <100ms (P95)
- Bridge sync (webhook mode): <5s (P95)
- Bridge sync (polling mode): <10s (P95)
- CDC sync: <5s for active connections
- AI processing (when implemented):
  - On-device translation: <2s (P95)
  - Server translation: <5s (P95)
  - Thread summarization: <10s for 100-message threads

**Throughput:**
- Phoenix backend: 1M+ concurrent WebSocket connections (Elixir baseline)
- Per-thread messaging: 1000+ messages/second
- Bridge polling: Respect API rate limits (Slack: 1/s, Telegram: 30/s)

**App Performance:**
- Cold start: <2s on iPhone 12+
- Thread list load: <500ms for 100 threads
- Message history load: <300ms for 500 messages
- Memory footprint: <150MB for typical usage

### 6.2 Scalability Requirements

**Data Scale:**
- SQLite per-thread: Up to 100M rows per database
- Total threads per user: No hard limit (storage-bound)
- Concurrent bridges: 1000+ per Phoenix node
- Bridge GenServers: Pool of workers, dynamically supervised

**Scaling Strategy:**
- Horizontal scaling: Add Phoenix nodes behind load balancer
- Database sharding: Per-thread SQLite files enable distributed storage
- Bridge isolation: Each bridge runs in separate GenServer process
- Turso option: Automatic global replication when enabled

**Capacity Planning:**
- Single Phoenix node: ~10,000 concurrent users
- SQLite database: ~100GB per thread before performance degrades
- Bridge polling overhead: ~1MB/hour per active bridge

### 6.3 Reliability Requirements

**Availability:**
- Target: 99.5% uptime (excludes planned maintenance)
- Graceful degradation: Bridge failures don't crash messaging
- Offline capability: Queue up to 10,000 messages locally

**Data Durability:**
- Local SQLite: WAL mode prevents data loss on crash
- CDC log: Persists unsynced changes until server confirms
- Turso (if enabled): Multi-region replication (3+ replicas)
- Backup strategy: Per-thread database files enable granular backups

**Error Handling:**
- Retry logic: Exponential backoff for network failures (max 5 attempts)
- Circuit breaker: Disable failing bridges after 10 consecutive errors
- Fallback: Polling when webhooks fail
- User notification: Show "Disconnected" UI, don't silently fail

### 6.4 Security Requirements

**Encryption:**
- Transport security: TLS 1.3 for all API communication
- Local storage: Encrypted SQLite (AES-256) with per-thread keys
- E2EE: Signal Protocol integration (stretch goal - not required for MVP)
- Key management: iOS Keychain (secure enclave on supported devices)

**Authentication & Authorization:**
- User authentication: JWT tokens with refresh mechanism
- Thread access control: Membership verified on every operation
- Bridge authorization: OAuth 2.0 for Slack, Bot API tokens for Telegram
- Webhook verification: HMAC signature validation for all inbound webhooks

**Privacy:**
- Server knowledge: Backend only sees encrypted blobs (when E2EE enabled)
- AI privacy: On-device processing default for free tier
- Audit trail: Log bridge activations, membership changes
- Data residency: User data stays in selected region (with Turso)

**Compliance:**
- GDPR: User data export (72h), deletion (30 days)
- CCPA: California residents get "Do Not Sell" option
- Platform policies: Adhere to Slack App Directory and Telegram Bot guidelines

### 6.5 Maintainability Requirements

**Code Quality:**
- Test coverage: ≥85% for backend, ≥70% for iOS
- Static analysis: Elixir Credo, Swift SwiftLint
- Type safety: Dialyzer for Elixir, strict Swift 6 concurrency
- Documentation: All public APIs documented with @doc (Elixir), /// (Swift)

**Monitoring & Observability:**
- Structured logging: JSON format for backend (ELK-compatible)
- Real-time metrics: Phoenix LiveDashboard
- Crash reporting: Sentry (backend), Crashlytics (iOS)
- Performance monitoring: Track P50/P95/P99 latencies

**Deployment:**
- Backend: Containerized (Docker), deployed on Fly.io
- Database: SQLite files on persistent volumes
- iOS: TestFlight for beta, App Store for production
- CI/CD: Automated tests on every PR, deploy on merge to main

### 6.6 Usability Requirements

**Accessibility:**
- VoiceOver: Full iOS accessibility support (labels, hints, traits)
- Dynamic Type: Support iOS text size scaling (all UI)
- Contrast: WCAG AA compliant (4.5:1 for normal text)
- Keyboard navigation: Full support for external keyboards

**Internationalization:**
- Initial: English only
- Future: Spanish, French, Hindi, Japanese, Mandarin
- RTL support: Architecture ready (SwiftUI handles automatically)
- Date/time: Respect user's locale

**Onboarding:**
- First-time setup: <3 minutes to send first message
- Bridge setup: <5 taps to activate Slack/Telegram
- Help documentation: Contextual tooltips, video tutorials
- Error messages: Clear, actionable (not technical jargon)

---

## 7. Risks & Mitigation Strategies

### 7.1 Technical Risks

| Risk | Impact | Likelihood | Mitigation Strategy | Owner |
|------|---------|-----------|---------------------|-------|
| Turso sync complexity delays development | High | Medium | Use manual CDC as primary implementation; Turso as optional toggle | Backend Lead |
| E2EE performance overhead on older devices | Medium | Low | Test on iPhone 11 (2019); optimize crypto with hardware acceleration; consider message batching (stretch goal) | iOS Lead |
| Bridge API rate limits cause message delays | High | High | Implement exponential backoff, queue messages, batch reads; monitor with alerts at 80% capacity | Backend Lead |
| Slack/Telegram API breaking changes | High | Low | Version lock dependencies; subscribe to API changelogs; maintain mock APIs for testing | DevOps |
| WebSocket connection stability issues | High | Medium | Implement heartbeat/keepalive; automatic reconnection with exponential backoff; fallback to HTTP polling | Backend Lead |
| SQLite database corruption on crash | High | Low | Use WAL mode; implement automatic corruption detection and recovery; regular backups | iOS Lead |
| Bridge GenServer crashes affect multiple threads | Medium | Low | Supervise with OTP; isolate bridges in separate processes; implement circuit breakers | Backend Lead |

### 7.2 Security & Privacy Risks

| Risk | Impact | Likelihood | Mitigation Strategy | Owner |
|------|---------|-----------|---------------------|-------|
| Webhook endpoints exposed to DoS | Medium | High | Rate limiting at nginx/load balancer; signature verification; IP allowlisting for known sources | DevOps |
| OAuth token leakage | Critical | Low | Store encrypted in database; rotate regularly; limit scopes to minimum required | Backend Lead |
| Man-in-the-middle attacks | Critical | Low | Enforce TLS 1.3; certificate pinning on iOS; reject non-HTTPS connections | iOS Lead |
| Local SQLite data extraction from device | High | Medium | Encrypt database at rest; use iOS Data Protection API; require device passcode | iOS Lead |
| AI model prompts leak sensitive data | High | Medium | Sanitize inputs before AI processing; on-device processing default; audit logging | AI/ML Lead |

### 7.3 Operational Risks

| Risk | Impact | Likelihood | Mitigation Strategy | Owner |
|------|---------|-----------|---------------------|-------|
| Backend scaling costs exceed budget | Medium | Medium | Start with single node; monitor usage; optimize queries before horizontal scaling | DevOps |
| Bridge bugs cause data loss/duplication | High | Medium | Transaction logs with rollback; idempotency keys; comprehensive testing of failure scenarios | Backend Lead |
| Lack of observability into production issues | High | Medium | Implement structured logging; real-time monitoring (LiveDashboard); error tracking (Sentry) | DevOps |
| Dependency vulnerabilities | Medium | High | Automated security scanning (Dependabot); regular dependency updates; audit trail | DevOps |

### 7.4 User Experience Risks

| Risk | Impact | Likelihood | Mitigation Strategy | Owner |
|------|---------|-----------|---------------------|-------|
| Bridge setup flow too complex | High | High | User testing with target personas; streamlined OAuth flows; clear error messages; video tutorials | Product Lead |
| Offline sync conflicts confuse users | Medium | Medium | Clear UI indicators for sync status; conflict resolution notifications; "last synced" timestamps | iOS Lead |
| AI translations inappropriate/offensive | High | Low | Content filtering; user feedback mechanism; ability to disable AI per thread | AI/ML Lead |

---

## 8. Dependencies & Assumptions

### 8.1 External Dependencies

**Infrastructure:**
- Phoenix/Elixir: Stable release (1.7+)
- Swift: Swift 6 with strict concurrency
- SQLite: Version 3.35+ for JSON support
- Turso (optional): iOS/Android SDKs (launched Q1 2025, assume production-ready)

**Third-Party APIs:**
- **Slack API:** Events API v2, OAuth 2.0, no breaking changes expected
- **Telegram Bot API:** Webhook/polling stability (historically 99% uptime)
- **Apple Push Notification Service (future):** For background notifications

**Libraries:**
- SwiftPhoenixClient: Maintained, compatible with Phoenix 1.7+
- Swiftea: Minimal (200 LOC), embedded in project for control
- SQLite.swift: Active maintenance, Swift 6 compatible

### 8.2 Key Assumptions

**Technical:**
- Phoenix Channels provide sufficient performance for real-time messaging (<100ms latency)
- SQLite per-thread sharding scales to 10,000+ threads per user
- iOS devices (iPhone 11+) have sufficient resources for on-device AI (when implemented)
- Manual CDC implementation is feasible within sprint (alternative to Turso)

**User Behavior:**
- Target users are comfortable with OAuth flows (not blocked by corporate policies)
- Users willing to trade minor performance overhead for E2EE privacy
- 60%+ of users will activate at least one bridge within first week
- Offline capability is critical for target personas (NGO workers, travelers)

**Market:**
- Remote work trend continues post-2025 (no major return-to-office shift)
- Slack and Telegram APIs remain accessible to third-party developers
- Privacy concerns drive demand for E2EE and on-device processing
- Multi-platform messaging fragmentation persists (no dominant unified solution emerges)

### 8.3 Out of Scope (Explicitly Not Included)

**MVP Exclusions:**
- AI features (translation, summarization) - architecture ready, not implemented
- Full E2EE implementation - crypto layer designed, keys not exchanged (stretch goal)
- Video/voice calls
- File storage beyond basic media (images)
- Desktop clients (macOS, Windows, Linux)
- WhatsApp, Discord, MS Teams bridges
- Advanced analytics and usage tracking
- Team management features (roles, permissions)

**Future Considerations:**
- Federation with other instances (ActivityPub, Matrix protocol)
- Blockchain-based identity verification
- Decentralized storage (IPFS)
- WebRTC for peer-to-peer calls

---

## 9. Appendices

### A. Glossary

- **CDC (Change Data Capture):** Mechanism to track and sync database changes between client and server
- **E2EE (End-to-End Encryption):** Data encrypted on sender's device, decrypted only on recipient's device
- **GenServer:** Erlang/Elixir process abstraction for building stateful services
- **MLX:** Apple's machine learning framework for on-device LLM inference
- **Phoenix Channels:** WebSocket abstraction in Phoenix framework for real-time bidirectional communication
- **Signal Protocol:** Industry-standard E2EE protocol used by Signal, WhatsApp
- **TEA/MVU:** The Elm Architecture / Model-View-Update, functional state management pattern
- **Turso:** SQLite-based edge database with global replication capabilities
- **WAL (Write-Ahead Logging):** SQLite journaling mode that improves concurrency and crash recovery
- **Bridge:** Integration that connects GlobalBridge threads with external platforms (Slack, Telegram)
- **Thread:** Conversation or chat group within GlobalBridge
- **Feature Flag:** Configuration toggle that enables/disables functionality based on user tier

### B. Technical References

**Documentation:**
- [Phoenix Framework](https://hexdocs.pm/phoenix/Phoenix.html)
- [Phoenix Channels](https://hexdocs.pm/phoenix/channels.html)
- [Elixir GenServer](https://hexdocs.pm/elixir/GenServer.html)
- [Swift Concurrency](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [SwiftUI](https://developer.apple.com/documentation/swiftui)
- [SQLite Documentation](https://www.sqlite.org/docs.html)

**Libraries & Frameworks:**
- [SwiftPhoenixClient](https://github.com/davidstump/SwiftPhoenixClient) - Phoenix Channels client for iOS
- [Swiftea](https://github.com/cooler333/Swiftea) - TEA/MVU state management for Swift
- [SQLite.swift](https://github.com/stephencelis/SQLite.swift) - Type-safe SQLite wrapper
- [Turso](https://turso.tech/docs) - Distributed SQLite platform

**APIs:**
- [Slack Events API](https://api.slack.com/events-api)
- [Slack OAuth](https://api.slack.com/authentication/oauth-v2)
- [Telegram Bot API](https://core.telegram.org/bots/api)
- [Telegram Webhooks](https://core.telegram.org/bots/webhooks)

**Security:**
- [Signal Protocol](https://signal.org/docs/)
- [libsodium](https://doc.libsodium.org/) - Modern cryptography library
- [CryptoKit](https://developer.apple.com/documentation/cryptokit) - Apple's cryptography framework

**AI/ML (Future):**
- [MLX Swift](https://github.com/ml-explore/mlx-swift) - Apple's ML framework
- [LangChain](https://python.langchain.com/docs/get_started/introduction) - LLM application framework

### C. API Contract Examples

**Message Schema:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "thread_id": "thread_abc123",
  "sender_id": "user_xyz789",
  "content": "Hello, world!",
  // "encrypted_content": null,  // E2EE stretch goal - not implemented in MVP
  "timestamp": 1698019200000,
  "source": "native",
  "metadata": {
    "reply_to": null,
    "attachments": []
  }
}
```

**CDC Change Record:**
```json
{
  "id": 1234,
  "table_name": "messages",
  "operation": "INSERT",
  "record_id": "550e8400-e29b-41d4-a716-446655440000",
  "changes": {
    "content": "Hello, world!",
    "timestamp": 1698019200000
  },
  "timestamp": 1698019200100,
  "synced": false,
  "sync_attempts": 0
}
```

**Bridge Configuration:**
```json
{
  "id": "bridge_slack_001",
  "thread_id": "thread_abc123",
  "platform": "slack",
  "config": {
    "token": "xoxb-...",
    "channel_id": "C01234567",
    "webhook_url": "https://hooks.slack.com/services/...",
    "team_id": "T01234567"
  },
  "status": "active",
  "rate_limit_config": {
    "max_per_sec": 1,
    "burst_size": 5
  },
  "created_at": 1698019200000
}
```

### D. Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | Oct 20, 2025 | Team | Initial PRD from repository synthesis |
| 2.0 | Oct 20, 2025 | Team | Refined to technical focus: removed timelines, pricing, KPIs; emphasized AI-ready architecture and feature flag system |
| 2.1 | Oct 24, 2025 | Team | Updated Telegram Bridge section (F4) with detailed implementation plan; added references to `docs/telegram-bridge-prd.md` for complete technical specification |

### F. Related Documents

| Document | Location | Purpose |
|----------|----------|---------|
| **Telegram Bridge Implementation PRD** | `docs/telegram-bridge-prd.md` | Complete technical specification for Telegram bridge feature including backend API, database schema, frontend integration, testing strategy, and deployment guide |
| **iOS Frontend PRD** | `.taskmaster/docs/ios-ai-frontend-prd-updated.md` | iOS client implementation details and API integration |
| **API Documentation** | `docs/API_DOCUMENTATION.md` | Auto-generated OpenAPI specification for all backend endpoints |
| **Backend Implementation Summary** | `docs/ios-prd-backend-sync-analysis.md` | Analysis of backend-iOS synchronization patterns |

### E. Approval & Sign-off

**Product Lead:** _____________________________ Date: __________

**Engineering Lead:** ___________________________ Date: __________

**Security Lead:** ______________________________ Date: __________

---

**Document Classification:** Internal - Technical Specification  
**Next Review:** As needed for significant architectural changes
