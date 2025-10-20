import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :globalbridge_backend, GlobalbridgeBackendWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "ChjGdZ9K2DwodXmm8yXGM1yw/EG1IzTCGRGsfpDRkcrB9k+EWNJxpRBawC68Pwhn",
  server: false

# In test we don't send emails
config :globalbridge_backend, GlobalbridgeBackend.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Configure SQLite for testing
config :globalbridge_backend, GlobalbridgeBackend.Repo,
  database: Path.expand("../priv/repo/test.db", Path.dirname(__ENV__.file)),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 10
