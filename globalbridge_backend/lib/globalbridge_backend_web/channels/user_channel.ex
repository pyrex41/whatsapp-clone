defmodule GlobalbridgeBackendWeb.UserChannel do
  @moduledoc """
  Channel for user-specific operations like bootstrap and thread creation.
  Topic format: "user:{user_id}"
  """
  use GlobalbridgeBackendWeb, :channel
  require Logger

  alias GlobalbridgeBackend.Contexts.{Threads, Contacts}
  alias GlobalbridgeBackend.Repo

  # Intercept outgoing broadcasts
  intercept(["thread_created"])

  @impl true
  def join("user:" <> identifier, _payload, socket) do
    # Verify user owns this channel
    # Support both UUID and username for test mode
    socket_user_id = socket.assigns.user_id
    socket_user = socket.assigns[:user]
    socket_auth0_id = if socket_user, do: socket_user.auth0_id, else: nil
    socket_username = if socket_user, do: socket_user.username, else: nil

    authorized? =
      socket_user_id == identifier or
        socket_auth0_id == identifier or
        socket_username == identifier

    if authorized? do
      Logger.info(
        "✅ [USER_CHANNEL] User #{identifier} joined their channel (matched: #{cond do
          socket_user_id == identifier -> "ID"
          socket_auth0_id == identifier -> "Auth0"
          socket_username == identifier -> "username"
          true -> "unknown"
        end})"
      )

      {:ok, %{joined_at: DateTime.utc_now()}, socket}
    else
      Logger.warning(
        "❌ [USER_CHANNEL] Unauthorized join attempt: socket_user=#{socket_user_id}, socket_auth0_id=#{socket_auth0_id}, socket_username=#{socket_username}, channel_identifier=#{identifier}"
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

    # Resolve emails to user IDs
    email_user_ids =
      Enum.flat_map(payload["participant_emails"] || [], fn email ->
        case Contacts.find_user_by_email(email) do
          nil -> []
          user -> [user.id]
        end
      end)

    # Create thread with current user + participants + resolved emails
    all_participants = ([user_id | participants] ++ email_user_ids) |> Enum.uniq()

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

  @doc """
  Create or get existing direct message thread with another user.
  """
  @impl true
  def handle_in("create_dm", %{"user_id" => other_user_id}, socket) do
    user_id = socket.assigns.user_id

    Logger.info(
      "💬 [USER_CHANNEL] Create DM request: user=#{user_id}, other_user=#{other_user_id}"
    )

    # Check if DM already exists between these two users
    existing_dm = Threads.find_direct_message(user_id, other_user_id)

    case existing_dm do
      nil ->
        # Create new DM thread
        attrs = %{
          thread_type: "direct",
          participant_ids: [user_id, other_user_id]
        }

        case Threads.create_thread(attrs) do
          {:ok, thread} ->
            Logger.info("✅ [USER_CHANNEL] New DM created: #{thread.id}")

            # Broadcast to both participants
            formatted_thread = format_thread(thread)

            Enum.each([user_id, other_user_id], fn participant_id ->
              GlobalbridgeBackendWeb.Endpoint.broadcast(
                "user:#{participant_id}",
                "thread_created",
                formatted_thread
              )
            end)

            {:reply, {:ok, formatted_thread}, socket}

          {:error, changeset} ->
            errors = format_errors(changeset)
            Logger.error("❌ [USER_CHANNEL] DM creation failed: #{inspect(errors)}")
            {:reply, {:error, %{errors: errors}}, socket}
        end

      thread ->
        # Return existing DM
        Logger.info("✅ [USER_CHANNEL] Existing DM found: #{thread.id}")
        {:reply, {:ok, format_thread(thread)}, socket}
    end
  end

  # Contact management handlers

  @impl true
  def handle_in("search_users", %{"query" => query}, socket) do
    user_id = socket.assigns.user_id
    Logger.debug("🔍 [USER_CHANNEL] Search users: query=#{query}, user=#{user_id}")

    results = Contacts.search_users_by_email(query)

    # Filter out current user and existing contacts
    contact_ids =
      Contacts.list_contacts(user_id)
      |> Enum.map(& &1.contact_user_id)
      |> MapSet.new()

    filtered_results =
      Enum.reject(results, fn user ->
        user.id == user_id or MapSet.member?(contact_ids, user.id)
      end)

    {:reply, {:ok, %{users: filtered_results}}, socket}
  end

  @impl true
  def handle_in("search_contacts", %{"query" => query}, socket) do
    user_id = socket.assigns.user_id
    Logger.debug("🔍 [USER_CHANNEL] Search contacts: query=#{query}, user=#{user_id}")

    contacts = Contacts.search_contacts(user_id, query)

    {:reply, {:ok, %{contacts: format_contacts(contacts)}}, socket}
  end

  @impl true
  def handle_in("get_contacts", _payload, socket) do
    user_id = socket.assigns.user_id
    Logger.debug("📋 [USER_CHANNEL] Get all contacts for user: #{user_id}")

    contacts = Contacts.list_contacts(user_id)

    {:reply, {:ok, %{contacts: format_contacts(contacts)}}, socket}
  end

  @impl true
  def handle_in("sync_contacts", %{"since" => since_timestamp}, socket) do
    user_id = socket.assigns.user_id
    Logger.debug("🔄 [USER_CHANNEL] Sync contacts since: #{since_timestamp}, user=#{user_id}")

    {:ok, since_dt, _} = DateTime.from_iso8601(since_timestamp)
    contacts = Contacts.list_contacts_since(user_id, since_dt)

    {:reply, {:ok, %{contacts: format_contacts(contacts), synced_at: DateTime.utc_now()}}, socket}
  end

  @impl true
  def handle_in("add_contact", %{"contact_user_id" => contact_user_id} = payload, socket) do
    user_id = socket.assigns.user_id
    Logger.info("➕ [USER_CHANNEL] Add contact: user=#{user_id}, contact=#{contact_user_id}")

    case Contacts.add_contact(user_id, contact_user_id, payload) do
      {:ok, contact} ->
        contact = Repo.preload(contact, [:contact_user])
        Logger.info("✅ [USER_CHANNEL] Contact added: #{contact.id}")
        {:reply, {:ok, format_contact(contact)}, socket}

      {:error, changeset} ->
        Logger.error("❌ [USER_CHANNEL] Add contact failed: #{inspect(changeset.errors)}")
        {:reply, {:error, %{errors: format_errors(changeset)}}, socket}
    end
  end

  @impl true
  def handle_in("remove_contact", %{"contact_user_id" => contact_user_id}, socket) do
    user_id = socket.assigns.user_id
    Logger.info("➖ [USER_CHANNEL] Remove contact: user=#{user_id}, contact=#{contact_user_id}")

    case Contacts.remove_contact(user_id, contact_user_id) do
      {1, _} ->
        Logger.info("✅ [USER_CHANNEL] Contact removed")
        {:reply, {:ok, %{removed: true}}, socket}

      _ ->
        Logger.warning("⚠️  [USER_CHANNEL] Contact not found for removal")
        {:reply, {:error, %{reason: "Contact not found"}}, socket}
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

  defp format_contact(contact) do
    %{
      id: contact.id,
      contact_user_id: contact.contact_user_id,
      display_name_override: contact.display_name_override,
      is_favorite: contact.is_favorite,
      notes: contact.notes,
      user: %{
        id: contact.contact_user.id,
        email: contact.contact_user.email,
        username: contact.contact_user.username,
        display_name: contact.contact_user.display_name,
        avatar_url: contact.contact_user.avatar_url
      },
      created_at: contact.inserted_at,
      updated_at: contact.updated_at
    }
  end

  defp format_contacts(contacts) do
    Enum.map(contacts, &format_contact/1)
  end
end
