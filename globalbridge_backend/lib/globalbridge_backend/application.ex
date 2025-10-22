defmodule GlobalbridgeBackend.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GlobalbridgeBackend.Repo,
      GlobalbridgeBackendWeb.Telemetry,
      {DNSCluster,
       query: Application.get_env(:globalbridge_backend, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: GlobalbridgeBackend.PubSub},
      # Phoenix Presence for online/offline tracking
      GlobalbridgeBackendWeb.Presence,
      # Task supervisor for async operations (message persistence, read receipts, notifications)
      {Task.Supervisor, name: GlobalbridgeBackend.TaskSupervisor},
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
end
