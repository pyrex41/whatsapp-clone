import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/globalbridge_backend start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :globalbridge_backend, GlobalbridgeBackendWeb.Endpoint, server: true
end

# Configure database for production
if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /mnt/data/users.db
      """

  config :globalbridge_backend, GlobalbridgeBackend.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  # Configure dev_mode for bypassing authentication (use carefully in production!)
  dev_mode = System.get_env("DEV_MODE") == "true"
  config :globalbridge_backend, dev_mode: dev_mode
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :globalbridge_backend, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :globalbridge_backend, GlobalbridgeBackendWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :globalbridge_backend, GlobalbridgeBackendWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :globalbridge_backend, GlobalbridgeBackendWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Here is an example configuration for Mailgun:
  #
  #     config :globalbridge_backend, GlobalbridgeBackend.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # Most non-SMTP adapters require an API client. Swoosh supports Req, Hackney,
  # and Finch out-of-the-box. This configuration is typically done at
  # compile-time in your config/prod.exs:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Req
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end

# AI Configuration (OpenAI, Anthropic, etc.)
if config_env() in [:dev, :prod] do
  # OpenAI API Key for embeddings and LLM calls
  openai_api_key = System.get_env("OPENAI_API_KEY")
  anthropic_api_key = System.get_env("ANTHROPIC_API_KEY")

  # Configure OpenAI
  if openai_api_key do
    openai_config = [
      api_key: openai_api_key,
      organization: System.get_env("OPENAI_ORGANIZATION"),
      http_options: [recv_timeout: 30_000]
    ]

    # Add custom URL if provided
    openai_url = System.get_env("OPENAI_URL")

    if openai_url do
      openai_config = Keyword.put(openai_config, :url, openai_url)
    end

    config :openai, openai_config
  end

  # Configure Anthropic (optional)
  if anthropic_api_key do
    config :anthropic,
      api_key: anthropic_api_key
  end

  # Warn about missing AI API keys in development
  if config_env() == :dev do
    unless openai_api_key do
      IO.warn("""
      ⚠️  Missing OpenAI API key: OPENAI_API_KEY
      AI features will not work without this key.
      Get one from: https://platform.openai.com/api-keys
      """)
    end
  end

  # Require OpenAI API key in production
  if config_env() == :prod do
    unless openai_api_key do
      raise """
      environment variable OPENAI_API_KEY is required in production.
      Get your API key from: https://platform.openai.com/api-keys
      """
    end
  end
end

# Oban Background Job Configuration
oban_config = [
  engine: Oban.Engines.Basic,
  notifier: Oban.Notifiers.PG,  # Use PG notifier (polling-based, works with SQLite)
  prefix: false,  # SQLite doesn't support table prefixes
  queues: [
    default: 10,
    embeddings: 5,
    ai_processing: 3
  ],
  repo: GlobalbridgeBackend.Repo
]

# Add cron jobs only for dev and prod environments
oban_config =
  if config_env() in [:dev, :prod] do
    Keyword.put(oban_config, :plugins, [
      {Oban.Plugins.Cron,
       crontab: [
         {"0 * * * *", GlobalbridgeBackend.AI.Jobs.CleanupCacheJob}
       ]}
    ])
  else
    oban_config
  end

config :globalbridge_backend, Oban, oban_config

# Auth0 Configuration (for all environments that use Auth0)
if config_env() in [:dev, :prod] do
  # Validate and configure Auth0 environment variables
  auth0_domain = System.get_env("AUTH0_DOMAIN")
  auth0_client_id = System.get_env("AUTH0_CLIENT_ID")
  auth0_client_secret = System.get_env("AUTH0_CLIENT_SECRET")
  auth0_audience = System.get_env("AUTH0_AUDIENCE", "globalbridge-api")

  # Warn about missing Auth0 variables in development
  if config_env() == :dev do
    required_vars = [
      {"AUTH0_DOMAIN", "your-tenant.auth0.com", auth0_domain},
      {"AUTH0_CLIENT_ID", "your_client_id_here", auth0_client_id},
      {"AUTH0_CLIENT_SECRET", "your_client_secret_here", auth0_client_secret}
    ]

    for {var_name, example, value} <- required_vars do
      unless value do
        IO.warn("""
        ⚠️  Missing Auth0 environment variable: #{var_name}
        Example: export #{var_name}="#{example}"
        See globalbridge_backend/AUTH0_ENV_SETUP.md for configuration details.
        """)
      end
    end
  end

  # In production, require all Auth0 variables
  if config_env() == :prod do
    unless auth0_domain do
      raise """
      environment variable AUTH0_DOMAIN is required in production.
      Example: your-tenant.auth0.com
      """
    end

    unless auth0_client_id do
      raise """
      environment variable AUTH0_CLIENT_ID is required in production.
      Get this from your Auth0 application settings.
      """
    end

    unless auth0_client_secret do
      raise """
      environment variable AUTH0_CLIENT_SECRET is required in production.
      Get this from your Auth0 application settings.
      """
    end
  end

  # Store in application config for runtime access
  config :globalbridge_backend,
    auth0_domain: auth0_domain,
    auth0_client_id: auth0_client_id,
    auth0_client_secret: auth0_client_secret,
    auth0_audience: auth0_audience
end
