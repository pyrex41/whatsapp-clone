defmodule GlobalbridgeBackendWeb.UserChannelBridgeTest do
  use GlobalbridgeBackendWeb.ChannelCase, async: true

  alias GlobalbridgeBackendWeb.UserSocket
  alias GlobalbridgeBackend.{Repo, Bridges}
  alias GlobalbridgeBackend.Schemas.{Bridge, User}

  setup do
    # Create test user
    {:ok, user} =
      GlobalbridgeBackend.Contexts.Auth.create_user(%{
        email: "test@example.com",
        username: "testuser",
        display_name: "Test User"
      })

    # Create socket connection
    {:ok, token, _claims} = GlobalbridgeBackend.Auth.Guardian.encode_and_sign(user)
    {:ok, socket} = connect(UserSocket, %{"token" => token})

    # Subscribe to user channel
    {:ok, _, socket} = subscribe_and_join(socket, "user:#{user.id}", %{})

    %{socket: socket, user: user}
  end

  describe "bridge_status_changed event" do
    test "broadcasts bridge status changes to user channel", %{socket: socket, user: user} do
      # Create a bridge for the user
      {:ok, bridge} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      # Simulate bridge status change broadcast
      bridge_status_payload = %{
        bridge_id: bridge.id,
        bridge_type: "telegram",
        status: "connected",
        phone_number: "+1234567890",
        error_message: nil,
        timestamp: DateTime.utc_now()
      }

      # Broadcast the event
      GlobalbridgeBackendWeb.Endpoint.broadcast(
        "user:#{user.id}",
        "bridge_status_changed",
        bridge_status_payload
      )

      # Assert the event is received
      assert_broadcast("bridge_status_changed", ^bridge_status_payload)
    end

    test "handles bridge connection status", %{socket: socket, user: user} do
      {:ok, bridge} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      payload = %{
        bridge_id: bridge.id,
        bridge_type: "telegram",
        status: "connected",
        phone_number: "+1234567890",
        timestamp: DateTime.utc_now()
      }

      GlobalbridgeBackendWeb.Endpoint.broadcast(
        "user:#{user.id}",
        "bridge_status_changed",
        payload
      )

      assert_broadcast("bridge_status_changed", received_payload)
      assert received_payload.bridge_id == bridge.id
      assert received_payload.status == "connected"
      assert received_payload.bridge_type == "telegram"
    end

    test "handles bridge disconnection status", %{socket: socket, user: user} do
      {:ok, bridge} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      payload = %{
        bridge_id: bridge.id,
        bridge_type: "telegram",
        status: "disconnected",
        phone_number: "+1234567890",
        timestamp: DateTime.utc_now()
      }

      GlobalbridgeBackendWeb.Endpoint.broadcast(
        "user:#{user.id}",
        "bridge_status_changed",
        payload
      )

      assert_broadcast("bridge_status_changed", received_payload)
      assert received_payload.status == "disconnected"
    end

    test "handles bridge error status with error message", %{socket: socket, user: user} do
      {:ok, bridge} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      error_message = "Failed to authenticate with Telegram API"

      payload = %{
        bridge_id: bridge.id,
        bridge_type: "telegram",
        status: "error",
        phone_number: "+1234567890",
        error_message: error_message,
        timestamp: DateTime.utc_now()
      }

      GlobalbridgeBackendWeb.Endpoint.broadcast(
        "user:#{user.id}",
        "bridge_status_changed",
        payload
      )

      assert_broadcast("bridge_status_changed", received_payload)
      assert received_payload.status == "error"
      assert received_payload.error_message == error_message
    end

    test "handles bridge connecting status", %{socket: socket, user: user} do
      {:ok, bridge} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      payload = %{
        bridge_id: bridge.id,
        bridge_type: "telegram",
        status: "connecting",
        phone_number: "+1234567890",
        timestamp: DateTime.utc_now()
      }

      GlobalbridgeBackendWeb.Endpoint.broadcast(
        "user:#{user.id}",
        "bridge_status_changed",
        payload
      )

      assert_broadcast("bridge_status_changed", received_payload)
      assert received_payload.status == "connecting"
    end
  end

  describe "bridge status payload structure" do
    test "includes all required fields", %{socket: socket, user: user} do
      {:ok, bridge} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      timestamp = DateTime.utc_now()

      payload = %{
        bridge_id: bridge.id,
        bridge_type: "telegram",
        status: "connected",
        phone_number: "+1234567890",
        error_message: "Optional error",
        timestamp: timestamp
      }

      GlobalbridgeBackendWeb.Endpoint.broadcast(
        "user:#{user.id}",
        "bridge_status_changed",
        payload
      )

      assert_broadcast("bridge_status_changed", received_payload)
      assert Map.has_key?(received_payload, :bridge_id)
      assert Map.has_key?(received_payload, :bridge_type)
      assert Map.has_key?(received_payload, :status)
      assert Map.has_key?(received_payload, :phone_number)
      assert Map.has_key?(received_payload, :timestamp)
    end
  end
end
