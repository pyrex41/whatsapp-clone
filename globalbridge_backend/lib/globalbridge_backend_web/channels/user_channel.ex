defmodule GlobalbridgeBackendWeb.UserChannel do
  @moduledoc """
  Channel for user-specific operations like bootstrap and thread creation.
  Topic format: "user:{user_id}"
  """
  use GlobalbridgeBackendWeb, :channel
  require Logger

  alias GlobalbridgeBackend.Contexts.{Auth, Threads}
  alias GlobalbridgeBackend.Repo

  # Intercept outgoing broadcasts
  intercept(["thread_created"])

  @impl true
  def join("user:" <> user_id, _payload, socket) do
    socket_user = socket.assigns.user
    socket_user_id = socket.assigns.user_id

    Logger.info("🔐 [USER_CHANNEL] Join attempt:")
    Logger.info("   - Channel user_id: #{user_id}")
    Logger.info("   - Socket user.id: #{socket_user_id}")
    Logger.info("   - Socket user.auth0_id: #{socket_user.auth0_id || "none"}")

    # Verify user owns this channel - accept either database UUID or Auth0 ID
    user_owns_channel =
      socket_user_id == user_id or socket_user.auth0_id == user_id

    if user_owns_channel do
      Logger.info("✅ [USER_CHANNEL] User #{user_id} joined their channel")

      # Return the database user ID so client knows what to use for future joins
      {:ok,
       %{
         joined_at: DateTime.utc_now(),
         user_id: socket_user_id,
         auth0_id: socket_user.auth0_id
       }, socket}
    else
      Logger.warning(
        "❌ [USER_CHANNEL] Unauthorized join attempt: socket_user=#{socket_user_id}, channel_user=#{user_id}"
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
  def handle_in("search_users", %{"query" => query}, socket) do
    user_id = socket.assigns.user_id
    Logger.info("🔍 [USER_CHANNEL] User search: query=#{query}, user=#{user_id}")

    users = Auth.search_users(query, user_id)

    formatted_users =
      Enum.map(users, fn user ->
        %{
          id: user.id,
          username: user.username,
          email: user.email,
          display_name: user.display_name,
          avatar_url: user.avatar_url,
          is_online: user.is_online
        }
      end)

    Logger.info("✅ [USER_CHANNEL] Found #{length(formatted_users)} users")
    {:reply, {:ok, %{users: formatted_users}}, socket}
  end

  @impl true
  def handle_in("create_dm", %{"user_id" => other_user_id}, socket) do
    user_id = socket.assigns.user_id

    Logger.info(
      "💬 [USER_CHANNEL] Create/get DM: requester=#{user_id}, other_user=#{other_user_id}"
    )

    case Threads.get_thread_for_direct_message(user_id, other_user_id) do
      {:ok, thread} ->
        Logger.info("✅ [USER_CHANNEL] DM thread: #{thread.id}")
        formatted_thread = format_thread(thread)
        {:reply, {:ok, formatted_thread}, socket}

      {:error, reason} ->
        Logger.error("❌ [USER_CHANNEL] DM creation failed: #{inspect(reason)}")
        {:reply, {:error, %{reason: "Failed to create DM", details: inspect(reason)}}, socket}
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

      {:error, reason} when is_binary(reason) ->
        Logger.error("❌ [USER_CHANNEL] Thread creation failed: #{reason}")
        {:reply, {:error, %{reason: reason}}, socket}

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
