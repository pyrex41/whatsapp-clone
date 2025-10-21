defmodule GlobalbridgeBackendWeb.UserChannel do
  @moduledoc """
  Channel for user-specific operations like bootstrap and thread creation.
  Topic format: "user:{user_id}"
  """
  use GlobalbridgeBackendWeb, :channel
  require Logger

  alias GlobalbridgeBackend.Contexts.Threads
  alias GlobalbridgeBackend.Repo

  # Intercept outgoing broadcasts
  intercept(["thread_created"])

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    # Verify user owns this channel
    if socket.assigns.user_id == user_id do
      Logger.info("✅ [USER_CHANNEL] User #{user_id} joined their channel")
      {:ok, %{joined_at: DateTime.utc_now()}, socket}
    else
      Logger.warning(
        "❌ [USER_CHANNEL] Unauthorized join attempt: socket_user=#{socket.assigns.user_id}, channel_user=#{user_id}"
      )

      {:error, %{reason: "Unauthorized"}}
    end
  end

  @impl true
  def handle_in("bootstrap", _payload, socket) do
    user_id = socket.assigns.user_id
    Logger.info("📥 [USER_CHANNEL] Bootstrap request from user: #{user_id}")

    try do
      # Fetch user's threads with participants
      threads = Threads.list_user_threads(user_id)
      Logger.info("📊 [USER_CHANNEL] Found #{length(threads)} threads for user: #{user_id}")

      # Format response
      response = %{
        threads: Enum.map(threads, &format_thread/1),
        user: format_user(socket.assigns.user)
      }

      Logger.info("✅ [USER_CHANNEL] Bootstrap successful for user: #{user_id}")
      {:reply, {:ok, response}, socket}
    rescue
      e ->
        Logger.error("❌ [USER_CHANNEL] Bootstrap failed for user #{user_id}: #{inspect(e)}")
        {:reply, {:error, %{reason: "Bootstrap failed", details: Exception.message(e)}}, socket}
    end
  end

  @impl true
  def handle_in(
        "create_thread",
        %{"thread_type" => type, "participant_ids" => participants} = payload,
        socket
      ) do
    user_id = socket.assigns.user_id

    Logger.info(
      "🆕 [USER_CHANNEL] Create thread request: type=#{type}, creator=#{user_id}, participants=#{inspect(participants)}"
    )

    # Create thread with current user + participants
    all_participants = [user_id | participants] |> Enum.uniq()

    attrs = %{
      thread_type: type,
      title: payload["title"],
      participant_ids: all_participants
    }

    case Threads.create_thread(attrs) do
      {:ok, thread} ->
        Logger.info("✅ [USER_CHANNEL] Thread created: #{thread.id}")

        # Broadcast to all participants
        formatted_thread = format_thread(thread)

        Enum.each(all_participants, fn participant_id ->
          Logger.debug("📢 [USER_CHANNEL] Broadcasting thread_created to user:#{participant_id}")

          GlobalbridgeBackendWeb.Endpoint.broadcast(
            "user:#{participant_id}",
            "thread_created",
            formatted_thread
          )
        end)

        {:reply, {:ok, formatted_thread}, socket}

      {:error, changeset} ->
        errors = format_errors(changeset)
        Logger.error("❌ [USER_CHANNEL] Thread creation failed: #{inspect(errors)}")
        {:reply, {:error, %{errors: errors}}, socket}
    end
  end

  # Handle incoming thread_created broadcasts
  @impl true
  def handle_out("thread_created", payload, socket) do
    Logger.debug(
      "📨 [USER_CHANNEL] Pushing thread_created event to user: #{socket.assigns.user_id}"
    )

    push(socket, "thread_created", payload)
    {:noreply, socket}
  end

  # Private helper functions

  defp format_thread(thread) do
    # Preload thread if not already loaded
    thread = Repo.preload(thread, [:thread_participants])

    %{
      id: thread.id,
      thread_type: thread.thread_type,
      title: thread.title,
      database_shard_id: thread.database_shard_id,
      last_message_at: thread.last_message_at,
      is_archived: thread.is_archived,
      is_muted: thread.is_muted,
      participant_ids: Enum.map(thread.thread_participants, & &1.user_id),
      created_at: thread.inserted_at,
      updated_at: thread.updated_at
    }
  end

  defp format_user(user) do
    %{
      id: user.id,
      username: user.username,
      email: user.email,
      display_name: user.display_name,
      avatar_url: user.avatar_url
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end
