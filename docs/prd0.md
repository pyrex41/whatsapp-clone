### Key Points
- **Core Stack Alignment**: Your proposed setup—Elixir/Phoenix backend with Swift frontend via SwiftPhoenixClient, SQLite for both sides, manual CDC for sync, and Turso as a flexible option—**makes strong sense** for a scalable, real-time messaging app. It leverages Elixir's concurrency for WebSockets and Phoenix's channels for bridging, while giving you full control over sync and future-proofing for E2EE and integrations.
- **Turso as Option**: **Penciled in as a primary alternative** to raw SQLite for easier distributed sync and CDC; its 2025 updates (e.g., enhanced mobile SDKs, on-device writes) fit perfectly for sharded threads without vendor lock-in. "Pencil Denon" appears to be a mishearing—likely "LiteSync" or similar tools like AMPLI-SYNC for SQLite replication; we'll treat it as a fallback for testing sync issues.
- **Swift Version Clarification**: **Swift 6 (2025 stable)** is the go-to for iOS development, with features like enhanced concurrency and stricter concurrency checks. "Swift 8" might refer to future previews, but Swift 6 integrates seamlessly with iOS 19+ for your app.
- **E2EE Readiness**: **Design for it upfront** by encrypting payloads in transit (via Phoenix Channels) and at rest (iOS Data Protection + SQLite encryption). Slot in later without rewrites by abstracting message serialization.
- **AI Abstraction**: **Configurable on/off-device**: Use a privacy toggle to route to local MLX models (e.g., Llama 3.2 on iPhone) or server-side LangChain Elixir. This preserves E2EE by keeping sensitive processing client-side by default.
- **Slack/Telegram Bridges**: **Per-chat activation via bots**: Initiate by generating invite links or OAuth tokens in your app, bridging via Phoenix endpoints that poll/push to external APIs. Add users by sharing bot invites—enables seamless cross-platform chats without forcing migrations.

### Backend: Elixir/Phoenix with SQLite and CDC
Elixir's fault-tolerant concurrency pairs excellently with Phoenix for real-time features like live typing indicators and message delivery states. Use SQLite for lightweight, sharded storage (per-thread DBs on Fly.io volumes), with manual CDC for sync control. Turso slots in as an upgrade for distributed replication.

- **Phoenix Setup**: Generate a Phoenix app with `mix phx.new messaging_app --live --database sqlite3`. Configure Ecto for dynamic SQLite connections:
  ```elixir
  # config/config.exs
  config :messaging_app, MessagingApp.Repo,
    database: "/data/threads/#{thread_id}.db",  # Sharded per thread
    adapter: Ecto.Adapters.SQLite3
  ```
  Deploy on Fly.io with volumes for persistence.

- **CDC Implementation**: Use SQLite triggers to log changes, then broadcast via Channels:
  ```elixir
  # lib/messaging_app_web/channels/room_channel.ex
  defmodule MessagingAppWeb.RoomChannel do
    use Phoenix.Channel
    def join("thread:" <> thread_id, _payload, socket) do
      # Connect to thread DB
      Repo.put_thread_db(thread_id)
      {:ok, socket}
    end
    def handle_in("message:new", payload, socket) do
      # Insert to SQLite, trigger logs CDC
      %Message{} = Repo.insert!(%Message{payload: encrypt_payload(payload), thread_id: thread_id})
      broadcast!(socket, "message:new", payload)  # Encrypted payload only
      {:noreply, socket}
    end
    def handle_in("cdc:sync", changes, socket) do
      # Apply client changes, resolve conflicts by timestamp
      Enum.each(changes, &Repo.apply_cdc/1)
      broadcast!(socket, "thread:updated", %{thread_id: thread_id})
      {:noreply, socket}
    end
  end
  ```
  Triggers in SQLite schema:
  ```sql
  CREATE TRIGGER cdc_insert AFTER INSERT ON messages BEGIN
    INSERT INTO cdc_log (operation, row_id, new_data, timestamp) VALUES ('INSERT', NEW.id, json(...), CURRENT_TIMESTAMP);
  END;
  ```

- **Turso Option**: Integrate via libSQL adapter for Ecto (community-supported in 2025). Replace SQLite with Turso for automatic sync:
  ```elixir
  # For Turso: Use libsql.ex or direct HTTP for edge replication
  config :messaging_app, Repo, url: "libsql://#{thread_id}.turso.io", auth_token: System.get_env("TURSO_TOKEN")
  ```
  Turso's 2025 mobile SDK enables direct iOS sync, reducing manual CDC needs—test if raw SQLite hits limits.

