defmodule GlobalbridgeBackend.AI.VectorStore do
  @moduledoc """
  Handles vector storage operations using SQLite vec0 extension.

  This module manages:
  - Creating vec0 virtual tables for vector similarity search
  - Inserting embeddings into vector tables
  - Performing cosine similarity searches
  - Managing per-thread vector databases
  - Storing user writing style embeddings for personalization
  - Tracking suggestion feedback with embeddings for learning
  """

  require Logger
  alias GlobalbridgeBackend.Repos.ThreadRepo

  @doc """
  Creates the message_embeddings virtual table in a thread database.

  This should be called when a thread database is first created.
  """
  def create_embeddings_table(repo) do
    sql = """
    CREATE VIRTUAL TABLE IF NOT EXISTS message_embeddings USING vec0(
      message_id TEXT PRIMARY KEY,
      embedding float[3072]
    );
    """

    case Ecto.Adapters.SQL.query(repo, sql) do
      {:ok, _} -> :ok
      {:error, %Exqlite.Error{message: message} = err} ->
        if String.contains?(String.downcase(message), "no such module: vec0") do
          Logger.warning("sqlite-vec (vec0) not available; skipping vector table creation")
          :ok
        else
          Logger.error("Failed to create message_embeddings vec table: #{inspect(err)}")
          :ok
        end
      {:error, err} ->
        Logger.error("Failed to create message_embeddings vec table: #{inspect(err)}")
        :ok
    end
  end

  @doc """
  Inserts an embedding for a message into the vector table.
  """
  def insert(thread_id, message_id, embedding) do
    repo = ThreadRepo.get_repo(thread_id)

    # Ensure the virtual table exists
    create_embeddings_table(repo)

    # Convert embedding list to binary format expected by vec0
    embedding_binary = embedding_to_binary(embedding)

    sql = """
    INSERT OR REPLACE INTO message_embeddings (message_id, embedding)
    VALUES (?, ?)
    """
    case Ecto.Adapters.SQL.query(repo, sql, [message_id, embedding_binary]) do
      {:ok, _} -> :ok
      {:error, %Exqlite.Error{} = err} ->
        require Logger
        Logger.error("vec0 insert failed for message #{message_id}: #{inspect(err)}")
        {:error, err}
      {:error, err} ->
        require Logger
        Logger.error("vec0 insert failed (unknown) for message #{message_id}: #{inspect(err)}")
        {:error, err}
    end
  end

  @doc """
  Searches for similar messages using cosine similarity.

  Returns a list of {message_id, distance} tuples, ordered by similarity.
  """
  def search(thread_id, query_embedding, opts \\ []) do
    repo = ThreadRepo.get_repo(thread_id)
    limit = Keyword.get(opts, :limit, 10)

    # Convert query embedding to binary
    query_binary = embedding_to_binary(query_embedding)

    sql = """
    SELECT message_id, distance
    FROM message_embeddings
    WHERE embedding MATCH ?
      AND k = ?
    ORDER BY distance
    """

    case Ecto.Adapters.SQL.query(repo, sql, [query_binary, limit]) do
      {:ok, %{rows: rows}} ->
        # Convert rows to {message_id, distance} tuples
        Enum.map(rows, fn [message_id, distance] ->
          %{message_id: message_id, distance: distance}
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Deletes an embedding from the vector table.
  """
  def delete(thread_id, message_id) do
    repo = ThreadRepo.get_repo(thread_id)

    sql = "DELETE FROM message_embeddings WHERE message_id = ?"
    Ecto.Adapters.SQL.query!(repo, sql, [message_id])
  end

  @doc """
  Gets the embedding for a specific message.
  """
  def get_embedding(thread_id, message_id) do
    repo = ThreadRepo.get_repo(thread_id)

    sql = "SELECT embedding FROM message_embeddings WHERE message_id = ?"

    case Ecto.Adapters.SQL.query(repo, sql, [message_id]) do
      {:ok, %{rows: [[binary_embedding]]}} ->
        {:ok, binary_to_embedding(binary_embedding)}

      {:ok, %{rows: []}} ->
        {:error, :not_found}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Counts the number of embeddings in a thread.
  """
  def count_embeddings(thread_id) do
    repo = ThreadRepo.get_repo(thread_id)

    sql = "SELECT COUNT(*) FROM message_embeddings"

    case Ecto.Adapters.SQL.query(repo, sql, []) do
      {:ok, %{rows: [[count]]}} -> count
      _ -> 0
    end
  end

  # Private functions

  defp embedding_to_binary(embedding) when is_list(embedding) do
    # Convert list of floats to binary
    # vec0 expects float32 little-endian format
    for float <- embedding, into: <<>> do
      <<float::float-32-little>>
    end
  end

  defp binary_to_embedding(binary) when is_binary(binary) do
    # Convert binary back to list of floats
    # Each float32 is 4 bytes
    for <<float::float-32-little <- binary>>, do: float
  end

  ## User Style Embeddings

  @doc """
  Creates the user_style_embeddings virtual table in a thread database.

  Stores embeddings of user's writing style for personalized suggestions.
  Each user has multiple embeddings representing different aspects of their style.
  """
  def create_user_style_table(repo) do
    sql = """
    CREATE VIRTUAL TABLE IF NOT EXISTS user_style_embeddings USING vec0(
      embedding_id TEXT PRIMARY KEY,
      user_id TEXT,
      style_aspect TEXT,
      embedding float[3072]
    );
    """

    case Ecto.Adapters.SQL.query(repo, sql) do
      {:ok, _} -> :ok
      {:error, %Exqlite.Error{message: message}} ->
        if String.contains?(String.downcase(message), "no such module: vec0") do
          Logger.warning("sqlite-vec (vec0) not available; skipping user style table creation")
          :ok
        else
          Logger.error("Failed to create user_style_embeddings table: #{inspect(message)}")
          :ok
        end
      {:error, err} ->
        Logger.error("Failed to create user_style_embeddings table: #{inspect(err)}")
        :ok
    end
  end

  @doc """
  Inserts a user style embedding into the vector table.

  ## Parameters
  - thread_id: The thread ID (for repo selection)
  - user_id: The user whose style is being stored
  - style_aspect: What aspect of style (e.g., "vocabulary", "tone", "punctuation")
  - embedding: The embedding vector

  ## Returns
  - :ok on success
  """
  def insert_user_style(thread_id, user_id, style_aspect, embedding) do
    repo = ThreadRepo.get_repo(thread_id)

    # Ensure the table exists
    create_user_style_table(repo)

    embedding_binary = embedding_to_binary(embedding)
    embedding_id = "#{user_id}_#{style_aspect}_#{:erlang.unique_integer([:positive])}"

    sql = """
    INSERT OR REPLACE INTO user_style_embeddings (embedding_id, user_id, style_aspect, embedding)
    VALUES (?, ?, ?, ?)
    """

    Ecto.Adapters.SQL.query!(repo, sql, [embedding_id, user_id, style_aspect, embedding_binary])
    :ok
  end

  @doc """
  Searches for similar user style patterns.

  Useful for finding users with similar writing styles for collaborative filtering.
  """
  def search_user_styles(thread_id, query_embedding, style_aspect, opts \\ []) do
    repo = ThreadRepo.get_repo(thread_id)
    limit = Keyword.get(opts, :limit, 10)

    query_binary = embedding_to_binary(query_embedding)

    sql = """
    SELECT user_id, distance
    FROM user_style_embeddings
    WHERE style_aspect = ?
      AND embedding MATCH ?
      AND k = ?
    ORDER BY distance
    """

    case Ecto.Adapters.SQL.query(repo, sql, [style_aspect, query_binary, limit]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [user_id, distance] ->
          %{user_id: user_id, distance: distance}
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets all style embeddings for a specific user.

  Returns embeddings for all style aspects (vocabulary, tone, etc.)
  """
  def get_user_styles(thread_id, user_id) do
    repo = ThreadRepo.get_repo(thread_id)

    sql = """
    SELECT style_aspect, embedding
    FROM user_style_embeddings
    WHERE user_id = ?
    """

    case Ecto.Adapters.SQL.query(repo, sql, [user_id]) do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, fn [aspect, binary] ->
          %{style_aspect: aspect, embedding: binary_to_embedding(binary)}
        end)}

      {:error, error} ->
        {:error, error}
    end
  end

  ## Suggestion Feedback Embeddings

  @doc """
  Creates the feedback_embeddings virtual table in a thread database.

  Stores embeddings of suggestions that were accepted/rejected for learning.
  """
  def create_feedback_table(repo) do
    sql = """
    CREATE VIRTUAL TABLE IF NOT EXISTS feedback_embeddings USING vec0(
      feedback_id TEXT PRIMARY KEY,
      user_id TEXT,
      suggestion_type TEXT,
      accepted INTEGER,
      embedding float[3072]
    );
    """

    case Ecto.Adapters.SQL.query(repo, sql) do
      {:ok, _} -> :ok
      {:error, %Exqlite.Error{message: message}} ->
        if String.contains?(String.downcase(message), "no such module: vec0") do
          Logger.warning("sqlite-vec (vec0) not available; skipping feedback table creation")
          :ok
        else
          Logger.error("Failed to create feedback_embeddings table: #{inspect(message)}")
          :ok
        end
      {:error, err} ->
        Logger.error("Failed to create feedback_embeddings table: #{inspect(err)}")
        :ok
    end
  end

  @doc """
  Inserts a suggestion feedback embedding for learning.

  ## Parameters
  - thread_id: The thread ID (for repo selection)
  - feedback_id: Unique ID for this feedback record
  - user_id: The user who provided feedback
  - suggestion_type: Type of suggestion (smart_reply, confusion_clarification, etc.)
  - accepted: Boolean - whether the suggestion was accepted
  - embedding: The embedding of the suggestion content

  ## Returns
  - :ok on success
  """
  def insert_feedback(thread_id, feedback_id, user_id, suggestion_type, accepted, embedding) do
    repo = ThreadRepo.get_repo(thread_id)

    # Ensure the table exists
    create_feedback_table(repo)

    embedding_binary = embedding_to_binary(embedding)
    accepted_int = if accepted, do: 1, else: 0

    sql = """
    INSERT OR REPLACE INTO feedback_embeddings (feedback_id, user_id, suggestion_type, accepted, embedding)
    VALUES (?, ?, ?, ?, ?)
    """

    Ecto.Adapters.SQL.query!(repo, sql, [feedback_id, user_id, suggestion_type, accepted_int, embedding_binary])
    :ok
  end

  @doc """
  Searches for similar accepted suggestions.

  Useful for finding what types of suggestions a user typically accepts.
  """
  def search_accepted_suggestions(thread_id, user_id, query_embedding, opts \\ []) do
    repo = ThreadRepo.get_repo(thread_id)
    limit = Keyword.get(opts, :limit, 10)

    query_binary = embedding_to_binary(query_embedding)

    sql = """
    SELECT feedback_id, suggestion_type, distance
    FROM feedback_embeddings
    WHERE user_id = ?
      AND accepted = 1
      AND embedding MATCH ?
      AND k = ?
    ORDER BY distance
    """

    case Ecto.Adapters.SQL.query(repo, sql, [user_id, query_binary, limit]) do
      {:ok, %{rows: rows}} ->
        Enum.map(rows, fn [feedback_id, suggestion_type, distance] ->
          %{feedback_id: feedback_id, suggestion_type: suggestion_type, distance: distance}
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Analyzes acceptance patterns for a user.

  Returns statistics on what types of suggestions are typically accepted vs rejected.
  """
  def analyze_user_acceptance_patterns(thread_id, user_id) do
    repo = ThreadRepo.get_repo(thread_id)

    sql = """
    SELECT
      suggestion_type,
      COUNT(*) as total,
      SUM(accepted) as accepted_count,
      CAST(SUM(accepted) AS FLOAT) / COUNT(*) as acceptance_rate
    FROM feedback_embeddings
    WHERE user_id = ?
    GROUP BY suggestion_type
    """

    case Ecto.Adapters.SQL.query(repo, sql, [user_id]) do
      {:ok, %{rows: rows}} ->
        {:ok, Enum.map(rows, fn [type, total, accepted, rate] ->
          %{
            suggestion_type: type,
            total: total,
            accepted: accepted,
            acceptance_rate: rate
          }
        end)}

      {:error, error} ->
        {:error, error}
    end
  end
end
