defmodule GlobalbridgeBackendWeb.PresenceTest do
  use GlobalbridgeBackendWeb.ChannelCase, async: true

  alias GlobalbridgeBackendWeb.Presence

  setup do
    thread_id = Ecto.UUID.generate()
    user_id_1 = Ecto.UUID.generate()
    user_id_2 = Ecto.UUID.generate()

    {:ok, thread_id: thread_id, user_id_1: user_id_1, user_id_2: user_id_2}
  end

  describe "presence tracking" do
    test "tracks user presence in thread", %{thread_id: thread_id, user_id_1: user_id} do
      # Start a mock socket
      socket = %Phoenix.Socket{
        topic: "thread:#{thread_id}",
        channel: GlobalbridgeBackendWeb.ThreadChannel,
        assigns: %{user_id: user_id, thread_id: thread_id}
      }

      # Track presence
      {:ok, _ref} = Presence.track_user(socket, user_id, %{device_type: "ios"})

      # Verify user is present
      presences = Presence.list("thread:#{thread_id}")
      assert Map.has_key?(presences, user_id)
    end

    test "checks if specific user is online", %{thread_id: thread_id, user_id_1: user_id} do
      socket = %Phoenix.Socket{
        topic: "thread:#{thread_id}",
        assigns: %{user_id: user_id}
      }

      # User not online initially
      refute Presence.user_online?(thread_id, user_id)

      # Track presence
      {:ok, _} = Presence.track_user(socket, user_id)

      # User should be online now
      assert Presence.user_online?(thread_id, user_id)
    end

    test "counts online users correctly", %{thread_id: thread_id, user_id_1: user1, user_id_2: user2} do
      socket1 = %Phoenix.Socket{topic: "thread:#{thread_id}", assigns: %{user_id: user1}}
      socket2 = %Phoenix.Socket{topic: "thread:#{thread_id}", assigns: %{user_id: user2}}

      # No users online
      assert Presence.online_count(thread_id) == 0

      # Track first user
      {:ok, _} = Presence.track_user(socket1, user1)
      assert Presence.online_count(thread_id) == 1

      # Track second user
      {:ok, _} = Presence.track_user(socket2, user2)
      assert Presence.online_count(thread_id) == 2
    end
  end
end
