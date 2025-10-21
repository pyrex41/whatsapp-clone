defmodule GlobalbridgeBackendWeb.AuthController do
  @moduledoc """
  Controller for authentication endpoints: signup, login, token refresh.
  """
  use GlobalbridgeBackendWeb, :controller

  alias GlobalbridgeBackend.Contexts.Auth
  alias GlobalbridgeBackend.Auth.Guardian

  action_fallback GlobalbridgeBackendWeb.FallbackController

  @doc """
  POST /api/auth/signup
  Register a new user account.

  Params:
    - username: string (3-30 chars)
    - phone_number: string (E.164 format)
    - password: string (min 8 chars)
    - display_name: string (optional)
    - public_key: string (optional, for E2EE)
  """
  def signup(conn, params) do
    with {:ok, user, tokens} <- Auth.signup(params) do
      conn
      |> put_status(:created)
      |> render(:auth_success, user: user, tokens: tokens)
    end
  end

  @doc """
  POST /api/auth/login
  Authenticate user and receive JWT tokens.

  Params:
    - identifier: string (username or phone_number)
    - password: string
  """
  def login(conn, %{"identifier" => identifier, "password" => password}) do
    with {:ok, user, tokens} <- Auth.login(identifier, password) do
      conn
      |> put_status(:ok)
      |> render(:auth_success, user: user, tokens: tokens)
    end
  end

  def login(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required fields: identifier and password"})
  end

  @doc """
  POST /api/auth/refresh
  Refresh access token using refresh token.

  Params:
    - refresh_token: string
  """
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    case Guardian.refresh_tokens(refresh_token) do
      {:ok, tokens} ->
        conn
        |> put_status(:ok)
        |> json(%{data: tokens})

      {:error, _reason} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Invalid or expired refresh token"})
    end
  end

  def refresh(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing refresh_token"})
  end

  @doc """
  GET /api/auth/me
  Get current authenticated user information.
  Requires valid JWT in Authorization header.
  """
  def me(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    conn
    |> put_status(:ok)
    |> render(:user, user: user)
  end

  @doc """
  PUT /api/auth/public-key
  Update user's public key for E2EE.
  """
  def update_public_key(conn, %{"public_key" => public_key}) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, updated_user} <- Auth.update_public_key(user.id, public_key) do
      conn
      |> put_status(:ok)
      |> render(:user, user: updated_user)
    end
  end

  def update_public_key(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing public_key"})
  end

  @doc """
  GET /api/auth/public-key/:user_id
  Get public key for a specific user (for E2EE key exchange).
  """
  def get_public_key(conn, %{"user_id" => user_id}) do
    case Auth.get_public_key(user_id) do
      {:ok, public_key} ->
        conn
        |> put_status(:ok)
        |> json(%{data: %{user_id: user_id, public_key: public_key}})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User not found"})

      {:error, :no_public_key} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "User has not set up E2EE yet"})
    end
  end

  @doc """
  POST /api/auth/logout
  Logout user (update online status).
  """
  def logout(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    Auth.update_online_status(user.id, false)

    conn
    |> put_status(:ok)
    |> json(%{message: "Logged out successfully"})
  end

  @doc """
  PUT /api/auth/password
  Change user password.

  Params:
    - current_password: string
    - new_password: string
  """
  def change_password(conn, %{"current_password" => current, "new_password" => new_pass}) do
    user = Guardian.Plug.current_resource(conn)

    case Auth.change_password(user.id, current, new_pass) do
      {:ok, _user} ->
        conn
        |> put_status(:ok)
        |> json(%{message: "Password changed successfully"})

      {:error, :invalid_password} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Current password is incorrect"})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to change password"})
    end
  end

  def change_password(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing current_password or new_password"})
  end
end
