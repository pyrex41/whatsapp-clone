defmodule GlobalbridgeBackend.Bridges.Process do
  @moduledoc """
  GenServer that manages an individual bridge process.

  This process:
  - Handles the lifecycle of a single bridge (WhatsApp, Telegram, etc.)
  - Manages connection state and session data
  - Processes incoming and outgoing messages
  - Handles bridge-specific operations like QR code generation
  """

  use GenServer

  require Logger

  alias GlobalbridgeBackend.Contexts.Bridges
  alias GlobalbridgeBackend.Schemas.Bridge
  alias GlobalbridgeBackend.Bridges.Telegram.Server, as: TelegramServer

  # Client API

  @doc """
  Starts a bridge process for the given bridge configuration.
  """
  def start_link(bridge) do
    GenServer.start_link(__MODULE__, bridge)
  end

  @doc """
  Gets the current status of the bridge.
  """
  def get_status(pid) do
    GenServer.call(pid, :get_status)
  end

  @doc """
  Connects the bridge.
  """
  def connect(pid) do
    GenServer.call(pid, :connect)
  end

  @doc """
  Disconnects the bridge.
  """
  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  @doc """
  Gets the QR code for bridge authentication (if applicable).
  """
  def get_qr_code(pid) do
    GenServer.call(pid, :get_qr_code)
  end

  @doc """
  Updates the bridge configuration.
  """
  def update_config(pid, config) do
    GenServer.call(pid, {:update_config, config})
  end

  # Server Callbacks

  @impl true
  def init(%Bridge{} = bridge) do
    Logger.info("Initializing bridge process for #{bridge.bridge_type} bridge #{bridge.id}")

    # Initialize bridge state
    state = %{
      bridge: bridge,
      status: :disconnected,
      session_data: bridge.session_data || %{},
      qr_code: nil,
      last_error: nil,
      connected_at: nil,
      server_pid: nil
    }

    # If bridge was previously connected, attempt to reconnect
    if bridge.status == "connected" and bridge.is_active do
      # Schedule reconnection attempt
      Process.send_after(self(), :auto_reconnect, 1000)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      bridge_id: state.bridge.id,
      bridge_type: state.bridge.bridge_type,
      status: state.status,
      qr_code: state.qr_code,
      last_error: state.last_error,
      connected_at: state.connected_at,
      session_data: state.session_data
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:connect, _from, state) do
    case connect_bridge(state.bridge, state.session_data) do
      {:ok, session_data, qr_code} ->
        # Update database with new session data
        {:ok, updated_bridge} =
          Bridges.update_bridge_session(state.bridge, %{
            status: "connecting",
            session_data: session_data,
            qr_code: qr_code,
            last_connected_at: DateTime.utc_now()
          })

        new_state = %{
          state
          | bridge: updated_bridge,
            status: :connecting,
            session_data: session_data,
            qr_code: qr_code,
            last_error: nil
        }

        Logger.info("Connecting #{state.bridge.bridge_type} bridge #{state.bridge.id}")
        {:reply, {:ok, qr_code}, new_state}

      {:error, reason} = error ->
        # Update database with error
        {:ok, _updated_bridge} =
          Bridges.update_bridge_session(state.bridge, %{
            status: "error",
            error_message: inspect(reason)
          })

        new_state = %{state | status: :error, last_error: reason}

        Logger.error(
          "Failed to connect #{state.bridge.bridge_type} bridge #{state.bridge.id}: #{inspect(reason)}"
        )

        {:reply, error, new_state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    case disconnect_bridge(state.bridge, state.session_data) do
      :ok ->
        # Update database
        {:ok, updated_bridge} =
          Bridges.update_bridge_session(state.bridge, %{
            status: "disconnected"
          })

        new_state = %{
          state
          | bridge: updated_bridge,
            status: :disconnected,
            qr_code: nil,
            connected_at: nil
        }

        Logger.info("Disconnected #{state.bridge.bridge_type} bridge #{state.bridge.id}")
        {:reply, :ok, new_state}

      {:error, reason} = error ->
        Logger.error(
          "Failed to disconnect #{state.bridge.bridge_type} bridge #{state.bridge.id}: #{inspect(reason)}"
        )

        {:reply, error, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "Terminating bridge process for #{state.bridge.bridge_type} bridge #{state.bridge.id}: #{inspect(reason)}"
    )

    # Clean up bridge connection
    disconnect_bridge(state.bridge, state.session_data)

    # The server process should be automatically terminated by the supervisor
    # when this process terminates

    # Update database status
    Bridges.update_bridge_session(state.bridge, %{
      status: "disconnected",
      error_message: "Process terminated: #{inspect(reason)}"
    })

    :ok
  end

  @impl true
  def handle_call({:update_config, config}, _from, state) do
    # Update bridge configuration
    {:ok, updated_bridge} = Bridges.update_bridge(state.bridge, config)

    new_state = %{state | bridge: updated_bridge}
    Logger.info("Updated configuration for #{state.bridge.bridge_type} bridge #{state.bridge.id}")

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:auto_reconnect, state) do
    Logger.info(
      "Attempting auto-reconnect for #{state.bridge.bridge_type} bridge #{state.bridge.id}"
    )

    case connect_bridge(state.bridge, state.session_data) do
      {:ok, session_data, _qr_code} ->
        # Update database
        {:ok, updated_bridge} =
          Bridges.update_bridge_session(state.bridge, %{
            status: "connected",
            session_data: session_data,
            last_connected_at: DateTime.utc_now()
          })

        new_state = %{
          state
          | bridge: updated_bridge,
            status: :connected,
            session_data: session_data,
            connected_at: DateTime.utc_now(),
            last_error: nil
        }

        Logger.info("Auto-reconnected #{state.bridge.bridge_type} bridge #{state.bridge.id}")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning(
          "Auto-reconnect failed for #{state.bridge.bridge_type} bridge #{state.bridge.id}: #{inspect(reason)}"
        )

        # Update database with error
        {:ok, _updated_bridge} =
          Bridges.update_bridge_session(state.bridge, %{
            status: "error",
            error_message: inspect(reason)
          })

        # Schedule another attempt in 30 seconds
        Process.send_after(self(), :auto_reconnect, 30_000)

        new_state = %{state | status: :error, last_error: reason}
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_info({:bridge_message, message}, state) do
    # Handle incoming messages from the bridge
    # This is a placeholder for message processing logic
    Logger.debug(
      "Received message from #{state.bridge.bridge_type} bridge #{state.bridge.id}: #{inspect(message)}"
    )

    # TODO: Process the message and forward to appropriate channels
    {:noreply, state}
  end

  @impl true
  def handle_info({:bridge_event, event}, state) do
    # Handle bridge events (connected, disconnected, etc.)
    Logger.info(
      "Bridge event for #{state.bridge.bridge_type} bridge #{state.bridge.id}: #{inspect(event)}"
    )

    case event do
      {:connected, session_data} ->
        # Update database
        {:ok, updated_bridge} =
          Bridges.update_bridge_session(state.bridge, %{
            status: "connected",
            session_data: session_data,
            last_connected_at: DateTime.utc_now()
          })

        new_state = %{
          state
          | bridge: updated_bridge,
            status: :connected,
            session_data: session_data,
            connected_at: DateTime.utc_now(),
            qr_code: nil,
            last_error: nil
        }

        {:noreply, new_state}

      {:disconnected, reason} ->
        # Update database
        {:ok, updated_bridge} =
          Bridges.update_bridge_session(state.bridge, %{
            status: "disconnected",
            error_message: inspect(reason)
          })

        new_state = %{
          state
          | bridge: updated_bridge,
            status: :disconnected,
            connected_at: nil,
            last_error: reason
        }

        {:noreply, new_state}

      {:error, reason} ->
        # Update database
        {:ok, updated_bridge} =
          Bridges.update_bridge_session(state.bridge, %{
            status: "error",
            error_message: inspect(reason)
          })

        new_state = %{state | status: :error, last_error: reason}
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    Logger.info(
      "Terminating bridge process for #{state.bridge.bridge_type} bridge #{state.bridge.id}: #{inspect(reason)}"
    )

    # Clean up bridge connection
    disconnect_bridge(state.bridge, state.session_data)

    # Update database status
    Bridges.update_bridge_session(state.bridge, %{
      status: "disconnected",
      error_message: "Process terminated: #{inspect(reason)}"
    })

    :ok
  end

  # Private helper functions

  defp connect_bridge(%Bridge{bridge_type: "whatsapp"} = bridge, session_data) do
    # TODO: Implement WhatsApp connection logic
    # This is a placeholder that simulates connection
    Logger.info("Connecting WhatsApp bridge #{bridge.id}")

    # Simulate successful connection with mock data
    mock_session_data =
      Map.merge(session_data, %{
        "connected_at" => DateTime.utc_now(),
        "client_id" => "mock_client_id"
      })

    # For WhatsApp, we might need a QR code for initial setup
    qr_code =
      if map_size(session_data) == 0 do
        "mock_qr_code_data"
      else
        nil
      end

    {:ok, mock_session_data, qr_code}
  end

  defp connect_bridge(%Bridge{bridge_type: "telegram"} = bridge, session_data) do
    Logger.info("Connecting Telegram bridge #{bridge.id}")

    # Start Telegram server
    case TelegramServer.start_link(bridge) do
      {:ok, server_pid} ->
        Logger.info("Started Telegram server for bridge #{bridge.id}")

        # Update session data
        updated_session_data =
          Map.merge(session_data, %{
            "connected_at" => DateTime.utc_now(),
            "server_started" => true
          })

        {:ok, updated_session_data, nil}

      {:error, reason} ->
        Logger.error(
          "Failed to start Telegram server for bridge #{bridge.id}: #{inspect(reason)}"
        )

        {:error, "Failed to start Telegram server: #{inspect(reason)}"}
    end
  end

  defp connect_bridge(%Bridge{bridge_type: type}, _session_data) do
    {:error, "Unsupported bridge type: #{type}"}
  end

  defp disconnect_bridge(%Bridge{bridge_type: "telegram"} = bridge, _session_data) do
    # Stop Telegram server if running
    # The server should be managed by the supervisor, so we don't need to manually stop it here
    Logger.info("Disconnecting Telegram bridge #{bridge.id}")
    :ok
  end

  defp disconnect_bridge(_bridge, _session_data) do
    # Default disconnect logic
    :ok
  end
end
