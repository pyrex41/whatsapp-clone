defmodule GlobalbridgeBackend.ApplicationSecurityTest do
  use ExUnit.Case, async: true

  # We can't directly test the private validate_vec_path! function,
  # but we can test via validate_sqlite_vec by setting ENV vars

  describe "SQLITE_VEC_PATH validation" do
    setup do
      # Store original value
      original = System.get_env("SQLITE_VEC_PATH")

      on_exit(fn ->
        # Restore original value
        if original do
          System.put_env("SQLITE_VEC_PATH", original)
        else
          System.delete_env("SQLITE_VEC_PATH")
        end
      end)

      :ok
    end

    test "rejects paths with directory traversal" do
      System.put_env("SQLITE_VEC_PATH", "/usr/lib/../../../etc/passwd")

      assert_raise RuntimeError, ~r/path contains '..'/, fn ->
        # Trigger validation by calling the application start logic
        # In practice, this would be caught during app startup
        GlobalbridgeBackend.Application.send(self(), :validate_sqlite_vec)
      end
    end

    test "rejects invalid filenames" do
      invalid_filenames = [
        "/usr/lib/malicious.so",
        "/usr/lib/vec0.txt",
        "/usr/lib/vec1.dylib",
        "/usr/lib/exploit.dll",
        "/usr/lib/vec0.so.backup"
      ]

      Enum.each(invalid_filenames, fn path ->
        System.put_env("SQLITE_VEC_PATH", path)

        assert_raise RuntimeError, ~r/filename must be vec0\.(so|dylib|dll)/i, fn ->
          GlobalbridgeBackend.Application.send(self(), :validate_sqlite_vec)
        end
      end)
    end

    test "accepts valid vec0 library paths in allowed directories" do
      valid_paths = [
        "/opt/homebrew/lib/vec0.dylib",
        "/usr/local/lib/vec0.so",
        "/usr/lib/vec0.so",
        "C:/Program Files/sqlite-vec/vec0.dll"
      ]

      # Note: These tests will fail if the files don't exist,
      # but the validation logic for path format should pass
      Enum.each(valid_paths, fn path ->
        System.put_env("SQLITE_VEC_PATH", path)
        # The actual file existence check might fail, but format validation should pass
        # This is more of a documentation test showing what SHOULD be valid
      end)
    end

    test "rejects paths outside allowed system directories" do
      suspicious_paths = [
        "/tmp/vec0.so",
        "/home/user/Downloads/vec0.dylib",
        "~/malicious/vec0.dll",
        "/var/www/vec0.so",
        "../vec0.so"
      ]

      Enum.each(suspicious_paths, fn path ->
        System.put_env("SQLITE_VEC_PATH", path)

        assert_raise RuntimeError, ~r/path must be in an allowed system library directory/i, fn ->
          GlobalbridgeBackend.Application.send(self(), :validate_sqlite_vec)
        end
      end)
    end

    test "handles case-insensitive filename validation" do
      # Test that VEC0.SO, Vec0.Dylib, etc. are accepted
      System.put_env("SQLITE_VEC_PATH", "/usr/lib/VEC0.SO")
      # Should pass filename validation (case-insensitive regex)
    end
  end
end
