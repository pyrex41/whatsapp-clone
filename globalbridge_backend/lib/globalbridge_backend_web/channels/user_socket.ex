defmodule GlobalbridgeBackendWeb.UserSocket do
  @moduledoc """
  WebSocket connection handler for authenticated users.
  Provides real-time communication for messaging threads.
  """
  use Phoenix.Socket
  require Logger

  alias GlobalbridgeBackend.Auth.Guardian
  alias GlobalbridgeBackend.Auth.Auth0Verifier
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.User

  # A Socket handler
  #
  # It's possible to control the websocket connection and
  # assign values that can be accessed by your channel topics.

  ## Channels
  channel("thread:*", GlobalbridgeBackendWeb.ThreadChannel)
  channel("user:*", GlobalbridgeBackendWeb.UserChannel)

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  # To deny connection, return `:error` or `{:error, term}`. To control the
  # response the client receives in that case, return a 2-tuple:
  #
  #     {:error, :unauthorized}
  #
  @impl true
  def connect(%{"token" => token}, socket, _connect_info) do
    Logger.info("🔐 [AUTH] Token-based connection attempt")

    # Try Auth0 token first, then Guardian, then fallback to simple format
    case verify_token(token) do
      {:ok, user} ->
        Logger.info(
          "✅ [AUTH] Token verified successfully, user_id: #{user.id}, username: #{user.username}"
        )

        socket =
          socket
          |> assign(:user_id, user.id)
          |> assign(:user, user)
          |> assign(:connected_at, System.system_time(:millisecond))

        Logger.debug(
          "📊 [AUTH] Socket assigned: user_id=#{user.id}, auth0_id=#{inspect(user.auth0_id)}, username=#{user.username}, connected_at=#{socket.assigns.connected_at}"
        )

        {:ok, socket}

      {:error, reason} ->
        Logger.warning("❌ [AUTH] JWT token verification failed: #{inspect(reason)}")
        :error
    end
  end

  # Development: Allow connections with user_id parameter
  # Production: This should return :error
  def connect(params, socket, _connect_info) do
    dev_mode = Application.get_env(:globalbridge_backend, :dev_mode, false)

    if dev_mode do
      Logger.info("🔓 [AUTH] Dev mode connection attempt")

      # In dev mode, allow connection with user_id parameter or create temp user
      user_id = params["user_id"] || Ecto.UUID.generate()

      # Try to find existing user, or create a mock user struct
      # Note: We need to fetch the full user record to get auth0_id for channel authorization
      user =
        case Repo.get(User, user_id) do
          nil ->
            # Create a mock user for development
            %User{
              id: user_id,
              username: "dev_user_#{String.slice(user_id, 0, 8)}",
              phone_number: "+15551234567",
              auth0_id: nil,
              inserted_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now()
            }

          existing_user ->
            # User is already fetched with all fields including auth0_id
            existing_user
        end

      Logger.info("✅ [AUTH] Dev mode connection accepted, user_id: #{user_id} (DEV MODE)")

      socket =
        socket
        |> assign(:user_id, user_id)
        |> assign(:user, user)
        |> assign(:connected_at, System.system_time(:millisecond))
        |> assign(:dev_mode, true)

      Logger.debug(
        "📊 [AUTH] Socket assigned (dev): user_id=#{user_id}, connected_at=#{socket.assigns.connected_at}, dev_mode=true"
      )

      {:ok, socket}
    else
      Logger.warning("❌ [AUTH] Connection rejected: dev_mode disabled, no token provided")
      :error
    end
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "user_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     Elixir.GlobalbridgeBackendWeb.Endpoint.broadcast("user_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.user_id}"

  # Private helper functions

  defp verify_token(token) do
    # Detect token type from JWT header to optimize verification
    case detect_token_type(token) do
      :auth0 ->
        # Try Auth0 JWT first
        case Auth0Verifier.verify_and_get_user(token) do
          {:ok, user} ->
            {:ok, user}

          {:error, :token_expired} ->
            Logger.warning("⏰ [AUTH] Auth0 token has expired")
            {:error, :token_expired}

          {:error, reason} ->
            Logger.debug("ℹ️ [AUTH] Auth0 verification failed: #{inspect(reason)}")
            {:error, reason}
        end

      :guardian ->
        # Try Guardian JWT
        case Guardian.decode_and_verify(token) do
          {:ok, claims} ->
            Guardian.resource_from_claims(claims)

          {:error, reason} ->
            Logger.debug("ℹ️ [AUTH] Guardian verification failed: #{inspect(reason)}")
            {:error, reason}
        end

      :simple ->
        # Fallback to simple token format
        verify_simple_token(token)

      :unknown ->
        # Try all methods in sequence as fallback
        case Auth0Verifier.verify_and_get_user(token) do
          {:ok, user} ->
            {:ok, user}

          _ ->
            case Guardian.decode_and_verify(token) do
              {:ok, claims} -> Guardian.resource_from_claims(claims)
              _ -> verify_simple_token(token)
            end
        end
    end
  end

  defp verify_simple_token(token) do
    # Simple token format: "user:{user_id}"
    case String.split(token, ":") do
      ["user", user_id] when byte_size(user_id) == 36 ->
        case Repo.get(User, user_id) do
          nil -> {:error, :user_not_found}
          user -> {:ok, user}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  defp detect_token_type(token) do
    # Try to decode JWT header to detect token type
    case String.split(token, ".") do
      [header_b64, _payload, _signature] ->
        try do
          header_json = Base.url_decode64!(header_b64, padding: false)
          header = Jason.decode!(header_json)

          case header do
            %{"alg" => "RS256", "typ" => "JWT", "kid" => _kid} ->
              # Looks like Auth0 token (RS256 with kid)
              :auth0

            %{"alg" => "HS256", "typ" => "JWT"} ->
              # Looks like Guardian token (HS256)
              :guardian

            _ ->
              :unknown
          end
        rescue
          _ -> :unknown
        end

      ["user", _user_id] ->
        # Simple token format
        :simple

      _ ->
        :unknown
    end
  end
end