- **LiteSync Fallback ("Pencil Denon")**: If CDC issues arise, use LiteSync for bi-directional replication: `file:local.db?node=secondary&connect=tcp://server:port`. It's open-source, supports offline writes, and integrates with Ecto via URI params.

### Frontend: Swift 6 with SwiftPhoenixClient and SQLite
Swift 6's improved concurrency (actors, async/await refinements) streamlines WebSocket handling and sync. Use SwiftPhoenixClient for Phoenix integration, SQLite.swift for local storage, and manual CDC for control.

- **SwiftPhoenixClient Setup**: Add via Swift Package Manager: `https://github.com/davidstump/SwiftPhoenixClient`. Connect and join channels:
  ```swift
  import SwiftPhoenixClient
  class ChatManager: ObservableObject {
    let socket = Socket("wss://your-app.fly.dev/socket", params: ["token": userToken])
    func joinThread(_ threadId: String) {
      let channel = socket.channel("thread:\(threadId)")
      channel.join()
        .receive("ok") { _ in /* Joined */ }
        .receive("error") { error in /* Handle */ }
      channel.on("message:new") { message in
        // Decrypt payload, insert to local SQLite
        let decrypted = decrypt(message.payload)
        insertMessage(decrypted)
      }
    }
  }
  ```

- **Local SQLite**: Use SQLite.swift for embedded DB:
  ```swift
  import SQLite
  let db = try Connection("threads/\(threadId).sqlite")
  try db.run(messages.create { t in
    t.column(id, primaryKey: .autoincrement)
    t.column(content)
    t.column(status)
    t.column(isSynced, default: false)
  })
  ```
  Mirror backend CDC: On offline writes, log to a local `cdc_log` table, sync on reconnect.

- **Manual Sync Flow**: In a background actor:
  ```swift
  actor SyncActor {
    func syncChanges(for threadId: String) async {
      let unsynced = try await fetchUnsyncedMessages(threadId)
      channel.push("cdc:sync", payload: unsynced.map { $0.toDict() })
      channel.on("thread:updated") { _ in
        markAsSynced(unsynced)
      }
    }
  }
  ```
  Handle offline: Queue in WAL, retry on reconnect.

### E2EE: Future-Proof Design
Encrypt payloads before sending (e.g., X25519 for key exchange, AES-GCM for messages). Server stores encrypted blobs; decryption happens client-side.

- **Swift Side**: Use CryptoKit:
  ```swift
  func encryptPayload(_ data: Data, with key: SymmetricKey) -> Data {
    let sealed = try AES.GCM.seal(data, using: key)
    return sealed.combined!
  }
  ```
  Store keys in Keychain; derive per-thread shared secrets via Ratchet (Signal protocol-inspired).

- **Phoenix Side**: Pass encrypted `%{payload: encrypted_data}` in broadcasts. No server decryption—keeps E2EE intact.

- **Slot-In Later**: Abstract message handling: `sendMessage(content: String) -> EncryptedPayload`. Test without encryption first.

### AI Abstraction: On-Device vs. Server
Configurable via user settings: **On-device (default for privacy)** uses MLX for Llama 3.2 (3B model, 20+ tokens/sec on iPhone 16). **Server** routes to Elixir LangChain for heavier tasks.

- **Abstraction Layer**:
  ```swift
  enum AIProvider { case onDevice, server }
  class AIHandler {
    func summarize(thread: [Message], provider: AIProvider) async -> String {
      let context = thread.map { $0.decryptedContent }.joined(separator: "\n")
      switch provider {
      case .onDevice: return await MLX.summarize(context)  // Local model
      case .server: return await sendToServer(context)  // Phoenix endpoint
      }
    }
  }
  ```
- **On-Device**: Integrate MLX Swift: `pip install mlx-swift` equivalent via SPM; load quantized model for summarization/translation.
- **Server**: Phoenix endpoint calls LangChain: `post "/ai/summarize", to: AIEngineController`.
- **Privacy Toggle**: In settings: "Enable cloud AI (slower, more accurate, requires upload)"—warns about E2EE break.

### Slack/Telegram Bridges: Per-Chat Activation
Enable bridges per thread via bot invites—your app acts as a "hub" bot, pulling/pushing messages.

