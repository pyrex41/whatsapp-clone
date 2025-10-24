defmodule GlobalbridgeBackendWeb.BridgeController do
  use GlobalbridgeBackendWeb, :controller

  alias GlobalbridgeBackend.Auth.Guardian
  alias GlobalbridgeBackend.Contexts.Bridges

  action_fallback(GlobalbridgeBackendWeb.FallbackController)

  @doc """
  Lists bridges for the authenticated user.
  """
  def index(conn, _params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    bridges = Bridges.list_user_bridges(user.id)

    render(conn, :index, bridges: bridges)
  end

  @doc """
  Shows a specific bridge for the authenticated user.
  """
  def show(conn, %{"id" => id}) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    case Bridges.get_bridge(id) do
      nil ->
        {:error, :not_found}

      bridge ->
        # Ensure user owns this bridge
        if bridge.user_id == user.id do
          render(conn, :show, bridge: bridge)
        else
          {:error, :forbidden}
        end
    end
  end

  @doc """
  Creates a new bridge for the authenticated user.
  """
  def create(conn, %{"bridge" => bridge_params}) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    # Add user_id to params
    bridge_params = Map.put(bridge_params, "user_id", user.id)

    case Bridges.create_bridge(bridge_params) do
      {:ok, bridge} ->
        conn
        |> put_status(:created)
        |> render(:show, bridge: bridge)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Updates a bridge for the authenticated user.
  """
  def update(conn, %{"id" => id, "bridge" => bridge_params}) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with bridge when not is_nil(bridge) <- Bridges.get_bridge(id),
         true <- bridge.user_id == user.id,
         {:ok, updated_bridge} <- Bridges.update_bridge(bridge, bridge_params) do
      render(conn, :show, bridge: updated_bridge)
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Updates bridge session data (status, session_data, etc.).
  """
  def update_session(conn, %{"id" => id, "bridge" => session_params}) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with bridge when not is_nil(bridge) <- Bridges.get_bridge(id),
         true <- bridge.user_id == user.id,
         {:ok, updated_bridge} <- Bridges.update_bridge_session(bridge, session_params) do
      render(conn, :show, bridge: updated_bridge)
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Toggles bridge active status.
  """
  def toggle_active(conn, %{"id" => id, "bridge" => %{"is_active" => is_active}}) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with bridge when not is_nil(bridge) <- Bridges.get_bridge(id),
         true <- bridge.user_id == user.id,
         {:ok, updated_bridge} <- Bridges.toggle_bridge_active(bridge, %{is_active: is_active}) do
      render(conn, :show, bridge: updated_bridge)
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Deletes a bridge for the authenticated user.
  """
  def delete(conn, %{"id" => id}) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with bridge when not is_nil(bridge) <- Bridges.get_bridge(id),
         true <- bridge.user_id == user.id,
         {:ok, _deleted_bridge} <- Bridges.delete_bridge(bridge) do
      send_resp(conn, :no_content, "")
    else
      nil -> {:error, :not_found}
      false -> {:error, :forbidden}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Gets bridge statistics for the authenticated user.
  """
  def stats(conn, _params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    stats = %{
      bridges_by_status: Bridges.count_bridges_by_status(user.id),
      active_bridges: length(Bridges.list_active_user_bridges(user.id))
    }

    json(conn, stats)
  end

  @doc """
  Creates a new Telegram bridge for the authenticated user.
  """
  def create_telegram_bridge(conn, %{"bridge" => bridge_params}) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    # Add user_id and bridge_type
    bridge_params =
      bridge_params
      |> Map.put("user_id", user.id)
      |> Map.put("bridge_type", "telegram")

    case Bridges.create_bridge(bridge_params) do
      {:ok, bridge} ->
        conn
        |> put_status(:created)
        |> render(:show, bridge: bridge)

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Gets the Telegram bridge for a specific thread.
  """
  def get_telegram_bridge_for_thread(conn, %{"thread_id" => thread_id}) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    # Find the Telegram bridge for this user
    case Bridges.get_bridge_by_user_and_type(user.id, "telegram") do
      nil ->
        conn
        |> put_status(404)
        |> json(%{error: "No Telegram bridge found for user"})

      bridge ->
        render(conn, :show, bridge: bridge)
    end
  end
end
