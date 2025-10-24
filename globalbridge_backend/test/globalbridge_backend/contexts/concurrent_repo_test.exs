defmodule GlobalbridgeBackend.Contexts.ConcurrentRepoTest do
  use GlobalbridgeBackend.DataCase, async: false

  alias GlobalbridgeBackend.Contexts.Messages
  alias GlobalbridgeBackend.Repo

  @moduletag :integration

  describe "concurrent per-thread repo creation" do
    setup do
      # Create test user and thread
      user = insert(:user)
      thread = insert(:thread)
      insert(:participant, thread: thread, user: user)

      {:ok, user: user, thread: thread}
    end

    test "creates multiple thread repos concurrently without conflicts", %{
      user: user,
      thread: thread
    } do
      # Spawn 10 concurrent tasks that each try to access the thread repo
      tasks =
        1..10
        |> Enum.map(fn i ->
          Task.async(fn ->
            # Each task tries to create a message, which will trigger repo creation
            {:ok, message} =
              Messages.create_message(%{
                thread_id: thread.id,
                sender_id: user.id,
                content: "Concurrent message #{i}",
                client_generated_id: UUID.uuid4()
              })

            message
          end)
        end)

      # Wait for all tasks to complete
      messages = Task.await_many(tasks, 10_000)

      # Verify all messages were created successfully
      assert length(messages) == 10

      # Verify all messages have unique IDs
      message_ids = Enum.map(messages, & &1.id)
      assert length(Enum.uniq(message_ids)) == 10

      # Verify we can query all messages from the thread repo
      active_repos = Messages.list_active_repos()
      thread_repo = Enum.find(active_repos, fn repo -> repo.thread_id == thread.id end)

      assert thread_repo != nil

      # Query messages using the thread repo
      messages_from_repo =
        thread_repo.repo
        |> Repo.all(GlobalbridgeBackend.Contexts.Message)

      assert length(messages_from_repo) >= 10
    end

    test "handles concurrent repo access for different threads", %{user: user} do
      # Create multiple threads
      threads = for _ <- 1..5, do: insert(:thread)

      Enum.each(threads, fn thread ->
        insert(:participant, thread: thread, user: user)
      end)

      # Create messages concurrently across different threads
      tasks =
        threads
        |> Enum.with_index()
        |> Enum.flat_map(fn {thread, thread_idx} ->
          1..3
          |> Enum.map(fn msg_idx ->
            Task.async(fn ->
              Messages.create_message(%{
                thread_id: thread.id,
                sender_id: user.id,
                content: "Thread #{thread_idx} message #{msg_idx}",
                client_generated_id: UUID.uuid4()
              })
            end)
          end)
        end)

      # Wait for all tasks
      results = Task.await_many(tasks, 15_000)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _message} -> true
               _ -> false
             end)

      # Verify we have repos for all threads
      active_repos = Messages.list_active_repos()
      assert length(active_repos) >= 5
    end

    test "sqlite-vec extension loads correctly for new repos", %{user: user, thread: thread} do
      # Create a message to trigger repo creation
      {:ok, _message} =
        Messages.create_message(%{
          thread_id: thread.id,
          sender_id: user.id,
          content: "Test message for vector extension",
          client_generated_id: UUID.uuid4()
        })

      # Get the thread repo
      active_repos = Messages.list_active_repos()
      thread_repo = Enum.find(active_repos, fn repo -> repo.thread_id == thread.id end)

      assert thread_repo != nil

      # Verify the repo can execute vector operations (if vec0 is loaded)
      # This will succeed if sqlite-vec is properly loaded
      # Note: This test may be skipped if SQLITE_VEC_PATH is not set
      if System.get_env("SQLITE_VEC_PATH") do
        # Try a simple vector operation to verify extension is loaded
        result =
          thread_repo.repo.query!(
            "SELECT vec_version()",
            []
          )

        assert result.num_rows == 1
      end
    end
  end
end
