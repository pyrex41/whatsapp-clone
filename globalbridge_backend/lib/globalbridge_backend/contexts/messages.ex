defmodule GlobalbridgeBackend.Contexts.Messages do
  @moduledoc """
  Context for managing messages within threads.
  Messages are stored in per-thread databases for horizontal sharding.
  This context handles routing queries to the appropriate shard.
  """

  import Ecto.Query, warn: false

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{Message, ReadReceipt, Thread}
  alias GlobalbridgeBackend.Repos.ThreadRepo
  alias GlobalbridgeBackendWeb.Plugs.ThreadCache

  @doc """
  Lists messages in a thread with optional filtering.

  ## Filters
  - `:sender_id` - Filter by sender (binary_id)
  - `:content_type` - Filter by content type ("text", "image", etc.)
  - `:is_deleted` - Filter by deleted status (boolean, default: false)
  - `:after` - Get messages after this timestamp (DateTime)
  - `:before` - Get messages before this timestamp (DateTime)
  - `:limit` - Limit number of results (default: 50)
  - `:offset` - Offset for pagination (default: 0)
  - `:order_by` - Order by field (default: :inserted_at, :desc)

  ## Examples

      iex> list_messages("thread-id")
      [%Message{}, ...]

      iex> list_messages("thread-id", limit: 10, is_deleted: false)
      [%Message{}, ...]
  """
  def list_messages(thread_id, filters \\ []) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    # Historical backfill was temporary during migration; removed to keep fetch path lean.

    Message
    |> where([m], m.thread_id == ^thread_id)
    |> apply_message_filters(filters)
    |> apply_ordering(filters)
    |> apply_pagination(filters)
    |> repo.all()
  end

  @doc """
  Gets a single message by ID, raising if not found.

  ## Examples

      iex> get_message!("thread-id", "message-id")
      %Message{}

      iex> get_message!("thread-id", "non-existent")
      ** (Ecto.NoResultsError)
  """
  def get_message!(thread_id, message_id) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    # Use get_by! to properly filter by both thread_id and message_id
    # This ensures we don't return messages from other threads
    repo.get_by!(Message, id: message_id, thread_id: thread_id)
  end

  @doc """
  Gets a single message by ID, returning nil if not found.

  ## Examples

      iex> get_message("thread-id", "message-id")
      %Message{}

      iex> get_message("thread-id", "non-existent")
      nil
  """
  def get_message(thread_id, message_id) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    query =
      from(m in Message,
        where: m.thread_id == ^thread_id and m.id == ^message_id
      )

    repo.one(query)
  end

  @doc """
  Gets a message by client_message_id (for client-generated UUIDs).

  Used when clients send their locally-generated message ID rather than
  the server-assigned ID (common in offline-first scenarios and style learning).
  """
  def get_message_by_client_id(thread_id, client_message_id) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    query =
      from(m in Message,
        where: m.thread_id == ^thread_id and m.client_message_id == ^client_message_id
      )

    repo.one(query)
  end

  @doc """
  Creates a new message in a thread.

  Automatically updates the thread's last_message_at timestamp.

  ## Examples

      iex> create_message("thread-id", %{
      ...>   sender_id: "user-id",
      ...>   content_type: "text",
      ...>   content: "Hello!"
      ...> })
      {:ok, %Message{}}

      iex> create_message("thread-id", %{content_type: "invalid"})
      {:error, %Ecto.Changeset{}}
  """
  def create_message(thread_id, attrs) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    attrs = Map.put(attrs, :thread_id, thread_id)

    result =
      %Message{}
      |> Message.create_changeset(attrs)
      |> repo.insert()

    case result do
      {:ok, message} ->
        # Update thread's last_message_at
        update_thread_timestamp(thread)

        # Enqueue embedding generation for this message (align with Chat path)
        GlobalbridgeBackend.Chat.enqueue_embedding_job(
          thread.database_shard_id,
          thread_id,
          message.id
        )

        # Eagerly generate query embedding for Smart Reply in background
        # This happens server-side when message is sent, so it's ready instantly
        # when user opens the app later
        Task.start(fn ->
          # Get recent messages for context
          recent_messages = list_messages(thread_id, limit: 10)
          GlobalbridgeBackend.AI.SmartReplyGenerator.prepare_embeddings_for_thread(thread_id, recent_messages)
        end)

        {:ok, message}

      error ->
        error
    end
  end

  @doc """
  Updates a message.

  Note: Only the content can be updated. Use edit_message/3 for a simpler interface.

  ## Examples

      iex> update_message("thread-id", message, %{content: "Updated"})
      {:ok, %Message{}}
  """
  def update_message(thread_id, %Message{} = message, attrs) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    message
    |> Message.edit_changeset(attrs)
    |> repo.update()
  end

  @doc """
  Edits a message's content.

  ## Examples

      iex> edit_message("thread-id", message, "Updated content")
      {:ok, %Message{}}
  """
  def edit_message(thread_id, %Message{} = message, content) do
    update_message(thread_id, message, %{content: content})
  end

  @doc """
  Soft deletes a message.

  ## Examples

      iex> delete_message("thread-id", message)
      {:ok, %Message{}}
  """
  def delete_message(thread_id, %Message{} = message) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    message
    |> Message.delete_changeset()
    |> repo.update()
  end

  @doc """
  Marks a message as read by a user.

  ## Examples

      iex> mark_as_read("thread-id", "message-id", "user-id")
      {:ok, %ReadReceipt{}}
  """
  def mark_as_read(thread_id, message_id, user_id) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    attrs = %{
      message_id: message_id,
      user_id: user_id
    }

    %ReadReceipt{}
    |> ReadReceipt.create_changeset(attrs)
    |> repo.insert(
      on_conflict: [set: [read_at: DateTime.utc_now()]],
      conflict_target: [:message_id, :user_id]
    )
  end

  @doc """
  Gets the count of unread messages for a user in a thread.

  ## Examples

      iex> get_unread_count("thread-id", "user-id")
      5
  """
  def get_unread_count(thread_id, user_id) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    query =
      from(m in Message,
        left_join: rr in ReadReceipt,
        on: rr.message_id == m.id and rr.user_id == ^user_id,
        where: m.thread_id == ^thread_id,
        where: m.sender_id != ^user_id,
        where: is_nil(rr.id),
        where: m.is_deleted == false,
        select: count(m.id)
      )

    repo.one(query) || 0
  end

  @doc """
  Searches messages in a thread by content.

  ## Examples

      iex> search_messages("thread-id", "hello")
      [%Message{}, ...]

      iex> search_messages("thread-id", "hello", limit: 10)
      [%Message{}, ...]
  """
  def search_messages(thread_id, query_string, filters \\ []) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    search_pattern = "%#{String.downcase(query_string)}%"

    # Use fragment for SQLite compatibility (SQLite doesn't support ilike)
    query =
      from(m in Message,
        where: m.thread_id == ^thread_id,
        where: fragment("lower(?) LIKE ?", m.content, ^search_pattern),
        where: m.is_deleted == false
      )

    query
    |> apply_message_filters(filters)
    |> apply_ordering(filters)
    |> apply_pagination(filters)
    |> repo.all()
  end

  @doc """
  Gets messages in a thread after a specific timestamp.
  Useful for pagination and real-time updates.

  ## Examples

      iex> get_thread_messages_after("thread-id", ~U[2024-01-01 00:00:00Z])
      [%Message{}, ...]

      iex> get_thread_messages_after("thread-id", ~U[2024-01-01 00:00:00Z], 25)
      [%Message{}, ...]
  """
  def get_thread_messages_after(thread_id, timestamp, limit \\ 50) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    query =
      from(m in Message,
        where: m.thread_id == ^thread_id,
        where: m.inserted_at > ^timestamp,
        where: m.is_deleted == false,
        order_by: [asc: m.inserted_at],
        limit: ^limit
      )

    repo.all(query)
  end

  @doc """
  Gets messages in a thread before a specific timestamp.
  Useful for pagination (loading older messages).

  ## Examples

      iex> get_thread_messages_before("thread-id", ~U[2024-01-01 00:00:00Z])
      [%Message{}, ...]

      iex> get_thread_messages_before("thread-id", ~U[2024-01-01 00:00:00Z], 25)
      [%Message{}, ...]
  """
  def get_thread_messages_before(thread_id, timestamp, limit \\ 50) do
    thread = get_thread_with_shard(thread_id)
    repo = ThreadRepo.get_repo(thread.database_shard_id)

    query =
      from(m in Message,
        where: m.thread_id == ^thread_id,
        where: m.inserted_at < ^timestamp,
        where: m.is_deleted == false,
        order_by: [desc: m.inserted_at],
        limit: ^limit
      )

    repo.all(query)
  end

  # Private helper functions

  defp get_thread_with_shard(thread_id) do
    # Check cache first to prevent N+1 queries
    case ThreadCache.get_cached_thread(thread_id) do
      nil ->
        # Cache miss - fetch from database and cache it
        case Repo.get(Thread, thread_id) do
          nil -> raise Ecto.NoResultsError, queryable: Thread
          thread -> ThreadCache.cache_thread(thread)
        end

      cached_thread ->
        # Cache hit - return cached thread
        cached_thread
    end
  end

  defp apply_message_filters(query, filters) do
    Enum.reduce(filters, query, fn
      {:sender_id, sender_id}, q ->
        where(q, [m], m.sender_id == ^sender_id)

      {:content_type, type}, q
      when type in ["text", "image", "video", "audio", "file", "location"] ->
        where(q, [m], m.content_type == ^type)

      {:is_deleted, value}, q when is_boolean(value) ->
        where(q, [m], m.is_deleted == ^value)

      {:after, timestamp}, q ->
        where(q, [m], m.inserted_at > ^timestamp)

      {:before, timestamp}, q ->
        where(q, [m], m.inserted_at < ^timestamp)

      _other, q ->
        q
    end)
  end

  defp apply_ordering(query, filters) do
    order_by = Keyword.get(filters, :order_by, {:inserted_at, :desc})

    case order_by do
      {field, direction} when direction in [:asc, :desc] ->
        order_by(query, [m], [{^direction, field(m, ^field)}])

      field when is_atom(field) ->
        order_by(query, [m], desc: field(m, ^field))

      _ ->
        order_by(query, [m], desc: :inserted_at)
    end
  end

  defp apply_pagination(query, filters) do
    limit = Keyword.get(filters, :limit, 50)
    offset = Keyword.get(filters, :offset, 0)

    query
    |> limit(^limit)
    |> offset(^offset)
  end

  defp update_thread_timestamp(thread) do
    Thread.update_changeset(thread, %{last_message_at: DateTime.utc_now()})
    |> Repo.update()
  end
end
