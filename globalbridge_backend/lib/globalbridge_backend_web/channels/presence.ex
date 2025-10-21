defmodule GlobalbridgeBackendWeb.Presence do
  @moduledoc """
  Phoenix Presence module for tracking user online/offline status.

  Leverages Phoenix.Presence to provide distributed presence tracking
  across nodes with automatic conflict resolution via CRDT.

  ## Features
  - Real-time online/offline tracking per thread
  - Automatic cleanup on disconnect
  - Distributed across multiple Phoenix nodes
  - Metadata tracking (join time, device info)

  ## Usage

      # Track user presence in a thread
      Presence.track(socket, user_id, %{
        online_at: System.system_time(:millisecond),
        device_type: "ios"
      })

      # List all users present in a thread
      Presence.list("thread:123")

      # Subscribe to presence changes
      Presence.subscribe("thread:123")
  """
  use Phoenix.Presence,
    otp_app: :globalbridge_backend,
    pubsub_server: GlobalbridgeBackend.PubSub

  @doc """
  Fetch current presence metadata for tracking.

  Called by Phoenix.Presence to retrieve initial state when tracking starts.
  This can be used to load additional user data from the database.
  """
  def fetch(_topic, presences) do
    # For now, return presences as-is
    # In production, you might want to enrich with user data from database
    presences
  end

  @doc """
  Track a user's presence in a thread.

  ## Parameters
  - `socket` - Phoenix.Socket with user assignments
  - `user_id` - User identifier to track
  - `meta` - Metadata map (online_at, device_type, etc.)

  ## Returns
  - `{:ok, ref}` on success
  - `{:error, reason}` on failure
  """
  def track_user(socket, user_id, meta \\ %{}) do
    default_meta = %{
      online_at: System.system_time(:millisecond),
      joined_at: DateTime.utc_now()
    }

    track(socket, user_id, Map.merge(default_meta, meta))
  end

  @doc """
  Get list of online users in a thread.

  Returns a map of user_id => metadata for all present users.
  """
  def online_users(thread_id) do
    list("thread:#{thread_id}")
    |> Enum.map(fn {user_id, %{metas: metas}} ->
      # Get the first meta (most recent)
      meta = List.first(metas) || %{}
      {user_id, meta}
    end)
    |> Map.new()
  end

  @doc """
  Check if a specific user is online in a thread.
  """
  def user_online?(thread_id, user_id) do
    "thread:#{thread_id}"
    |> list()
    |> Map.has_key?(user_id)
  end

  @doc """
  Get count of online users in a thread.
  """
  def online_count(thread_id) do
    "thread:#{thread_id}"
    |> list()
    |> map_size()
  end
end
