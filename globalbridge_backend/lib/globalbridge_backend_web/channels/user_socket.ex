defmodule GlobalbridgeBackendWeb.UserSocket do
  @moduledoc """
  WebSocket connection handler for authenticated users.
  Provides real-time communication for messaging threads.
  """
  use Phoenix.Socket
  require Logger

  alias GlobalbridgeBackend.Auth.Guardian
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

    # Try JWT token first, then fallback to simple format for backward compatibility
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
          "📊 [AUTH] Socket assigned: user_id=#{user.id}, connected_at=#{socket.assigns.connected_at}"
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
      user =
        case Repo.get(User, user_id) do
          nil ->
            # Create a mock user for development
            %User{
              id: user_id,
              username: "dev_user_#{String.slice(user_id, 0, 8)}",
              phone_number: "+15551234567",
              inserted_at: DateTime.utc_now(),
              updated_at: DateTime.utc_now()
            }

          existing_user ->
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
    # Try Auth0 JWT first, then Guardian, then fallback to simple format
    case verify_auth0_token(token) do
      {:ok, user} ->
        {:ok, user}

      {:error, :not_auth0} ->
        # Try Guardian JWT
        case Guardian.decode_and_verify(token) do
          {:ok, claims} ->
            Guardian.resource_from_claims(claims)

          {:error, _jwt_error} ->
            # Fallback to simple token format for backward compatibility
            verify_simple_token(token)
        end

      error ->
        error
    end
  end

  defp verify_auth0_token(token) do
    # For now, if token contains '@' it's likely an Auth0 token
    # A proper implementation would verify the JWT signature against Auth0's public keys
    # For development, we'll accept the token and extract claims

    case decode_jwt(token) do
      {:ok, claims} when is_map(claims) ->
        # Check if this looks like an Auth0 token
        if Map.has_key?(claims, "sub") and
             (Map.has_key?(claims, "iss") or Map.has_key?(claims, "aud")) do
          auth0_user_id = claims["sub"]
          email = claims["email"]
          name = claims["name"] || claims["nickname"] || claims["preferred_username"]

          Logger.info("🔐 [AUTH0] Token claims: sub=#{auth0_user_id}, email=#{email}")

          # Find or create user
          ensure_user_exists(auth0_user_id, email, name)
        else
          {:error, :not_auth0}
        end

      _ ->
        {:error, :not_auth0}
    end
  rescue
    _ -> {:error, :not_auth0}
  end

  defp decode_jwt(token) do
    # Simple JWT decoding without verification (for development)
    # In production, use proper JWT library with signature verification
    case String.split(token, ".") do
      [_header, payload, _signature] ->
        with {:ok, decoded} <- Base.url_decode64(payload, padding: false),
             {:ok, json} <- Jason.decode(decoded) do
          {:ok, json}
        else
          _ -> {:error, :invalid_jwt}
        end

      _ ->
        {:error, :invalid_jwt}
    end
  end

  defp ensure_user_exists(auth0_id, email, name) do
    # Try to find user by auth0_id
    case Repo.get_by(User, auth0_id: auth0_id) do
      nil ->
        # User doesn't exist, create them
        Logger.info("👤 [AUTH0] Creating new user: auth0_id=#{auth0_id}, email=#{email}")

        username = generate_username(email, name)

        attrs = %{
          auth0_id: auth0_id,
          email: email,
          username: username,
          display_name: name,
          # Placeholder
          phone_number: "+10000000000",
          # Auth0 manages password
          password_hash: "auth0_managed"
        }

        case User.create_changeset(%User{}, attrs) |> Repo.insert() do
          {:ok, user} ->
            Logger.info("✅ [AUTH0] User created: id=#{user.id}, username=#{user.username}")
            {:ok, user}

          {:error, changeset} ->
            Logger.error("❌ [AUTH0] User creation failed: #{inspect(changeset.errors)}")
            {:error, :user_creation_failed}
        end

      user ->
        Logger.info("✅ [AUTH0] Existing user found: id=#{user.id}, username=#{user.username}")
        {:ok, user}
    end
  end

  defp generate_username(email, name) do
    # Generate username from email or name
    base =
      cond do
        email && String.contains?(email, "@") ->
          email |> String.split("@") |> List.first()

        name ->
          name |> String.downcase() |> String.replace(~r/\s+/, "_")

        true ->
          "user"
      end

    # Add timestamp to ensure uniqueness
    "#{base}_#{:os.system_time(:millisecond)}"
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
end
