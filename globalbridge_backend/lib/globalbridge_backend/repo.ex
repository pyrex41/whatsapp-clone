defmodule GlobalbridgeBackend.Repo do
  use Ecto.Repo,
    otp_app: :globalbridge_backend,
    adapter: Ecto.Adapters.SQLite3

  # Note: exqlite uses Ecto.Adapters.SQLite3 as the adapter name
end
