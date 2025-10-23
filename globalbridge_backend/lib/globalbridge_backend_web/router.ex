defmodule GlobalbridgeBackendWeb.Router do
  use GlobalbridgeBackendWeb, :router
  import Phoenix.LiveView.Router

  # API Security Headers
  def put_api_security_headers(conn, _opts) do
    conn
    |> put_resp_header("x-content-type-options", "nosniff")
    |> put_resp_header("x-frame-options", "DENY")
    |> put_resp_header("x-xss-protection", "1; mode=block")
    |> put_resp_header("strict-transport-security", "max-age=31536000; includeSubDomains")
    |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
  end

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
    plug(CORSPlug)
    plug(:put_api_security_headers)
    plug(:rate_limit_api)
  end

  def rate_limit_api(conn, _opts) do
    case Hammer.check_rate("api:#{conn.remote_ip}", 60_000, 100) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_status(429)
        |> put_resp_header("retry-after", "60")
        |> Phoenix.Controller.json(%{error: "Too many requests"})
        |> halt()
    end
  end

  pipeline :rate_limited_auth do
    # Rate limiting for auth endpoints using Hammer
    plug(:rate_limit_auth)
  end

  def rate_limit_auth(conn, _opts) do
    case Hammer.check_rate("auth:#{conn.remote_ip}", 60_000, 5) do
      {:allow, _count} ->
        conn

      {:deny, _limit} ->
        conn
        |> put_status(429)
        |> put_resp_header("retry-after", "60")
        |> Phoenix.Controller.json(%{error: "Too many requests"})
        |> halt()
    end
  end

  pipeline :auth do
    plug(GlobalbridgeBackend.Auth.Pipeline)
  end

  # LiveView App
  scope "/", GlobalbridgeBackendWeb do
    pipe_through(:browser)

    live("/", AuthLive, :index)
  end

  scope "/auth", GlobalbridgeBackendWeb do
    pipe_through(:browser)

    get("/logout", AuthController, :logout)
  end

  scope "/app", GlobalbridgeBackendWeb do
    pipe_through([:browser, :auth])

    live("/", AppLive, :index)
    live("/threads/:thread_id", AppLive, :show)
  end

  # Bootstrap endpoint for Elm client initial data
  scope "/api/bootstrap", GlobalbridgeBackendWeb do
    pipe_through([:api, :auth])

    get("/", BootstrapController, :index)
  end

  scope "/api/auth", GlobalbridgeBackendWeb do
    pipe_through([:api, :rate_limited_auth])

    # Public auth routes
    post("/signup", AuthController, :signup)
    post("/login", AuthController, :login)
    post("/refresh", AuthController, :refresh)

    # OAuth routes
    get("/:provider", AuthController, :request)
    get("/:provider/callback", AuthController, :callback)
  end

  scope "/api/auth", GlobalbridgeBackendWeb do
    pipe_through([:api, :auth])

    # Protected auth routes
    get("/me", AuthController, :me)
    post("/logout", AuthController, :logout)
    put("/password", AuthController, :change_password)
    put("/public-key", AuthController, :update_public_key)
    get("/public-key/:user_id", AuthController, :get_public_key)
  end

  scope "/api/v1", GlobalbridgeBackendWeb do
    pipe_through([:api, :auth])

    # Feature flags
    get("/features", FeatureController, :index)
    get("/features/:feature", FeatureController, :show)
    put("/features/tier", FeatureController, :update_tier)

    # CDC Sync endpoints
    scope "/sync" do
      post("/pull", SyncController, :pull)
      post("/push", SyncController, :push)
    end

    get("/threads", ThreadController, :index)

    # Protected API routes will go here
    # Example: resources for threads, messages, etc.
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:globalbridge_backend, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through([:fetch_session, :protect_from_forgery])

      live_dashboard("/dashboard", metrics: GlobalbridgeBackendWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end
end
