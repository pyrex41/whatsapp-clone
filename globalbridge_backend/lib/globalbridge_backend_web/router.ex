defmodule GlobalbridgeBackendWeb.Router do
  use GlobalbridgeBackendWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug CORSPlug
  end

  pipeline :auth do
    plug GlobalbridgeBackend.Auth.Pipeline
  end

  # Elm Web Client
  scope "/", GlobalbridgeBackendWeb do
    pipe_through :browser

    get "/", PageController, :elm_client
  end

  # Bootstrap endpoint for Elm client initial data
  scope "/api/bootstrap", GlobalbridgeBackendWeb do
    pipe_through [:api, :auth]

    get "/", BootstrapController, :index
  end

  scope "/api/auth", GlobalbridgeBackendWeb do
    pipe_through :api

    # Public auth routes
    post "/signup", AuthController, :signup
    post "/login", AuthController, :login
    post "/refresh", AuthController, :refresh
  end

  scope "/api/auth", GlobalbridgeBackendWeb do
    pipe_through [:api, :auth]

    # Protected auth routes
    get "/me", AuthController, :me
    post "/logout", AuthController, :logout
    put "/password", AuthController, :change_password
    put "/public-key", AuthController, :update_public_key
    get "/public-key/:user_id", AuthController, :get_public_key
  end

  scope "/api/v1", GlobalbridgeBackendWeb do
    pipe_through [:api, :auth]

    # Feature flags
    get "/features", FeatureController, :index
    get "/features/:feature", FeatureController, :show
    put "/features/tier", FeatureController, :update_tier

    # CDC Sync endpoints
    scope "/sync" do
      post "/pull", SyncController, :pull
      post "/push", SyncController, :push
    end

    get "/threads", ThreadController, :index

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
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: GlobalbridgeBackendWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
