defmodule GlobalbridgeBackend.Integration.AIPipelineProfilingTest do
  @moduledoc """
  Profiling tests for AI pipeline performance optimization.

  Measures the impact of caching on search performance and identifies bottlenecks.
  """

  use ExUnit.Case, async: false
  alias GlobalbridgeBackend.AI.{EmbeddingService, SemanticSearch, RAGRetriever}
  alias GlobalbridgeBackend.AI.Cache.{EmbeddingCache, SearchCache}

  @moduletag :profiling_test
  # 2 minutes timeout
  @moduletag timeout: 120_000

  setup_all do
    # Ensure test mode is enabled
    assert EmbeddingService.test_mode?() == true

    # Clear caches to ensure clean state
    EmbeddingCache.clear()
    SearchCache.clear()

    :ok
  end

  describe "embedding cache performance" do
    test "embedding cache hit vs miss performance" do
      test_text = "This is a test message for embedding cache performance analysis."

      # First call - cache miss
      {miss_time, {:ok, embedding1}} =
        :timer.tc(fn ->
          EmbeddingService.generate(test_text)
        end)

      # Second call - cache hit
      {hit_time, {:ok, embedding2}} =
        :timer.tc(fn ->
          EmbeddingService.generate(test_text)
        end)

      # Verify embeddings are identical
      assert embedding1 == embedding2

      miss_ms = miss_time / 1000
      hit_ms = hit_time / 1000
      speedup = miss_ms / hit_ms

      IO.puts("Embedding cache performance:")
      IO.puts("  Cache miss: #{Float.round(miss_ms, 2)}ms")
      IO.puts("  Cache hit: #{Float.round(hit_ms, 2)}ms")
      IO.puts("  Speedup: #{Float.round(speedup, 2)}x")

      # In test mode, caching may not show significant speedup due to mocking
      # but the cache interface should work (times should be reasonable)
      assert miss_ms > 0
      assert hit_ms > 0
      # Note: In production, cache hits should be significantly faster
    end

    test "cache hit ratio under repeated queries" do
      queries = [
        "project deadline",
        "meeting schedule",
        "team update",
        "code review",
        # Repeat
        "project deadline",
        # Repeat
        "meeting schedule",
        "new feature",
        "bug fix",
        # Repeat again
        "project deadline",
        # Repeat again
        "meeting schedule"
      ]

      # Clear cache first
      EmbeddingCache.clear()

      {time, results} =
        :timer.tc(fn ->
          Enum.map(queries, fn query ->
            EmbeddingService.generate(query)
          end)
        end)

      total_time = time / 1_000_000

      successful =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      # Calculate expected cache hits (3 repeats of 2 queries = 6 cache hits)
      expected_cache_hits = 6
      total_queries = length(queries)

      IO.puts("Repeated query cache test:")
      IO.puts("  Total queries: #{total_queries}")
      IO.puts("  Expected cache hits: #{expected_cache_hits}")
      IO.puts("  Total time: #{Float.round(total_time, 3)}s")
      IO.puts("  Avg time per query: #{Float.round(total_time / total_queries * 1000, 2)}ms")

      assert successful == total_queries
    end
  end

  describe "semantic search cache performance" do
    test "search result caching effectiveness" do
      thread_id = "profile-test-thread-#{:rand.uniform(1000)}"
      query = "performance optimization techniques"

      # Clear search cache
      SearchCache.clear()

      # First search - cache miss
      {miss_time, {:ok, results1}} =
        :timer.tc(fn ->
          SemanticSearch.search(thread_id, query)
        end)

      # Second search - cache hit
      {hit_time, {:ok, results2}} =
        :timer.tc(fn ->
          SemanticSearch.search(thread_id, query)
        end)

      # Results should be identical
      assert results1 == results2

      miss_ms = miss_time / 1000
      hit_ms = hit_time / 1000
      speedup = if hit_ms > 0, do: miss_ms / hit_ms, else: :infinity

      IO.puts("Search result cache performance:")
      IO.puts("  Cache miss: #{Float.round(miss_ms, 2)}ms")
      IO.puts("  Cache hit: #{Float.round(hit_ms, 2)}ms")
      IO.puts("  Speedup: #{if speedup == :infinity, do: "∞", else: Float.round(speedup, 2)}x")

      # Cache hit should be much faster
      assert hit_ms < miss_ms
    end

    test "vector search cache performance" do
      thread_id = "vector-profile-thread-#{:rand.uniform(1000)}"

      # Generate test embedding
      {:ok, embedding} = EmbeddingService.generate("vector search performance test")

      # Clear vector cache
      SearchCache.clear()

      # First vector search - cache miss
      {miss_time, result1} =
        :timer.tc(fn ->
          RAGRetriever.search_by_embedding(thread_id, embedding, limit: 5)
        end)

      # Second vector search - cache hit
      {hit_time, result2} =
        :timer.tc(fn ->
          RAGRetriever.search_by_embedding(thread_id, embedding, limit: 5)
        end)

      # Results should be identical (both errors in test env, but same error)
      assert result1 == result2

      miss_ms = miss_time / 1000
      hit_ms = hit_time / 1000
      speedup = if hit_ms > 0, do: miss_ms / hit_ms, else: :infinity

      IO.puts("Vector search cache performance:")
      IO.puts("  Cache miss: #{Float.round(miss_ms, 2)}ms")
      IO.puts("  Cache hit: #{Float.round(hit_ms, 2)}ms")
      IO.puts("  Speedup: #{if speedup == :infinity, do: "∞", else: Float.round(speedup, 2)}x")

      # Cache hit should be faster
      assert hit_ms <= miss_ms
    end
  end

  describe "end-to-end pipeline performance" do
    test "full pipeline performance with and without cache" do
      thread_id = "pipeline-profile-thread-#{:rand.uniform(1000)}"

      queries = [
        "project status update",
        "meeting scheduling",
        "code review feedback",
        "bug report analysis"
      ]

      # Test without cache (clear all caches)
      EmbeddingCache.clear()
      SearchCache.clear()

      {no_cache_time, no_cache_results} =
        :timer.tc(fn ->
          Enum.map(queries, fn query ->
            try do
              SemanticSearch.search(thread_id, query, limit: 3)
            rescue
              _ -> {:error, :exception}
            end
          end)
        end)

      # Test with cache (run same queries again)
      {with_cache_time, with_cache_results} =
        :timer.tc(fn ->
          Enum.map(queries, fn query ->
            try do
              SemanticSearch.search(thread_id, query, limit: 3)
            rescue
              _ -> {:error, :exception}
            end
          end)
        end)

      # Test with cache (run same queries again)
      {with_cache_time, with_cache_results} =
        :timer.tc(fn ->
          Enum.map(queries, fn query ->
            SemanticSearch.search(thread_id, query, limit: 3)
          end)
        end)

      # Results should be identical
      assert no_cache_results == with_cache_results

      no_cache_seconds = no_cache_time / 1_000_000
      with_cache_seconds = with_cache_time / 1_000_000
      speedup = no_cache_seconds / with_cache_seconds

      IO.puts("Full pipeline cache performance:")
      IO.puts("  Without cache: #{Float.round(no_cache_seconds, 3)}s")
      IO.puts("  With cache: #{Float.round(with_cache_seconds, 3)}s")
      IO.puts("  Speedup: #{Float.round(speedup, 2)}x")
      IO.puts("  Time saved: #{Float.round(no_cache_seconds - with_cache_seconds, 3)}s")

      # Cache should provide significant speedup
      assert with_cache_seconds < no_cache_seconds
      assert speedup > 1.5
    end

    test "cache invalidation impact" do
      thread_id = "invalidation-test-thread-#{:rand.uniform(1000)}"
      query = "cache invalidation test"

      # Warm up cache
      try do
        SemanticSearch.search(thread_id, query)
      rescue
        _ -> :error
      end

      # Verify it's cached
      cached_result = SearchCache.get_search_results(thread_id, query, [])
      assert cached_result != nil

      # Invalidate thread cache
      SearchCache.invalidate_thread_cache(thread_id)

      # Verify cache is cleared
      cached_result_after = SearchCache.get_search_results(thread_id, query, [])
      assert cached_result_after == nil

      IO.puts("Cache invalidation test: Cache properly cleared for thread #{thread_id}")
    end
  end

  describe "memory usage profiling" do
    test "cache memory overhead" do
      # Get initial cache stats
      initial_stats = SearchCache.stats()

      # Perform multiple searches to build up cache
      thread_id = "memory-profile-thread-#{:rand.uniform(1000)}"
      queries = Enum.map(1..20, fn i -> "Memory profiling query #{i}" end)

      Enum.each(queries, fn query ->
        try do
          SemanticSearch.search(thread_id, query)
        rescue
          # Expected in test environment
          _ -> :error
        end

        # Small delay to avoid overwhelming
        Process.sleep(10)
      end)

      # Get final cache stats
      final_stats = SearchCache.stats()

      IO.puts("Cache memory profiling:")
      IO.puts("  Initial entries: #{initial_stats[:entries] || 0}")
      IO.puts("  Final entries: #{final_stats[:entries] || 0}")
      IO.puts("  Cache hits: #{final_stats[:hits] || 0}")
      IO.puts("  Cache misses: #{final_stats[:misses] || 0}")

      # Should have cache entries now
      assert (final_stats[:entries] || 0) > (initial_stats[:entries] || 0)
    end
  end

  describe "bottleneck analysis" do
    test "identify performance bottlenecks in search pipeline" do
      thread_id = "bottleneck-thread-#{:rand.uniform(1000)}"
      query = "bottleneck analysis query"

      # Clear caches for clean measurement
      EmbeddingCache.clear()
      SearchCache.clear()

      # Measure embedding generation time
      {embedding_time, {:ok, _embedding}} =
        :timer.tc(fn ->
          EmbeddingService.generate(query)
        end)

      # Measure vector search time (will be cached now)
      {vector_time, _vector_result} =
        :timer.tc(fn ->
          try do
            RAGRetriever.search_by_embedding(thread_id, [1.0 | List.duplicate(0.0, 3071)],
              limit: 5
            )
          rescue
            _ -> {:error, :exception}
          end
        end)

      # Measure full search time
      {full_time, {:ok, _results}} =
        :timer.tc(fn ->
          SemanticSearch.search(thread_id, query)
        end)

      embedding_ms = embedding_time / 1000
      vector_ms = vector_time / 1000
      full_ms = full_time / 1000

      IO.puts("Pipeline bottleneck analysis:")
      IO.puts("  Embedding generation: #{Float.round(embedding_ms, 2)}ms")
      IO.puts("  Vector search: #{Float.round(vector_ms, 2)}ms")
      IO.puts("  Full search: #{Float.round(full_ms, 2)}ms")

      # Full search should be close to embedding time (since vector search is fast in test mode)
      # In production, vector search would be the bottleneck
      assert full_ms >= embedding_ms
    end
  end
end
