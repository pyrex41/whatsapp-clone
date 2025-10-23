defmodule GlobalbridgeBackend.Contexts.ThreadsTest do
  use GlobalbridgeBackend.DataCase

  alias GlobalbridgeBackend.Contexts.Threads
  alias GlobalbridgeBackend.Schemas.{Thread, ThreadParticipant, User}

  describe "list_threads/1" do
    setup do
      # Create test users
      user1 = insert(:user)
      user2 = insert(:user)

      # Create threads
      {:ok, thread1} =
        create_thread_with_participants([user1.id, user2.id], %{thread_type: "direct"})

      {:ok, thread2} =
        create_thread_with_participants([user1.id, user2.id], %{
          thread_type: "group",
          title: "Test Group"
        })

      {:ok, archived_thread} =
        create_thread_with_participants([user1.id], %{thread_type: "direct", is_archived: true})

      %{
        user1: user1,
        user2: user2,
        thread1: thread1,
        thread2: thread2,
        archived_thread: archived_thread
      }
    end

    test "lists all threads", %{
      thread1: thread1,
      thread2: thread2,
      archived_thread: archived_thread
    } do
      threads = Threads.list_threads()
      thread_ids = Enum.map(threads, & &1.id)

      assert length(threads) == 3
      assert thread1.id in thread_ids
      assert thread2.id in thread_ids
      assert archived_thread.id in thread_ids
    end

    test "filters by archived status" do
      threads = Threads.list_threads(is_archived: false)
      assert length(threads) == 2

      archived_threads = Threads.list_threads(is_archived: true)
      assert length(archived_threads) == 1
    end

    test "filters by thread type", %{thread1: thread1, thread2: thread2} do
      direct_threads = Threads.list_threads(thread_type: "direct")
      assert length(direct_threads) == 2

      group_threads = Threads.list_threads(thread_type: "group")
      assert length(group_threads) == 1
      assert hd(group_threads).id == thread2.id
    end

    test "supports pagination" do
      page1 = Threads.list_threads(limit: 1, offset: 0)
      page2 = Threads.list_threads(limit: 1, offset: 1)

      assert length(page1) == 1
      assert length(page2) == 1
      assert hd(page1).id != hd(page2).id
    end

    test "supports custom ordering" do
      threads = Threads.list_threads(order_by: {:inserted_at, :asc})
      assert length(threads) == 3
    end
  end

  describe "get_thread!/1" do
    test "returns thread with id" do
      {:ok, thread} =
        create_thread_with_participants([insert(:user).id], %{thread_type: "direct"})

      found_thread = Threads.get_thread!(thread.id)

      assert found_thread.id == thread.id
      assert is_list(found_thread.thread_participants)
    end

    test "raises error when thread not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Threads.get_thread!("non-existent-id")
      end
    end
  end

  describe "get_thread/1" do
    test "returns thread with id" do
      {:ok, thread} =
        create_thread_with_participants([insert(:user).id], %{thread_type: "direct"})

      found_thread = Threads.get_thread(thread.id)

      assert found_thread.id == thread.id
    end

    test "returns nil when thread not found" do
      assert Threads.get_thread("non-existent-id") == nil
    end
  end

  describe "create_thread/1" do
    test "creates direct message thread with valid attributes" do
      user1 = insert(:user)
      user2 = insert(:user)

      attrs = %{
        thread_type: "direct",
        participant_ids: [user1.id, user2.id]
      }

      assert {:ok, %Thread{} = thread} = Threads.create_thread(attrs)
      assert thread.thread_type == "direct"
      assert thread.database_shard_id != nil
      assert length(thread.thread_participants) == 2
    end

    test "creates group thread with title" do
      user1 = insert(:user)
      user2 = insert(:user)

      attrs = %{
        thread_type: "group",
        title: "Test Group",
        participant_ids: [user1.id, user2.id]
      }

      assert {:ok, %Thread{} = thread} = Threads.create_thread(attrs)
      assert thread.thread_type == "group"
      assert thread.title == "Test Group"
    end

    test "fails with invalid thread type" do
      attrs = %{
        thread_type: "invalid",
        participant_ids: [insert(:user).id]
      }

      assert {:error, changeset} = Threads.create_thread(attrs)
      assert "is invalid" in errors_on(changeset).thread_type
    end

    test "generates unique shard IDs" do
      user = insert(:user)
      attrs = %{thread_type: "direct", participant_ids: [user.id]}

      {:ok, thread1} = Threads.create_thread(attrs)
      {:ok, thread2} = Threads.create_thread(attrs)

      assert thread1.database_shard_id != thread2.database_shard_id
    end
  end

  describe "update_thread/2" do
    test "updates thread with valid attributes" do
      {:ok, thread} = create_thread_with_participants([insert(:user).id], %{thread_type: "group"})

      assert {:ok, %Thread{} = updated_thread} =
               Threads.update_thread(thread, %{title: "Updated Title"})

      assert updated_thread.title == "Updated Title"
    end

    test "fails with invalid attributes" do
      {:ok, thread} =
        create_thread_with_participants([insert(:user).id], %{thread_type: "direct"})

      assert {:error, changeset} =
               Threads.update_thread(thread, %{title: String.duplicate("a", 200)})

      assert "should be at most 100 character(s)" in errors_on(changeset).title
    end
  end

  describe "delete_thread/1" do
    test "deletes thread" do
      {:ok, thread} =
        create_thread_with_participants([insert(:user).id], %{thread_type: "direct"})

      assert {:ok, %Thread{}} = Threads.delete_thread(thread)
      assert Threads.get_thread(thread.id) == nil
    end
  end

  describe "archive_thread/1 and unarchive_thread/1" do
    test "archives a thread" do
      {:ok, thread} =
        create_thread_with_participants([insert(:user).id], %{thread_type: "direct"})

      assert {:ok, %Thread{} = archived} = Threads.archive_thread(thread)
      assert archived.is_archived == true
    end

    test "unarchives a thread" do
      {:ok, thread} =
        create_thread_with_participants([insert(:user).id], %{
          thread_type: "direct",
          is_archived: true
        })

      assert {:ok, %Thread{} = unarchived} = Threads.unarchive_thread(thread)
      assert unarchived.is_archived == false
    end
  end

  describe "mute_thread/1 and unmute_thread/1" do
    test "mutes a thread" do
      {:ok, thread} =
        create_thread_with_participants([insert(:user).id], %{thread_type: "direct"})

      assert {:ok, %Thread{} = muted} = Threads.mute_thread(thread)
      assert muted.is_muted == true
    end

    test "unmutes a thread" do
      {:ok, thread} =
        create_thread_with_participants([insert(:user).id], %{
          thread_type: "direct",
          is_muted: true
        })

      assert {:ok, %Thread{} = unmuted} = Threads.unmute_thread(thread)
      assert unmuted.is_muted == false
    end
  end

  describe "add_participant/3" do
    test "adds participant to thread" do
      user = insert(:user)
      new_user = insert(:user)
      {:ok, thread} = create_thread_with_participants([user.id], %{thread_type: "group"})

      assert {:ok, %ThreadParticipant{} = participant} =
               Threads.add_participant(thread, new_user.id)

      assert participant.user_id == new_user.id
      assert participant.role == "member"
    end

    test "adds participant with admin role" do
      user = insert(:user)
      admin_user = insert(:user)
      {:ok, thread} = create_thread_with_participants([user.id], %{thread_type: "group"})

      assert {:ok, %ThreadParticipant{} = participant} =
               Threads.add_participant(thread, admin_user.id, "admin")

      assert participant.role == "admin"
    end
  end

  describe "remove_participant/2" do
    test "removes participant from thread" do
      user1 = insert(:user)
      user2 = insert(:user)

      {:ok, thread} =
        create_thread_with_participants([user1.id, user2.id], %{thread_type: "group"})

      assert {:ok, %ThreadParticipant{}} = Threads.remove_participant(thread, user2.id)

      participants = Threads.list_participants(thread)
      user_ids = Enum.map(participants, & &1.user_id)
      refute user2.id in user_ids
    end

    test "returns error when participant not found" do
      {:ok, thread} = create_thread_with_participants([insert(:user).id], %{thread_type: "group"})

      assert {:error, :not_found} = Threads.remove_participant(thread, "non-existent-user")
    end
  end

  describe "list_participants/1" do
    test "lists all participants in a thread" do
      user1 = insert(:user)
      user2 = insert(:user)

      {:ok, thread} =
        create_thread_with_participants([user1.id, user2.id], %{thread_type: "group"})

      participants = Threads.list_participants(thread)
      assert length(participants) == 2
    end

    test "returns participants ordered by joined_at" do
      user1 = insert(:user)
      user2 = insert(:user)
      {:ok, thread} = create_thread_with_participants([user1.id], %{thread_type: "group"})

      # Add second user later
      Process.sleep(10)
      Threads.add_participant(thread, user2.id)

      participants = Threads.list_participants(thread)
      assert length(participants) == 2
      assert hd(participants).user_id == user1.id
    end
  end

  describe "get_thread_for_direct_message/2" do
    test "finds existing direct message thread" do
      user1 = insert(:user)
      user2 = insert(:user)

      {:ok, thread} =
        create_thread_with_participants([user1.id, user2.id], %{thread_type: "direct"})

      assert {:ok, found_thread} = Threads.get_thread_for_direct_message(user1.id, user2.id)
      assert found_thread.id == thread.id
    end

    test "creates new direct message thread if none exists" do
      user1 = insert(:user)
      user2 = insert(:user)

      assert {:ok, thread} = Threads.get_thread_for_direct_message(user1.id, user2.id)
      assert thread.thread_type == "direct"
      assert length(thread.thread_participants) == 2
    end

    test "returns same thread regardless of user order" do
      user1 = insert(:user)
      user2 = insert(:user)

      {:ok, thread1} = Threads.get_thread_for_direct_message(user1.id, user2.id)
      {:ok, thread2} = Threads.get_thread_for_direct_message(user2.id, user1.id)

      assert thread1.id == thread2.id
    end
  end

  describe "list_user_threads/2" do
    test "lists threads for a specific user" do
      user1 = insert(:user)
      user2 = insert(:user)
      user3 = insert(:user)

      {:ok, thread1} =
        create_thread_with_participants([user1.id, user2.id], %{thread_type: "direct"})

      {:ok, thread2} =
        create_thread_with_participants([user1.id, user3.id], %{thread_type: "direct"})

      {:ok, _thread3} =
        create_thread_with_participants([user2.id, user3.id], %{thread_type: "direct"})

      user1_threads = Threads.list_user_threads(user1.id)
      thread_ids = Enum.map(user1_threads, & &1.id)

      assert length(user1_threads) == 2
      assert thread1.id in thread_ids
      assert thread2.id in thread_ids
    end

    test "filters user threads by archived status" do
      user = insert(:user)
      {:ok, _active_thread} = create_thread_with_participants([user.id], %{thread_type: "direct"})

      {:ok, _archived_thread} =
        create_thread_with_participants([user.id], %{thread_type: "direct", is_archived: true})

      active_threads = Threads.list_user_threads(user.id, is_archived: false)
      archived_threads = Threads.list_user_threads(user.id, is_archived: true)

      assert length(active_threads) == 1
      assert length(archived_threads) == 1
    end
  end

  describe "search_threads/2" do
    test "searches threads by title" do
      user = insert(:user)

      {:ok, thread1} =
        create_thread_with_participants([user.id], %{
          thread_type: "group",
          title: "Engineering Team"
        })

      {:ok, _thread2} =
        create_thread_with_participants([user.id], %{
          thread_type: "group",
          title: "Marketing Team"
        })

      results = Threads.search_threads("Engineering")
      assert length(results) == 1
      assert hd(results).id == thread1.id
    end

    test "search is case-insensitive" do
      user = insert(:user)

      {:ok, thread} =
        create_thread_with_participants([user.id], %{thread_type: "group", title: "Project Alpha"})

      results = Threads.search_threads("project alpha")
      assert length(results) == 1
      assert hd(results).id == thread.id
    end

    test "returns empty list when no matches found" do
      results = Threads.search_threads("NonExistent")
      assert results == []
    end
  end

  # Helper functions

  defp create_thread_with_participants(participant_ids, attrs) do
    attrs = Map.merge(%{thread_type: "direct"}, attrs)
    attrs = Map.put(attrs, :participant_ids, participant_ids)
    Threads.create_thread(attrs)
  end

  defp insert(:user) do
    Repo.insert!(%User{
      email: "user_#{System.unique_integer([:positive])}@example.com",
      username: "user_#{System.unique_integer([:positive])}",
      password_hash: Bcrypt.hash_pwd_salt("password123")
    })
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
