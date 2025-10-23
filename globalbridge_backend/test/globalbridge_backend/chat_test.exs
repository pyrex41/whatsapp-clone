defmodule GlobalbridgeBackend.ChatTest do
  use GlobalbridgeBackend.DataCase, async: true

  alias GlobalbridgeBackend.{Chat, Repo}
  alias GlobalbridgeBackend.Schemas.{Thread, ThreadParticipant, ReadReceipt}

  describe "read receipts" do
    setup do
      # Create test thread
      thread =
        %Thread{
          id: Ecto.UUID.generate(),
          thread_type: "direct",
          database_shard_id: "main"
        }
        |> Repo.insert!()

      user_id = Ecto.UUID.generate()
      message_id = Ecto.UUID.generate()

      # Add user as participant
      %ThreadParticipant{
        thread_id: thread.id,
        user_id: user_id,
        role: "member"
      }
      |> Repo.insert!()

      {:ok, thread: thread, user_id: user_id, message_id: message_id}
    end

    test "marks message as read", %{thread: thread, user_id: user_id, message_id: message_id} do
      # Mark message as read
      assert {:ok, receipt} = Chat.mark_message_read(thread.id, message_id, user_id)

      assert receipt.message_id == message_id
      assert receipt.user_id == user_id
      assert receipt.read_at != nil
    end

    test "handles duplicate read receipts gracefully", %{
      thread: thread,
      user_id: user_id,
      message_id: message_id
    } do
      # Mark as read first time
      {:ok, receipt1} = Chat.mark_message_read(thread.id, message_id, user_id)
      timestamp1 = receipt1.read_at

      # Small delay to ensure different timestamp
      Process.sleep(10)

      # Mark as read again (should update, not error)
      {:ok, receipt2} = Chat.mark_message_read(thread.id, message_id, user_id)

      assert receipt2.message_id == message_id
      assert receipt2.user_id == user_id
      # Should have updated timestamp
      assert DateTime.compare(receipt2.read_at, timestamp1) == :gt
    end

    test "retrieves read receipts for a message", %{thread: thread, message_id: message_id} do
      user1 = Ecto.UUID.generate()
      user2 = Ecto.UUID.generate()

      # Add users as participants
      Enum.each([user1, user2], fn uid ->
        %ThreadParticipant{thread_id: thread.id, user_id: uid, role: "member"}
        |> Repo.insert!()
      end)

      # Both users read the message
      Chat.mark_message_read(thread.id, message_id, user1)
      Chat.mark_message_read(thread.id, message_id, user2)

      # Get receipts
      {:ok, receipts} = Chat.get_message_read_receipts(thread.id, message_id)

      assert length(receipts) == 2
      user_ids = Enum.map(receipts, & &1.user_id)
      assert user1 in user_ids
      assert user2 in user_ids
    end

    test "gets last read message for user", %{thread: thread, user_id: user_id} do
      message1 = Ecto.UUID.generate()
      message2 = Ecto.UUID.generate()

      # Read first message
      Chat.mark_message_read(thread.id, message1, user_id)
      Process.sleep(10)

      # Read second message (more recent)
      Chat.mark_message_read(thread.id, message2, user_id)

      # Should return the most recent
      {:ok, last_read} = Chat.get_last_read_message(thread.id, user_id)
      assert last_read == message2
    end

    test "returns nil when no messages read", %{thread: thread, user_id: user_id} do
      {:ok, last_read} = Chat.get_last_read_message(thread.id, user_id)
      assert last_read == nil
    end

    test "returns error for non-existent thread", %{user_id: user_id, message_id: message_id} do
      fake_thread_id = Ecto.UUID.generate()

      assert {:error, :thread_not_found} =
               Chat.mark_message_read(fake_thread_id, message_id, user_id)
    end
  end
end
