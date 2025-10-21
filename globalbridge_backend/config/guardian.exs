import Config

# Guardian JWT configuration
config :globalbridge_backend, GlobalbridgeBackend.Auth.Guardian,
  issuer: "globalbridge_backend",
  secret_key: System.get_env("GUARDIAN_SECRET_KEY") || "dev_secret_key_change_in_production_minimum_32_characters_long"
