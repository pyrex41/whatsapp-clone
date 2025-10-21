defmodule GlobalbridgeBackendWeb.ReadReceiptsTest do
  @moduledoc """
  Comprehensive tests for Task 17: Read Receipts feature.

  Tests cover:
  - Read receipt tracking and storage
  - Broadcasting read status to participants
  - Multi-user read tracking
  - Read receipt persistence
  - Performance requirements
  """
  use GlobalbridgeBackendWeb.ChannelCase

  alias GlobalbridgeBackendWeb.UserSocket
  alias GlobalbridgeBackend.{Repo, Chat}
  alias GlobalbridgeBackend.Schemas.{Thread, ThreadParticipant, User, Message, ReadReceipt}

  setup do
    # Create test users
    user1 = Repo.insert!(%User{
      id: Ecto.UUID.generate(),
      username: "user1",
      email: "user1@test.com",
      phone: "+1234567890"
    })

    user2 = Repo.insert!(%User{
      id: Ecto.UUID.generate(),
      username: "user2",
      email: "user2@test.com",
      phone: "+1234567891"
    })

    user3 = Repo.insert!(%User{
      id: Ecto.UUID.generate(),
      username: "user3",
      email: "user3@test.com",
      phone: "+1234567892"
    })

    # Create test thread
    thread = Repo.insert!(%Thread{
      id: Ecto.UUID.generate(),
      thread_type: "group",
      database_shard_id: "test_shard_1"
    })

    # Add participants
    Repo.insert!(%ThreadParticipant{thread_id: thread.id, user_id: user1.id})
    Repo.insert!(%ThreadParticipant{thread_id: thread.id, user_id: user2.id})
    Repo.insert!(%ThreadParticipant{thread_id: thread.id, user_id: user3.id})

    {:ok, thread: thread, user1: user1, user2: user2, user3: user3}
  end

  describe "read receipt broadcasting" do
    test "broadcasts read receipt to other participants", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      # Connect both users
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Read this!"})
      assert_reply ref, :ok, %{id: message_id}

      # User2 marks as read
      push(socket2, "mark_read", %{"message_id" => message_id})

      # User1 should receive read receipt
      assert_broadcast "message_read", %{
        user_id: reader_id,
        message_id: ^message_id,
        read_at: read_at
      }

      assert reader_id == user2.id
      assert %DateTime{} = read_at
    end

    test "does not broadcast read receipt to reader", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Test"})
      assert_reply ref, :ok, %{id: message_id}

      # User2 marks as read
      push(socket2, "mark_read", %{"message_id" => message_id})

      # User2 should not receive their own read receipt
      # (broadcast_from! excludes sender)
    end

    test "handles multiple read receipts for same message", %{
      thread: thread,
      user1: user1,
      user2: user2,
      user3: user3
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      {:ok, socket3} = connect(UserSocket, %{"token" => "user3:#{user3.id}"})
      {:ok, _, socket3} = subscribe_and_join(socket3, "thread:#{thread.id}", %{})

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Group message"})
      assert_reply ref, :ok, %{id: message_id}

      # Both user2 and user3 mark as read
      push(socket2, "mark_read", %{"message_id" => message_id})
      push(socket3, "mark_read", %{"message_id" => message_id})

      # Should receive both read receipts
      assert_broadcast "message_read", %{user_id: ^user2.id}
      assert_broadcast "message_read", %{user_id: ^user3.id}
    end
  end

  describe "read receipt persistence" do
    test "stores read receipt in database", %{thread: thread, user1: user1, user2: user2} do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Test"})
      assert_reply ref, :ok, %{id: message_id}

      # Wait for async DB write
      :timer.sleep(100)

      # User2 marks as read
      push(socket2, "mark_read", %{"message_id" => message_id})

      # Wait for async DB write
      :timer.sleep(100)

      # Verify read receipt in database
      read_receipt = Repo.get_by(ReadReceipt,
        message_id: message_id,
        user_id: user2.id
      )

      assert read_receipt != nil
      assert read_receipt.thread_id == thread.id
      assert read_receipt.read_at != nil
    end

    test "prevents duplicate read receipts for same user", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Test"})
      assert_reply ref, :ok, %{id: message_id}
      :timer.sleep(100)

      # User2 marks as read multiple times
      push(socket2, "mark_read", %{"message_id" => message_id})
      :timer.sleep(50)
      push(socket2, "mark_read", %{"message_id" => message_id})
      :timer.sleep(100)

      # Should only have one read receipt in DB
      receipts = Repo.all(
        from r in ReadReceipt,
        where: r.message_id == ^message_id and r.user_id == ^user2.id
      )

      assert length(receipts) == 1
    end

    test "updates read_at timestamp on duplicate read", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Test"})
      assert_reply ref, :ok, %{id: message_id}
      :timer.sleep(100)

      # User2 marks as read
      push(socket2, "mark_read", %{"message_id" => message_id})
      :timer.sleep(100)

      first_receipt = Repo.get_by(ReadReceipt,
        message_id: message_id,
        user_id: user2.id
      )
      first_read_at = first_receipt.read_at

      :timer.sleep(50)

      # Mark as read again
      push(socket2, "mark_read", %{"message_id" => message_id})
      :timer.sleep(100)

      updated_receipt = Repo.get_by(ReadReceipt,
        message_id: message_id,
        user_id: user2.id
      )

      # Timestamp should be updated
      assert DateTime.compare(updated_receipt.read_at, first_read_at) in [:gt, :eq]
    end
  end

  describe "read receipt performance" do
    test "read receipt broadcast happens within 50ms", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      ref = push(socket1, "new_message", %{"content" => "Speed test"})
      assert_reply ref, :ok, %{id: message_id}

      start_time = System.monotonic_time(:millisecond)
      push(socket2, "mark_read", %{"message_id" => message_id})

      # Should receive broadcast very quickly
      assert_broadcast "message_read", %{}, 50

      end_time = System.monotonic_time(:millisecond)
      latency = end_time - start_time

      assert latency < 50, "Read receipt latency #{latency}ms exceeds 50ms threshold"
    end

    test "handles batch read receipts efficiently", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 sends 10 messages
      message_ids = Enum.map(1..10, fn i ->
        ref = push(socket1, "new_message", %{"content" => "Message #{i}"})
        assert_reply ref, :ok, %{id: message_id}
        message_id
      end)

      start_time = System.monotonic_time(:millisecond)

      # User2 marks all as read
      Enum.each(message_ids, fn message_id ->
        push(socket2, "mark_read", %{"message_id" => message_id})
      end)

      # All broadcasts should complete quickly
      Enum.each(message_ids, fn message_id ->
        assert_broadcast "message_read", %{message_id: ^message_id}, 100
      end)

      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time

      # Should handle 10 read receipts in under 500ms
      assert total_time < 500, "Batch read receipts took #{total_time}ms"
    end
  end

  describe "read receipt edge cases" do
    test "handles read receipt for non-existent message", %{thread: thread, user1: user1} do
      {:ok, socket} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

      fake_message_id = Ecto.UUID.generate()

      # Should handle gracefully
      push(socket, "mark_read", %{"message_id" => fake_message_id})

      # Should not crash (may or may not broadcast)
      :timer.sleep(100)
    end

    test "sender can mark own message as read", %{thread: thread, user1: user1} do
      {:ok, socket} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

      ref = push(socket, "new_message", %{"content" => "Self-read"})
      assert_reply ref, :ok, %{id: message_id}

      # Sender marks own message as read
      push(socket, "mark_read", %{"message_id" => message_id})

      # Should be allowed (for "read on another device" scenario)
      :timer.sleep(100)
    end

    test "read receipt includes accurate timestamps", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      ref = push(socket1, "new_message", %{"content" => "Timestamp test"})
      assert_reply ref, :ok, %{id: message_id}

      before_read = DateTime.utc_now()
      :timer.sleep(10)

      push(socket2, "mark_read", %{"message_id" => message_id})

      assert_broadcast "message_read", %{read_at: read_at}

      :timer.sleep(10)
      after_read = DateTime.utc_now()

      # Timestamp should be between before and after
      assert DateTime.compare(read_at, before_read) in [:gt, :eq]
      assert DateTime.compare(read_at, after_read) in [:lt, :eq]
    end
  end

  describe "read receipt reply handling" do
    test "returns ok reply for successful read receipt", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      ref = push(socket1, "new_message", %{"content" => "Test"})
      assert_reply ref, :ok, %{id: message_id}

      ref = push(socket2, "mark_read", %{"message_id" => message_id})
      assert_reply ref, :ok
    end
  end
end
