defmodule GlobalbridgeBackend.Contexts.Threads do
  @moduledoc """
  Context for managing chat threads (conversations).
  Thread metadata is stored in users.db, while actual messages are stored in per-thread databases.
  """

  import Ecto.Query, warn: false

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{Thread, ThreadParticipant, User}

  @doc """
  Lists all threads with optional filtering.

  ## Filters
  - `:is_archived` - Filter by archived status (boolean)
  - `:is_muted` - Filter by muted status (boolean)
  - `:thread_type` - Filter by type ("direct" or "group")
  - `:limit` - Limit number of results (default: 50)
  - `:offset` - Offset for pagination (default: 0)
  - `:order_by` - Order by field (default: :last_message_at, :desc)

  ## Examples

      iex> list_threads()
      [%Thread{}, ...]

      iex> list_threads(is_archived: false, limit: 10)
      [%Thread{}, ...]
  """
  def list_threads(filters \\ []) do
    Thread
    |> apply_thread_filters(filters)
    |> apply_ordering(filters)
    |> apply_pagination(filters)
    |> preload(:thread_participants)
    |> Repo.all()
  end

  @doc """
  Gets a single thread by ID, raising if not found.

  ## Examples

      iex> get_thread!("thread-id")
      %Thread{}

      iex> get_thread!("non-existent")
      ** (Ecto.NoResultsError)
  """
  def get_thread!(id) do
    Thread
    |> Repo.get!(id)
    |> Repo.preload([:thread_participants, participants: :user])
  end

  @doc """
  Gets a single thread by ID, returning nil if not found.

  ## Examples

      iex> get_thread("thread-id")
      %Thread{}

      iex> get_thread("non-existent")
      nil
  """
  def get_thread(id) do
    case Repo.get(Thread, id) do
      nil -> nil
      thread -> Repo.preload(thread, [:thread_participants, participants: :user])
    end
  end

  @doc """
  Creates a new thread with participants.

  Automatically generates a database shard ID for per-thread message storage.

  ## Examples

      iex> create_thread(%{
      ...>   thread_type: "direct",
      ...>   participant_ids: ["user-1", "user-2"]
      ...> })
      {:ok, %Thread{}}

      iex> create_thread(%{thread_type: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def create_thread(attrs) do
    participant_ids = Map.get(attrs, :participant_ids, [])

    attrs =
      attrs
      |> Map.put(:database_shard_id, generate_shard_id())
      |> Map.delete(:participant_ids)

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:thread, Thread.create_changeset(%Thread{}, attrs))
    |> Ecto.Multi.run(:participants, fn _repo, %{thread: thread} ->
      add_participants(thread, participant_ids)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{thread: thread}} ->
        {:ok, get_thread!(thread.id)}

      {:error, :thread, changeset, _} ->
        {:error, changeset}

      {:error, :participants, reason, _} ->
        {:error, reason}
    end
  end

  @doc """
  Updates a thread.

  ## Examples

      iex> update_thread(thread, %{title: "New Title"})
      {:ok, %Thread{}}

      iex> update_thread(thread, %{thread_type: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def update_thread(%Thread{} = thread, attrs) do
    thread
    |> Thread.update_changeset(attrs)
    |> Repo.update()
    |> case do
      {:ok, updated_thread} -> {:ok, get_thread!(updated_thread.id)}
      error -> error
    end
  end

  @doc """
  Deletes a thread.

  Note: This only deletes the thread metadata. The per-thread database file
  should be handled separately for complete cleanup.

  ## Examples

      iex> delete_thread(thread)
      {:ok, %Thread{}}

      iex> delete_thread(thread)
      {:error, %Ecto.Changeset{}}
  """
  def delete_thread(%Thread{} = thread) do
    Repo.delete(thread)
  end

  @doc """
  Archives a thread.

  ## Examples

      iex> archive_thread(thread)
      {:ok, %Thread{}}
  """
  def archive_thread(%Thread{} = thread) do
    update_thread(thread, %{is_archived: true})
  end

  @doc """
  Unarchives a thread.

  ## Examples

      iex> unarchive_thread(thread)
      {:ok, %Thread{}}
  """
  def unarchive_thread(%Thread{} = thread) do
    update_thread(thread, %{is_archived: false})
  end

  @doc """
  Mutes a thread.

  ## Examples

      iex> mute_thread(thread)
      {:ok, %Thread{}}
  """
  def mute_thread(%Thread{} = thread) do
    update_thread(thread, %{is_muted: true})
  end

  @doc """
  Unmutes a thread.

  ## Examples

      iex> unmute_thread(thread)
      {:ok, %Thread{}}
  """
  def unmute_thread(%Thread{} = thread) do
    update_thread(thread, %{is_muted: false})
  end

  @doc """
  Adds a participant to a thread.

  ## Examples

      iex> add_participant(thread, "user-id", "admin")
      {:ok, %ThreadParticipant{}}

      iex> add_participant(thread, "user-id")
      {:ok, %ThreadParticipant{}}
  """
  def add_participant(%Thread{} = thread, user_id, role \\ "member") do
    attrs = %{
      thread_id: thread.id,
      user_id: user_id,
      role: role
    }

    %ThreadParticipant{}
    |> ThreadParticipant.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Removes a participant from a thread.

  ## Examples

      iex> remove_participant(thread, "user-id")
      {:ok, %ThreadParticipant{}}
  """
  def remove_participant(%Thread{} = thread, user_id) do
    query =
      from(tp in ThreadParticipant,
        where: tp.thread_id == ^thread.id and tp.user_id == ^user_id
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      participant -> Repo.delete(participant)
    end
  end

  @doc """
  Lists all participants in a thread.

  ## Examples

      iex> list_participants(thread)
      [%ThreadParticipant{}, ...]
  """
  def list_participants(%Thread{} = thread) do
    query =
      from(tp in ThreadParticipant,
        where: tp.thread_id == ^thread.id,
        preload: [:user],
        order_by: [asc: tp.joined_at]
      )

    Repo.all(query)
  end

  @doc """
  Finds or creates a direct message thread between two users.

  ## Examples

      iex> get_thread_for_direct_message("user-1", "user-2")
      {:ok, %Thread{}}
  """
  def get_thread_for_direct_message(user_id_1, user_id_2) do
    # Find existing direct message thread between these users
    query =
      from(t in Thread,
        join: tp1 in ThreadParticipant,
        on: tp1.thread_id == t.id,
        join: tp2 in ThreadParticipant,
        on: tp2.thread_id == t.id,
        where: t.thread_type == "direct",
        where: tp1.user_id == ^user_id_1,
        where: tp2.user_id == ^user_id_2,
        limit: 1
      )

    case Repo.one(query) do
      nil ->
        # Create new direct message thread
        create_thread(%{
          thread_type: "direct",
          participant_ids: [user_id_1, user_id_2]
        })

      thread ->
        {:ok, get_thread!(thread.id)}
    end
  end

  @doc """
  Lists all threads for a specific user.

  ## Examples

      iex> list_user_threads("user-id")
      [%Thread{}, ...]

      iex> list_user_threads("user-id", is_archived: false)
      [%Thread{}, ...]
  """
  def list_user_threads(user_id, filters \\ []) do
    query =
      from(t in Thread,
        join: tp in ThreadParticipant,
        on: tp.thread_id == t.id,
        where: tp.user_id == ^user_id
      )

    query
    |> apply_thread_filters(filters)
    |> apply_ordering(filters)
    |> apply_pagination(filters)
    |> preload(:thread_participants)
    |> Repo.all()
  end

  @doc """
  Searches threads by title.

  ## Examples

      iex> search_threads("project")
      [%Thread{}, ...]
  """
  def search_threads(query_string, filters \\ []) do
    search_pattern = "%#{query_string}%"

    query =
      from(t in Thread,
        where: ilike(t.title, ^search_pattern)
      )

    query
    |> apply_thread_filters(filters)
    |> apply_ordering(filters)
    |> apply_pagination(filters)
    |> preload(:thread_participants)
    |> Repo.all()
  end

  # Private helper functions

  defp apply_thread_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:is_archived, value}, q when is_boolean(value) ->
        where(q, [t], t.is_archived == ^value)

      {:is_muted, value}, q when is_boolean(value) ->
        where(q, [t], t.is_muted == ^value)

      {:thread_type, type}, q when type in ["direct", "group"] ->
        where(q, [t], t.thread_type == ^type)

      _other, q ->
        q
    end)
  end

  defp apply_ordering(query, filters) do
    order_by = Keyword.get(filters, :order_by, {:last_message_at, :desc})

    case order_by do
      {field, direction} when direction in [:asc, :desc] ->
        order_by(query, [t], [{^direction, field(t, ^field)}])

      field when is_atom(field) ->
        order_by(query, [t], desc: field(t, ^field))

      _ ->
        order_by(query, [t], desc: :last_message_at)
    end
  end

  defp apply_pagination(query, filters) do
    limit = Keyword.get(filters, :limit, 50)
    offset = Keyword.get(filters, :offset, 0)

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  defp add_participants(thread, participant_ids) do
    results =
      Enum.map(participant_ids, fn user_id ->
        add_participant(thread, user_id)
      end)

    if Enum.all?(results, &match?({:ok, _}, &1)) do
      {:ok, Enum.map(results, fn {:ok, p} -> p end)}
    else
      error = Enum.find(results, &match?({:error, _}, &1))
      error
    end
  end

  defp generate_shard_id do
    # Generate a unique shard ID using UUID
    # This will be used for the per-thread database filename
    Ecto.UUID.generate()
  end
end
