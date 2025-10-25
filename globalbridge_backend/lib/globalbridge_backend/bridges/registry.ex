defmodule GlobalbridgeBackend.Bridges.Registry do
  @moduledoc """
  GenServer that manages active bridge processes and provides lifecycle management.

  This registry:
  - Tracks all active bridge processes by bridge ID
  - Provides functions to start, stop, and lookup bridge processes
  - Handles bridge process lifecycle events
  - Integrates with the application supervisor for automatic restarts
  """

  use GenServer

  require Logger

  alias GlobalbridgeBackend.Contexts.Bridges
  alias GlobalbridgeBackend.Bridges.Supervisor, as: BridgeSupervisor

  # Client API

  @doc """
  Starts the Bridge Registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a bridge process for the given bridge configuration.

  Returns {:ok, pid} if successful, {:error, reason} otherwise.
  """
  def start_bridge(bridge) do
    GenServer.call(__MODULE__, {:start_bridge, bridge})
  end

  @doc """
  Stops a bridge process for the given bridge ID.

  Returns :ok if successful, {:error, reason} otherwise.
  """
  def stop_bridge(bridge_id) do
    GenServer.call(__MODULE__, {:stop_bridge, bridge_id})
  end

  @doc """
  Looks up the PID of a bridge process by bridge ID.

  Returns {:ok, pid} if found, {:error, :not_found} otherwise.
  """
  def lookup_bridge(bridge_id) do
    GenServer.call(__MODULE__, {:lookup_bridge, bridge_id})
  end

  @doc """
  Lists all active bridge processes.

  Returns a map of bridge_id => pid.
  """
  def list_active_bridges do
    GenServer.call(__MODULE__, :list_active_bridges)
  end

  @doc """
  Gets the status of a bridge process.

  Returns {:ok, status} if found, {:error, :not_found} otherwise.
  """
  def get_bridge_status(bridge_id) do
    GenServer.call(__MODULE__, {:get_bridge_status, bridge_id})
  end

  @doc """
  Restarts a bridge process.

  Returns {:ok, new_pid} if successful, {:error, reason} otherwise.
  """
  def restart_bridge(bridge_id) do
    GenServer.call(__MODULE__, {:restart_bridge, bridge_id})
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Initialize ETS table for tracking bridge processes
    :ets.new(:bridge_processes, [:named_table, :protected, read_concurrency: true])

    # Load existing active bridges on startup
    load_existing_bridges()

    {:ok, %{bridges: %{}, supervisors: %{}}}
  end

  @impl true
  def handle_call({:start_bridge, bridge}, _from, state) do
    case start_bridge_process(bridge) do
      {:ok, pid} ->
        # Store the bridge process info
        bridge_info = %{
          id: bridge.id,
          type: bridge.bridge_type,
          pid: pid,
          started_at: DateTime.utc_now(),
          status: :running
        }

        :ets.insert(:bridge_processes, {bridge.id, bridge_info})

        new_state = put_in(state.bridges[bridge.id], bridge_info)
        Logger.info("Started bridge process for #{bridge.bridge_type} bridge #{bridge.id}")

        {:reply, {:ok, pid}, new_state}

      {:error, reason} = error ->
        Logger.error(
          "Failed to start bridge process for #{bridge.bridge_type} bridge #{bridge.id}: #{inspect(reason)}"
        )

        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:stop_bridge, bridge_id}, _from, state) do
    case lookup_bridge_process(bridge_id) do
      {:ok, bridge_info} ->
        # Stop the bridge process
        case stop_bridge_process(bridge_info.pid) do
          :ok ->
            # Remove from ETS and state
            :ets.delete(:bridge_processes, bridge_id)
            new_state = %{state | bridges: Map.delete(state.bridges, bridge_id)}
            Logger.info("Stopped bridge process for bridge #{bridge_id}")
            {:reply, :ok, new_state}

          {:error, reason} = error ->
            Logger.error(
              "Failed to stop bridge process for bridge #{bridge_id}: #{inspect(reason)}"
            )

            {:reply, error, state}
        end

      {:error, :not_found} = error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:lookup_bridge, bridge_id}, _from, state) do
    case :ets.lookup(:bridge_processes, bridge_id) do
      [{^bridge_id, %{pid: pid, status: :running}}] ->
        # Verify the process is still alive
        if Process.alive?(pid) do
          {:reply, {:ok, pid}, state}
        else
          # Process died, clean up
          :ets.delete(:bridge_processes, bridge_id)
          new_state = %{state | bridges: Map.delete(state.bridges, bridge_id)}
          {:reply, {:error, :not_found}, new_state}
        end

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_active_bridges, _from, state) do
    active_bridges =
      :ets.tab2list(:bridge_processes)
      |> Enum.filter(fn {_id, info} -> info.status == :running && Process.alive?(info.pid) end)
      |> Enum.into(%{}, fn {id, info} -> {id, info.pid} end)

    {:reply, active_bridges, state}
  end

  @impl true
  def handle_call({:get_bridge_status, bridge_id}, _from, state) do
    case :ets.lookup(:bridge_processes, bridge_id) do
      [{^bridge_id, %{status: status, pid: pid}}] ->
        # Check if process is still alive
        actual_status = if Process.alive?(pid), do: status, else: :dead
        {:reply, {:ok, actual_status}, state}

      _ ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:restart_bridge, bridge_id}, _from, state) do
    with {:ok, bridge} <- get_bridge_config(bridge_id),
         {:ok, _old_pid} <- lookup_bridge_process(bridge_id),
         :ok <- stop_bridge_process_by_id(bridge_id),
         {:ok, new_pid} <- start_bridge_process(bridge) do
      # Update ETS with new process info
      bridge_info = %{
        id: bridge.id,
        type: bridge.bridge_type,
        pid: new_pid,
        started_at: DateTime.utc_now(),
        status: :running
      }

      :ets.insert(:bridge_processes, {bridge.id, bridge_info})
      new_state = put_in(state.bridges[bridge.id], bridge_info)

      Logger.info("Restarted bridge process for #{bridge.bridge_type} bridge #{bridge.id}")
      {:reply, {:ok, new_pid}, new_state}
    else
      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}

      {:error, reason} = error ->
        Logger.error(
          "Failed to restart bridge process for bridge #{bridge_id}: #{inspect(reason)}"
        )

        {:reply, error, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    # A bridge process died, clean up
    case find_bridge_by_pid(pid) do
      {:ok, bridge_id} ->
        Logger.warning("Bridge process #{bridge_id} died: #{inspect(reason)}")

        # Delete from ETS immediately to prevent memory leak
        # Previously we were marking as :dead, but this causes accumulation of dead entries
        :ets.delete(:bridge_processes, bridge_id)

        # Remove from active state
        new_state = %{state | bridges: Map.delete(state.bridges, bridge_id)}

        # Update database status to disconnected
        update_bridge_status_async(bridge_id, "disconnected")

        # Log for monitoring/alerting
        Logger.info("Cleaned up bridge #{bridge_id} from registry after process termination")

        # TODO: Implement automatic restart logic here if desired
        {:noreply, new_state}

      :error ->
        # Process was not in our registry, ignore
        {:noreply, state}
    end
  end

  # Private helper functions

  defp start_bridge_process(bridge) do
    # Start the bridge process under the BridgeSupervisor
    # This is a placeholder - actual bridge process implementation will be added later
    case BridgeSupervisor.start_bridge(bridge) do
      {:ok, pid} ->
        # Monitor the process
        Process.monitor(pid)
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp stop_bridge_process(pid) when is_pid(pid) do
    # Stop the bridge process
    # This is a placeholder - actual bridge process stopping will be added later
    BridgeSupervisor.stop_bridge(pid)
  end

  defp stop_bridge_process_by_id(bridge_id) do
    case lookup_bridge_process(bridge_id) do
      {:ok, %{pid: pid}} -> stop_bridge_process(pid)
      error -> error
    end
  end

  defp lookup_bridge_process(bridge_id) do
    case :ets.lookup(:bridge_processes, bridge_id) do
      [{^bridge_id, info}] -> {:ok, info}
      [] -> {:error, :not_found}
    end
  end

  defp find_bridge_by_pid(pid) do
    # Search ETS for bridge with matching PID
    :ets.foldl(
      fn
        {bridge_id, %{pid: ^pid}}, _acc -> {:ok, bridge_id}
        _entry, acc -> acc
      end,
      :error,
      :bridge_processes
    )
  end

  defp get_bridge_config(bridge_id) do
    case Bridges.get_bridge(bridge_id) do
      nil -> {:error, :not_found}
      bridge -> {:ok, bridge}
    end
  end

  defp load_existing_bridges do
    # Load all active bridges from database and start their processes
    # This runs on application startup
    active_bridges = Bridges.list_bridges(is_active: true, status: "connected")

    Logger.info("Loading #{length(active_bridges)} existing active bridges")

    Enum.each(active_bridges, fn bridge ->
      case start_bridge_process(bridge) do
        {:ok, pid} ->
          bridge_info = %{
            id: bridge.id,
            type: bridge.bridge_type,
            pid: pid,
            started_at: DateTime.utc_now(),
            status: :running
          }

          :ets.insert(:bridge_processes, {bridge.id, bridge_info})
          Logger.info("Loaded existing bridge #{bridge.bridge_type} #{bridge.id}")

        {:error, reason} ->
          Logger.error(
            "Failed to load existing bridge #{bridge.bridge_type} #{bridge.id}: #{inspect(reason)}"
          )
      end
    end)
  end

  defp update_bridge_status_async(bridge_id, status) do
    # Update bridge status in database asynchronously to avoid blocking the registry
    Task.Supervisor.start_child(GlobalbridgeBackend.TaskSupervisor, fn ->
      try do
        case Bridges.get_bridge(bridge_id) do
          nil ->
            Logger.warning("Bridge #{bridge_id} not found in database when updating status")

          bridge ->
            case Bridges.update_bridge(bridge, %{status: status}) do
              {:ok, _updated_bridge} ->
                Logger.debug("Updated bridge #{bridge_id} status to #{status}")

              {:error, changeset} ->
                Logger.error(
                  "Failed to update bridge #{bridge_id} status: #{inspect(changeset.errors)}"
                )
            end
        end
      rescue
        error ->
          Logger.error(
            "Error updating bridge #{bridge_id} status: #{Exception.message(error)}"
          )
      end
    end)
  end
end
