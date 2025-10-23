defmodule GlobalbridgeBackend.Auth.JWKSCache do
  @moduledoc """
  JWKS (JSON Web Key Set) cache for Auth0 JWT verification.

  Fetches and caches JWKS from Auth0's /.well-known/jwks.json endpoint
  with TTL-based expiration and automatic refresh.
  """

  use GenServer
  require Logger

  # Cache keys for 24 hours
  @cache_ttl :timer.hours(24)
  # Refresh 1 hour before expiration
  @refresh_interval :timer.hours(23)

  defstruct [
    :keys,
    :last_fetched,
    :auth0_domain
  ]

  # Client API

  @doc """
  Starts the JWKS cache process.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a key by kid (Key ID) from the cache.
  Returns {:ok, key} or {:error, reason}.
  """
  def get_key(kid) do
    GenServer.call(__MODULE__, {:get_key, kid})
  end

  @doc """
  Forces a refresh of the JWKS cache.
  """
  def refresh do
    GenServer.call(__MODULE__, :refresh)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    auth0_domain =
      System.get_env("AUTH0_DOMAIN") || raise "AUTH0_DOMAIN environment variable is required"

    state = %__MODULE__{
      keys: %{},
      last_fetched: nil,
      auth0_domain: auth0_domain
    }

    # Schedule periodic refresh (but don't fetch immediately)
    Process.send_after(self(), :schedule_refresh, @refresh_interval)

    {:ok, state}
  end

  @impl true
  def handle_call({:get_key, kid}, _from, state) do
    # Lazy load keys if not already fetched
    state =
      if state.last_fetched == nil do
        case fetch_jwks(state.auth0_domain) do
          {:ok, keys} ->
            %{state | keys: keys, last_fetched: DateTime.utc_now()}

          {:error, _reason} ->
            # Keep trying on next call
            state
        end
      else
        state
      end

    case Map.get(state.keys, kid) do
      nil ->
        Logger.warning("JWKS key not found for kid: #{kid}")
        {:reply, {:error, :key_not_found}, state}

      key ->
        {:reply, {:ok, key}, state}
    end
  end

  @impl true
  def handle_call(:refresh, _from, state) do
    case fetch_jwks(state.auth0_domain) do
      {:ok, keys} ->
        new_state = %{state | keys: keys, last_fetched: DateTime.utc_now()}
        Logger.info("JWKS cache refreshed successfully")
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.error("Failed to refresh JWKS cache: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_info(:schedule_refresh, state) do
    # Trigger refresh
    Process.send_after(self(), :refresh_keys, 100)

    # Schedule next refresh
    Process.send_after(self(), :schedule_refresh, @refresh_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info(:refresh_keys, state) do
    case fetch_jwks(state.auth0_domain) do
      {:ok, keys} ->
        new_state = %{state | keys: keys, last_fetched: DateTime.utc_now()}
        Logger.info("JWKS cache auto-refreshed successfully")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("Failed to auto-refresh JWKS cache: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Private Functions

  defp fetch_jwks(auth0_domain) do
    url = "https://#{auth0_domain}/.well-known/jwks.json"

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        parse_jwks_response(body)

      {:ok, %{status: status}} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_jwks_response(%{"keys" => keys}) when is_list(keys) do
    try do
      key_map =
        Map.new(keys, fn key ->
          case JOSE.JWK.from_map(key) do
            %JOSE.JWK{} = jwk ->
              {key["kid"], jwk}

            _ ->
              throw({:invalid_key, key})
          end
        end)

      {:ok, key_map}
    catch
      {:invalid_key, key} ->
        Logger.error("Invalid JWK in response: #{inspect(key)}")
        {:error, :invalid_jwk}
    end
  end

  defp parse_jwks_response(_), do: {:error, :invalid_response}
end
