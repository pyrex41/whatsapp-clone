defmodule GlobalbridgeBackend.AI.VectorStore do
  @moduledoc """
  Handles vector storage operations using SQLite vec0 extension.

  This module manages:
  - Creating vec0 virtual tables for vector similarity search
  - Inserting embeddings into vector tables
  - Performing cosine similarity searches
  - Managing per-thread vector databases
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

    Ecto.Adapters.SQL.query!(repo, sql, [message_id, embedding_binary])
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
end
