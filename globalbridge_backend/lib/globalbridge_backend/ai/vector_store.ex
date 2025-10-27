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
      embedding float[1536]
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

    # Convert embedding list to JSON array string expected by vec0
    # vec0 expects format: "[0.1, 0.2, 0.3, ...]"
    embedding_json = Jason.encode!(embedding)

    sql = """
    INSERT OR REPLACE INTO message_embeddings (message_id, embedding)
    VALUES (?, ?)
    """
    case Ecto.Adapters.SQL.query(repo, sql, [message_id, embedding_json]) do
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
  Searches for similar messages using real semantic search with cosine similarity.

  Uses real OpenAI embeddings to find messages semantically similar to the query.

  ## Parameters
  - thread_id: Thread database to search
  - query_embedding: Real embedding vector (3072 dimensions)
  - opts: Options including :limit (default 10)

  ## Returns
  - List of %{message_id, distance, similarity} sorted by similarity
  - {:error, reason} on failure
  """
  def search(thread_id, query_embedding, opts \\ []) do
    repo = ThreadRepo.get_repo(thread_id)
    limit = Keyword.get(opts, :limit, 10)

    # Get all message embeddings
    get_sql = """
    SELECT message_id, embedding
    FROM message_embeddings
    """

    case Ecto.Adapters.SQL.query(repo, get_sql, []) do
      {:ok, %{rows: rows}} ->
        # Calculate cosine similarity for each embedding
        results = rows
        |> Enum.map(fn [message_id, embedding_binary] ->
          # Convert binary to embedding
          stored_embedding = binary_to_embedding(embedding_binary)

          # Calculate cosine similarity
          similarity = GlobalbridgeBackend.AI.Embeddings.cosine_similarity(
            query_embedding,
            stored_embedding
          )

          # Convert to distance (1 - similarity)
          distance = 1.0 - similarity

          %{
            message_id: message_id,
            distance: distance,
            similarity: similarity
          }
        end)
        |> Enum.sort_by(& &1.distance)  # Sort by distance (lower = more similar)
        |> Enum.take(limit)

        {:ok, results}

      {:error, error} ->
        Logger.error("Failed to search messages: #{inspect(error)}")
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
      embedding float[1536]
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

    # Convert embedding to JSON array format for vec0
    embedding_json = Jason.encode!(embedding)
    embedding_id = "#{user_id}_#{style_aspect}_#{:erlang.unique_integer([:positive])}"

    sql = """
    INSERT OR REPLACE INTO user_style_embeddings (embedding_id, user_id, style_aspect, embedding)
    VALUES (?, ?, ?, ?)
    """

    Ecto.Adapters.SQL.query!(repo, sql, [embedding_id, user_id, style_aspect, embedding_json])
    :ok
  end

  @doc """
  Searches for similar user style patterns using real semantic search.

  Useful for finding users with similar writing styles for collaborative filtering.

  ## Parameters
  - thread_id: Thread database to search
  - query_embedding: Real embedding vector (3072 dimensions)
  - style_aspect: Filter by style aspect
  - opts: Options including :limit (default 10)

  ## Returns
  - List of %{user_id, distance, similarity} sorted by similarity
  - {:error, reason} on failure
  """
  def search_user_styles(thread_id, query_embedding, style_aspect, opts \\ []) do
    repo = ThreadRepo.get_repo(thread_id)
    limit = Keyword.get(opts, :limit, 10)

    # Get all user style embeddings for the specified aspect
    get_sql = """
    SELECT user_id, embedding
    FROM user_style_embeddings
    WHERE style_aspect = ?
    """

    case Ecto.Adapters.SQL.query(repo, get_sql, [style_aspect]) do
      {:ok, %{rows: rows}} ->
        # Calculate cosine similarity for each embedding
        results = rows
        |> Enum.map(fn [user_id, embedding_json] ->
          # Parse JSON embedding
          {:ok, stored_embedding} = Jason.decode(embedding_json)

          # Calculate cosine similarity
          similarity = GlobalbridgeBackend.AI.Embeddings.cosine_similarity(
            query_embedding,
            stored_embedding
          )

          # Convert to distance (1 - similarity)
          distance = 1.0 - similarity

          %{
            user_id: user_id,
            distance: distance,
            similarity: similarity
          }
        end)
        |> Enum.sort_by(& &1.distance)  # Sort by distance (lower = more similar)
        |> Enum.take(limit)

        results

      {:error, error} ->
        Logger.error("Failed to search user styles: #{inspect(error)}")
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
        {:ok, Enum.map(rows, fn [aspect, embedding_json] ->
          # Parse JSON embedding
          {:ok, embedding} = Jason.decode(embedding_json)
          %{style_aspect: aspect, embedding: embedding}
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
      embedding float[1536]
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

    # Convert embedding to JSON array format for vec0
    embedding_json = Jason.encode!(embedding)
    accepted_int = if accepted, do: 1, else: 0

    sql = """
    INSERT OR REPLACE INTO feedback_embeddings (feedback_id, user_id, suggestion_type, accepted, embedding)
    VALUES (?, ?, ?, ?, ?)
    """

    Ecto.Adapters.SQL.query!(repo, sql, [feedback_id, user_id, suggestion_type, accepted_int, embedding_json])
    :ok
  end

  @doc """
  Searches for similar accepted suggestions using real semantic search.

  Uses OpenAI embeddings and cosine similarity to find previously accepted
  suggestions that are semantically similar to the query.

  ## Parameters
  - thread_id: Thread database to search
  - user_id: User whose accepted suggestions to search
  - query_embedding: Real embedding vector (1536 dimensions from text-embedding-3-small)
  - opts: Options including :limit (default 10)

  ## Returns
  - List of %{feedback_id, suggestion_type, distance} sorted by similarity
  - {:error, reason} on failure
  """
  def search_accepted_suggestions(thread_id, user_id, query_embedding, opts \\ []) do
    repo = ThreadRepo.get_repo(thread_id)
    limit = Keyword.get(opts, :limit, 10)

    # First, get all accepted suggestions for this user
    get_sql = """
    SELECT feedback_id, suggestion_type, embedding
    FROM feedback_embeddings
    WHERE user_id = ?
      AND accepted = 1
    """

    case Ecto.Adapters.SQL.query(repo, get_sql, [user_id]) do
      {:ok, %{rows: rows}} ->
        # Calculate cosine similarity for each embedding
        results = rows
        |> Enum.map(fn [feedback_id, suggestion_type, embedding_json] ->
          # Parse JSON embedding
          {:ok, stored_embedding} = Jason.decode(embedding_json)

          # Calculate cosine similarity using Embeddings module
          similarity = GlobalbridgeBackend.AI.Embeddings.cosine_similarity(
            query_embedding,
            stored_embedding
          )

          # Convert similarity to distance (1 - similarity for sorting)
          distance = 1.0 - similarity

          %{
            feedback_id: feedback_id,
            suggestion_type: suggestion_type,
            distance: distance,
            similarity: similarity
          }
        end)
        |> Enum.sort_by(& &1.distance)  # Sort by distance (lower = more similar)
        |> Enum.take(limit)

        results

      {:error, error} ->
        Logger.error("Failed to search accepted suggestions: #{inspect(error)}")
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