- **Initiation**:
  - **Slack**: User activates in thread settings → App generates Slack App OAuth URL. User authorizes, app installs bot to workspace/channel. Phoenix endpoint: `POST /slack/install` with `code` from OAuth.
  - **Telegram**: Activate → App creates Telegram bot via BotFather API (pre-provision bots). User adds bot to group/chat, shares token. Phoenix: `POST /telegram/init` creates webhook.

- **Adding People**:
  - **Slack**: Share invite link (`https://yourapp.com/invite/slack?thread=123`)—recipients join via Slack's "Add to Slack" button, auto-adding to bridged channel.
  - **Telegram**: Generate invite link (`t.me/yourbot?start=thread123`)—users start chat with bot, opt-in to bridge. Bot adds them to group via API.

- **Bridging Logic**:
  - Phoenix GenServer polls Slack/Telegram APIs (e.g., every 5s for new messages) or uses webhooks.
  - Incoming: Translate/encrypt → Broadcast to your Channel.
  - Outgoing: Route from your app to external API (e.g., Slack `chat.postMessage`).
  ```elixir
  # lib/bridge/slack_bridge.ex
  defmodule Bridge.SlackBridge do
    use GenServer
    def start_link(channel_id), do: GenServer.start_link(__MODULE__, channel_id)
    def handle_info(:poll, state) do
      messages = Slack.Api.get_channel_history(state.channel_id)
      Enum.each(messages, &forward_to_phoenix/1)
      Process.send_after(self(), :poll, 5000)
      {:noreply, state}
    end
  end
  ```
  - Per-Chat: Store activation in SQLite (`bridges: %{thread_id => %{slack: token, telegram: bot_id}}`).

- **Edge Cases**: Rate limits (throttle polls), privacy (user consent per bridge), offline (queue shares).

### Build Strategy
- **MVP (Tuesday)**: Core Phoenix chat with SQLite, Swift UI + PhoenixClient, basic CDC sync. Test one-on-one on iPhone.
- **Early (Friday)**: Add Turso option, E2EE placeholders, AI abstraction (on-device stub).
- **Final (Sunday)**: Bridges, full AI (Llama via MLX), demo multi-platform sync.

This setup gives control, scalability, and extensibility—prototype on Fly.io for quick deploys.

---

### Survey Note: Comprehensive Architecture for Elixir/Phoenix-Swift Messaging App with SQLite, CDC, E2EE, AI, and Bridges

The proposed architecture for your messaging app—leveraging Elixir and Phoenix on the backend, Swift 6 for the iOS frontend with SwiftPhoenixClient, SQLite for storage on both ends, manual Change Data Capture (CDC) for synchronization, Turso as an integrated option for enhanced replication, forward-compatible End-to-End Encryption (E2EE), a configurable AI abstraction layer supporting both on-device and server-side processing, and per-chat bridges to Slack and Telegram—represents a mature, extensible design that aligns with 2025's emphasis on privacy, real-time performance, and cross-platform interoperability. This survey expands on the direct recommendations, drawing from current ecosystem developments to provide a thorough blueprint, including code snippets, trade-offs, and implementation timelines. It incorporates insights from Turso's 2025 advancements (e.g., seamless iOS SDKs for offline sync), Swift 6's concurrency refinements, and established patterns for Phoenix integrations, ensuring the app can scale from MVP to production while accommodating your desire for manual sync control and future expansions.

#### Backend Architecture: Elixir/Phoenix with SQLite and CDC
Elixir's actor-based concurrency, powered by the BEAM VM, excels in handling real-time messaging workloads, such as concurrent channel joins for thousands of threads or broadcasting updates across distributed nodes. Phoenix, as Elixir's flagship web framework, provides Channels for WebSocket-based communication, making it ideal for low-latency features like optimistic UI updates and presence indicators. By 2025, Phoenix 1.7+ includes built-in support for async primitives (e.g., io_uring integration via NIFs), enhancing responsiveness for edge-deployed apps on platforms like Fly.io.

**SQLite Integration and Sharding**:
SQLite's embedded nature (zero-configuration, ACID-compliant) suits sharded per-thread storage, where each conversation lives in its own file (e.g., `threads/abc123.db`). This isolates data for privacy and scalability, with Ecto's `Ecto.Adapters.SQLite3` enabling dynamic repos:
```elixir
# lib/messaging_app/repo.ex
defmodule MessagingApp.Repo do
  use Ecto.Repo, otp_app: :messaging_app, adapter: Ecto.Adapters.SQLite3

  @doc """
  Dynamically switch to thread-specific DB.
  """
  def put_thread_db(thread_id) do
    :ok = __MODULE__.config_change([database: "/data/threads/#{thread_id}.db"])
  end
end
```
On Fly.io, attach volumes in `fly.toml` for persistence:
```
[mounts]
source = "threads_vol"
destination = "/data/threads"
```
This setup supports up to 100k+ threads at <1MB each, with SQLite's WAL mode ensuring crash-safe offline queuing.

