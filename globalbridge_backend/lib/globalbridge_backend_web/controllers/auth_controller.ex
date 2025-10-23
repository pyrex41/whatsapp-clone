defmodule GlobalbridgeBackendWeb.AuthController do
  @moduledoc """
  Controller for authentication endpoints: signup, login, token refresh.
  """
  use GlobalbridgeBackendWeb, :controller

  alias GlobalbridgeBackend.Contexts.Auth
  alias GlobalbridgeBackend.Auth.Guardian
  alias GlobalbridgeBackend.Auth.Auth0Verifier

  action_fallback(GlobalbridgeBackendWeb.FallbackController)

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

  @doc """
  GET /api/auth/:provider
  Initiate OAuth flow with the specified provider.
  """
  def request(conn, %{"provider" => "auth0"}) do
    # Redirect to Auth0 authorization URL
    auth0_domain = Application.get_env(:globalbridge_backend, :auth0_domain) ||
      raise "AUTH0_DOMAIN not configured"
    client_id = Application.get_env(:globalbridge_backend, :auth0_client_id) ||
      raise "AUTH0_CLIENT_ID not configured"

    redirect_uri = "#{conn.scheme}://#{conn.host}:#{conn.port}/api/auth/auth0/callback"

    auth_url =
      "https://#{auth0_domain}/authorize?" <>
        URI.encode_query(%{
          client_id: client_id,
          redirect_uri: redirect_uri,
          response_type: "code",
          scope: "openid profile email",
          state: generate_state()
        })

    conn
    |> put_status(:found)
    |> redirect(external: auth_url)
  end

  def request(conn, %{"provider" => provider}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Unsupported OAuth provider: #{provider}"})
  end

  @doc """
  GET /api/auth/:provider/callback
  Handle OAuth callback from the provider.
  """
  def callback(conn, %{"provider" => "auth0", "code" => code, "state" => state}) do
    # Verify state parameter for CSRF protection
    if verify_state(state) do
      case exchange_code_for_token(code) do
        {:ok, token_data} ->
          # Extract user info and create/update user
          case Auth0Verifier.verify_and_get_user(token_data["access_token"]) do
            {:ok, user} ->
              # Generate our own JWT tokens for the user
              {:ok, tokens} = Guardian.encode_and_sign(user)

              # Store tokens in session for LiveView
              conn
              |> put_session(:guardian_token, tokens.access)
              |> put_session(:user_id, user.id)
              |> redirect(to: "/app")

            {:error, reason} ->
              conn
              |> put_status(:unauthorized)
              |> json(%{error: "Failed to authenticate user: #{inspect(reason)}"})
          end

        {:error, reason} ->
          conn
          |> put_status(:unauthorized)
          |> json(%{error: "Failed to exchange code for token: #{inspect(reason)}"})
      end
    else
      conn
      |> put_status(:bad_request)
      |> json(%{error: "Invalid state parameter"})
    end
  end

  def callback(conn, %{"provider" => "auth0", "error" => error}) do
    conn
    |> put_status(:unauthorized)
    |> json(%{error: "OAuth error: #{error}"})
  end

  def callback(conn, %{"provider" => provider}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Unsupported OAuth provider: #{provider}"})
  end

  @doc """
  GET /auth/logout
  Logout user and redirect to login page.
  """
  def logout(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: "/")
  end

  # Private helper functions

  defp generate_state do
    # Generate a random state for CSRF protection
    :crypto.strong_rand_bytes(32) |> Base.url_encode64()
  end

  defp verify_state(_state) do
    # In production, verify the state matches what we stored in session
    # For now, accept any state
    true
  end

  defp exchange_code_for_token(code) do
    auth0_domain = Application.get_env(:globalbridge_backend, :auth0_domain) ||
      raise "AUTH0_DOMAIN not configured"
    client_id = Application.get_env(:globalbridge_backend, :auth0_client_id) ||
      raise "AUTH0_CLIENT_ID not configured"
    client_secret = Application.get_env(:globalbridge_backend, :auth0_client_secret) ||
      raise "AUTH0_CLIENT_SECRET not configured"

    url = "https://#{auth0_domain}/oauth/token"

    body = %{
      grant_type: "authorization_code",
      client_id: client_id,
      client_secret: client_secret,
      code: code,
      redirect_uri:
        "#{System.get_env("APP_URL", "http://localhost:4000")}/api/auth/auth0/callback"
    }

    headers = [{"Content-Type", "application/json"}]

    case Req.post(url, json: body, headers: headers) do
      {:ok, %{status: 200, body: response}} ->
        {:ok, response}

      {:ok, %{status: status, body: error}} ->
        {:error, "HTTP #{status}: #{inspect(error)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
