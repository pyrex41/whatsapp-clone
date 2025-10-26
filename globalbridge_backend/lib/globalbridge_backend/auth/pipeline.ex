defmodule GlobalbridgeBackend.Auth.Pipeline do
  @moduledoc """
  Authentication pipeline that supports both Guardian JWT and Auth0 tokens.
  """
  use Guardian.Plug.Pipeline,
    otp_app: :globalbridge_backend,
    module: GlobalbridgeBackend.Auth.Guardian,
    error_handler: GlobalbridgeBackend.Auth.ErrorHandler

  # First try to verify Auth0 token, then fall back to Guardian
  plug(:verify_auth0_token)
  plug(:conditionally_verify_guardian)
  plug(Guardian.Plug.LoadResource, allow_blank: true)
  plug(:ensure_authenticated_custom)
  plug(:assign_current_user)

  @doc """
  Verify Auth0 token from Authorization header.
  If successful, assigns the user to Guardian's resource.
  """
  def verify_auth0_token(conn, _opts) do
    require Logger

    case Plug.Conn.get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        Logger.info("🔍 [AUTH] Found Bearer token in request")

        case GlobalbridgeBackend.Auth.Auth0Verifier.verify_and_get_user(token) do
          {:ok, user} ->
            Logger.info("✅ [AUTH] Auth0 token verified for user: #{user.id}")
            # Put the user in Guardian's expected location
            conn
            |> Guardian.Plug.put_current_resource(user)
            |> Plug.Conn.assign(:current_user, user)
            |> Plug.Conn.assign(:auth0_verified, true)
            |> Plug.Conn.assign(:auth_bypass_used, token == "test-token-for-backend-integration")

          {:error, reason} ->
            Logger.warning("⚠️ [AUTH] Auth0 verification failed: #{inspect(reason)}")
            conn
        end

      [] ->
        Logger.debug("📭 [AUTH] No Authorization header found")
        conn

      other ->
        Logger.warning("⚠️ [AUTH] Unexpected Authorization header format: #{inspect(other)}")
        conn
    end
  end

  @doc """
  Conditionally verify Guardian token, skipping for auth bypass or Auth0 tokens.
  """
  def conditionally_verify_guardian(conn, _opts) do
    cond do
      # Skip if Auth0 already verified the user
      conn.assigns[:auth0_verified] ->
        conn

      # Skip Guardian verification for test token
      conn.assigns[:auth_bypass_used] ->
        conn

      # Use normal Guardian verification for Guardian tokens
      true ->
        Guardian.Plug.VerifyHeader.call(conn, [])
    end
  end

  @doc """
  Custom authentication check that accepts either Auth0 or Guardian tokens.
  In dev mode, bypasses authentication and creates a mock user.
  """
  def ensure_authenticated_custom(conn, _opts) do
    dev_mode = Application.get_env(:globalbridge_backend, :dev_mode, false)

    cond do
      # Already authenticated
      Guardian.Plug.current_resource(conn) || conn.assigns[:current_user] ->
        conn

      # Dev mode bypass - create mock user
      dev_mode ->
        require Logger
        Logger.info("🔓 [AUTH] Dev mode: bypassing authentication for #{conn.request_path}")

        # Create a mock user for development
        mock_user = %GlobalbridgeBackend.Schemas.User{
          id: Ecto.UUID.generate(),
          username: "dev_user",
          phone_number: "+15551234567",
          inserted_at: DateTime.utc_now(),
          updated_at: DateTime.utc_now()
        }

        conn
        |> Plug.Conn.assign(:current_user, mock_user)
        |> Plug.Conn.assign(:dev_mode, true)

      # Normal authentication required
      true ->
        Guardian.Plug.EnsureAuthenticated.call(conn, [])
    end
  end

  @doc """
  Assigns the Guardian resource to conn.assigns.current_user for easier access.
  """
  def assign_current_user(conn, _opts) do
    cond do
      conn.assigns[:current_user] ->
        conn

      user = Guardian.Plug.current_resource(conn) ->
        Plug.Conn.assign(conn, :current_user, user)

      true ->
        conn
    end
  end
end
