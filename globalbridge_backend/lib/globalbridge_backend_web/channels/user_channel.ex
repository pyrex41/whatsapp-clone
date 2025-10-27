defmodule GlobalbridgeBackendWeb.UserChannel do
  @moduledoc """
  Channel for user-specific operations like bootstrap and thread creation.
  Topic format: "user:{user_id}"
  """
  use GlobalbridgeBackendWeb, :channel
  require Logger

  alias GlobalbridgeBackend.Contexts.{Threads, Contacts}
  alias GlobalbridgeBackend.Schemas.User
  alias GlobalbridgeBackend.Repo

  # Intercept outgoing broadcasts
  intercept(["thread_created"])

  @impl true
  def join("user:" <> identifier, _payload, socket) do
    # Verify user owns this channel
    # Support both UUID, Auth0 ID, and username for flexible authorization
    socket_user_id = socket.assigns.user_id
    socket_user = socket.assigns[:user]
    socket_auth0_id = if socket_user, do: socket_user.auth0_id, else: nil
    socket_username = if socket_user, do: socket_user.username, else: nil

    # Check direct matches first
    authorized? =
      socket_user_id == identifier or
        socket_auth0_id == identifier or
        socket_username == identifier

    # If not authorized yet, check if identifier is an Auth0 ID that maps to socket_user_id
    authorized? =
      if authorized? do
        true
      else
        # Try to find a user by auth0_id matching the identifier
        case Repo.get_by(User, auth0_id: identifier) do
          nil -> false
          user -> user.id == socket_user_id
        end
      end

    # Also check reverse: if identifier is a UUID, see if it matches a user whose auth0_id matches socket
    authorized? =
      if authorized? do
        true
      else
        # Try to find a user by UUID matching the identifier
        case Repo.get(User, identifier) do
          nil -> false
          user -> user.auth0_id == socket_auth0_id or user.id == socket_user_id
        end
      end

    if authorized? do
      Logger.info(
        "✅ [USER_CHANNEL] User #{identifier} joined their channel (socket_user=#{socket_user_id}, socket_auth0=#{socket_auth0_id})"
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

      # Collect all unique participant IDs from all threads
      all_participant_ids =
        threads
        |> Enum.flat_map(fn thread ->
          thread = Repo.preload(thread, [:thread_participants])
          Enum.map(thread.thread_participants, & &1.user_id)
        end)
        |> Enum.uniq()

      Logger.info("👥 [USER_CHANNEL] Fetching info for #{length(all_participant_ids)} unique participants")

      # Fetch user info for all participants
      users_map =
        all_participant_ids
        |> Enum.map(fn uid -> Repo.get(User, uid) end)
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn user ->
          {user.id,
           %{
             id: user.id,
             username: user.username,
             display_name: user.display_name,
             avatar_url: user.avatar_url
           }}
        end)
        |> Enum.into(%{})

      Logger.info("✅ [USER_CHANNEL] Fetched #{map_size(users_map)} user records")

      # Format response with user info
      response = %{
        threads: Enum.map(threads, &format_thread_for_user(&1, user_id)),
        user: format_user(socket.assigns.user),
        users: users_map
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
        Enum.each([user_id, other_user_id], fn participant_id ->
          formatted_thread = format_thread_for_user(thread, participant_id)
          GlobalbridgeBackendWeb.Endpoint.broadcast(
            "user:#{participant_id}",
            "thread_created",
            formatted_thread
          )
        end)

            {:reply, {:ok, format_thread_for_user(thread, user_id)}, socket}

          {:error, changeset} ->
            errors = format_errors(changeset)
            Logger.error("❌ [USER_CHANNEL] DM creation failed: #{inspect(errors)}")
            {:reply, {:error, %{errors: errors}}, socket}
        end

      thread ->
        # Return existing DM
        Logger.info("✅ [USER_CHANNEL] Existing DM found: #{thread.id}")
        {:reply, {:ok, format_thread_for_user(thread, user_id)}, socket}
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

  @impl true
  def handle_in("update_display_name", %{"display_name" => new_name}, socket) do
    user_id = socket.assigns.user_id
    Logger.info("👤 [USER_CHANNEL] Update display name: user=#{user_id}, new_name=#{new_name}")

    case Repo.get(User, user_id) do
      nil ->
        Logger.error("❌ [USER_CHANNEL] User not found: #{user_id}")
        {:reply, {:error, %{reason: "User not found"}}, socket}

      user ->
        changeset = User.update_changeset(user, %{display_name: new_name})

        case Repo.update(changeset) do
          {:ok, updated_user} ->
            Logger.info("✅ [USER_CHANNEL] Display name updated: #{updated_user.display_name}")
            {:reply, {:ok, %{display_name: updated_user.display_name}}, socket}

          {:error, changeset} ->
            errors = format_errors(changeset)
            Logger.error("❌ [USER_CHANNEL] Failed to update display name: #{inspect(errors)}")
            {:reply, {:error, %{errors: errors}}, socket}
        end
    end
  end

  @impl true
  def handle_in("update_preferred_language", %{"preferred_language" => language}, socket) do
    user_id = socket.assigns.user_id
    Logger.info("🌐 [USER_CHANNEL] Update preferred language: user=#{user_id}, language=#{language}")

    case Repo.get(User, user_id) do
      nil ->
        Logger.error("❌ [USER_CHANNEL] User not found: #{user_id}")
        {:reply, {:error, %{reason: "User not found"}}, socket}

      user ->
        changeset = User.update_changeset(user, %{preferred_language: language})

        case Repo.update(changeset) do
          {:ok, updated_user} ->
            Logger.info("✅ [USER_CHANNEL] Preferred language updated: #{updated_user.preferred_language}")
            {:reply, {:ok, %{preferred_language: updated_user.preferred_language}}, socket}

          {:error, changeset} ->
            errors = format_errors(changeset)
            Logger.error("❌ [USER_CHANNEL] Failed to update preferred language: #{inspect(errors)}")
            {:reply, {:error, %{errors: errors}}, socket}
        end
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

  # Same as format_thread/1 but with a per-user resolved title for DMs
  defp format_thread_for_user(thread, current_user_id) do
    thread = Repo.preload(thread, [:thread_participants])

    participant_ids = Enum.map(thread.thread_participants, & &1.user_id)

    # Resolve a friendlier title for direct threads when none provided
    resolved_title =
      case {thread.thread_type, thread.title} do
        {"direct", nil} ->
          case Enum.find(participant_ids, fn uid -> uid != current_user_id end) do
            nil -> nil
            other_id ->
              case Repo.get(User, other_id) do
                nil -> "User #{String.slice(other_id, 0, 8)}"
                %User{display_name: dn, username: un, email: em} ->
                  cond do
                    is_binary(dn) and String.trim(dn) != "" -> dn
                    is_binary(un) and String.trim(un) != "" -> un
                    is_binary(em) and String.trim(em) != "" -> em
                    true -> "User #{String.slice(other_id, 0, 8)}"
                  end
              end
          end

        _ ->
          thread.title
      end

    %{
      id: thread.id,
      thread_type: thread.thread_type,
      title: resolved_title,
      database_shard_id: thread.database_shard_id,
      last_message_at: thread.last_message_at,
      is_archived: thread.is_archived,
      is_muted: thread.is_muted,
      participant_ids: participant_ids,
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
      avatar_url: user.avatar_url,
      preferred_language: user.preferred_language
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
