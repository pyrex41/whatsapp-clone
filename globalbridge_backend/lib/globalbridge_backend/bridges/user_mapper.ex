defmodule GlobalbridgeBackend.Bridges.UserMapper do
  @moduledoc """
  User Mapper for bridging external platform users to GlobalBridge users.

  This module handles:
  - Mapping Telegram users to GlobalBridge users
  - Mapping GlobalBridge users to Telegram users
  - User discovery and creation for new external users
  - Caching user mappings for performance
  """

  require Logger

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.User

  @doc """
  Maps a Telegram user to a GlobalBridge user.

  If the Telegram user doesn't exist in GlobalBridge, creates a new user.
  Returns {:ok, globalbridge_user_id} or {:error, reason}.
  """
  def map_telegram_user_to_globalbridge(telegram_user, bridge_id) do
    # Check cache first
    cache_key = "telegram_user:#{telegram_user.id}"

    case get_cached_mapping(cache_key) do
      {:ok, gb_user_id} ->
        {:ok, gb_user_id}

      {:error, :not_found} ->
        # Not in cache, check database
        case find_or_create_globalbridge_user_from_telegram(telegram_user, bridge_id) do
          {:ok, gb_user} ->
            # Cache the mapping
            put_cached_mapping(cache_key, gb_user.id)
            {:ok, gb_user.id}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Maps a GlobalBridge user to a Telegram user.

  Returns {:ok, telegram_user_id} or {:error, reason}.
  """
  def map_globalbridge_user_to_telegram(gb_user_id, bridge_id) do
    # Check cache first
    cache_key = "gb_to_telegram:#{gb_user_id}"

    case get_cached_mapping(cache_key) do
      {:ok, telegram_user_id} ->
        {:ok, telegram_user_id}

      {:error, :not_found} ->
        # Not in cache, check database
        case find_telegram_user_for_globalbridge_user(gb_user_id, bridge_id) do
          {:ok, telegram_user_id} ->
            # Cache the mapping
            put_cached_mapping(cache_key, telegram_user_id)
            {:ok, telegram_user_id}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Links a Telegram user to an existing GlobalBridge user.

  This is useful when a user already exists in GlobalBridge and wants to link their Telegram account.
  Returns {:ok, gb_user_id} or {:error, reason}.
  """
  def link_telegram_user_to_globalbridge_user(telegram_user_id, gb_user_id, bridge_id) do
    # Store the mapping in database/cache
    mapping_key = "telegram_user:#{telegram_user_id}"
    reverse_key = "gb_to_telegram:#{gb_user_id}"

    # In a real implementation, this would store in a user_mappings table
    # For now, just cache it
    put_cached_mapping(mapping_key, gb_user_id)
    put_cached_mapping(reverse_key, telegram_user_id)

    {:ok, gb_user_id}
  end

  # Private functions

  defp find_existing_user_by_telegram_id(telegram_user_id) do
    # In a real implementation, this would query a user_external_ids table
    # For now, check cache
    cache_key = "telegram_user:#{telegram_user_id}"

    case get_cached_mapping(cache_key) do
      {:ok, gb_user_id} ->
        case Repo.get(User, gb_user_id) do
          nil -> {:error, :not_found}
          user -> {:ok, user}
        end

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp find_existing_user_by_similarity(telegram_user) do
    # Try to find existing users by similar attributes
    # This is a simplified implementation

    # Try by username if available
    if telegram_user.username do
      case Repo.get_by(User, username: telegram_user.username) do
        nil -> :not_found
        user -> {:ok, user}
      end
    else
      # Try by name similarity (first + last name)
      full_name =
        "#{telegram_user.first_name || ""} #{telegram_user.last_name || ""}" |> String.trim()

      if full_name != "" do
        # This would be a more complex query in production
        # For now, just return not found
        {:error, :not_found}
      else
        {:error, :not_found}
      end
    end
  end

  defp find_or_create_globalbridge_user_from_telegram(telegram_user, bridge_id) do
    # First, try to find existing user by Telegram ID (if we have a mapping)
    case find_existing_user_by_telegram_id(telegram_user.id) do
      {:ok, existing_user} ->
        {:ok, existing_user}

      {:error, :not_found} ->
        # No direct mapping, try to find by username/email similarity
        case find_existing_user_by_similarity(telegram_user) do
          {:ok, existing_user} ->
            # Link the Telegram user to the existing GlobalBridge user
            link_telegram_user_to_globalbridge_user(telegram_user.id, existing_user.id, bridge_id)
            {:ok, existing_user}

          {:error, :not_found} ->
            # Create new user
            username = generate_unique_username_from_telegram_user(telegram_user)
            create_globalbridge_user_from_telegram(telegram_user, username)
        end
    end
  end

  defp find_telegram_user_for_globalbridge_user(gb_user_id, _bridge_id) do
    # In a real implementation, this would query the user_mappings table
    # For now, return not found
    {:error, :mapping_not_found}
  end

  defp create_globalbridge_user_from_telegram(telegram_user, username) do
    # Create a new GlobalBridge user from Telegram user info
    user_attrs = %{
      username: username,
      email: generate_email_from_telegram_user(telegram_user),
      first_name: telegram_user.first_name,
      last_name: telegram_user.last_name,
      # Could be fetched from Telegram
      avatar_url: nil,
      is_active: true
    }

    case %User{}
         |> User.registration_changeset(user_attrs)
         |> Repo.insert() do
      {:ok, user} ->
        Logger.info(
          "Created new GlobalBridge user #{user.username} from Telegram user #{telegram_user.id}"
        )

        {:ok, user}

      {:error, changeset} ->
        Logger.error(
          "Failed to create GlobalBridge user from Telegram user: #{inspect(changeset.errors)}"
        )

        {:error, :user_creation_failed}
    end
  end

  defp generate_unique_username_from_telegram_user(telegram_user) do
    # Generate a unique username from Telegram user info
    base_username = if telegram_user.username do
      telegram_user.username
    else
      "#{telegram_user.first_name || "user"}#{telegram_user.last_name || ""}"
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]/, "")
    end

    # Ensure uniqueness
    ensure_unique_username(base_username, telegram_user.id)
  end

  defp ensure_unique_username(base_username, telegram_id) do
    # Check if username is available
    case Repo.get_by(User, username: base_username) do
      nil ->
        # Username is available
        base_username

      _existing_user ->
        # Username taken, append Telegram ID
        unique_username = "#{base_username}_tg#{telegram_id}"

        # Double-check uniqueness (though very unlikely to collide)
        case Repo.get_by(User, username: unique_username) do
          nil -> unique_username
          _ -> "#{unique_username}_#{:rand.uniform(1000)}"  # Add random number if still collision
        end
    end
  end

    # Ensure uniqueness by appending Telegram ID if needed
    "#{base_username}_tg#{telegram_user.id}"
  end

  defp generate_email_from_telegram_user(telegram_user) do
    # Generate a placeholder email
    # In production, this would need proper email handling
    "#{telegram_user.id}@telegram.bridge.local"
  end

  # Simple cache implementation using persistent_term
  # In production, this would use a proper cache like Cachex

  defp get_cached_mapping(key) do
    case :persistent_term.get({:user_mapping, key}, :not_found) do
      :not_found -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  defp put_cached_mapping(key, value) do
    :persistent_term.put({:user_mapping, key}, value)
  end
end
