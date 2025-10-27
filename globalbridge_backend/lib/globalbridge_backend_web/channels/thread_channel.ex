defmodule GlobalbridgeBackendWeb.ThreadChannel do
  @moduledoc """
  Channel for real-time thread messaging.

  Optimized for <100ms latency with:
  - Direct PubSub broadcasting (no intermediary processes)
  - Minimal serialization overhead
  - Async message persistence
  - Connection pooling for database operations
  """
  use GlobalbridgeBackendWeb, :channel

  alias GlobalbridgeBackend.Chat
  alias GlobalbridgeBackend.Contexts.Messages
  alias GlobalbridgeBackend.Notifications
  alias GlobalbridgeBackend.Sync
  alias GlobalbridgeBackend.Cache.ParticipantCache
  alias GlobalbridgeBackend.AI.{ConversationMonitor, SmartReplyGenerator}
  alias GlobalbridgeBackendWeb.Presence
  require Logger

  @doc """
  Join a thread channel with authorization.

  Users can only join threads they are participants in.
  """
  @impl true
  def join("thread:" <> thread_id, _payload, socket) do
    # Normalize thread_id to lowercase for case-insensitive UUID lookup
    thread_id = String.downcase(thread_id)
    user_id = socket.assigns.user_id

    Logger.info("🔌 Channel join attempt: thread=#{thread_id}, user=#{user_id}")

    case authorize_user(thread_id, user_id) do
      {:ok, thread} ->
        Logger.info("✅ Channel join authorized: thread=#{thread_id}, user=#{user_id}")

        # Assign thread info to socket for fast access
        socket =
          socket
          |> assign(:thread_id, thread_id)
          |> assign(:thread, thread)

        # Track join time for latency metrics and defer presence setup
        send(self(), :after_join)

        {:ok, %{thread_id: thread_id, joined_at: DateTime.utc_now()}, socket}

      {:error, :not_participant} ->
        Logger.warning(
          "❌ Channel join denied (not participant): thread=#{thread_id}, user=#{user_id}"
        )

        {:error, %{reason: "Not authorized to join this thread"}}

      {:error, :thread_not_found} ->
        Logger.warning(
          "❌ Channel join denied (thread not found): thread=#{thread_id}, user=#{user_id}"
        )

        {:error, %{reason: "Thread not found"}}

      {:error, reason} ->
        Logger.error(
          "❌ Channel join failed: thread=#{thread_id}, user=#{user_id}, reason=#{inspect(reason)}"
        )

        {:error, %{reason: "Unable to join thread"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Track user presence in this thread
    thread_id = socket.assigns.thread_id
    user_id = socket.assigns.user_id

    Logger.debug("👋 After join: tracking presence for user=#{user_id} in thread=#{thread_id}")

    # Start tracking presence
    {:ok, _} =
      Presence.track_user(socket, user_id, %{
        online_at: System.system_time(:millisecond),
        thread_id: thread_id
      })

    # Push current presence state to newly joined user
    push(socket, "presence_state", Presence.list(socket))

    # Start monitoring this thread for AI suggestions
    ConversationMonitor.monitor_thread(thread_id)

    Logger.debug("📊 Presence state pushed and AI monitoring started for user=#{user_id}")

    {:noreply, socket}
  end

  @impl true
  def handle_info({:ai_suggestions, suggestions}, socket) do
    # Broadcast AI suggestions to all participants in real-time
    thread_id = socket.assigns.thread_id

    Logger.info("🤖 Broadcasting #{length(suggestions)} AI suggestions to thread:#{thread_id}")

    # Push to all connected users in thread
    broadcast!(socket, "ai_suggestions", %{
      suggestions: suggestions,
      timestamp: DateTime.utc_now()
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info(:stop_typing, socket) do
    # Auto-broadcast typing stopped
    broadcast_from!(socket, "user_typing", %{
      user_id: socket.assigns.user_id,
      is_typing: false,
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, assign(socket, :typing_timer, nil)}
  end

  @doc """
  Handle incoming message from client.

  Optimizations:
  - Broadcast immediately to all subscribers
  - Persist to database asynchronously
  - Use Task.async for non-blocking DB write
  """
  @impl true
  def handle_in("new_message", %{"content" => content} = payload, socket) do
    thread_id = socket.assigns.thread_id
    user_id = socket.assigns.user_id

    # Truncate content for logging if it's too long
    truncated_content = truncate_message(content, 50)

    Logger.info(
      "📥 [MSG] Received message from user #{user_id} in thread #{thread_id}: \"#{truncated_content}\""
    )

    Logger.debug("📦 [MSG] Full payload: #{inspect(payload)}")

    # Generate message ID immediately for client feedback
    message_id = Ecto.UUID.generate()
    client_timestamp = System.system_time(:millisecond)

    Logger.debug(
      "🆔 [MSG] Generated message_id: #{message_id}, client_timestamp: #{client_timestamp}"
    )

    # Extract client_message_id for deduplication
    client_message_id = payload["client_message_id"]

    # Detect language of the message content
    detected_language = detect_message_language(content)
    Logger.debug("🔍 [MSG] Detected language: #{detected_language}")

    # Fetch sender's current display name for real-time propagation
    sender_display_name = get_user_display_name(user_id)
    Logger.debug("👤 [MSG] Sender display name: #{sender_display_name}")

    # Build message struct with detected language in metadata
    message_attrs = %{
      id: message_id,
      thread_id: thread_id,
      sender_id: user_id,
      content: content,
      content_type: payload["content_type"] || "text",
      media_url: payload["media_url"],
      media_size: payload["media_size"],
      media_mime_type: payload["media_mime_type"],
      reply_to_id: payload["reply_to_id"],
      client_created_at: payload["client_created_at"],
      client_message_id: client_message_id,
      metadata: %{detected_language: detected_language}
    }

    # Broadcast immediately to all thread participants
    # This happens BEFORE database write for minimum latency
    # Include detected_language so clients can skip unnecessary translations
    # Include sender_display_name so clients can update their cache in real-time
    broadcast_message = %{
      id: message_id,
      thread_id: thread_id,
      sender_id: user_id,
      sender_display_name: sender_display_name,
      content: content,
      content_type: message_attrs.content_type,
      media_url: message_attrs.media_url,
      reply_to_id: message_attrs.reply_to_id,
      created_at: DateTime.utc_now(),
      client_timestamp: client_timestamp,
      client_message_id: client_message_id,
      detected_language: detected_language
    }

    Logger.info("📡 [MSG] Broadcasting message #{message_id} to thread:#{thread_id}")
    broadcast!(socket, "new_message", broadcast_message)
    Logger.info("✅ [MSG] Message #{message_id} broadcast complete, queuing for persistence")

    # Persist to database asynchronously
    # Using Task.Supervisor for monitored async operations
    Task.Supervisor.start_child(GlobalbridgeBackend.TaskSupervisor, fn ->
      Logger.debug("💾 [MSG] Starting database persistence for message #{message_id}")

      case Chat.create_message(thread_id, message_attrs) do
        {:ok, message} ->
          Logger.info("✅ [MSG] Message #{message_id} persisted to database successfully")

          # Update thread last_message_at timestamp
          Chat.update_thread_timestamp(thread_id)

          # Learn user writing style from this message
          SmartReplyGenerator.learn_user_style(user_id, message, thread_id)

          # Notify ConversationMonitor of new message for analysis
          ConversationMonitor.handle_new_message(thread_id, message)

          # Send push notifications to offline users
          send_push_notifications_for_message(thread_id, message, user_id)

          :ok

        {:error, changeset} ->
          Logger.error(
            "❌ [MSG] Failed to persist message #{message_id}: #{inspect(changeset.errors)}"
          )

          # Optionally broadcast error to sender only
          push(socket, "message_error", %{
            temp_id: message_id,
            error: "Failed to save message"
          })
      end
    end)

    # Reply immediately to sender with full message (iOS expects complete message object)
    Logger.debug("↩️  [MSG] Replying to sender with full message: #{message_id}")

    # Return the same format as broadcast so iOS can parse it
    {:reply, {:ok, broadcast_message}, socket}
  end

  @doc """
  Fetch historical messages for a thread.
  Used when client's local database is empty and needs to pull down existing messages.
  """
  @impl true
  def handle_in("fetch_messages", payload, socket) do
    thread_id = socket.assigns.thread_id
    limit = payload["limit"] || 50
    before_timestamp = payload["before"]

    Logger.debug(
      "📥 [FETCH] Fetching messages: thread=#{thread_id}, limit=#{limit}, before=#{inspect(before_timestamp)}"
    )

    filters = [limit: limit]
    filters = if before_timestamp, do: [{:before, before_timestamp} | filters], else: filters

    # Guard against any accidental duplicates at the DB layer
    messages =
      thread_id
      |> Messages.list_messages(filters)
      |> Enum.uniq_by(& &1.id)

    # Get unique sender IDs and fetch user info
    sender_ids = messages |> Enum.map(& &1.sender_id) |> Enum.uniq()

    users =
      Enum.map(sender_ids, fn sender_id ->
        case GlobalbridgeBackend.Repo.get(GlobalbridgeBackend.Schemas.User, sender_id) do
          nil ->
            nil

          user ->
            Logger.debug("👤 [FETCH] User #{user.id}: username=#{user.username}, display_name=#{inspect(user.display_name)}")
            {sender_id,
             %{
               id: user.id,
               username: user.username,
               display_name: user.display_name,
               avatar_url: user.avatar_url
             }}
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    formatted_messages =
      Enum.map(messages, fn msg ->
        %{
          id: msg.id,
          thread_id: msg.thread_id,
          sender_id: msg.sender_id,
          content: msg.content,
          content_type: msg.content_type || "text",
          created_at: msg.inserted_at,
          reply_to_id: msg.reply_to_id,
          media_url: msg.media_url,
          client_message_id: Map.get(msg, :client_message_id)
        }
      end)

    Logger.info(
      "✅ [FETCH] Returning #{length(formatted_messages)} messages + #{map_size(users)} users for thread #{thread_id}"
    )

    # NOTE: Query embeddings are now generated server-side when messages are sent,
    # so they're already cached by the time user opens the thread. No need to
    # generate here!

    {:reply, {:ok, %{messages: formatted_messages, users: users}}, socket}
  end

  @impl true
  def handle_in("edit_message", %{"message_id" => message_id, "content" => new_content}, socket) do
    thread_id = socket.assigns.thread_id
    user_id = socket.assigns.user_id

    case Chat.edit_message(thread_id, message_id, user_id, new_content) do
      {:ok, message} ->
        # Broadcast edit to all participants
        broadcast!(socket, "message_edited", %{
          id: message_id,
          content: new_content,
          edited_at: message.edited_at,
          editor_id: user_id
        })

        {:reply, {:ok, %{id: message_id}}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "Message not found"}}, socket}

      {:error, :unauthorized} ->
        {:reply, {:error, %{reason: "Not authorized to edit this message"}}, socket}

      {:error, _reason} ->
        {:reply, {:error, %{reason: "Failed to edit message"}}, socket}
    end
  end

  @impl true
  def handle_in("delete_message", %{"message_id" => message_id}, socket) do
    thread_id = socket.assigns.thread_id
    user_id = socket.assigns.user_id

    case Chat.delete_message(thread_id, message_id, user_id) do
      {:ok, _message} ->
        # Broadcast deletion to all participants
        broadcast!(socket, "message_deleted", %{
          id: message_id,
          deleted_by: user_id,
          deleted_at: DateTime.utc_now()
        })

        {:reply, {:ok, %{id: message_id}}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "Message not found"}}, socket}

      {:error, :unauthorized} ->
        {:reply, {:error, %{reason: "Not authorized to delete this message"}}, socket}

      {:error, _reason} ->
        {:reply, {:error, %{reason: "Failed to delete message"}}, socket}
    end
  end

  @impl true
  def handle_in("typing", %{"is_typing" => is_typing}, socket) do
    user_id = socket.assigns.user_id

    # Cancel existing typing timeout if present
    if socket.assigns[:typing_timer] do
      Process.cancel_timer(socket.assigns.typing_timer)
    end

    # Broadcast typing indicator (ephemeral, not persisted)
    broadcast_from!(socket, "user_typing", %{
      user_id: user_id,
      is_typing: is_typing,
      timestamp: System.system_time(:millisecond)
    })

    # Auto-stop typing after 3 seconds if no new typing events
    socket =
      if is_typing do
        timer = Process.send_after(self(), :stop_typing, :timer.seconds(3))
        assign(socket, :typing_timer, timer)
      else
        assign(socket, :typing_timer, nil)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_in("mark_read", %{"message_id" => message_id}, socket) do
    thread_id = socket.assigns.thread_id
    user_id = socket.assigns.user_id

    # Update read receipt asynchronously
    Task.Supervisor.start_child(GlobalbridgeBackend.TaskSupervisor, fn ->
      case Chat.mark_message_read(thread_id, message_id, user_id) do
        {:ok, _receipt} ->
          Logger.debug("Marked message #{message_id} as read by user #{user_id}")

        {:error, reason} ->
          Logger.error("Failed to mark message as read: #{inspect(reason)}")
      end
    end)

    # Broadcast read receipt to other participants immediately
    broadcast_from!(socket, "message_read", %{
      user_id: user_id,
      message_id: message_id,
      read_at: DateTime.utc_now()
    })

    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("get_read_receipts", %{"message_id" => message_id}, socket) do
    thread_id = socket.assigns.thread_id

    case Chat.get_message_read_receipts(thread_id, message_id) do
      {:ok, receipts} ->
        formatted_receipts =
          Enum.map(receipts, fn receipt ->
            %{
              user_id: receipt.user_id,
              read_at: receipt.read_at
            }
          end)

        {:reply, {:ok, %{receipts: formatted_receipts}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: inspect(reason)}}, socket}
    end
  end

  @impl true
  def handle_in("style:learn", %{"message_id" => message_id, "thread_id" => thread_id}, socket) do
    user_id = socket.assigns.user_id

    Logger.info("🧠 [STYLE_LEARN] Received style learning request for message: #{message_id}")

    # Trigger async style learning (non-blocking)
    Task.start(fn ->
      # Use get_message_by_client_id since iOS sends the client-generated UUID
      case Messages.get_message_by_client_id(thread_id, message_id) do
        nil ->
          Logger.warning("⚠️  [STYLE_LEARN] Message #{message_id} not found (searched by client_message_id)")

        message ->
          SmartReplyGenerator.learn_user_style(user_id, message, thread_id)
          Logger.info("✅ [STYLE_LEARN] Style learning completed for user: #{user_id}")
      end
    end)

    {:reply, :ok, socket}
  end

  @impl true
  def handle_in("ai:feedback", payload, socket) do
    thread_id = socket.assigns.thread_id
    user_id = socket.assigns.user_id

    # Extract feedback data
    suggestion = payload["suggestion"]
    accepted = payload["accepted"]
    modified_content = payload["modified_content"]
    rejection_reason = payload["rejection_reason"]
    time_to_response_ms = payload["time_to_response_ms"]

    Logger.info("🤖 [FEEDBACK] Received AI feedback from user #{user_id} in thread #{thread_id}: accepted=#{accepted}")

    # Record feedback asynchronously
    Task.Supervisor.start_child(GlobalbridgeBackend.TaskSupervisor, fn ->
      opts = [
        modified_content: modified_content,
        rejection_reason: rejection_reason,
        time_to_response_ms: time_to_response_ms
      ]

      case SmartReplyGenerator.record_feedback(user_id, thread_id, suggestion, accepted, opts) do
        :ok ->
          Logger.info("✅ [FEEDBACK] Recorded successfully for user #{user_id}")

        {:error, reason} ->
          Logger.error("❌ [FEEDBACK] Failed to record: #{inspect(reason)}")
      end
    end)

    {:reply, {:ok, %{recorded: true}}, socket}
  end

  @impl true
  def handle_in("cdc:pull", payload, socket) do
    thread = socket.assigns.thread
    since = parse_since(payload)

    {changes, cursor} = Sync.pull_changes(thread, since: since)

    response = %{
      "changes" => Enum.map(changes, &Sync.format_change/1),
      "next_cursor" => format_cursor(cursor)
    }

    {:reply, {:ok, response}, socket}
  end

  @impl true
  def handle_in("cdc:push", %{"logs" => changes} = _payload, socket) when is_list(changes) do
    thread = socket.assigns.thread
    user_id = socket.assigns.user_id

    results = Sync.apply_changes(thread, changes, user_id)

    applied = Enum.count(results, &match?(%{"success" => true}, &1))
    failed = Enum.count(results, &match?(%{"success" => false}, &1))

    response = %{
      "applied" => applied,
      "failed" => failed,
      "results" => results
    }

    {:reply, {:ok, response}, socket}
  end

  def handle_in("cdc:push", _payload, socket) do
    {:reply, {:error, %{reason: "Missing required parameter: logs"}}, socket}
  end

  @doc """
  Translates a specific message on-demand.

  Used for "Show original" / "Show translation" toggle in UI.
  """
  @impl true
  def handle_in("translate_message", %{"message_id" => message_id, "target_language" => target_lang} = _payload, socket) do
    thread_id = socket.assigns.thread_id

    case Messages.get_message(thread_id, message_id) do
      nil ->
        {:reply, {:error, %{reason: "Message not found"}}, socket}

      message ->
        source_lang = message.detected_language || "en"

        case GlobalbridgeBackend.AI.TranslationCoordinator.translate_message_on_demand(
          message.content,
          source_lang,
          target_lang
        ) do
          {:ok, translated_content} ->
            response = %{
              message_id: message_id,
              translated_content: translated_content,
              source_language: source_lang,
              target_language: target_lang
            }

            {:reply, {:ok, response}, socket}

          {:error, reason} ->
            Logger.error("[TRANSLATION] Failed to translate message #{message_id}: #{inspect(reason)}")
            {:reply, {:error, %{reason: "Translation failed"}}, socket}
        end
    end
  end

  @doc """
  Gets effective translation preferences for the current user in this thread.
  """
  @impl true
  def handle_in("get_translation_preferences", _payload, socket) do
    user_id = socket.assigns.user_id
    thread_id = socket.assigns.thread_id

    prefs = GlobalbridgeBackend.Contexts.TranslationPreferences.get_effective_preferences(user_id, thread_id)

    {:reply, {:ok, prefs}, socket}
  end

  @doc """
  Updates translation preferences for the current user.

  Can update either global preferences or thread-specific overrides.
  """
  @impl true
  def handle_in("set_translation_preference", %{"scope" => "global"} = payload, socket) do
    user_id = socket.assigns.user_id

    attrs = Map.take(payload, ["auto_translate_incoming", "auto_translate_outgoing", "show_translation_offers"])

    case GlobalbridgeBackend.Contexts.TranslationPreferences.update_user_preferences(user_id, attrs) do
      {:ok, _prefs} ->
        {:reply, {:ok, %{updated: true}}, socket}

      {:error, changeset} ->
        {:reply, {:error, %{reason: "Invalid preferences", errors: format_errors(changeset)}}, socket}
    end
  end

  @impl true
  def handle_in("set_translation_preference", %{"scope" => "thread"} = payload, socket) do
    user_id = socket.assigns.user_id
    thread_id = socket.assigns.thread_id

    attrs = Map.take(payload, ["auto_translate_incoming", "auto_translate_outgoing", "preferred_thread_language"])

    case GlobalbridgeBackend.Contexts.TranslationPreferences.update_thread_preferences(user_id, thread_id, attrs) do
      {:ok, _participant} ->
        {:reply, {:ok, %{updated: true}}, socket}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  @impl true
  def handle_in("set_translation_preference", _payload, socket) do
    {:reply, {:error, %{reason: "Invalid scope. Must be 'global' or 'thread'"}}, socket}
  end

  @doc """
  Checks if an outgoing message should offer translation.

  Returns suggestion if user's message language differs from thread language.
  """
  @impl true
  def handle_in("check_translation_suggestion", %{"content" => content} = _payload, socket) do
    user_id = socket.assigns.user_id
    thread_id = socket.assigns.thread_id

    case GlobalbridgeBackend.AI.TranslationCoordinator.check_outgoing_message(content, user_id, thread_id) do
      {:suggest, thread_language, available_languages} ->
        response = %{
          should_translate: true,
          thread_language: thread_language,
          available_languages: available_languages
        }

        {:reply, {:ok, response}, socket}

      {:skip, _reason} ->
        {:reply, {:ok, %{should_translate: false}}, socket}
    end
  end

  @doc """
  Translates an outgoing message before sending.

  Used when user accepts translation suggestion.
  """
  @impl true
  def handle_in("translate_and_send", %{"content" => content, "target_language" => target_lang} = payload, socket) do
    user_id = socket.assigns.user_id
    thread_id = socket.assigns.thread_id

    # Detect source language
    source_lang = detect_message_language(content)

    case GlobalbridgeBackend.AI.TranslationCoordinator.translate_outgoing_message(
      content,
      source_lang,
      target_lang
    ) do
      {:ok, translated_content, metadata} ->
        # Send the translated message
        message_attrs = %{
          content: translated_content,
          content_type: "text",
          original_content: content,
          source_language: source_lang,
          target_language: target_lang,
          is_translated: true,
          detected_language: target_lang
        }

        # Merge with other payload fields (reply_to_id, etc.)
        message_attrs = Map.merge(message_attrs, Map.take(payload, ["reply_to_id"]))

        # Send message through normal flow
        handle_in("new_message", message_attrs, socket)

      {:error, reason} ->
        Logger.error("[TRANSLATION] Failed to translate outgoing message: #{inspect(reason)}")
        {:reply, {:error, %{reason: "Translation failed"}}, socket}
    end
  end

  # Private helper functions

  defp authorize_user(thread_id, user_id) do
    case Chat.get_thread(thread_id) do
      nil ->
        {:error, :thread_not_found}

      thread ->
        # Use cached participant check for better performance
        if ParticipantCache.is_participant?(thread_id, user_id) do
          {:ok, thread}
        else
          {:error, :not_participant}
        end
    end
  end

  defp send_push_notifications_for_message(thread_id, message, sender_id) do
    # Get all thread participants except the sender
    participants = get_thread_participants_except(thread_id, sender_id)

    # Get sender info for notification
    sender = get_user_info(sender_id)
    sender_name = sender[:name] || "Someone"

    # Send notification to each offline participant
    Enum.each(participants, fn participant_id ->
      # Check if user is online in this thread
      unless Presence.user_online?(thread_id, participant_id) do
        # User is offline, send push notification
        Notifications.send_message_notification(%{
          user_id: participant_id,
          thread_id: thread_id,
          message_id: message.id,
          sender_name: sender_name,
          message_content: truncate_message(message.content)
        })
      end
    end)
  end

  defp get_thread_participants_except(_thread_id, _except_user_id) do
    # TODO: Implement actual participant lookup
    # For now, return empty list
    []
  end

  defp get_user_info(user_id) do
    # TODO: Implement actual user lookup
    # For now, return basic info
    %{id: user_id, name: "User"}
  end

  defp get_user_display_name(user_id) do
    alias GlobalbridgeBackend.Repo
    alias GlobalbridgeBackend.Schemas.User

    case Repo.get(User, user_id) do
      nil ->
        # User not found, return user_id as fallback
        user_id

      user ->
        # Return display_name if available, otherwise username, otherwise user_id
        user.display_name || user.username || user_id
    end
  end

  defp truncate_message(content, max_length \\ 100) do
    if String.length(content) > max_length do
      String.slice(content, 0, max_length) <> "..."
    else
      content
    end
  end

  defp detect_message_language(content) do
    # Use language detection service to detect message language
    # This runs synchronously but should be fast (< 100ms typically)
    case GlobalbridgeBackend.AI.LanguageDetectionService.detect_language_dedicated(content) do
      {:ok, %{language_code: language_code}} ->
        language_code

      {:ok, language_code} when is_binary(language_code) ->
        # Fallback for older format
        language_code

      {:error, _reason} ->
        # Default to English if detection fails
        "en"
    end
  end

  defp parse_since(payload) do
    payload
    |> Map.get("since")
    |> case do
      nil ->
        nil

      "" ->
        nil

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _} -> datetime
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp format_cursor(nil), do: nil
  defp format_cursor(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_cursor(value), do: value

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end

end
