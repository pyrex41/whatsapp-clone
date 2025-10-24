defmodule GlobalbridgeBackend.AI.Jobs.CleanupCacheJob do
  @moduledoc """
  Periodic cache cleanup job.

  Runs on a cron schedule to clear or compact AI-related caches to control memory usage.
  Configured via Oban.Plugins.Cron in runtime.exs.
  """

  use Oban.Worker, queue: :ai_processing, max_attempts: 1

  alias GlobalbridgeBackend.AI.Cache.{SearchCache, EmbeddingCache, TranslationCache}

  @impl Oban.Worker
  def perform(_job) do
    # Best-effort cleanup; ignore errors
    try do
      SearchCache.clear()
    rescue
      _ -> :ok
    end

    try do
      EmbeddingCache.clear()
    rescue
      _ -> :ok
    end

    try do
      TranslationCache.clear()
    rescue
      _ -> :ok
    end

    :ok
  end
end

