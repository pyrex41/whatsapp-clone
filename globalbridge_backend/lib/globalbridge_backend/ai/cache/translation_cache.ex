defmodule GlobalbridgeBackend.AI.Cache.TranslationCache do
  @moduledoc """
  Redis-based cache for translation results.

  Caches translations for 7 days to reduce API costs and improve performance.
  """

  # 7 days
  @ttl :timer.hours(168)

  @doc """
  Gets a cached translation result.
  """
  def get(text, target_lang) do
    key = cache_key(text, target_lang)

    case Cachex.get(:ai_cache, key) do
      {:ok, nil} -> nil
      {:ok, cached} -> Jason.decode!(cached)
    end
  end

  @doc """
  Stores a translation result in cache.
  """
  def put(text, target_lang, result) do
    key = cache_key(text, target_lang)
    json = Jason.encode!(result)

    Cachex.put(:ai_cache, key, json, ttl: @ttl)
  end

  @doc """
  Clears all translation cache entries.
  """
  def clear do
    # Note: This clears the entire AI cache, not just translations
    # In a production system, you might want separate caches
    Cachex.clear(:ai_cache)
  end

  # Private functions

  defp cache_key(text, target_lang) do
    # Create a hash of the text for cache key
    hash = :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
    "translation:#{hash}:#{target_lang}"
  end
end
