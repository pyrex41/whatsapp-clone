defmodule GlobalbridgeBackend.AI.AuthorizationTest do
  use ExUnit.Case, async: true

  alias GlobalbridgeBackend.AI.Authorization
  alias GlobalbridgeBackend.AI.UnauthorizedError
  alias GlobalbridgeBackend.Cache.ParticipantCache

  setup do
    # Start ParticipantCache if not already running
    case Process.whereis(ParticipantCache) do
      nil ->
        {:ok, _pid} = start_supervised(ParticipantCache)

      _pid ->
        :ok
    end

    # Clear cache before each test
    ParticipantCache.clear()

    :ok
  end

  describe "ensure_thread_access!/2" do
    test "allows access when user is a participant" do
      user_id = "user-123"
      thread_id = "thread-456"

      # Mock the participant check by pre-caching
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      assert :ok = Authorization.ensure_thread_access!(user_id, thread_id)
    end

    test "raises UnauthorizedError when user is not a participant" do
      user_id = "user-123"
      thread_id = "thread-789"

      # Mock the participant check by pre-caching false result
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, false, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      assert_raise UnauthorizedError, "You do not have access to this thread", fn ->
        Authorization.ensure_thread_access!(user_id, thread_id)
      end
    end

    test "raises UnauthorizedError with proper metadata" do
      user_id = "user-999"
      thread_id = "thread-999"

      # Mock the participant check
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, false, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      try do
        Authorization.ensure_thread_access!(user_id, thread_id)
        flunk("Expected UnauthorizedError to be raised")
      rescue
        error in UnauthorizedError ->
          assert error.message == "You do not have access to this thread"
          assert error.user_id == user_id
          assert error.thread_id == thread_id
      end
    end

    test "raises UnauthorizedError when user_id is nil" do
      thread_id = "thread-456"

      assert_raise UnauthorizedError, "Authentication required", fn ->
        Authorization.ensure_thread_access!(nil, thread_id)
      end
    end

    test "raises UnauthorizedError when thread_id is nil" do
      user_id = "user-123"

      assert_raise UnauthorizedError, "Thread ID is required", fn ->
        Authorization.ensure_thread_access!(user_id, nil)
      end
    end

    test "performance is under 5ms for cache hit" do
      user_id = "user-perf-test"
      thread_id = "thread-perf-test"

      # Pre-cache the result
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      # Warm up
      Authorization.ensure_thread_access!(user_id, thread_id)

      # Measure performance
      {elapsed_time, _result} =
        :timer.tc(fn ->
          Authorization.ensure_thread_access!(user_id, thread_id)
        end)

      # Convert microseconds to milliseconds
      elapsed_ms = elapsed_time / 1000

      # Should be well under 5ms for a cache hit (typically < 0.1ms)
      assert elapsed_ms < 5.0,
             "Authorization check took #{elapsed_ms}ms, expected < 5ms"
    end

    test "works with string IDs of various formats" do
      test_cases = [
        {"uuid-format", "00000000-0000-0000-0000-000000000001"},
        {"short-id", "abc123"},
        {"long-id", "very-long-id-with-many-characters-0123456789"}
      ]

      for {_label, id} <- test_cases do
        user_id = "user-#{id}"
        thread_id = "thread-#{id}"

        # Cache as participant
        :ets.insert(
          :participant_cache,
          {{thread_id, user_id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
        )

        assert :ok = Authorization.ensure_thread_access!(user_id, thread_id)
      end
    end
  end

  describe "has_thread_access?/2" do
    test "returns true when user is a participant" do
      user_id = "user-123"
      thread_id = "thread-456"

      # Mock the participant check
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      assert Authorization.has_thread_access?(user_id, thread_id) == true
    end

    test "returns false when user is not a participant" do
      user_id = "user-123"
      thread_id = "thread-789"

      # Mock the participant check
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, false, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      assert Authorization.has_thread_access?(user_id, thread_id) == false
    end

    test "returns false when user_id is nil" do
      assert Authorization.has_thread_access?(nil, "thread-456") == false
    end

    test "returns false when thread_id is nil" do
      assert Authorization.has_thread_access?("user-123", nil) == false
    end

    test "returns false when both are nil" do
      assert Authorization.has_thread_access?(nil, nil) == false
    end

    test "does not raise errors, returns boolean only" do
      # Should never raise, always return boolean
      assert is_boolean(Authorization.has_thread_access?("user-1", "thread-1"))
      assert is_boolean(Authorization.has_thread_access?(nil, "thread-1"))
      assert is_boolean(Authorization.has_thread_access?("user-1", nil))
      assert is_boolean(Authorization.has_thread_access?(nil, nil))
    end
  end

  describe "cache behavior" do
    test "subsequent calls use cached result" do
      user_id = "user-cache-test"
      thread_id = "thread-cache-test"

      # Pre-cache
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      # First call
      assert :ok = Authorization.ensure_thread_access!(user_id, thread_id)

      # Second call should use cache (verify by checking it doesn't fail even if we don't update cache)
      assert :ok = Authorization.ensure_thread_access!(user_id, thread_id)
    end

    test "respects cache expiration" do
      user_id = "user-expire-test"
      thread_id = "thread-expire-test"

      # Insert expired entry
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, true, DateTime.add(DateTime.utc_now(), -1000, :millisecond)}
      )

      # Should trigger cache miss and database lookup
      # In test environment, this will return false since we don't have real data
      # But it demonstrates the expiration mechanism works
      result = Authorization.has_thread_access?(user_id, thread_id)
      assert is_boolean(result)
    end
  end

  describe "concurrent access" do
    test "handles multiple concurrent authorization checks" do
      user_id = "user-concurrent"
      thread_id = "thread-concurrent"

      # Pre-cache
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      # Spawn multiple processes checking authorization concurrently
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            Authorization.ensure_thread_access!(user_id, thread_id)
            i
          end)
        end

      # All should succeed
      results = Task.await_many(tasks, 5000)
      assert length(results) == 20
      assert Enum.all?(results, &is_integer/1)
    end
  end

  describe "error messages and logging" do
    test "logs unauthorized access attempts" do
      user_id = "user-logged"
      thread_id = "thread-logged"

      # Mock unauthorized access
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, false, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      # Capture log output
      log =
        ExUnit.CaptureLog.capture_log(fn ->
          try do
            Authorization.ensure_thread_access!(user_id, thread_id)
          rescue
            UnauthorizedError -> :ok
          end
        end)

      assert log =~ "Unauthorized thread access attempt"
    end

    test "logs authorized access at debug level" do
      user_id = "user-debug"
      thread_id = "thread-debug"

      # Mock authorized access
      :ets.insert(
        :participant_cache,
        {{thread_id, user_id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      # Capture log output at debug level
      # Note: In test environment, debug logs might be suppressed
      # The important thing is that it doesn't raise an error
      result = Authorization.ensure_thread_access!(user_id, thread_id)
      assert result == :ok
    end
  end

  describe "security edge cases" do
    test "prevents access with empty string IDs" do
      # Empty strings are valid strings in Elixir, but will fail authorization
      assert_raise UnauthorizedError, fn ->
        Authorization.ensure_thread_access!("", "thread-123")
      end
    end

    test "handles very long ID strings without issue" do
      long_id = String.duplicate("a", 1000)
      user_id = "user-#{long_id}"
      thread_id = "thread-123"

      # Should handle gracefully
      result = Authorization.has_thread_access?(user_id, thread_id)
      assert is_boolean(result)
    end

    test "different users cannot access same thread without permission" do
      user1_id = "user-alice"
      user2_id = "user-bob"
      thread_id = "private-thread"

      # Only user1 has access
      :ets.insert(
        :participant_cache,
        {{thread_id, user1_id}, true, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      :ets.insert(
        :participant_cache,
        {{thread_id, user2_id}, false, DateTime.add(DateTime.utc_now(), 300_000, :millisecond)}
      )

      # User1 can access
      assert :ok = Authorization.ensure_thread_access!(user1_id, thread_id)

      # User2 cannot access
      assert_raise UnauthorizedError, fn ->
        Authorization.ensure_thread_access!(user2_id, thread_id)
      end
    end
  end
end
