defmodule GlobalbridgeBackendWeb.AuthControllerTest do
  use GlobalbridgeBackendWeb.ConnCase, async: true

  alias GlobalbridgeBackend.Contexts.Auth
  alias GlobalbridgeBackend.Auth.Guardian

  @signup_attrs %{
    "username" => "testuser",
    "phone_number" => "+1234567890",
    "password" => "TestPassword123",
    "display_name" => "Test User"
  }

  describe "POST /api/auth/signup" do
    test "creates user and returns tokens with valid data", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/signup", @signup_attrs)
      assert %{"data" => data} = json_response(conn, 201)
      assert %{"user" => user, "tokens" => tokens} = data
      assert user["username"] == "testuser"
      assert user["phone_number"] == "+1234567890"
      assert user["display_name"] == "Test User"
      assert Map.has_key?(tokens, "access_token")
      assert Map.has_key?(tokens, "refresh_token")
      refute Map.has_key?(user, "password_hash")
    end

    test "includes has_public_key flag when public_key provided", %{conn: conn} do
      attrs = Map.put(@signup_attrs, "public_key", "test_key_data")
      conn = post(conn, ~p"/api/auth/signup", attrs)
      assert %{"data" => %{"user" => user}} = json_response(conn, 201)
      assert user["has_public_key"] == true
    end

    test "has_public_key is false when no public_key provided", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/signup", @signup_attrs)
      assert %{"data" => %{"user" => user}} = json_response(conn, 201)
      assert user["has_public_key"] == false
    end

    test "returns error with duplicate username", %{conn: conn} do
      post(conn, ~p"/api/auth/signup", @signup_attrs)
      conn = post(conn, ~p"/api/auth/signup", @signup_attrs)
      assert %{"errors" => errors} = json_response(conn, 422)
      assert Map.has_key?(errors, "username")
    end

    test "returns error with invalid phone format", %{conn: conn} do
      attrs = Map.put(@signup_attrs, "phone_number", "1234567890")
      conn = post(conn, ~p"/api/auth/signup", attrs)
      assert %{"errors" => errors} = json_response(conn, 422)
      assert Map.has_key?(errors, "phone_number")
    end

    test "returns error with short username", %{conn: conn} do
      attrs = Map.put(@signup_attrs, "username", "ab")
      conn = post(conn, ~p"/api/auth/signup", attrs)
      assert %{"errors" => errors} = json_response(conn, 422)
      assert Map.has_key?(errors, "username")
    end

    test "returns error with missing required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/signup", %{})
      assert %{"errors" => errors} = json_response(conn, 422)
      assert Map.has_key?(errors, "username")
      assert Map.has_key?(errors, "phone_number")
    end
  end

  describe "POST /api/auth/login" do
    setup do
      {:ok, user, _tokens} = Auth.signup(@signup_attrs)
      %{user: user}
    end

    test "authenticates with username and returns tokens", %{conn: conn} do
      conn =
        post(conn, ~p"/api/auth/login", %{
          "identifier" => "testuser",
          "password" => "TestPassword123"
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert %{"user" => user, "tokens" => tokens} = data
      assert user["username"] == "testuser"
      assert Map.has_key?(tokens, "access_token")
      assert Map.has_key?(tokens, "refresh_token")
    end

    test "authenticates with phone number", %{conn: conn} do
      conn =
        post(conn, ~p"/api/auth/login", %{
          "identifier" => "+1234567890",
          "password" => "TestPassword123"
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["user"]["phone_number"] == "+1234567890"
    end

    test "sets is_online to true after login", %{conn: conn} do
      conn =
        post(conn, ~p"/api/auth/login", %{
          "identifier" => "testuser",
          "password" => "TestPassword123"
        })

      assert %{"data" => %{"user" => user}} = json_response(conn, 200)
      assert user["is_online"] == true
    end

    test "returns error with wrong password", %{conn: conn} do
      conn =
        post(conn, ~p"/api/auth/login", %{
          "identifier" => "testuser",
          "password" => "WrongPassword"
        })

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns error with non-existent user", %{conn: conn} do
      conn =
        post(conn, ~p"/api/auth/login", %{
          "identifier" => "nonexistent",
          "password" => "SomePassword"
        })

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns error with missing identifier", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/login", %{"password" => "TestPassword123"})
      assert %{"error" => _} = json_response(conn, 400)
    end

    test "returns error with missing password", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/login", %{"identifier" => "testuser"})
      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "POST /api/auth/refresh" do
    setup do
      {:ok, _user, tokens} = Auth.signup(@signup_attrs)
      %{tokens: tokens}
    end

    test "refreshes tokens with valid refresh token", %{conn: conn, tokens: tokens} do
      conn =
        post(conn, ~p"/api/auth/refresh", %{
          "refresh_token" => tokens.refresh_token
        })

      assert %{"data" => new_tokens} = json_response(conn, 200)
      assert Map.has_key?(new_tokens, "access_token")
      assert Map.has_key?(new_tokens, "refresh_token")
      assert new_tokens["access_token"] != tokens.access_token
    end

    test "returns error with invalid refresh token", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/refresh", %{"refresh_token" => "invalid_token"})
      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns error with missing refresh token", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/refresh", %{})
      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "GET /api/auth/me (protected)" do
    setup do
      {:ok, user, tokens} = Auth.signup(@signup_attrs)
      %{user: user, tokens: tokens}
    end

    test "returns current user with valid token", %{conn: conn, tokens: tokens} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> get(~p"/api/auth/me")

      assert %{"data" => user} = json_response(conn, 200)
      assert user["username"] == "testuser"
    end

    test "returns error without token", %{conn: conn} do
      conn = get(conn, ~p"/api/auth/me")
      assert json_response(conn, 401)
    end

    test "returns error with invalid token", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_token")
        |> get(~p"/api/auth/me")

      assert json_response(conn, 401)
    end
  end

  describe "PUT /api/auth/public-key (protected)" do
    setup do
      {:ok, user, tokens} = Auth.signup(@signup_attrs)
      %{user: user, tokens: tokens}
    end

    test "updates public key with valid token", %{conn: conn, tokens: tokens} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> put(~p"/api/auth/public-key", %{"public_key" => "new_public_key_data"})

      assert %{"data" => user} = json_response(conn, 200)
      assert user["has_public_key"] == true
    end

    test "returns error without token", %{conn: conn} do
      conn = put(conn, ~p"/api/auth/public-key", %{"public_key" => "key"})
      assert json_response(conn, 401)
    end

    test "returns error with missing public_key", %{conn: conn, tokens: tokens} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> put(~p"/api/auth/public-key", %{})

      assert %{"error" => _} = json_response(conn, 400)
    end
  end

  describe "GET /api/auth/public-key/:user_id (protected)" do
    setup do
      {:ok, user1, tokens} = Auth.signup(@signup_attrs)

      {:ok, user2, _} =
        Auth.signup(%{
          "username" => "user2",
          "phone_number" => "+1987654321",
          "password" => "Password123",
          "public_key" => "user2_public_key"
        })

      %{user1: user1, user2: user2, tokens: tokens}
    end

    test "retrieves another user's public key", %{conn: conn, user2: user2, tokens: tokens} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> get(~p"/api/auth/public-key/#{user2.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["user_id"] == user2.id
      assert data["public_key"] == "user2_public_key"
    end

    test "returns error when user has no public key", %{conn: conn, user1: user1, tokens: tokens} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> get(~p"/api/auth/public-key/#{user1.id}")

      assert %{"error" => _} = json_response(conn, 404)
    end

    test "returns error for non-existent user", %{conn: conn, tokens: tokens} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> get(~p"/api/auth/public-key/#{Ecto.UUID.generate()}")

      assert %{"error" => _} = json_response(conn, 404)
    end

    test "returns error without token", %{conn: conn, user2: user2} do
      conn = get(conn, ~p"/api/auth/public-key/#{user2.id}")
      assert json_response(conn, 401)
    end
  end

  describe "POST /api/auth/logout (protected)" do
    setup do
      {:ok, user, tokens} = Auth.signup(@signup_attrs)
      %{user: user, tokens: tokens}
    end

    test "logs out user successfully", %{conn: conn, tokens: tokens, user: user} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> post(~p"/api/auth/logout")

      assert %{"message" => _} = json_response(conn, 200)

      # Verify user is offline
      {:ok, updated_user} = Auth.get_user(user.id)
      assert updated_user.is_online == false
    end

    test "returns error without token", %{conn: conn} do
      conn = post(conn, ~p"/api/auth/logout")
      assert json_response(conn, 401)
    end
  end

  describe "PUT /api/auth/password (protected)" do
    setup do
      {:ok, user, tokens} = Auth.signup(@signup_attrs)
      %{user: user, tokens: tokens}
    end

    test "changes password with valid current password", %{conn: conn, tokens: tokens} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> put(~p"/api/auth/password", %{
          "current_password" => "TestPassword123",
          "new_password" => "NewPassword456"
        })

      assert %{"message" => _} = json_response(conn, 200)

      # Verify new password works
      login_conn =
        post(build_conn(), ~p"/api/auth/login", %{
          "identifier" => "testuser",
          "password" => "NewPassword456"
        })

      assert json_response(login_conn, 200)
    end

    test "returns error with wrong current password", %{conn: conn, tokens: tokens} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> put(~p"/api/auth/password", %{
          "current_password" => "WrongPassword",
          "new_password" => "NewPassword456"
        })

      assert %{"error" => _} = json_response(conn, 401)
    end

    test "returns error without token", %{conn: conn} do
      conn =
        put(conn, ~p"/api/auth/password", %{
          "current_password" => "TestPassword123",
          "new_password" => "NewPassword456"
        })

      assert json_response(conn, 401)
    end

    test "returns error with missing fields", %{conn: conn, tokens: tokens} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")
        |> put(~p"/api/auth/password", %{})

      assert %{"error" => _} = json_response(conn, 400)
    end
  end
end
