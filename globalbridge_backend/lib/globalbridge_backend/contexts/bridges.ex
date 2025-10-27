defmodule GlobalbridgeBackend.Contexts.Bridges do
  @moduledoc """
  Context for managing bridge configurations (WhatsApp, Telegram, etc.).
  Bridge configurations are stored in the shared bridges.db database.
  """

  import Ecto.Query, warn: false

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.Bridge

  @doc """
  Lists all bridges with optional filtering.

  ## Filters
  - `:user_id` - Filter by user ID
  - `:bridge_type` - Filter by bridge type ("whatsapp", "telegram")
  - `:status` - Filter by status ("connected", "disconnected", "error", "connecting")
  - `:is_active` - Filter by active status (boolean)
  - `:limit` - Limit number of results (default: 50)
  - `:offset` - Offset for pagination (default: 0)

  ## Examples

      iex> list_bridges()
      [%Bridge{}, ...]

      iex> list_bridges(user_id: "user-id", bridge_type: "telegram")
      [%Bridge{}, ...]
  """
  def list_bridges(filters \\ []) do
    Bridge
    |> apply_bridge_filters(filters)
    |> apply_pagination(filters)
    |> Repo.all()
  end

  @doc """
  Gets a single bridge by ID, raising if not found.

  ## Examples

      iex> get_bridge!("bridge-id")
      %Bridge{}

      iex> get_bridge!("non-existent")
      ** (Ecto.NoResultsError)
  """
  def get_bridge!(id) do
    Repo.get!(Bridge, id)
  end

  @doc """
  Gets a single bridge by ID, returning nil if not found.

  ## Examples

      iex> get_bridge("bridge-id")
      %Bridge{}

      iex> get_bridge("non-existent")
      nil
  """
  def get_bridge(id) do
    Repo.get(Bridge, id)
  end

  @doc """
  Gets a bridge by user ID and bridge type.

  ## Examples

      iex> get_bridge_by_user_and_type("user-id", "telegram")
      %Bridge{}

      iex> get_bridge_by_user_and_type("user-id", "non-existent")
      nil
  """
  def get_bridge_by_user_and_type(user_id, bridge_type) do
    query =
      from(b in Bridge,
        where: b.user_id == ^user_id and b.bridge_type == ^bridge_type
      )

    Repo.one(query)
  end

  @doc """
  Creates a new bridge configuration.

  ## Examples

      iex> create_bridge(%{
      ...>   user_id: "user-id",
      ...>   bridge_type: "telegram",
      ...>   phone_number: "+1234567890"
      ...> })
      {:ok, %Bridge{}}

      iex> create_bridge(%{bridge_type: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def create_bridge(attrs) do
    %Bridge{}
    |> Bridge.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a bridge's session data and status.

  ## Examples

      iex> update_bridge_session(bridge, %{
      ...>   status: "connected",
      ...>   session_data: %{token: "abc123"}
      ...> })
      {:ok, %Bridge{}}

      iex> update_bridge_session(bridge, %{status: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def update_bridge_session(%Bridge{} = bridge, attrs) do
    bridge
    |> Bridge.session_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a bridge's active status.

  ## Examples

      iex> toggle_bridge_active(bridge, %{is_active: false})
      {:ok, %Bridge{}}

      iex> toggle_bridge_active(bridge, %{is_active: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def toggle_bridge_active(%Bridge{} = bridge, attrs) do
    bridge
    |> Bridge.toggle_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Updates a bridge.

  ## Examples

      iex> update_bridge(bridge, %{phone_number: "+1987654321"})
      {:ok, %Bridge{}}

      iex> update_bridge(bridge, %{bridge_type: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def update_bridge(%Bridge{} = bridge, attrs) do
    bridge
    |> Bridge.create_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a bridge.

  ## Examples

      iex> delete_bridge(bridge)
      {:ok, %Bridge{}}

      iex> delete_bridge(bridge)
      {:error, %Ecto.Changeset{}}
  """
  def delete_bridge(%Bridge{} = bridge) do
    Repo.delete(bridge)
  end

  @doc """
  Lists all bridges for a specific user.

  ## Examples

      iex> list_user_bridges("user-id")
      [%Bridge{}, ...]

      iex> list_user_bridges("user-id", bridge_type: "telegram")
      [%Bridge{}, ...]
  """
  def list_user_bridges(user_id, filters \\ []) do
    filters = Keyword.put(filters, :user_id, user_id)
    list_bridges(filters)
  end

  @doc """
  Lists active bridges for a specific user.

  ## Examples

      iex> list_active_user_bridges("user-id")
      [%Bridge{}, ...]
  """
  def list_active_user_bridges(user_id) do
    list_user_bridges(user_id, is_active: true)
  end

  @doc """
  Counts bridges by status for a user.

  ## Examples

      iex> count_bridges_by_status("user-id")
      %{"connected" => 1, "disconnected" => 2, "error" => 0}
  """
  def count_bridges_by_status(user_id) do
    query =
      from(b in Bridge,
        where: b.user_id == ^user_id,
        group_by: b.status,
        select: {b.status, count(b.id)}
      )

    Repo.all(query)
    |> Enum.into(%{})
  end

  # Private helper functions

  defp apply_bridge_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:user_id, user_id}, q ->
        where(q, [b], b.user_id == ^user_id)

      {:bridge_type, type}, q when type in ["whatsapp", "telegram"] ->
        where(q, [b], b.bridge_type == ^type)

      {:status, status}, q when status in ["connected", "disconnected", "error", "connecting"] ->
        where(q, [b], b.status == ^status)

      {:is_active, active}, q when is_boolean(active) ->
        where(q, [b], b.is_active == ^active)

      _other, q ->
        q
    end)
  end

  defp apply_pagination(query, filters) do
    limit = Keyword.get(filters, :limit, 50)
    offset = Keyword.get(filters, :offset, 0)

    query
    |> limit(^limit)
    |> offset(^offset)
  end
end
