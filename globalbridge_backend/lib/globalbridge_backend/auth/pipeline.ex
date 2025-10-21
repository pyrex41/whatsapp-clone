defmodule GlobalbridgeBackend.Auth.Pipeline do
  @moduledoc """
  Guardian pipeline for protecting routes with JWT authentication.
  """
  use Guardian.Plug.Pipeline,
    otp_app: :globalbridge_backend,
    module: GlobalbridgeBackend.Auth.Guardian,
    error_handler: GlobalbridgeBackend.Auth.ErrorHandler

  plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
  plug Guardian.Plug.EnsureAuthenticated
  plug Guardian.Plug.LoadResource
  plug :assign_current_user

  @doc """
  Assigns the Guardian resource to conn.assigns.current_user for easier access.
  """
  def assign_current_user(conn, _opts) do
    case Guardian.Plug.current_resource(conn) do
      nil -> conn
      user -> Plug.Conn.assign(conn, :current_user, user)
    end
  end
end
