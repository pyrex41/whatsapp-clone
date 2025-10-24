defmodule GlobalbridgeBackendWeb.Plugs.ThreadCacheTest do
  use ExUnit.Case, async: true
  import Plug.Test

  alias GlobalbridgeBackendWeb.Plugs.ThreadCache
  alias GlobalbridgeBackend.Schemas.Thread

  describe "ThreadCache" do
    setup do
      # Clear cache before each test
      ThreadCache.clear_all()
      :ok
    end

    test "get_cached_thread returns nil for uncached thread" do
      assert ThreadCache.get_cached_thread("thread-123") == nil
    end

    test "cache_thread stores and retrieves thread" do
      thread = %Thread{
        id: "thread-123",
        thread_type: "direct",
        database_shard_id: "shard-1"
      }

      # Cache the thread
      result = ThreadCache.cache_thread(thread)

      # Verify it returns the thread for chaining
      assert result.id == "thread-123"

      # Verify we can retrieve it
      cached = ThreadCache.get_cached_thread("thread-123")
      assert cached.id == "thread-123"
      assert cached.thread_type == "direct"
      assert cached.database_shard_id == "shard-1"
    end

    test "cache_thread overwrites existing cached thread" do
      thread1 = %Thread{
        id: "thread-123",
        thread_type: "direct",
        database_shard_id: "shard-1",
        title: "Original"
      }

      thread2 = %Thread{
        id: "thread-123",
        thread_type: "group",
        database_shard_id: "shard-2",
        title: "Updated"
      }

      # Cache first version
      ThreadCache.cache_thread(thread1)
      cached1 = ThreadCache.get_cached_thread("thread-123")
      assert cached1.title == "Original"

      # Cache updated version
      ThreadCache.cache_thread(thread2)
      cached2 = ThreadCache.get_cached_thread("thread-123")
      assert cached2.title == "Updated"
      assert cached2.thread_type == "group"
      assert cached2.database_shard_id == "shard-2"
    end

    test "multiple threads can be cached independently" do
      thread1 = %Thread{id: "thread-1", thread_type: "direct", database_shard_id: "shard-1"}
      thread2 = %Thread{id: "thread-2", thread_type: "group", database_shard_id: "shard-2"}
      thread3 = %Thread{id: "thread-3", thread_type: "direct", database_shard_id: "shard-1"}

      # Cache all threads
      ThreadCache.cache_thread(thread1)
      ThreadCache.cache_thread(thread2)
      ThreadCache.cache_thread(thread3)

      # Verify all are cached independently
      assert ThreadCache.get_cached_thread("thread-1").id == "thread-1"
      assert ThreadCache.get_cached_thread("thread-2").id == "thread-2"
      assert ThreadCache.get_cached_thread("thread-3").id == "thread-3"

      # Verify correct attributes
      assert ThreadCache.get_cached_thread("thread-1").thread_type == "direct"
      assert ThreadCache.get_cached_thread("thread-2").thread_type == "group"
      assert ThreadCache.get_cached_thread("thread-3").thread_type == "direct"
    end

    test "clear_thread removes specific thread from cache" do
      thread1 = %Thread{id: "thread-1", thread_type: "direct", database_shard_id: "shard-1"}
      thread2 = %Thread{id: "thread-2", thread_type: "group", database_shard_id: "shard-2"}

      # Cache both threads
      ThreadCache.cache_thread(thread1)
      ThreadCache.cache_thread(thread2)

      # Clear thread-1
      ThreadCache.clear_thread("thread-1")

      # Verify thread-1 is cleared but thread-2 remains
      assert ThreadCache.get_cached_thread("thread-1") == nil
      assert ThreadCache.get_cached_thread("thread-2").id == "thread-2"
    end

    test "clear_all removes all cached threads" do
      thread1 = %Thread{id: "thread-1", thread_type: "direct", database_shard_id: "shard-1"}
      thread2 = %Thread{id: "thread-2", thread_type: "group", database_shard_id: "shard-2"}
      thread3 = %Thread{id: "thread-3", thread_type: "direct", database_shard_id: "shard-1"}

      # Cache multiple threads
      ThreadCache.cache_thread(thread1)
      ThreadCache.cache_thread(thread2)
      ThreadCache.cache_thread(thread3)

      # Verify all are cached
      assert ThreadCache.cache_size() == 3

      # Clear all
      ThreadCache.clear_all()

      # Verify all are cleared
      assert ThreadCache.get_cached_thread("thread-1") == nil
      assert ThreadCache.get_cached_thread("thread-2") == nil
      assert ThreadCache.get_cached_thread("thread-3") == nil
      assert ThreadCache.cache_size() == 0
    end

    test "cache_size returns correct count" do
      assert ThreadCache.cache_size() == 0

      # Add one thread
      ThreadCache.cache_thread(%Thread{
        id: "thread-1",
        thread_type: "direct",
        database_shard_id: "shard-1"
      })

      assert ThreadCache.cache_size() == 1

      # Add another thread
      ThreadCache.cache_thread(%Thread{
        id: "thread-2",
        thread_type: "group",
        database_shard_id: "shard-2"
      })

      assert ThreadCache.cache_size() == 2

      # Overwriting doesn't increase count
      ThreadCache.cache_thread(%Thread{
        id: "thread-1",
        thread_type: "direct",
        database_shard_id: "shard-1",
        title: "Updated"
      })

      assert ThreadCache.cache_size() == 2

      # Clear one thread
      ThreadCache.clear_thread("thread-1")
      assert ThreadCache.cache_size() == 1

      # Clear all
      ThreadCache.clear_all()
      assert ThreadCache.cache_size() == 0
    end

    test "cache is process-local" do
      parent = self()

      # Cache in parent process
      parent_thread = %Thread{
        id: "parent-thread",
        thread_type: "direct",
        database_shard_id: "shard-1"
      }

      ThreadCache.cache_thread(parent_thread)
      assert ThreadCache.get_cached_thread("parent-thread") != nil

      # Spawn child process
      child_task =
        Task.async(fn ->
          # Cache should be empty in child process
          assert ThreadCache.get_cached_thread("parent-thread") == nil
          assert ThreadCache.cache_size() == 0

          # Cache in child process
          child_thread = %Thread{
            id: "child-thread",
            thread_type: "group",
            database_shard_id: "shard-2"
          }

          ThreadCache.cache_thread(child_thread)
          assert ThreadCache.get_cached_thread("child-thread") != nil
          assert ThreadCache.cache_size() == 1

          send(parent, :child_done)
        end)

      # Wait for child
      Task.await(child_task)
      assert_receive :child_done

      # Verify parent cache is unchanged
      assert ThreadCache.get_cached_thread("parent-thread") != nil
      assert ThreadCache.get_cached_thread("child-thread") == nil
      assert ThreadCache.cache_size() == 1
    end

    test "plug passes connection through unchanged" do
      # Use Plug.Test to create a proper test connection
      conn = conn(:get, "/api/threads")

      # Call plug
      result_conn = ThreadCache.call(conn, [])

      # Verify connection is unchanged (same reference)
      assert result_conn == conn
      assert result_conn.halted == false
    end

    test "init returns opts unchanged" do
      assert ThreadCache.init([]) == []
      assert ThreadCache.init(some: :opts) == [some: :opts]
    end
  end

  describe "ThreadCache performance characteristics" do
    test "cache retrieval is faster than database lookup" do
      # This is a logical test - we don't actually measure timing here
      # but we verify the behavior that would lead to performance gains

      thread = %Thread{
        id: "perf-test-thread",
        thread_type: "direct",
        database_shard_id: "shard-1"
      }

      # First call - simulates DB hit
      ThreadCache.cache_thread(thread)

      # Subsequent calls - simulate cache hits
      cached1 = ThreadCache.get_cached_thread("perf-test-thread")
      cached2 = ThreadCache.get_cached_thread("perf-test-thread")
      cached3 = ThreadCache.get_cached_thread("perf-test-thread")

      # All return the same cached object (no additional DB queries)
      assert cached1 == thread
      assert cached2 == thread
      assert cached3 == thread
    end

    test "demonstrates N+1 prevention pattern" do
      # Simulate a request that accesses the same thread multiple times
      thread = %Thread{
        id: "n-plus-one-test",
        thread_type: "direct",
        database_shard_id: "shard-1"
      }

      # First access - cache miss (DB query)
      ThreadCache.cache_thread(thread)
      first_access = ThreadCache.get_cached_thread("n-plus-one-test")
      assert first_access != nil

      # Simulate multiple subsequent accesses within same request
      # (e.g., list_messages, mark_as_read, get_unread_count)
      accesses =
        for _ <- 1..10 do
          ThreadCache.get_cached_thread("n-plus-one-test")
        end

      # All accesses return the cached thread (no additional DB queries)
      assert Enum.all?(accesses, &(&1.id == "n-plus-one-test"))

      # Verify cache was only populated once
      assert ThreadCache.cache_size() == 1
    end
  end
end
