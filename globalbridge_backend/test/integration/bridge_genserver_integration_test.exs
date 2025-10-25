defmodule GlobalbridgeBackend.BridgeGenServerIntegrationTest do
  use GlobalbridgeBackend.DataCase, async: false

  alias GlobalbridgeBackend.{Repo, Bridges}
  alias GlobalbridgeBackend.Bridges.Telegram.Server
  alias GlobalbridgeBackend.Schemas.Bridge

  @moduletag :integration

  setup do
    # Create test user
    {:ok, user} =
      GlobalbridgeBackend.Contexts.Auth.create_user(%{
        email: "test@example.com",
        username: "testuser",
        display_name: "Test User"
      })

    # Create test bridge with mock bot token
    {:ok, bridge} =
      Bridges.create_bridge(%{
        user_id: user.id,
        bridge_type: "telegram",
        phone_number: "+1234567890",
        session_data: %{
          "bot_token" => "123456789:AAFakeBotTokenForTestingPurposes123456789"
        }
      })

    %{user: user, bridge: bridge}
  end

  describe "Telegram Server GenServer lifecycle" do
    test "starts successfully with valid bridge", %{bridge: bridge} do
      assert {:ok, pid} = Server.start_link(bridge)
      assert Process.alive?(pid)

      # Cleanup
      Process.exit(pid, :normal)
    end

    test "initializes with correct state", %{bridge: bridge} do
      {:ok, pid} = Server.start_link(bridge)

      status = Server.get_status(pid)

      assert status.bridge_id == bridge.id
      assert status.status == :disconnected
      assert status.bot_token_set == true
      assert status.polling_active == false
      assert status.webhook_enabled == false

      # Cleanup
      Process.exit(pid, :normal)
    end

    test "handles missing bot token gracefully", %{bridge: bridge} do
      # Create bridge without bot token
      bridge_without_token = %{bridge | session_data: %{}}

      {:ok, pid} = Server.start_link(bridge_without_token)

      status = Server.get_status(pid)

      assert status.bot_token_set == false
      assert status.status == :disconnected

      # Cleanup
      Process.exit(pid, :normal)
    end
  end

  describe "Telegram Server polling behavior" do
    test "starts polling when bot token is available", %{bridge: bridge} do
      {:ok, pid} = Server.start_link(bridge)

      # Wait for polling to start (async)
      :timer.sleep(1500)

      status = Server.get_status(pid)

      # Should be connected and polling active
      assert status.status == :connected
      assert status.polling_active == true

      # Cleanup
      Process.exit(pid, :normal)
    end

    test "handles polling errors gracefully", %{bridge: bridge} do
      {:ok, pid} = Server.start_link(bridge)

      # Wait for initial polling attempt
      :timer.sleep(1500)

      # Manually trigger a poll (this will fail with fake token)
      result = Server.poll_messages(pid)

      # Should return error but not crash
      assert {:error, _reason} = result

      # Server should still be alive
      assert Process.alive?(pid)

      status = Server.get_status(pid)
      assert status.error_count >= 1

      # Cleanup
      Process.exit(pid, :normal)
    end
  end

  describe "Telegram Server webhook functionality" do
    test "can enable webhook mode", %{bridge: bridge} do
      {:ok, pid} = Server.start_link(bridge)

      webhook_url = "https://example.com/webhook"
      webhook_secret = "test_secret"

      # This will fail with fake token but should handle gracefully
      result = Server.enable_webhook(pid, webhook_url, webhook_secret)

      # Should return error but not crash
      assert {:error, _reason} = result
      assert Process.alive?(pid)

      # Cleanup
      Process.exit(pid, :normal)
    end

    test "can disable webhook mode", %{bridge: bridge} do
      {:ok, pid} = Server.start_link(bridge)

      # This will fail but should handle gracefully
      result = Server.disable_webhook(pid)

      # Should return error but not crash
      assert {:error, _reason} = result
      assert Process.alive?(pid)

      # Cleanup
      Process.exit(pid, :normal)
    end
  end

  describe "Telegram Server message sending" do
    test "handles send message errors gracefully", %{bridge: bridge} do
      {:ok, pid} = Server.start_link(bridge)

      # Try to send message (will fail with fake token)
      result = Server.send_message(pid, "123456789", "Test message")

      # Should return error but not crash
      assert {:error, _reason} = result
      assert Process.alive?(pid)

      status = Server.get_status(pid)
      assert status.error_count >= 1

      # Cleanup
      Process.exit(pid, :normal)
    end
  end

  describe "Telegram Server health checks" do
    test "performs health checks periodically", %{bridge: bridge} do
      {:ok, pid} = Server.start_link(bridge)

      # Wait for health check to run
      :timer.sleep(35_000)

      # Server should still be alive
      assert Process.alive?(pid)

      status = Server.get_status(pid)
      # Health check should have updated status
      assert is_atom(status.status)

      # Cleanup
      Process.exit(pid, :normal)
    end
  end

  describe "Telegram Server termination" do
    test "terminates gracefully", %{bridge: bridge} do
      {:ok, pid} = Server.start_link(bridge)

      # Terminate normally
      Process.exit(pid, :normal)

      # Wait for termination
      :timer.sleep(100)

      refute Process.alive?(pid)
    end

    test "handles abnormal termination", %{bridge: bridge} do
      {:ok, pid} = Server.start_link(bridge)

      # Terminate abnormally
      Process.exit(pid, :kill)

      # Should be dead
      refute Process.alive?(pid)
    end
  end

  describe "Bridge Registry integration" do
    test "integrates with bridge registry", %{bridge: bridge} do
      # Start the bridge registry
      {:ok, _registry_pid} = GlobalbridgeBackend.Bridges.Registry.start_link([])

      # Start bridge supervisor
      {:ok, _supervisor_pid} = GlobalbridgeBackend.Bridges.Supervisor.start_link([])

      # The bridge should be registered
      registered_bridge = GlobalbridgeBackend.Bridges.Registry.get_bridge(bridge.id)
      assert registered_bridge.id == bridge.id

      # Cleanup - this would normally be handled by application shutdown
    end
  end
end
