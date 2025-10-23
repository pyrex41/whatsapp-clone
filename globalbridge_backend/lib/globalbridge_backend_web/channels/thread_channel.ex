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
  alias GlobalbridgeBackend.Notifications
  alias GlobalbridgeBackend.Sync
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

        # Track join time for latency metrics
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

    Logger.debug("📊 Presence state pushed to user=#{user_id}")

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

    # Build message struct
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
      client_created_at: payload["client_created_at"]
    }

    # Broadcast immediately to all thread participants
    # This happens BEFORE database write for minimum latency
    broadcast_message = %{
      id: message_id,
      thread_id: thread_id,
      sender_id: user_id,
      content: content,
      content_type: message_attrs.content_type,
      media_url: message_attrs.media_url,
      reply_to_id: message_attrs.reply_to_id,
      created_at: DateTime.utc_now(),
      client_timestamp: client_timestamp,
      client_message_id: client_message_id
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

  # Private helper functions

  defp authorize_user(thread_id, user_id) do
    case Chat.get_thread(thread_id) do
      nil ->
        {:error, :thread_not_found}

      thread ->
        if Chat.is_thread_participant?(thread_id, user_id) do
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

  defp truncate_message(content, max_length \\ 100) do
    if String.length(content) > max_length do
      String.slice(content, 0, max_length) <> "..."
    else
      content
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
end