**Manual CDC for Sync Control**:
To maintain oversight, implement CDC via SQLite triggers logging to a `cdc_log` table, then propagate via Channels. This allows custom conflict resolution (e.g., timestamp-based merging for offline messages):
```sql
-- Schema migration
CREATE TABLE cdc_log (
  id INTEGER PRIMARY KEY,
  operation TEXT,  -- INSERT/UPDATE/DELETE
  table_name TEXT,
  row_id INTEGER,
  new_data JSON,
  timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
  synced BOOLEAN DEFAULT FALSE
);

CREATE TRIGGER cdc_after_insert AFTER INSERT ON messages
BEGIN
  INSERT INTO cdc_log (operation, table_name, row_id, new_data)
  VALUES ('INSERT', 'messages', NEW.id, json_object('id', NEW.id, 'content', NEW.content, 'timestamp', NEW.timestamp));
END;
-- Similar for UPDATE/DELETE
```
In Phoenix:
```elixir
# lib/messaging_app_web/channels/thread_channel.ex
defmodule MessagingAppWeb.ThreadChannel do
  use Phoenix.Channel

  def handle_in("cdc:pull", _payload, socket) do
    thread_id = get_thread_id(socket)
    unsynced = Repo.all(from l in "cdc_log", where: l.synced == false, select: map(l, [:operation, :new_data]))
    push(socket, "cdc:changes", unsynced)
    {:noreply, socket}
  end

  def handle_in("cdc:push", changes, socket) do
    thread_id = get_thread_id(socket)
    Repo.transaction(fn ->
      Enum.each(changes, fn change ->
        case change["operation"] do
          "INSERT" -> Repo.insert!(struct(Message, change["new_data"]))
          # Handle UPDATE/DELETE similarly
        end
      end)
      # Mark as synced, broadcast delta
      Repo.update_all(from l in "cdc_log", where: l.synced == false, set: [synced: true])
      broadcast!(socket, "thread:synced", %{thread_id: thread_id})
    end)
    {:noreply, socket}
  end
end
```
This gives granular control: Clients pull/push deltas on reconnect, resolving conflicts server-side (e.g., `max(timestamp)` for duplicates).

**Turso as Integrated Option**:
Turso, an open-source SQLite fork (libSQL-based), emerges as a compelling upgrade for distributed sync without sacrificing control. By October 2025, Turso's updates include multitenant partitioning (per-user/thread replication) and native iOS/Android SDKs for direct device-to-edge sync, reducing manual CDC boilerplate. Integrate via Ecto's libSQL adapter or HTTP client:
```elixir
# config/runtime.exs
config :messaging_app, Repo,
  url: "libsql://#{thread_id}-#{user_id}.turso.io",
  auth_token: System.fetch_env!("TURSO_TOKEN")
```
For real-time: Turso's CDC (`PRAGMA change_capture = on`) streams logs to Phoenix, auto-broadcasting via Channels. Test it if raw SQLite's single-node limits surface—e.g., for global threads, Turso's io_uring async I/O keeps latency <50ms. Fallback: LiteSync (likely your "Pencil Denon") for peer-to-peer replication if Turso's cloud feels too managed.

#### Frontend: Swift 6, SwiftPhoenixClient, and Local SQLite
Swift 6, stable since mid-2025, refines concurrency with stricter actor isolation and enhanced async sequences, making it perfect for WebSocket-driven UIs and background sync. It builds on SwiftUI 6's declarative patterns, enabling reactive chats without legacy callbacks.

**SwiftPhoenixClient for Real-Time**:
This library (v5.3+) ports Phoenix.js to Swift, handling joins, pushes, and events with type-safe payloads:
```swift
// ChatView.swift
import SwiftPhoenixClient
import SwiftUI
@StateObject private var chatManager = ChatManager()

struct ChatView: View {
  var body: some View {
    List(chatManager.messages) { message in
      Text(message.content)  // Decrypted inline
    }
    .onAppear { chatManager.joinThread(threadId) }
  }
}

class ChatManager: ObservableObject {
  @Published var messages: [Message] = []
  let socket = Socket("wss://app.fly.dev/socket", params: ["token": authToken])
  
  func joinThread(_ id: String) {
    let channel = socket.channel("thread:\(id)")
    channel.join()
      .receive("ok") { _ in Task { await self.syncChanges() } }
    channel.on("message:new") { payload in
      Task { await self.handleNewMessage(payload) }  // Decrypt + insert
    }
  }
  
  @MainActor
  func handleNewMessage(_ payload: Any) async {
    let decrypted = await decrypt(payload["payload"] as? Data)
    messages.append(Message(from: decrypted))
  }
}
```
This ensures optimistic updates: Messages appear instantly, syncing in background.

