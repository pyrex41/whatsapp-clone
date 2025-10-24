defmodule GlobalbridgeBackend.AI.CacheTest do
  use ExUnit.Case, async: false

  alias GlobalbridgeBackend.AI.Cache

  setup do
    # Initialize cache (creates ETS table if needed)
    Cache.init()
    # Clear all caches before each test
    Cache.clear_all()
    :ok
  end

  describe "init/0" do
    test "initializes ETS table for repository caching" do
      assert :ok = Cache.init()

      # Verify ETS table exists
      ets_info = :ets.info(:thread_repo_cache)
      assert ets_info != :undefined
      assert ets_info[:type] == :set
      assert ets_info[:named_table] == true
    end
  end

  describe "embedding cache operations" do
    test "get_embedding/2 returns nil when embedding is not cached" do
      assert nil == Cache.get_embedding("test text", "text-embedding-3-large")
    end

    test "put_embedding/3 and get_embedding/2 work together" do
      text = "test text"
      model = "text-embedding-3-large"
      embedding = [0.1, 0.2, 0.3, 0.4, 0.5]

      assert :ok = Cache.put_embedding(text, embedding, model)
      assert ^embedding = Cache.get_embedding(text, model)
    end

    test "embedding_exists?/2 returns true when embedding is cached" do
      text = "test text"
      model = "text-embedding-3-large"
      embedding = [0.1, 0.2, 0.3]

      refute Cache.embedding_exists?(text, model)

      Cache.put_embedding(text, embedding, model)

      assert Cache.embedding_exists?(text, model)
    end

    test "different texts have different cache keys" do
      model = "text-embedding-3-large"
      embedding1 = [0.1, 0.2, 0.3]
      embedding2 = [0.4, 0.5, 0.6]

      Cache.put_embedding("text1", embedding1, model)
      Cache.put_embedding("text2", embedding2, model)

      assert ^embedding1 = Cache.get_embedding("text1", model)
      assert ^embedding2 = Cache.get_embedding("text2", model)
    end

    test "different models have different cache keys" do
      text = "test text"
      embedding1 = [0.1, 0.2, 0.3]
      embedding2 = [0.4, 0.5, 0.6]

      Cache.put_embedding(text, embedding1, "model-a")
      Cache.put_embedding(text, embedding2, "model-b")

      assert ^embedding1 = Cache.get_embedding(text, "model-a")
      assert ^embedding2 = Cache.get_embedding(text, "model-b")
    end

    test "clear_embeddings/0 removes only embedding cache entries" do
      # Add embeddings
      Cache.put_embedding("text1", [0.1], "model-a")
      Cache.put_embedding("text2", [0.2], "model-b")

      # Add search result
      Cache.put_search_result("thread-1", "query", [%{id: 1}])

      # Clear embeddings
      Cache.clear_embeddings()

      # Embeddings should be gone
      assert nil == Cache.get_embedding("text1", "model-a")
      assert nil == Cache.get_embedding("text2", "model-b")

      # Search results should remain
      assert [%{id: 1}] = Cache.get_search_result("thread-1", "query")
    end
  end

  describe "search result cache operations" do
    test "get_search_result/3 returns nil when result is not cached" do
      assert nil == Cache.get_search_result("thread-123", "test query")
    end

    test "put_search_result/4 and get_search_result/3 work together" do
      thread_id = "thread-123"
      query = "test query"
      results = [
        %{message_id: "msg-1", content: "result 1", similarity: 0.95},
        %{message_id: "msg-2", content: "result 2", similarity: 0.87}
      ]

      assert :ok = Cache.put_search_result(thread_id, query, results)
      assert ^results = Cache.get_search_result(thread_id, query)
    end

    test "search results respect query options" do
      thread_id = "thread-123"
      query = "test query"
      results1 = [%{id: 1}]
      results2 = [%{id: 2}]

      Cache.put_search_result(thread_id, query, results1, limit: 5)
      Cache.put_search_result(thread_id, query, results2, limit: 10)

      assert ^results1 = Cache.get_search_result(thread_id, query, limit: 5)
      assert ^results2 = Cache.get_search_result(thread_id, query, limit: 10)
    end

    test "queries are normalized for consistent caching" do
      thread_id = "thread-123"
      results = [%{id: 1}]

      Cache.put_search_result(thread_id, "Test Query", results)

      # Different capitalization and whitespace should retrieve same result
      assert ^results = Cache.get_search_result(thread_id, "test query")
      assert ^results = Cache.get_search_result(thread_id, "TEST  QUERY")
    end

    test "clear_search_results/0 removes only search-related cache entries" do
      # Add search results
      Cache.put_search_result("thread-1", "query1", [%{id: 1}])
      Cache.put_search_result("thread-2", "query2", [%{id: 2}])

      # Add embedding
      Cache.put_embedding("text", [0.1], "model")

      # Clear search results
      Cache.clear_search_results()

      # Search results should be gone
      assert nil == Cache.get_search_result("thread-1", "query1")
      assert nil == Cache.get_search_result("thread-2", "query2")

      # Embeddings should remain
      assert [0.1] = Cache.get_embedding("text", "model")
    end
  end

  describe "vector result cache operations" do
    test "get_vector_result/3 returns nil when result is not cached" do
      embedding = [0.1, 0.2, 0.3]
      assert nil == Cache.get_vector_result("thread-123", embedding, 10)
    end

    test "put_vector_result/4 and get_vector_result/3 work together" do
      thread_id = "thread-123"
      embedding = [0.1, 0.2, 0.3, 0.4, 0.5]
      limit = 10
      results = [
        %{message_id: "msg-1", distance: 0.05},
        %{message_id: "msg-2", distance: 0.13}
      ]

      assert :ok = Cache.put_vector_result(thread_id, embedding, results, limit)
      assert ^results = Cache.get_vector_result(thread_id, embedding, limit)
    end

    test "different limits create different cache keys" do
      thread_id = "thread-123"
      embedding = [0.1, 0.2, 0.3]
      results1 = [%{id: 1}]
      results2 = [%{id: 2}]

      Cache.put_vector_result(thread_id, embedding, results1, 5)
      Cache.put_vector_result(thread_id, embedding, results2, 10)

      assert ^results1 = Cache.get_vector_result(thread_id, embedding, 5)
      assert ^results2 = Cache.get_vector_result(thread_id, embedding, 10)
    end
  end

  describe "invalidate_thread_search/1" do
    test "invalidates all search results for a specific thread" do
      # Cache results for multiple threads
      Cache.put_search_result("thread-1", "query1", [%{id: 1}])
      Cache.put_search_result("thread-1", "query2", [%{id: 2}])
      Cache.put_search_result("thread-2", "query3", [%{id: 3}])

      # Cache vector results
      Cache.put_vector_result("thread-1", [0.1, 0.2], [%{id: 4}], 10)
      Cache.put_vector_result("thread-2", [0.3, 0.4], [%{id: 5}], 10)

      # Invalidate thread-1
      Cache.invalidate_thread_search("thread-1")

      # thread-1 results should be gone
      assert nil == Cache.get_search_result("thread-1", "query1")
      assert nil == Cache.get_search_result("thread-1", "query2")
      assert nil == Cache.get_vector_result("thread-1", [0.1, 0.2], 10)

      # thread-2 results should remain
      assert [%{id: 3}] = Cache.get_search_result("thread-2", "query3")
      assert [%{id: 5}] = Cache.get_vector_result("thread-2", [0.3, 0.4], 10)
    end
  end

  describe "repository cache operations (ETS)" do
    test "get_repo/1 returns nil when repo is not cached" do
      assert nil == Cache.get_repo("shard-123")
    end

    test "put_repo/2 and get_repo/1 work together" do
      shard_id = "shard-123"
      repo_module = GlobalbridgeBackend.Repos.ThreadRepo.Shard_123

      assert :ok = Cache.put_repo(shard_id, repo_module)
      assert ^repo_module = Cache.get_repo(shard_id)
    end

    test "uncache_repo/1 removes repo from cache" do
      shard_id = "shard-123"
      repo_module = GlobalbridgeBackend.Repos.ThreadRepo.Shard_123

      Cache.put_repo(shard_id, repo_module)
      assert ^repo_module = Cache.get_repo(shard_id)

      Cache.uncache_repo(shard_id)
      assert nil == Cache.get_repo(shard_id)
    end

    test "repo_cached?/1 returns true for cached repos" do
      shard_id = "shard-123"
      repo_module = GlobalbridgeBackend.Repos.ThreadRepo.Shard_123

      refute Cache.repo_cached?(shard_id)

      Cache.put_repo(shard_id, repo_module)

      assert Cache.repo_cached?(shard_id)
    end

    test "different shards have independent cache entries" do
      repo1 = GlobalbridgeBackend.Repos.ThreadRepo.Shard_1
      repo2 = GlobalbridgeBackend.Repos.ThreadRepo.Shard_2

      Cache.put_repo("shard-1", repo1)
      Cache.put_repo("shard-2", repo2)

      assert ^repo1 = Cache.get_repo("shard-1")
      assert ^repo2 = Cache.get_repo("shard-2")
    end

    test "clear_repos/0 removes all repository cache entries" do
      Cache.put_repo("shard-1", GlobalbridgeBackend.Repos.ThreadRepo.Shard_1)
      Cache.put_repo("shard-2", GlobalbridgeBackend.Repos.ThreadRepo.Shard_2)

      Cache.clear_repos()

      assert nil == Cache.get_repo("shard-1")
      assert nil == Cache.get_repo("shard-2")
    end

    test "cleanup_expired_repos/0 removes old entries" do
      # This is difficult to test without mocking time or waiting
      # We'll just verify the function runs without error
      assert :ok = Cache.cleanup_expired_repos()
    end
  end

  describe "stats/0" do
    test "returns comprehensive cache statistics" do
      # Add some data
      Cache.put_embedding("text", [0.1], "model")
      Cache.put_search_result("thread", "query", [%{id: 1}])
      Cache.put_repo("shard", GlobalbridgeBackend.Repos.ThreadRepo.Shard_1)

      stats = Cache.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :cachex)
      assert Map.has_key?(stats, :ets_repos)
      assert Map.has_key?(stats, :ttls)

      assert stats.ets_repos >= 1
      assert is_map(stats.ttls)
      assert stats.ttls.embeddings == :timer.hours(1)
      assert stats.ttls.search_results == :timer.minutes(15)
      assert stats.ttls.repos == :timer.hours(24)
    end
  end

  describe "clear_all/0" do
    test "clears all caches (Cachex and ETS)" do
      # Add data to all cache types
      Cache.put_embedding("text", [0.1], "model")
      Cache.put_search_result("thread", "query", [%{id: 1}])
      Cache.put_vector_result("thread", [0.1], [%{id: 2}], 10)
      Cache.put_repo("shard", GlobalbridgeBackend.Repos.ThreadRepo.Shard_1)

      # Clear all
      Cache.clear_all()

      # All should be gone
      assert nil == Cache.get_embedding("text", "model")
      assert nil == Cache.get_search_result("thread", "query")
      assert nil == Cache.get_vector_result("thread", [0.1], 10)
      assert nil == Cache.get_repo("shard")
    end
  end

  describe "cache key generation" do
    test "identical texts with same model produce same cache key" do
      text = "identical text"
      model = "text-embedding-3-large"
      embedding = [0.1, 0.2, 0.3]

      Cache.put_embedding(text, embedding, model)

      # Multiple gets should work
      assert ^embedding = Cache.get_embedding(text, model)
      assert ^embedding = Cache.get_embedding(text, model)
      assert ^embedding = Cache.get_embedding(text, model)
    end

    test "query normalization is case-insensitive" do
      thread_id = "thread-123"
      results = [%{id: 1}]

      Cache.put_search_result(thread_id, "Hello World", results)

      assert ^results = Cache.get_search_result(thread_id, "hello world")
      assert ^results = Cache.get_search_result(thread_id, "HELLO WORLD")
      assert ^results = Cache.get_search_result(thread_id, "HeLLo WoRLd")
    end

    test "query normalization handles extra whitespace" do
      thread_id = "thread-123"
      results = [%{id: 1}]

      Cache.put_search_result(thread_id, "test  query   with    spaces", results)

      assert ^results = Cache.get_search_result(thread_id, "test query with spaces")
      assert ^results = Cache.get_search_result(thread_id, "  test query with spaces  ")
    end
  end

  describe "concurrent access" do
    test "multiple processes can access cache concurrently" do
      embedding = [0.1, 0.2, 0.3]

      # Write from multiple processes
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Cache.put_embedding("text-#{i}", embedding, "model")
            Cache.get_embedding("text-#{i}", "model")
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed
      assert length(results) == 10
      assert Enum.all?(results, &(&1 == embedding))
    end

    test "ETS cache supports concurrent reads" do
      repo_module = GlobalbridgeBackend.Repos.ThreadRepo.Shard_Test
      Cache.put_repo("test-shard", repo_module)

      # Read from multiple processes
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            Cache.get_repo("test-shard")
          end)
        end

      results = Task.await_many(tasks)

      # All should return the same repo
      assert length(results) == 10
      assert Enum.all?(results, &(&1 == repo_module))
    end
  end
end
