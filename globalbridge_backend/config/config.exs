# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :globalbridge_backend,
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  ecto_repos: [GlobalbridgeBackend.Repo]

# SQLite Adapter Configuration
# Using ecto_sqlite3 for all environments
config :globalbridge_backend, GlobalbridgeBackend.Repo,
  adapter: Ecto.Adapters.SQLite3,
  # WAL mode for better concurrency
  journal_mode: :wal,
  # Enable foreign keys
  foreign_keys: :on,
  # Cache configuration
  cache_size: -64000,
  # Busy timeout (5 seconds)
  busy_timeout: 5000

# Configures the endpoint
config :globalbridge_backend, GlobalbridgeBackendWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: GlobalbridgeBackendWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GlobalbridgeBackend.PubSub,
  live_view: [signing_salt: "nWZaIJ6y"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :globalbridge_backend, GlobalbridgeBackend.Mailer, adapter: Swoosh.Adapters.Local

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Guardian JWT configuration
import_config "guardian.exs"

# Auth0 configuration
import_config "auth0.exs"

# Hammer rate limiting configuration
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 4, cleanup_interval_ms: 60_000 * 10]}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