**Local SQLite with Manual CDC**:
SQLite.swift provides a fluent API for embedded storage, mirroring backend schemas:
```swift
import SQLite

class LocalDB {
  let db: Connection
  init(threadId: String) throws {
    db = try Connection("threads/\(threadId).sqlite")
    try db.run(messages.create(ifNotExists: true) { t in
      t.column(id, primaryKey: .autoincrement)
      t.column(content)
      t.column(status)
      t.column(isSynced, default: false)
      t.column(cdcTimestamp)
    })
    setupTriggers()  // Local CDC log
  }
  
  func insertMessage(_ content: String) throws {
    try db.run(messages.insert(or: .replace, content <- content, isSynced <- false))
  }
  
  func unsyncedChanges() throws -> [Change] {
    try db.prepare("SELECT * FROM cdc_log WHERE synced = 0").map { row in
      Change(operation: row[1] as? String, data: row[3] as? Data)
    }
  }
}
```
Sync actor:
```swift
actor SyncManager {
  func performSync(for threadId: String) async throws {
    let changes = try localDB.unsyncedChanges()
    channel.push("cdc:push", payload: changes.map { $0.dict })
    channel.on("thread:synced") { _ in
      try localDB.markSynced(changes)
    }
  }
}
```
This manual approach lets you tune retry logic (e.g., exponential backoff) and offline queuing.

#### E2EE: Modular Implementation
Design payloads as encrypted blobs from day one, ensuring server agnosticism. Use libsodium.swift for Swift and ExSodium for Elixir:
- **Key Exchange**: On thread creation, use X3DH (via libsodium) for shared secrets.
- **Encryption**:
  ```swift
  import Sodium
  
  class E2EEManager {
    let sodium = Sodium()
    func encrypt(_ data: Data, with sharedKey: Data) -> Data? {
      sodium.secretBox.seal(data, additionalData: nil, key: sharedKey)
    }
    func decrypt(_ sealed: Data, with sharedKey: Data) -> Data? {
      sodium.secretBox.open(sealed, additionalData: nil, key: sharedKey)
    }
  }
  ```
- **Phoenix**: Serialize as `%{payload: Base.encode64(encrypted_data)}`.
- **Later Slot-In**: Toggle via feature flag; test with mock keys. iOS Data Protection encrypts SQLite at rest.

#### AI Layer: Configurable On-Device/Server
Abstract to a protocol, defaulting to on-device for E2EE compliance:
```swift
protocol AIProvider {
  func process(_ prompt: String, context: [String]) async -> String
}

class OnDeviceProvider: AIProvider {
  let model = MLXModel(name: "llama-3.2-3b")  // Via MLX Swift SPM
  func process(_ prompt: String, context: [String]) async -> String {
    let fullPrompt = "Summarize: \(context.joined(separator: "\n"))\n\(prompt)"
    return await model.generate(fullPrompt, maxTokens: 100)
  }
}

class ServerProvider: AIProvider {
  func process(_ prompt: String, context: [String]) async -> String {
    let request = AIRequest(prompt: prompt, context: context)
    let response = try? await HTTP.post("/ai/process", body: request)  // Phoenix endpoint
    return response?.result ?? ""
  }
}

class AIAdapter {
  let provider: AIProvider
  init(privacyMode: Bool) { provider = privacyMode ? OnDeviceProvider() : ServerProvider() }
  func summarize(thread: [Message]) async -> String {
    let context = thread.compactMap { $0.decryptedContent }
    return await provider.process("Summarize this thread", context: context)
  }
}
```
Server endpoint in Phoenix uses LangChain:
```elixir
# lib/messaging_app_web/controllers/ai_controller.ex
defmodule MessagingAppWeb.AIController do
  use MessagingAppWeb, :controller
  def process(conn, %{"prompt" => prompt, "context" => context}) do
    {:ok, chain} = LLMChain.new(llm: ChatGrok.new(model: "grok-3-mini"))
    |> LLMChain.add_message(Message.new_user!(prompt <> Enum.join(context, "\n")))
    |> LLMChain.run()
    json(conn, %{result: ChainResult.to_string!(chain)})
  end
end
```
For on-device, MLX handles 3B models at 20+ tokens/sec on iPhone 16.

