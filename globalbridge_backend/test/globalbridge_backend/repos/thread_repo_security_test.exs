defmodule GlobalbridgeBackend.Repos.ThreadRepoSecurityTest do
  use GlobalbridgeBackend.DataCase, async: true

  alias GlobalbridgeBackend.Repos.ThreadRepo

  describe "sanitize_shard_id/1" do
    test "allows valid alphanumeric shard IDs" do
      assert ThreadRepo.sanitize_shard_id("abc123") == "abc123"
      assert ThreadRepo.sanitize_shard_id("thread-abc-123") == "thread-abc-123"
      assert ThreadRepo.sanitize_shard_id("thread_abc_123") == "thread_abc_123"
      assert ThreadRepo.sanitize_shard_id("ABC123DEF456") == "ABC123DEF456"
    end

    test "rejects path traversal attempts" do
      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("../../../etc/passwd")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("../../database.db")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread/../other")
      end
    end

    test "rejects special characters that could be used in attacks" do
      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread;DROP TABLE users;")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread' OR '1'='1")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread<script>alert(1)</script>")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread|rm -rf /")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread&cmd")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread$var")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread`cmd`")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread(test)")
      end
    end

    test "rejects null bytes and unicode exploits" do
      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread\0malicious")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread\u0000exploit")
      end
    end

    test "rejects non-string inputs" do
      assert_raise ArgumentError, "shard_id must be a string", fn ->
        ThreadRepo.sanitize_shard_id(nil)
      end

      assert_raise ArgumentError, "shard_id must be a string", fn ->
        ThreadRepo.sanitize_shard_id(123)
      end

      assert_raise ArgumentError, "shard_id must be a string", fn ->
        ThreadRepo.sanitize_shard_id(%{id: "test"})
      end

      assert_raise ArgumentError, "shard_id must be a string", fn ->
        ThreadRepo.sanitize_shard_id(["test"])
      end
    end

    test "rejects path-like input with slashes" do
      # We reject any input that looks like a path
      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("path/to/thread123")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("/absolute/path/thread456")
      end

      assert_raise ArgumentError, fn ->
        ThreadRepo.sanitize_shard_id("thread789\\windows\\path")
      end
    end
  end

  describe "database_path/1" do
    test "sanitizes shard_id and generates safe database path" do
      path = ThreadRepo.database_path("safe-shard-123")
      assert String.ends_with?(path, "safe-shard-123.db")
      refute String.contains?(path, "..")
    end

    test "prevents path traversal via database_path" do
      assert_raise ArgumentError, fn ->
        ThreadRepo.database_path("../../../etc/passwd")
      end
    end

    test "prevents SQL injection via database_path" do
      assert_raise ArgumentError, fn ->
        ThreadRepo.database_path("thread'; DROP TABLE messages; --")
      end
    end

    test "handles edge cases safely" do
      # Empty string should fail validation
      assert_raise ArgumentError, fn ->
        ThreadRepo.database_path("")
      end

      # Dots alone should fail
      assert_raise ArgumentError, fn ->
        ThreadRepo.database_path("...")
      end

      # Single dot should fail (special directory)
      assert_raise ArgumentError, fn ->
        ThreadRepo.database_path(".")
      end

      # Double dot should fail (parent directory)
      assert_raise ArgumentError, fn ->
        ThreadRepo.database_path("..")
      end
    end
  end

  describe "security integration tests" do
    test "get_repo refuses malicious shard IDs" do
      assert_raise ArgumentError, fn ->
        ThreadRepo.get_repo("../../../etc/passwd")
      end
    end

    test "start_repo refuses malicious shard IDs" do
      assert_raise ArgumentError, fn ->
        ThreadRepo.start_repo("thread'; DROP TABLE users; --")
      end
    end

    test "multiple valid shard IDs work correctly" do
      # Test that legitimate use cases still work
      shard_ids = ["test-shard-1", "test_shard_2", "testShard3", "TESTSHARD4"]

      Enum.each(shard_ids, fn shard_id ->
        sanitized = ThreadRepo.sanitize_shard_id(shard_id)
        assert is_binary(sanitized)
        assert String.match?(sanitized, ~r/^[a-zA-Z0-9_-]+$/)
      end)
    end
  end

  describe "SQL injection prevention" do
    test "sanitized IDs cannot inject SQL" do
      malicious_inputs = [
        "thread' OR '1'='1",
        "thread'; SELECT * FROM users; --",
        "thread\"; DROP TABLE messages; --",
        "thread' UNION SELECT password FROM users --",
        "thread\\' OR 1=1 --"
      ]

      Enum.each(malicious_inputs, fn input ->
        assert_raise ArgumentError, fn ->
          ThreadRepo.sanitize_shard_id(input)
        end
      end)
    end
  end

  describe "command injection prevention" do
    test "sanitized IDs cannot execute system commands" do
      command_injections = [
        "thread;ls -la",
        "thread|cat /etc/passwd",
        "thread&whoami",
        "thread`rm -rf /`",
        "thread$(reboot)",
        "thread> /tmp/pwned"
      ]

      Enum.each(command_injections, fn input ->
        assert_raise ArgumentError, fn ->
          ThreadRepo.sanitize_shard_id(input)
        end
      end)
    end
  end
end
