defmodule GlobalbridgeBackend.AI.Cache.EmbeddingCache do
  @moduledoc """
  Cache for embedding vectors to reduce OpenAI API calls.

  Uses Cachex for in-memory caching with configurable TTL.
  """

  # Cache embeddings for 30 days (embeddings don't change)
  @ttl :timer.hours(720)

  @doc """
  Gets a cached embedding for text.
  """
  def get(text, model \\ "text-embedding-3-large") do
    key = cache_key(text, model)

    case Cachex.get(:ai_cache, key) do
      {:ok, nil} -> nil
      {:ok, cached} -> Jason.decode!(cached)
    end
  end

  @doc """
  Stores an embedding in cache.
  """
  def put(text, embedding, model \\ "text-embedding-3-large") do
    key = cache_key(text, model)
    json = Jason.encode!(embedding)

    Cachex.put(:ai_cache, key, json, ttl: @ttl)
  end

  @doc """
  Checks if an embedding exists in cache.
  """
  def exists?(text, model \\ "text-embedding-3-large") do
    key = cache_key(text, model)

    case Cachex.exists?(:ai_cache, key) do
      {:ok, exists} -> exists
    end
  end

  @doc """
  Clears all embedding cache entries.
  """
  def clear do
    # This clears the entire AI cache
    # In production, you might want separate caches for different types
    Cachex.clear(:ai_cache)
  end

  @doc """
  Gets cache statistics.
  """
  def stats do
    Cachex.stats(:ai_cache)
  end

  # Private functions

  defp cache_key(text, model) do
    # Create a hash of the text for cache key
    hash = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
    "embedding:#{model}:#{hash}"
  end
end
