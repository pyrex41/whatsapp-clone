defmodule GlobalbridgeBackend.Bridges.Supervisor do
  @moduledoc """
  Supervisor for managing bridge process lifecycles.

  This supervisor:
  - Manages individual bridge processes as child processes
  - Provides functions to start and stop bridge processes
  - Handles bridge process crashes and restarts
  - Uses a :simple_one_for_one strategy for dynamic bridge process management
  """

  use Supervisor

  require Logger

  @doc """
  Starts the Bridge Supervisor.
  """
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a bridge process for the given bridge configuration.

  Returns {:ok, pid} if successful, {:error, reason} otherwise.
  """
  def start_bridge(bridge) do
    # Generate a unique ID for this bridge process
    child_id = {:bridge_process, bridge.id}

    # Child spec for the bridge process
    child_spec = %{
      id: child_id,
      start: {GlobalbridgeBackend.Bridges.Process, :start_link, [bridge]},
      restart: :transient,
      type: :worker
    }

    case Supervisor.start_child(__MODULE__, child_spec) do
      {:ok, pid} ->
        Logger.info("Started bridge process for #{bridge.bridge_type} bridge #{bridge.id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.warning(
          "Bridge process for #{bridge.bridge_type} bridge #{bridge.id} already running"
        )

        {:ok, pid}

      {:error, reason} = error ->
        Logger.error(
          "Failed to start bridge process for #{bridge.bridge_type} bridge #{bridge.id}: #{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Stops a bridge process by its PID.

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def stop_bridge(pid) when is_pid(pid) do
    case Supervisor.terminate_child(__MODULE__, pid) do
      :ok ->
        Logger.info("Stopped bridge process #{inspect(pid)}")
        :ok

      {:error, :not_found} ->
        Logger.warning("Bridge process #{inspect(pid)} not found")
        {:error, :not_found}

      {:error, reason} = error ->
        Logger.error("Failed to stop bridge process #{inspect(pid)}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stops a bridge process by bridge ID.

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def stop_bridge_by_id(bridge_id) do
    child_id = {:bridge_process, bridge_id}

    case Supervisor.terminate_child(__MODULE__, child_id) do
      :ok ->
        Logger.info("Stopped bridge process for bridge #{bridge_id}")
        :ok

      {:error, :not_found} ->
        Logger.warning("Bridge process for bridge #{bridge_id} not found")
        {:error, :not_found}

      {:error, reason} = error ->
        Logger.error("Failed to stop bridge process for bridge #{bridge_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Lists all bridge processes managed by this supervisor.

  Returns a list of {id, pid, type} tuples.
  """
  def list_bridge_processes do
    Supervisor.which_children(__MODULE__)
    |> Enum.map(fn
      {{:bridge_process, bridge_id}, pid, :worker, _modules} ->
        {bridge_id, pid, :bridge_process}

      _other ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Gets the count of active bridge processes.

  Returns the number of active bridge processes.
  """
  def count_bridge_processes do
    Supervisor.count_children(__MODULE__).workers
  end

  # Supervisor Callbacks

  @impl true
  def init(_opts) do
    children = [
      # Bridge processes will be started dynamically
      # We use :simple_one_for_one for dynamic child management
    ]

    Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
  end
end
