defmodule GlobalbridgeBackend.Bridges.Telegram.Server do
  @moduledoc """
  GenServer for handling Telegram Bot API integration.

  This server manages:
  - Polling the Telegram API for new messages
  - Processing incoming messages and forwarding to GlobalBridge
  - Sending messages from GlobalBridge to Telegram
  - Managing bot token and API rate limiting
  - Health checks and connection monitoring
  """

  use GenServer

  require Logger

  alias GlobalbridgeBackend.Bridges.Telegram.API
  alias GlobalbridgeBackend.Contexts.Messaging
  alias GlobalbridgeBackend.Notifications
  alias GlobalbridgeBackendWeb.Endpoint

  # Configuration
  @poll_interval Application.compile_env(:globalbridge_backend, [:bridge, :poll_interval], 2000)
  @health_check_interval Application.compile_env(
                           :globalbridge_backend,
                           [:bridge, :health_check_interval],
                           30_000
                         )
  @max_failures Application.compile_env(:globalbridge_backend, [:bridge, :max_failures], 5)
  @max_backoff_time 300_000

  # Client API

  @doc """
  Starts the Telegram server for a bridge.
  """
  def start_link(bridge) do
    GenServer.start_link(__MODULE__, bridge)
  end

  @doc """
  Sends a message to a Telegram chat.

  Returns {:ok, message} or {:error, reason}.
  """
  def send_message(pid, chat_id, text, opts \\ []) do
    GenServer.call(pid, {:send_message, chat_id, text, opts})
  end

  @doc """
  Gets the current status of the Telegram server.
  """
  def get_status(pid) do
    GenServer.call(pid, :get_status)
  end

  @doc """
  Manually triggers a poll for new messages.
  """
  def poll_messages(pid) do
    GenServer.call(pid, :poll_messages)
  end

  @doc """
  Updates the bot token.
  """
  def update_token(pid, token) do
    GenServer.call(pid, {:update_token, token})
  end

  @doc """
  Enables webhook mode with the given URL and secret.
  """
  def enable_webhook(pid, url, secret \\ nil) do
    GenServer.call(pid, {:enable_webhook, url, secret})
  end

  @doc """
  Disables webhook mode and switches back to polling.
  """
  def disable_webhook(pid) do
    GenServer.call(pid, :disable_webhook)
  end

  @doc """
  Processes a webhook update from Telegram.
  """
  def process_webhook_update(pid, update) do
    GenServer.cast(pid, {:webhook_update, update})
  end

  # Server Callbacks

  # Helper function to send bridge status notifications
  defp send_bridge_status_notification(state, new_status, error_message \\ nil) do
    if state.status != new_status do
      Logger.info(
        "Bridge #{state.bridge.id} status changed from #{state.status} to #{new_status}"
      )

      # Send push notification asynchronously
      Task.start(fn ->
        Notifications.send_bridge_notification(%{
          user_id: state.bridge.user_id,
          bridge_id: state.bridge.id,
          bridge_type: "telegram",
          status: Atom.to_string(new_status),
          phone_number: state.bridge.phone_number,
          error_message: error_message
        })
      end)

      # Broadcast status change to user's Phoenix channel
      bridge_status_payload = %{
        bridge_id: state.bridge.id,
        bridge_type: "telegram",
        status: Atom.to_string(new_status),
        phone_number: state.bridge.phone_number,
        error_message: error_message,
        timestamp: DateTime.utc_now()
      }

      Endpoint.broadcast(
        "user:#{state.bridge.user_id}",
        "bridge_status_changed",
        bridge_status_payload
      )
    end
  end

  @impl true
  def init(bridge) do
    Logger.info("Initializing Telegram server for bridge #{bridge.id}")

    # Extract bot token from session data
    bot_token = get_bot_token(bridge)

    # Load saved offset from database
    last_update_id = get_saved_offset(bridge)

    state = %{
      bridge: bridge,
      bot_token: bot_token,
      last_update_id: last_update_id,
      polling_timer: nil,
      webhook_url: nil,
      webhook_secret: nil,
      use_webhook: false,
      status: :disconnected,
      error_count: 0,
      consecutive_errors: 0,
      circuit_breaker: :closed,
      last_error_time: nil,
      backoff_until: nil,
      last_poll: nil,
      health_check_timer: nil
    }

    # Start health check timer
    health_timer = Process.send_after(self(), :health_check, @health_check_interval)

    # If we have a bot token, start polling
    if bot_token do
      Process.send_after(self(), :start_polling, 1000)
    end

    {:ok, %{state | health_check_timer: health_timer}}
  end

  @impl true
  def handle_call({:send_message, chat_id, text, opts}, _from, state) do
    case API.send_message(state.bot_token, chat_id, text, opts) do
      {:ok, telegram_message} ->
        Logger.debug("Sent message to Telegram chat #{chat_id}")
        {:reply, {:ok, telegram_message}, state}

      {:error, reason} ->
        Logger.error("Failed to send message to Telegram chat #{chat_id}: #{inspect(reason)}")
        {:reply, {:error, reason}, %{state | error_count: state.error_count + 1}}
    end
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      bridge_id: state.bridge.id,
      status: state.status,
      bot_token_set: not is_nil(state.bot_token),
      last_update_id: state.last_update_id,
      last_poll: state.last_poll,
      error_count: state.error_count,
      consecutive_errors: state.consecutive_errors,
      circuit_breaker: state.circuit_breaker,
      polling_active: not is_nil(state.polling_timer),
      webhook_enabled: state.use_webhook,
      webhook_url: state.webhook_url
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call(:poll_messages, _from, state) do
    {result, new_state} = do_poll_messages(state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:update_token, token}, _from, state) do
    Logger.info("Updated bot token for bridge #{state.bridge.id}")

    new_state = %{state | bot_token: token}

    # If we now have a token and weren't polling/webhook, start appropriate mode
    if token && is_nil(state.polling_timer) && !state.use_webhook do
      Process.send_after(self(), :start_polling, 1000)
      {:reply, :ok, new_state}
    else
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:enable_webhook, url, secret}, _from, state) do
    Logger.info("Enabling webhook mode for bridge #{state.bridge.id} with URL: #{url}")

    case API.set_webhook(state.bot_token, url, %{secret_token: secret}) do
      {:ok, result} ->
        Logger.info("Webhook set successfully for bridge #{state.bridge.id}")

        # Stop polling if active
        if state.polling_timer do
          Process.cancel_timer(state.polling_timer)
        end

        new_state = %{
          state
          | webhook_url: url,
            webhook_secret: secret,
            use_webhook: true,
            polling_timer: nil,
            status: :connected
        }

        # Send connection notification
        send_bridge_status_notification(new_state, :connected)

        {:reply, {:ok, result}, new_state}

      {:error, reason} ->
        Logger.error("Failed to set webhook for bridge #{state.bridge.id}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disable_webhook, _from, state) do
    Logger.info("Disabling webhook mode for bridge #{state.bridge.id}")

    case API.delete_webhook(state.bot_token) do
      {:ok, _result} ->
        Logger.info("Webhook deleted successfully for bridge #{state.bridge.id}")

        new_state = %{
          state
          | webhook_url: nil,
            webhook_secret: nil,
            use_webhook: false
        }

        # Start polling as fallback
        Process.send_after(self(), :start_polling, 1000)

        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to delete webhook for bridge #{state.bridge.id}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:start_polling, state) do
    Logger.info("Starting Telegram polling for bridge #{state.bridge.id}")

    # Cancel any existing timer
    if state.polling_timer do
      Process.cancel_timer(state.polling_timer)
    end

    # Start polling immediately
    Process.send(self(), :poll)

    # Set up recurring poll timer (every 2 seconds)
    timer = Process.send_after(self(), :poll, @poll_interval)

    new_state = %{state | status: :connected, polling_timer: timer}

    # Send connection notification
    send_bridge_status_notification(new_state, :connected)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:poll, state) do
    # Check circuit breaker
    case check_circuit_breaker(state) do
      :open ->
        # Circuit breaker is open, skip polling
        timer = Process.send_after(self(), :poll, @poll_interval)
        {:noreply, %{state | polling_timer: timer}}

      :half_open ->
        # Try polling again
        {result, new_state} = do_poll_messages(state)

        case result do
          {:ok, _} ->
            # Success - close circuit breaker
            timer = Process.send_after(self(), :poll, @poll_interval)

            {:noreply,
             %{new_state | polling_timer: timer, circuit_breaker: :closed, consecutive_errors: 0}}

          {:error, _reason} ->
            # Still failing - keep circuit breaker open
            backoff_time = calculate_backoff_time(new_state.consecutive_errors + 1)
            timer = Process.send_after(self(), :poll, backoff_time)

            {:noreply,
             %{
               new_state
               | polling_timer: timer,
                 circuit_breaker: :open,
                 consecutive_errors: new_state.consecutive_errors + 1
             }}
        end

      :closed ->
        {result, new_state} = do_poll_messages(state)

        case result do
          {:ok, _} ->
            # Success
            timer = Process.send_after(self(), :poll, @poll_interval)
            {:noreply, %{new_state | polling_timer: timer, consecutive_errors: 0}}

          {:error, _reason} ->
            # Error - check if we should open circuit breaker
            consecutive_errors = new_state.consecutive_errors + 1

            if consecutive_errors >= @max_failures do
              # Open circuit breaker
              backoff_time = calculate_backoff_time(consecutive_errors)
              timer = Process.send_after(self(), :poll, backoff_time)

              {:noreply,
               %{
                 new_state
                 | polling_timer: timer,
                   circuit_breaker: :open,
                   consecutive_errors: consecutive_errors
               }}
            else
              # Continue polling
              timer = Process.send_after(self(), :poll, @poll_interval)

              {:noreply,
               %{new_state | polling_timer: timer, consecutive_errors: consecutive_errors}}
            end
        end
    end
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform comprehensive health check
    health_status = perform_comprehensive_health_check(state)

    # Update status based on health check
    new_status =
      case health_status do
        :healthy ->
          if state.status == :error, do: :connected, else: state.status

        :degraded ->
          :degraded

        :unhealthy ->
          :error
      end

    # Log health status
    case health_status do
      :healthy ->
        Logger.debug("Telegram bridge #{state.bridge.id} health check: healthy")

      :degraded ->
        Logger.warning("Telegram bridge #{state.bridge.id} health check: degraded")

      :unhealthy ->
        Logger.error("Telegram bridge #{state.bridge.id} health check: unhealthy")
    end

    # Persist offset to database periodically
    if health_status == :healthy do
      persist_offset_to_database(state)
    end

    # Schedule next health check
    timer = Process.send_after(self(), :health_check, @health_check_interval)

    {:noreply, %{state | health_check_timer: timer, status: new_status}}
  end

  @impl true
  def handle_cast({:webhook_update, update}, state) do
    Logger.debug("Processing webhook update for bridge #{state.bridge.id}: #{inspect(update)}")

    # Process the update similar to polling
    {processed_count, new_state} = process_updates([update], state)

    if processed_count > 0 do
      Logger.debug("Processed #{processed_count} webhook update(s) for bridge #{state.bridge.id}")
    end

    {:noreply, update_last_update_id(new_state, update)}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Terminating Telegram server for bridge #{state.bridge.id}: #{inspect(reason)}")

    # Send disconnection notification if we were connected
    if state.status == :connected do
      send_bridge_status_notification(
        state,
        :disconnected,
        "Bridge server terminated: #{inspect(reason)}"
      )
    end

    # Cancel timers
    if state.polling_timer do
      Process.cancel_timer(state.polling_timer)
    end

    if state.health_check_timer do
      Process.cancel_timer(state.health_check_timer)
    end

    :ok
  end

  # Private functions

  defp do_poll_messages(state) do
    case API.get_updates(state.bot_token, state.last_update_id) do
      {:ok, updates} ->
        new_state = %{state | last_poll: DateTime.utc_now(), error_count: 0}

        # Process updates
        {processed_count, final_state} = process_updates(updates, new_state)

        if processed_count > 0 do
          Logger.debug(
            "Processed #{processed_count} Telegram updates for bridge #{state.bridge.id}"
          )
        end

        {{:ok, processed_count}, final_state}

      {:error, reason} ->
        Logger.error(
          "Failed to poll Telegram API for bridge #{state.bridge.id}: #{inspect(reason)}"
        )

        new_status = if(state.error_count >= 5, do: :error, else: state.status)

        new_state = %{
          state
          | last_poll: DateTime.utc_now(),
            error_count: state.error_count + 1,
            status: new_status
        }

        # Send error notification if status changed to error
        if new_status == :error do
          send_bridge_status_notification(
            new_state,
            :error,
            "Too many consecutive errors (#{new_state.error_count})"
          )
        end

        {{:error, reason}, new_state}
    end
  end

  defp process_updates(updates, state) do
    Enum.reduce(updates, {0, state}, fn update, {count, current_state} ->
      case process_update(update, current_state) do
        {:ok, new_state} ->
          {count + 1, update_last_update_id(new_state, update)}

        {:error, reason} ->
          Logger.error(
            "Failed to process Telegram update #{update["update_id"]}: #{inspect(reason)}"
          )

          {count, current_state}
      end
    end)
  end

  defp process_update(%{"message" => message}, state) do
    # Process incoming message
    case API.parse_message(message) do
      {:ok, parsed_message} ->
        # Forward to GlobalBridge messaging system
        forward_message_to_globalbridge(parsed_message, state)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp process_update(update, state) do
    # Handle other update types (callback queries, etc.)
    Logger.debug("Received unhandled Telegram update type: #{inspect(update)}")
    {:ok, state}
  end

  defp forward_message_to_globalbridge(parsed_message, state) do
    # Use the MessageRouter to forward the message
    case GlobalbridgeBackend.Bridges.MessageRouter.route_incoming_message(
           state.bridge.id,
           parsed_message
         ) do
      {:ok, gb_message} ->
        Logger.info(
          "Successfully forwarded Telegram message to GlobalBridge message #{gb_message.id}"
        )

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to forward Telegram message to GlobalBridge: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp update_last_update_id(state, update) do
    update_id = update["update_id"]
    %{state | last_update_id: update_id + 1}
  end

  defp perform_health_check(state) do
    # Simple health check - try to get bot info
    case API.get_me(state.bot_token) do
      {:ok, _bot_info} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_bot_token(bridge) do
    # Extract bot token from bridge session data
    case bridge.session_data do
      %{"bot_token" => token} when is_binary(token) and token != "" ->
        token

      _ ->
        nil
    end
  end

  defp get_saved_offset(bridge) do
    # Extract saved offset from bridge session data
    case bridge.session_data do
      %{"last_update_id" => offset} when is_integer(offset) and offset >= 0 ->
        offset

      _ ->
        nil
    end
  end

  defp check_circuit_breaker(state) do
    case state.circuit_breaker do
      :closed ->
        :closed

      :open ->
        # Check if we should try half-open
        if state.consecutive_errors >= @max_failures * 2 do
          # Too many errors, stay open
          :open
        else
          # Try half-open after backoff period
          now = DateTime.utc_now()

          if state.backoff_until && DateTime.compare(now, state.backoff_until) == :lt do
            :open
          else
            :half_open
          end
        end

      :half_open ->
        :half_open
    end
  end

  defp calculate_backoff_time(consecutive_errors) do
    # Exponential backoff: 2^errors seconds, max 300 seconds (5 minutes)
    base_time = :math.pow(2, min(consecutive_errors, 8)) * 1000
    min(@max_backoff_time, trunc(base_time))
  end

  defp perform_comprehensive_health_check(state) do
    checks = [
      {:bot_token, fn -> check_bot_token_validity(state) end},
      {:api_connectivity, fn -> check_api_connectivity(state) end},
      {:polling_status, fn -> check_polling_status(state) end},
      {:webhook_status, fn -> check_webhook_status(state) end},
      {:offset_tracking, fn -> check_offset_tracking(state) end}
    ]

    results =
      Enum.map(checks, fn {name, check_fn} ->
        try do
          case check_fn.() do
            :ok -> {:ok, name}
            {:error, reason} -> {:error, name, reason}
          end
        rescue
          error -> {:error, name, error}
        end
      end)

    # Determine overall health
    error_count =
      Enum.count(results, fn
        {:error, _, _} -> true
        _ -> false
      end)

    cond do
      error_count == 0 -> :healthy
      error_count <= 2 -> :degraded
      true -> :unhealthy
    end
  end

  defp check_bot_token_validity(state) do
    if is_nil(state.bot_token) do
      {:error, :no_bot_token}
    else
      :ok
    end
  end

  defp check_api_connectivity(state) do
    case API.get_me(state.bot_token) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  end

  defp check_polling_status(state) do
    if state.use_webhook do
      # Webhook mode - polling should be disabled
      if is_nil(state.polling_timer) do
        :ok
      else
        {:error, :polling_active_in_webhook_mode}
      end
    else
      # Polling mode - should be active
      if state.circuit_breaker == :open do
        {:error, :circuit_breaker_open}
      else
        :ok
      end
    end
  end

  defp check_webhook_status(state) do
    if state.use_webhook do
      case API.get_webhook_info(state.bot_token) do
        {:ok, info} ->
          configured_url = info["url"]

          if configured_url == state.webhook_url do
            :ok
          else
            {:error, {:webhook_url_mismatch, configured_url, state.webhook_url}}
          end

        {:error, _} = error ->
          error
      end
    else
      :ok
    end
  end

  defp check_offset_tracking(state) do
    # Check if offset is reasonable (not too old, not negative)
    if is_nil(state.last_update_id) or state.last_update_id >= 0 do
      :ok
    else
      {:error, :invalid_offset}
    end
  end

  defp persist_offset_to_database(state) do
    # Periodically save the last_update_id to bridge session data
    # This helps recover from crashes
    if state.last_update_id do
      session_data =
        Map.put(state.bridge.session_data || %{}, "last_update_id", state.last_update_id)

      case Bridges.update_bridge_session(state.bridge, %{session_data: session_data}) do
        {:ok, _} ->
          Logger.debug("Persisted offset #{state.last_update_id} for bridge #{state.bridge.id}")

        {:error, reason} ->
          Logger.warning(
            "Failed to persist offset for bridge #{state.bridge.id}: #{inspect(reason)}"
          )
      end
    end
  end
end
