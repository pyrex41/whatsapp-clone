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
end
