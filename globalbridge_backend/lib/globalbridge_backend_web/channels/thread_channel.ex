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
  alias GlobalbridgeBackend.Schemas.{Message, Thread}
  require Logger

  @doc """
  Join a thread channel with authorization.

  Users can only join threads they are participants in.
  """
  @impl true
  def join("thread:" <> thread_id, _payload, socket) do
    user_id = socket.assigns.user_id

    case authorize_user(thread_id, user_id) do
      {:ok, thread} ->
        # Assign thread info to socket for fast access
        socket =
          socket
          |> assign(:thread_id, thread_id)
          |> assign(:thread, thread)

        # Track join time for latency metrics
        send(self(), :after_join)

        {:ok, %{thread_id: thread_id, joined_at: DateTime.utc_now()}, socket}

      {:error, :not_participant} ->
        {:error, %{reason: "Not authorized to join this thread"}}

      {:error, :thread_not_found} ->
        {:error, %{reason: "Thread not found"}}

      {:error, reason} ->
        Logger.error("Failed to join thread #{thread_id}: #{inspect(reason)}")
        {:error, %{reason: "Unable to join thread"}}
    end
  end

  @impl true
  def handle_info(:after_join, socket) do
    # Send presence information to client
    # This is async to not block the join response
    thread_id = socket.assigns.thread_id

    # Broadcast user presence
    push(socket, "presence_state", %{
      user_id: socket.assigns.user_id,
      online_at: System.system_time(:millisecond)
    })

    {:noreply, socket}
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

    # Generate message ID immediately for client feedback
    message_id = Ecto.UUID.generate()
    client_timestamp = System.system_time(:millisecond)

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
      client_timestamp: client_timestamp
    }

    broadcast!(socket, "new_message", broadcast_message)

    # Persist to database asynchronously
    # Using Task.Supervisor for monitored async operations
    Task.Supervisor.start_child(GlobalbridgeBackend.TaskSupervisor, fn ->
      case Chat.create_message(thread_id, message_attrs) do
        {:ok, _message} ->
          # Update thread last_message_at timestamp
          Chat.update_thread_timestamp(thread_id)
          :ok

        {:error, changeset} ->
          Logger.error("Failed to persist message #{message_id}: #{inspect(changeset.errors)}")
          # Optionally broadcast error to sender only
          push(socket, "message_error", %{
            temp_id: message_id,
            error: "Failed to save message"
          })
      end
    end)

    # Reply immediately to sender with message ID
    {:reply, {:ok, %{id: message_id, timestamp: client_timestamp}}, socket}
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

    # Broadcast typing indicator (ephemeral, not persisted)
    broadcast_from!(socket, "user_typing", %{
      user_id: user_id,
      is_typing: is_typing,
      timestamp: System.system_time(:millisecond)
    })

    {:noreply, socket}
  end

  @impl true
  def handle_in("mark_read", %{"message_id" => message_id}, socket) do
    thread_id = socket.assigns.thread_id
    user_id = socket.assigns.user_id

    # Update read receipt asynchronously
    Task.Supervisor.start_child(GlobalbridgeBackend.TaskSupervisor, fn ->
      Chat.mark_message_read(thread_id, message_id, user_id)
    end)

    # Broadcast read receipt to other participants
    broadcast_from!(socket, "message_read", %{
      user_id: user_id,
      message_id: message_id,
      read_at: DateTime.utc_now()
    })

    {:reply, :ok, socket}
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
end
