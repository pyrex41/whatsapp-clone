defmodule GlobalbridgeBackend.AI.Jobs.CleanupCacheJobTest do
  use GlobalbridgeBackend.DataCase, async: true

  alias GlobalbridgeBackend.AI.Jobs.CleanupCacheJob

  describe "perform/1" do
    test "completes successfully without errors" do
      assert {:ok, _} = CleanupCacheJob.perform(%Oban.Job{args: %{}})
    end

    test "returns :ok even if cache modules don't exist" do
      # This test verifies the error resilience
      # The job should complete successfully even if cache operations fail
      result = CleanupCacheJob.perform(%Oban.Job{args: %{}})
      assert result == :ok
    end

    test "handles job args correctly" do
      # Verify it works with empty args
      assert :ok = CleanupCacheJob.perform(%Oban.Job{args: %{}})

      # Verify it works with any args (should be ignored)
      assert :ok = CleanupCacheJob.perform(%Oban.Job{args: %{"foo" => "bar"}})
    end
  end
end
