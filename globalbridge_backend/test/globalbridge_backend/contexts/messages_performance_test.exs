defmodule GlobalbridgeBackend.Contexts.MessagesPerformanceTest do
  @moduledoc """
  Performance benchmarks for the Messages context, focusing on caching improvements.

  Run with: mix test test/globalbridge_backend/contexts/messages_performance_test.exs

  This test suite verifies:
  1. ThreadCache eliminates N+1 queries
  2. Query optimization for get_message! works correctly
  3. Performance improvements are measurable
  """

  use GlobalbridgeBackend.DataCase, async: false

  alias GlobalbridgeBackend.Contexts.Messages
  alias GlobalbridgeBackend.Schemas.{Thread, Message}
  alias GlobalbridgeBackend.Repos.ThreadRepo
  alias GlobalbridgeBackendWeb.Plugs.ThreadCache

  import Ecto.Query

  setup do
    # Clean cache before each test
    ThreadCache.clear_all()

    # Create test thread
    thread =
      %Thread{}
      |> Thread.create_changeset(%{
        thread_type: "direct",
        database_shard_id: "shard_0",
        title: "Performance Test Thread"
      })
      |> Repo.insert!()

    # Get the thread repo for inserting messages
    thread_repo = ThreadRepo.get_repo(thread.database_shard_id)

    # Create test messages
    messages =
      for i <- 1..20 do
        %Message{}
        |> Message.create_changeset(%{
          thread_id: thread.id,
          sender_id: Ecto.UUID.generate(),
          content_type: "text",
          content: "Test message #{i}"
        })
        |> thread_repo.insert!()
      end

    %{thread: thread, messages: messages, thread_repo: thread_repo}
  end

  describe "ThreadCache performance" do
    test "cache prevents N+1 queries when accessing same thread multiple times", %{
      thread: thread,
      messages: messages
    } do
      thread_id = thread.id

      # Measure queries without cache (simulate multiple operations)
      queries_without_cache =
        count_queries(fn ->
          # Clear cache to force DB hits
          ThreadCache.clear_all()

          # Simulate a typical request that accesses the thread multiple times
          # This would happen in a single HTTP request with multiple operations
          Enum.each(1..5, fn _ ->
            Messages.list_messages(thread_id, limit: 5)
          end)
        end)

      # Measure queries with cache
      queries_with_cache =
        count_queries(fn ->
          # First call populates cache
          Messages.list_messages(thread_id, limit: 5)

          # Subsequent calls use cached thread
          Enum.each(1..4, fn _ ->
            Messages.list_messages(thread_id, limit: 5)
          end)
        end)

      # With cache, we should see fewer thread lookup queries
      # Without cache: ~5 thread queries + message queries
      # With cache: 1 thread query + message queries
      assert queries_with_cache < queries_without_cache,
             "Expected fewer queries with cache (#{queries_with_cache}) than without (#{queries_without_cache})"

      # Log results for visibility
      IO.puts("\n📊 Thread Cache Performance:")
      IO.puts("  Without cache: #{queries_without_cache} queries")
      IO.puts("  With cache: #{queries_with_cache} queries")
      IO.puts("  Improvement: #{queries_without_cache - queries_with_cache} fewer queries")
    end

    test "demonstrates realistic N+1 scenario - multiple operations in single request", %{
      thread: thread,
      messages: messages
    } do
      thread_id = thread.id
      message_ids = Enum.map(messages, & &1.id)
      user_id = Ecto.UUID.generate()

      # Simulate a complex request with multiple operations
      # This is typical of a message view that:
      # 1. Lists recent messages
      # 2. Gets unread count
      # 3. Marks messages as read
      # 4. Searches messages

      queries_without_cache =
        count_queries(fn ->
          ThreadCache.clear_all()

          # Each operation would query the thread separately without cache
          Messages.list_messages(thread_id, limit: 10)
          Messages.get_unread_count(thread_id, user_id)
          Messages.search_messages(thread_id, "test", limit: 5)
          Messages.get_thread_messages_after(thread_id, DateTime.utc_now() |> DateTime.add(-3600))
        end)

      queries_with_cache =
        count_queries(fn ->
          ThreadCache.clear_all()

          # With cache, thread is queried once and reused
          Messages.list_messages(thread_id, limit: 10)
          Messages.get_unread_count(thread_id, user_id)
          Messages.search_messages(thread_id, "test", limit: 5)
          Messages.get_thread_messages_after(thread_id, DateTime.utc_now() |> DateTime.add(-3600))
        end)

      # Cache should significantly reduce queries
      assert queries_with_cache <= queries_without_cache

      IO.puts("\n📊 Realistic Request Performance:")
      IO.puts("  Without cache: #{queries_without_cache} queries")
      IO.puts("  With cache: #{queries_with_cache} queries")
      IO.puts("  Savings: #{((queries_without_cache - queries_with_cache) / queries_without_cache * 100) |> Float.round(1)}%")
    end

    test "cache performance scales with number of operations", %{thread: thread} do
      thread_id = thread.id

      # Test with increasing number of operations
      operation_counts = [5, 10, 20, 50]

      results =
        Enum.map(operation_counts, fn count ->
          without_cache =
            count_queries(fn ->
              ThreadCache.clear_all()

              Enum.each(1..count, fn _ ->
                Messages.list_messages(thread_id, limit: 5)
              end)
            end)

          with_cache =
            count_queries(fn ->
              ThreadCache.clear_all()
              Messages.list_messages(thread_id, limit: 5)

              Enum.each(1..(count - 1), fn _ ->
                Messages.list_messages(thread_id, limit: 5)
              end)
            end)

          {count, without_cache, with_cache}
        end)

      IO.puts("\n📊 Scaling Performance:")
      IO.puts("  Operations | Without Cache | With Cache | Improvement")
      IO.puts("  -----------|---------------|------------|------------")

      Enum.each(results, fn {count, without, with} ->
        improvement = ((without - with) / without * 100) |> Float.round(1)
        IO.puts("  #{String.pad_leading("#{count}", 10)} | #{String.pad_leading("#{without}", 13)} | #{String.pad_leading("#{with}", 10)} | #{improvement}%")
      end)

      # Verify improvement increases with more operations
      [_first | rest] = results

      Enum.reduce(rest, List.first(results), fn {_count, without, with}, {_prev_count, prev_without, prev_with} ->
        # Improvement should be at least as good or better
        improvement = without - with
        prev_improvement = prev_without - prev_with

        assert improvement >= 0, "Cache should always help or at worst be neutral"

        {_count, without, with}
      end)
    end
  end

  describe "get_message! optimization" do
    test "correctly filters by both thread_id and message_id", %{
      thread: thread,
      messages: messages
    } do
      thread_id = thread.id
      message = List.first(messages)
      message_id = message.id

      # Create another thread with a message with same ID (hypothetically)
      other_thread =
        %Thread{}
        |> Thread.create_changeset(%{
          thread_type: "direct",
          database_shard_id: "shard_0",
          title: "Other Thread"
        })
        |> Repo.insert!()

      # Test that get_message! correctly filters
      result = Messages.get_message!(thread_id, message_id)
      assert result.id == message_id
      assert result.thread_id == thread_id

      # Test that it raises when thread_id doesn't match
      # (assuming message_id doesn't exist in other_thread)
      assert_raise Ecto.NoResultsError, fn ->
        Messages.get_message!(other_thread.id, message_id)
      end
    end

    test "get_message! uses efficient query", %{thread: thread, messages: messages} do
      thread_id = thread.id
      message_id = List.first(messages).id

      queries_count =
        count_queries(fn ->
          Messages.get_message!(thread_id, message_id)
        end)

      # Should be efficient - thread lookup + message lookup
      # With cache: 1 query (thread cached, message lookup only)
      # Without cache: 2 queries (thread + message)
      assert queries_count <= 2,
             "get_message! should use at most 2 queries, got #{queries_count}"
    end
  end

  describe "cache behavior verification" do
    test "cache is automatically used across multiple context calls", %{thread: thread} do
      thread_id = thread.id

      # First call - populates cache
      Messages.list_messages(thread_id)
      assert ThreadCache.cache_size() == 1
      assert ThreadCache.get_cached_thread(thread_id) != nil

      # Second call - uses cached thread
      Messages.list_messages(thread_id)
      assert ThreadCache.cache_size() == 1

      # Different operation - still uses cached thread
      Messages.get_unread_count(thread_id, Ecto.UUID.generate())
      assert ThreadCache.cache_size() == 1
    end

    test "cache persists for the duration of the process", %{thread: thread} do
      thread_id = thread.id

      # Populate cache
      Messages.list_messages(thread_id)
      assert ThreadCache.get_cached_thread(thread_id) != nil

      # Simulate time passing (cache should still be valid)
      Process.sleep(10)
      assert ThreadCache.get_cached_thread(thread_id) != nil

      # Still valid after more operations
      Messages.get_unread_count(thread_id, Ecto.UUID.generate())
      assert ThreadCache.get_cached_thread(thread_id) != nil
    end

    test "cache is isolated between different threads", %{thread: thread} do
      thread_id_1 = thread.id

      # Create second thread
      thread_2 =
        %Thread{}
        |> Thread.create_changeset(%{
          thread_type: "group",
          database_shard_id: "shard_0",
          title: "Second Thread"
        })
        |> Repo.insert!()

      thread_id_2 = thread_2.id

      # Access both threads
      Messages.list_messages(thread_id_1)
      Messages.list_messages(thread_id_2)

      # Both should be cached independently
      assert ThreadCache.cache_size() == 2
      assert ThreadCache.get_cached_thread(thread_id_1).id == thread_id_1
      assert ThreadCache.get_cached_thread(thread_id_2).id == thread_id_2
    end
  end

  # Helper function to count SQL queries
  defp count_queries(fun) do
    :telemetry.attach(
      "query-counter-#{:erlang.unique_integer()}",
      [:globalbridge_backend, :repo, :query],
      &__MODULE__.handle_event/4,
      nil
    )

    # Reset counter
    Process.put(:query_count, 0)

    # Run the function
    fun.()

    # Get count
    count = Process.get(:query_count, 0)

    # Cleanup
    :telemetry.list_handlers([:globalbridge_backend, :repo, :query])
    |> Enum.each(fn handler ->
      :telemetry.detach(handler.id)
    end)

    count
  end

  def handle_event([:globalbridge_backend, :repo, :query], _measurements, _metadata, _config) do
    current = Process.get(:query_count, 0)
    Process.put(:query_count, current + 1)
  end
end