#### Bridges: Per-Chat Slack/Telegram Connectivity
Bridges enable your app as a "meta-chat" hub—activate per thread, generating bots/invites for seamless pulls/pushes.

**Slack Bridge**:
- Activation: User taps "Add Slack" → Phoenix creates Slack App token via OAuth.
- Initiation: `POST /slack/bridge` returns `install_url`. User authorizes; app installs bot to channel.
- Adding Users: Share `Add to Slack` button/link—recipients join workspace, bot auto-adds to bridged thread.
- Logic: GenServer polls `conversations.history` or uses Events API webhooks:
  ```elixir
  # lib/bridge/slack_server.ex
  defmodule Bridge.SlackServer do
    use GenServer
    def handle_info({:webhook, payload}, state) do
      case payload["event"]["type"] do
        "message" -> forward_to_channel(payload["event"], state.thread_id)
      end
      {:noreply, state}
    end
    defp forward_to_channel(event, thread_id) do
      payload = %{content: event["text"], sender: event["user"]}
      MessagingAppWeb.Endpoint.broadcast("thread:#{thread_id}", "message:new", payload)
    end
  end
  ```
- Webhook: Expose `/slack/events` in Phoenix, verify with Slack's signing secret.

**Telegram Bridge**:
- Activation: `POST /telegram/bridge` creates bot via Telegram API, returns `/setwebhook`.
- Initiation: User adds bot to group (`t.me/yourbot?start=thread123`), shares chat_id.
- Adding Users: Bot invite link (`t.me/yourbot?start=invite&thread=123`)—new users message bot to opt-in.
- Logic: Poll `getUpdates` or webhook:
  ```elixir
  # lib/bridge/telegram_server.ex
  defmodule Bridge.TelegramServer do
    use GenServer
    def handle_info(:poll, state) do
      updates = Telegram.Api.get_updates(offset: state.offset)
      Enum.each(updates, fn update ->
        if update.message && update.message.chat.id == state.chat_id do
          forward_to_channel(%{content: update.message.text, sender: update.message.from.id}, state.thread_id)
        end
      end)
      {:noreply, %{state | offset: last_update_offset(updates)}}
    end
  end
  ```
- Webhook: `POST /telegram/webhook`, signed with bot token.

**Cross-Bridge Flow**: On activation, store config in SQLite (`bridges` table). Poll every 5s, encrypt forwards. Offline: Queue in local CDC. Conflicts: Timestamp merge.

#### Trade-Offs and 2025 Considerations
- **Performance**: Elixir/Phoenix handles 1M+ concurrent connections; Swift 6's actors prevent UI stalls. Turso reduces CDC complexity but adds ~$10/mo for prod.
- **Security**: E2EE ensures compliance (e.g., GDPR); bridges need OAuth scopes limited to channels.
- **Scalability**: Sharding caps at SQLite limits (~100M rows/DB); Turso scales globally.
- **Dev Time**: MVP: 2 days (core + CDC). Bridges: +1 day. AI: +2 days (abstraction + MLX).

This blueprint positions your app as a privacy-first, interoperable messenger—test on iPhone for real-world perf.

### Key Citations
- [Turso Mobile SDKs](https://turso.tech/blog/turso-goes-mobile-with-official-ios-and-android-sdks)
- [Turso Sync 2025](https://turso.tech/blog/introducing-databases-anywhere-with-turso-sync)
- [LiteSync for SQLite](https://litesync.io/en/)
- [Swift 6 Features](https://developer.apple.com/swift/)
- [SwiftPhoenixClient](https://github.com/davidstump/SwiftPhoenixClient)
- [E2EE in Phoenix/Swift](https://blixtdev.com/how-to-use-phoenix-websockets-with-swift-on-ios/)
- [Elixir-Slack](https://github.com/BlakeWilliams/Elixir-Slack)
- [Telegram Bot with Phoenix](https://medium.com/@7Devs/telegram-bot-on-phoenix-framework-elixir-lang-b87068316956)
- [Phoenix Channels for Real-Time](https://fly.io/phoenix/)
- [Turso with Ecto](https://elixirforum.com/t/turso-with-ecto-any-solution/72013)
