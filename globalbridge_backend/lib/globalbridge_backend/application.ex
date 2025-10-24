defmodule GlobalbridgeBackend.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Validate sqlite-vec extension before starting
    validate_sqlite_vec()

    # Background job processing with Oban (not in test)
    children =
      [
        GlobalbridgeBackend.Repo,
        GlobalbridgeBackendWeb.Telemetry,
        {DNSCluster,
         query: Application.get_env(:globalbridge_backend, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: GlobalbridgeBackend.PubSub},
        # Phoenix Presence for online/offline tracking
        GlobalbridgeBackendWeb.Presence,
        # JWKS cache for Auth0 JWT verification
        GlobalbridgeBackend.Auth.JWKSCache,
        # Participant cache for thread authorization
        GlobalbridgeBackend.Cache.ParticipantCache,
        # Task supervisor for async operations (message persistence, read receipts, notifications)
        {Task.Supervisor, name: GlobalbridgeBackend.TaskSupervisor},
        # Dynamic supervisor for per-thread database repos
        {DynamicSupervisor,
         name: GlobalbridgeBackend.DynamicRepoSupervisor, strategy: :one_for_one},
        # Agens Multi-Agent Framework Supervisor
        Agens.Supervisor
      ] ++
        if Mix.env() != :test do
          [{Oban, Application.fetch_env!(:globalbridge_backend, Oban)}]
        else
          []
        end ++
        [
          # Caching with Cachex
          {Cachex, name: :ai_cache},
          # AI Components Setup (runs after other supervisors are started)
          {Task,
           fn ->
             GlobalbridgeBackend.AI.AgensSetup.start_components()
             GlobalbridgeBackend.AI.Telemetry.setup()
           end},
          # AI Cost Tracking and Budget Monitoring
          GlobalbridgeBackend.AI.CostTracker,
          GlobalbridgeBackend.AI.BudgetMonitor,
          # Start a worker by calling: GlobalbridgeBackend.Worker.start_link(arg)
          # {GlobalbridgeBackend.Worker, arg},
          # Start to serve requests, typically the last entry
          GlobalbridgeBackendWeb.Endpoint
        ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: GlobalbridgeBackend.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GlobalbridgeBackendWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Private functions

  defp validate_sqlite_vec do
    require Logger

    case System.get_env("SQLITE_VEC_PATH") do
      nil ->
        Logger.warning(
          "SQLITE_VEC_PATH not set. Vector operations may fail. " <>
            "Set this environment variable to the path of your vec0 shared library."
        )

      path ->
        # Validate path to prevent directory traversal
        expanded_path = Path.expand(path)

        # Check if path looks suspicious (contains ..)
        if String.contains?(path, "..") do
          raise """
          Invalid SQLITE_VEC_PATH: path contains '..' which may indicate directory traversal.
          Provided path: #{path}
          """
        end

        # Verify file exists
        if File.exists?(expanded_path) do
          Logger.info("sqlite-vec extension found at #{expanded_path}")
        else
          raise """
          SQLITE_VEC_PATH points to non-existent file.
          Provided path: #{path}
          Expanded path: #{expanded_path}
          Please ensure the vec0 shared library is installed and the path is correct.
          """
        end
    end
  end
end
