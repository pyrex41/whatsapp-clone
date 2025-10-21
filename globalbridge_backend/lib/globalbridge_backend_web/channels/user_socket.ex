defmodule GlobalbridgeBackendWeb.UserSocket do
  @moduledoc """
  WebSocket connection handler for authenticated users.
  Provides real-time communication for messaging threads.
  """
  use Phoenix.Socket

  # A Socket handler
  #
  # It's possible to control the websocket connection and
  # assign values that can be accessed by your channel topics.

  ## Channels
  channel "thread:*", GlobalbridgeBackendWeb.ThreadChannel

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
    # Verify token and authenticate user
    case verify_user_token(token) do
      {:ok, user_id} ->
        socket =
          socket
          |> assign(:user_id, user_id)
          |> assign(:connected_at, System.system_time(:millisecond))

        {:ok, socket}

      {:error, _reason} ->
        :error
    end
  end

  def connect(_params, _socket, _connect_info) do
    :error
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

  defp verify_user_token(token) do
    # TODO: Implement proper JWT verification
    # For now, decode a simple token format: "user:{user_id}"
    case String.split(token, ":") do
      ["user", user_id] when byte_size(user_id) == 36 ->
        {:ok, user_id}

      _ ->
        {:error, :invalid_token}
    end
  end
end
