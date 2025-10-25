defmodule GlobalbridgeBackendWeb.BridgeControllerTest do
  use GlobalbridgeBackendWeb.ConnCase, async: true

  alias GlobalbridgeBackend.{Repo, Bridges}
  alias GlobalbridgeBackend.Schemas.Bridge

  setup %{conn: conn} do
    # Create a test user
    {:ok, user} =
      GlobalbridgeBackend.Contexts.Auth.create_user(%{
        email: "test@example.com",
        username: "testuser",
        display_name: "Test User"
      })

    # Create authenticated connection
    {:ok, token, _claims} = GlobalbridgeBackend.Auth.Guardian.encode_and_sign(user)
    conn = put_req_header(conn, "authorization", "Bearer #{token}")

    %{conn: conn, user: user}
  end

  describe "GET /api/v1/bridges" do
    test "lists bridges for authenticated user", %{conn: conn, user: user} do
      # Create test bridges
      {:ok, bridge1} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      {:ok, bridge2} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "whatsapp",
          phone_number: "+0987654321"
        })

      conn = get(conn, "/api/v1/bridges")

      assert %{"bridges" => bridges} = json_response(conn, 200)
      assert length(bridges) == 2

      bridge_ids = Enum.map(bridges, & &1["id"])
      assert bridge1.id in bridge_ids
      assert bridge2.id in bridge_ids
    end

    test "returns empty list when no bridges exist", %{conn: conn} do
      conn = get(conn, "/api/v1/bridges")

      assert %{"bridges" => []} = json_response(conn, 200)
    end

    test "requires authentication" do
      conn = build_conn()
      conn = get(conn, "/api/v1/bridges")

      assert json_response(conn, 401)
    end
  end

  describe "POST /api/v1/bridges" do
    test "creates a new bridge", %{conn: conn, user: user} do
      params = %{
        bridge_type: "telegram",
        phone_number: "+1234567890"
      }

      conn = post(conn, "/api/v1/bridges", params)

      assert %{"bridge" => bridge} = json_response(conn, 201)
      assert bridge["bridge_type"] == "telegram"
      assert bridge["phone_number"] == "+1234567890"
      assert bridge["user_id"] == user.id
      assert bridge["status"] == "disconnected"
    end

    test "validates required parameters", %{conn: conn} do
      params = %{}

      conn = post(conn, "/api/v1/bridges", params)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert "can't be blank" in errors["bridge_type"]
      assert "can't be blank" in errors["phone_number"]
    end

    test "validates phone number format", %{conn: conn} do
      params = %{
        bridge_type: "telegram",
        phone_number: "invalid"
      }

      conn = post(conn, "/api/v1/bridges", params)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert "has invalid format" in errors["phone_number"]
    end

    test "validates bridge type", %{conn: conn} do
      params = %{
        bridge_type: "invalid",
        phone_number: "+1234567890"
      }

      conn = post(conn, "/api/v1/bridges", params)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert "is invalid" in errors["bridge_type"]
    end

    test "prevents duplicate bridges for same user and type", %{conn: conn, user: user} do
      # Create first bridge
      {:ok, _bridge} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      # Try to create duplicate
      params = %{
        bridge_type: "telegram",
        phone_number: "+0987654321"
      }

      conn = post(conn, "/api/v1/bridges", params)

      assert %{"errors" => errors} = json_response(conn, 422)
      assert "has already been taken" in errors["bridge_type"]
    end
  end

  describe "GET /api/v1/bridges/:thread_id/:bridge_type" do
    test "returns bridge for thread", %{conn: conn, user: user} do
      {:ok, bridge} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      # Mock thread-bridge association (in real implementation this would be stored)
      thread_id = "thread_123"

      conn = get(conn, "/api/v1/bridges/#{thread_id}/telegram")

      assert %{"bridge" => response_bridge} = json_response(conn, 200)
      assert response_bridge["id"] == bridge.id
    end

    test "returns 404 when bridge not found", %{conn: conn} do
      conn = get(conn, "/api/v1/bridges/thread_123/telegram")

      assert json_response(conn, 404)
    end
  end

  describe "DELETE /api/v1/bridges/:id" do
    test "deletes bridge", %{conn: conn, user: user} do
      {:ok, bridge} =
        Bridges.create_bridge(%{
          user_id: user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      conn = delete(conn, "/api/v1/bridges/#{bridge.id}")

      assert response(conn, 204)

      # Verify bridge is deleted
      assert is_nil(Repo.get(Bridge, bridge.id))
    end

    test "returns 404 for non-existent bridge", %{conn: conn} do
      conn = delete(conn, "/api/v1/bridges/#{Ecto.UUID.generate()}")

      assert json_response(conn, 404)
    end

    test "prevents deleting other user's bridge", %{conn: conn} do
      # Create another user and their bridge
      {:ok, other_user} =
        GlobalbridgeBackend.Contexts.Auth.create_user(%{
          email: "other@example.com",
          username: "otheruser",
          display_name: "Other User"
        })

      {:ok, other_bridge} =
        Bridges.create_bridge(%{
          user_id: other_user.id,
          bridge_type: "telegram",
          phone_number: "+1234567890"
        })

      # Try to delete other user's bridge
      conn = delete(conn, "/api/v1/bridges/#{other_bridge.id}")

      assert json_response(conn, 404)
    end
  end
end
