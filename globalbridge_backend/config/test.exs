import Config

# Test environment variables
System.put_env("AUTH0_DOMAIN", "test.auth0.com")
System.put_env("AUTH0_CLIENT_ID", "test_client_id")
System.put_env("AUTH0_CLIENT_SECRET", "test_client_secret")
System.put_env("AUTH0_AUDIENCE", "test-audience")
System.put_env("OPENAI_API_KEY", "test_openai_key")
System.put_env("ANTHROPIC_API_KEY", "test_anthropic_key")

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

# Configure Oban for testing (disabled)
config :globalbridge_backend, Oban,
  testing: :manual,
  queues: false,
  plugins: false

# Configure OpenAI for testing (mocked)
config :openai,
  api_key: "test_openai_key",
  http_options: [recv_timeout: 30_000]

# Enable test mode for AI services
config :globalbridge_backend, test_mode: true

# Configure Cachex for testing
config :cachex, :caches,
  ai_cache: [
    default_ttl: :timer.minutes(30),
    ttl_interval: :timer.minutes(5),
    limit: 1000
  ]
