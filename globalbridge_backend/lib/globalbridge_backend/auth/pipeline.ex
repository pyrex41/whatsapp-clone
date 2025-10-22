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
  plug(Guardian.Plug.VerifyHeader, scheme: "Bearer")
  plug(:ensure_authenticated_custom)
  plug(Guardian.Plug.LoadResource, allow_blank: true)
  plug(:assign_current_user)

  @doc """
  Verify Auth0 token from Authorization header.
  If successful, assigns the user to Guardian's resource.
  """
  def verify_auth0_token(conn, _opts) do
    with ["Bearer " <> token] <- Plug.Conn.get_req_header(conn, "authorization"),
         {:ok, user} <- GlobalbridgeBackend.Auth.Auth0Verifier.verify_and_get_user(token) do
      # Put the user in Guardian's expected location
      conn
      |> Guardian.Plug.put_current_resource(user)
      |> Plug.Conn.assign(:current_user, user)
    else
      _ ->
        # No Auth0 token or verification failed, continue to Guardian verification
        conn
    end
  end

  @doc """
  Custom authentication check that accepts either Auth0 or Guardian tokens.
  """
  def ensure_authenticated_custom(conn, _opts) do
    if Guardian.Plug.current_resource(conn) || conn.assigns[:current_user] do
      conn
    else
      # Try Guardian authentication
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
