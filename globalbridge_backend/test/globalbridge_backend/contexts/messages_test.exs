defmodule GlobalbridgeBackend.Contexts.MessagesTest do
  use GlobalbridgeBackend.DataCase

  alias GlobalbridgeBackend.Contexts.{Messages, Threads}
  alias GlobalbridgeBackend.Schemas.{Message, User}

  setup do
    # Create test users
    user1 = insert(:user)
    user2 = insert(:user)

    # Create a test thread
    {:ok, thread} =
      Threads.create_thread(%{
        thread_type: "direct",
        participant_ids: [user1.id, user2.id]
      })

    %{
      user1: user1,
      user2: user2,
      thread: thread
    }
  end

  describe "create_message/2" do
    test "creates text message with valid attributes", %{thread: thread, user1: user1} do
      attrs = %{
        sender_id: user1.id,
        content_type: "text",
        content: "Hello, world!"
      }

      assert {:ok, %Message{} = message} = Messages.create_message(thread.id, attrs)
      assert message.thread_id == thread.id
      assert message.sender_id == user1.id
      assert message.content == "Hello, world!"
      assert message.content_type == "text"
    end

    test "creates image message with media_url", %{thread: thread, user1: user1} do
      attrs = %{
        sender_id: user1.id,
        content_type: "image",
        media_url: "https://example.com/image.jpg",
        media_size: 1024,
        media_mime_type: "image/jpeg"
      }

      assert {:ok, %Message{} = message} = Messages.create_message(thread.id, attrs)
      assert message.content_type == "image"
      assert message.media_url == "https://example.com/image.jpg"
    end

    test "creates reply message", %{thread: thread, user1: user1, user2: user2} do
      {:ok, original_message} =
        Messages.create_message(thread.id, %{
          sender_id: user1.id,
          content_type: "text",
          content: "Original message"
        })

      reply_attrs = %{
        sender_id: user2.id,
        content_type: "text",
        content: "Reply message",
        reply_to_id: original_message.id
      }

      assert {:ok, %Message{} = reply} = Messages.create_message(thread.id, reply_attrs)
      assert reply.reply_to_id == original_message.id
    end

    test "fails with invalid content type", %{thread: thread, user1: user1} do
      attrs = %{
        sender_id: user1.id,
        content_type: "invalid",
        content: "Test"
      }

      assert {:error, changeset} = Messages.create_message(thread.id, attrs)
      assert "is invalid" in errors_on(changeset).content_type
    end

    test "fails when text message has no content", %{thread: thread, user1: user1} do
      attrs = %{
        sender_id: user1.id,
        content_type: "text"
      }

      assert {:error, changeset} = Messages.create_message(thread.id, attrs)
      assert "can't be blank" in errors_on(changeset).content
    end

    test "fails when media message has no media_url", %{thread: thread, user1: user1} do
      attrs = %{
        sender_id: user1.id,
        content_type: "image"
      }

      assert {:error, changeset} = Messages.create_message(thread.id, attrs)
      assert "can't be blank" in errors_on(changeset).media_url
    end

    test "updates thread last_message_at timestamp", %{thread: thread, user1: user1} do
      original_timestamp = thread.last_message_at

      attrs = %{
        sender_id: user1.id,
        content_type: "text",
        content: "Test message"
      }

      {:ok, _message} = Messages.create_message(thread.id, attrs)

      updated_thread = Threads.get_thread!(thread.id)
      assert DateTime.compare(updated_thread.last_message_at, original_timestamp) == :gt
    end
  end

  describe "list_messages/2" do
    test "lists all messages in a thread", %{thread: thread, user1: user1} do
      {:ok, msg1} = create_message(thread.id, user1.id, "Message 1")
      {:ok, msg2} = create_message(thread.id, user1.id, "Message 2")

      messages = Messages.list_messages(thread.id)
      message_ids = Enum.map(messages, & &1.id)

      assert length(messages) == 2
      assert msg1.id in message_ids
      assert msg2.id in message_ids
    end

    test "filters by sender_id", %{thread: thread, user1: user1, user2: user2} do
      {:ok, _msg1} = create_message(thread.id, user1.id, "From user1")
      {:ok, msg2} = create_message(thread.id, user2.id, "From user2")

      messages = Messages.list_messages(thread.id, sender_id: user2.id)
      assert length(messages) == 1
      assert hd(messages).id == msg2.id
    end

    test "filters by content_type", %{thread: thread, user1: user1} do
      {:ok, _text_msg} = create_message(thread.id, user1.id, "Text")
      {:ok, image_msg} = create_image_message(thread.id, user1.id)

      image_messages = Messages.list_messages(thread.id, content_type: "image")
      assert length(image_messages) == 1
      assert hd(image_messages).id == image_msg.id
    end

    test "excludes deleted messages by default", %{thread: thread, user1: user1} do
      {:ok, msg1} = create_message(thread.id, user1.id, "Active")
      {:ok, msg2} = create_message(thread.id, user1.id, "To delete")
      {:ok, _deleted} = Messages.delete_message(thread.id, msg2)

      messages = Messages.list_messages(thread.id, is_deleted: false)
      message_ids = Enum.map(messages, & &1.id)

      assert length(messages) == 1
      assert msg1.id in message_ids
    end

    test "supports pagination", %{thread: thread, user1: user1} do
      {:ok, _msg1} = create_message(thread.id, user1.id, "Message 1")
      {:ok, _msg2} = create_message(thread.id, user1.id, "Message 2")
      {:ok, _msg3} = create_message(thread.id, user1.id, "Message 3")

      page1 = Messages.list_messages(thread.id, limit: 2, offset: 0)
      page2 = Messages.list_messages(thread.id, limit: 2, offset: 2)

      assert length(page1) == 2
      assert length(page2) == 1
    end

    test "supports custom ordering", %{thread: thread, user1: user1} do
      {:ok, msg1} = create_message(thread.id, user1.id, "First")
      Process.sleep(10)
      {:ok, _msg2} = create_message(thread.id, user1.id, "Second")

      messages = Messages.list_messages(thread.id, order_by: {:inserted_at, :asc})
      assert hd(messages).id == msg1.id
    end
  end

  describe "get_message!/2" do
    test "returns message with valid id", %{thread: thread, user1: user1} do
      {:ok, message} = create_message(thread.id, user1.id, "Test")

      found_message = Messages.get_message!(thread.id, message.id)
      assert found_message.id == message.id
    end

    test "raises error when message not found", %{thread: thread} do
      assert_raise Ecto.NoResultsError, fn ->
        Messages.get_message!(thread.id, "non-existent-id")
      end
    end
  end

  describe "get_message/2" do
    test "returns message with valid id", %{thread: thread, user1: user1} do
      {:ok, message} = create_message(thread.id, user1.id, "Test")

      found_message = Messages.get_message(thread.id, message.id)
      assert found_message.id == message.id
    end

    test "returns nil when message not found", %{thread: thread} do
      assert Messages.get_message(thread.id, "non-existent-id") == nil
    end
  end

  describe "edit_message/3" do
    test "updates message content", %{thread: thread, user1: user1} do
      {:ok, message} = create_message(thread.id, user1.id, "Original")

      assert {:ok, %Message{} = edited} = Messages.edit_message(thread.id, message, "Edited")
      assert edited.content == "Edited"
      assert edited.edited_at != nil
    end
  end

  describe "delete_message/2" do
    test "soft deletes message", %{thread: thread, user1: user1} do
      {:ok, message} = create_message(thread.id, user1.id, "To delete")

      assert {:ok, %Message{} = deleted} = Messages.delete_message(thread.id, message)
      assert deleted.is_deleted == true
      assert deleted.deleted_at != nil
    end
  end

  describe "mark_as_read/3" do
    test "creates read receipt", %{thread: thread, user1: user1, user2: user2} do
      {:ok, message} = create_message(thread.id, user1.id, "Test")

      assert {:ok, receipt} = Messages.mark_as_read(thread.id, message.id, user2.id)
      assert receipt.message_id == message.id
      assert receipt.user_id == user2.id
      assert receipt.read_at != nil
    end

    test "updates existing read receipt", %{thread: thread, user1: user1, user2: user2} do
      {:ok, message} = create_message(thread.id, user1.id, "Test")

      {:ok, first_receipt} = Messages.mark_as_read(thread.id, message.id, user2.id)
      Process.sleep(10)
      {:ok, second_receipt} = Messages.mark_as_read(thread.id, message.id, user2.id)

      assert first_receipt.id == second_receipt.id
      assert DateTime.compare(second_receipt.read_at, first_receipt.read_at) == :gt
    end
  end

  describe "get_unread_count/2" do
    test "returns count of unread messages", %{thread: thread, user1: user1, user2: user2} do
      {:ok, msg1} = create_message(thread.id, user1.id, "Message 1")
      {:ok, _msg2} = create_message(thread.id, user1.id, "Message 2")
      {:ok, _msg3} = create_message(thread.id, user1.id, "Message 3")

      # Mark one as read
      Messages.mark_as_read(thread.id, msg1.id, user2.id)

      unread_count = Messages.get_unread_count(thread.id, user2.id)
      assert unread_count == 2
    end

    test "excludes user's own messages", %{thread: thread, user1: user1, user2: user2} do
      {:ok, _msg1} = create_message(thread.id, user1.id, "From user1")
      {:ok, _msg2} = create_message(thread.id, user2.id, "From user2")

      unread_count = Messages.get_unread_count(thread.id, user2.id)
      assert unread_count == 1
    end

    test "excludes deleted messages", %{thread: thread, user1: user1, user2: user2} do
      {:ok, msg1} = create_message(thread.id, user1.id, "Message 1")
      {:ok, msg2} = create_message(thread.id, user1.id, "Message 2")

      Messages.delete_message(thread.id, msg2)

      unread_count = Messages.get_unread_count(thread.id, user2.id)
      assert unread_count == 1
    end
  end

  describe "search_messages/3" do
    test "searches messages by content", %{thread: thread, user1: user1} do
      {:ok, msg1} = create_message(thread.id, user1.id, "Hello world")
      {:ok, _msg2} = create_message(thread.id, user1.id, "Goodbye")

      results = Messages.search_messages(thread.id, "hello")
      assert length(results) == 1
      assert hd(results).id == msg1.id
    end

    test "search is case-insensitive", %{thread: thread, user1: user1} do
      {:ok, message} = create_message(thread.id, user1.id, "Important Message")

      results = Messages.search_messages(thread.id, "important message")
      assert length(results) == 1
      assert hd(results).id == message.id
    end

    test "excludes deleted messages", %{thread: thread, user1: user1} do
      {:ok, msg} = create_message(thread.id, user1.id, "Searchable")
      Messages.delete_message(thread.id, msg)

      results = Messages.search_messages(thread.id, "Searchable")
      assert results == []
    end
  end

  describe "get_thread_messages_after/3" do
    test "returns messages after timestamp", %{thread: thread, user1: user1} do
      {:ok, msg1} = create_message(thread.id, user1.id, "First")
      timestamp = msg1.inserted_at

      Process.sleep(10)
      {:ok, msg2} = create_message(thread.id, user1.id, "Second")
      {:ok, msg3} = create_message(thread.id, user1.id, "Third")

      messages = Messages.get_thread_messages_after(thread.id, timestamp)
      message_ids = Enum.map(messages, & &1.id)

      assert length(messages) == 2
      assert msg2.id in message_ids
      assert msg3.id in message_ids
    end

    test "respects limit parameter", %{thread: thread, user1: user1} do
      {:ok, msg1} = create_message(thread.id, user1.id, "First")
      timestamp = msg1.inserted_at

      Process.sleep(10)
      {:ok, _msg2} = create_message(thread.id, user1.id, "Second")
      {:ok, _msg3} = create_message(thread.id, user1.id, "Third")

      messages = Messages.get_thread_messages_after(thread.id, timestamp, 1)
      assert length(messages) == 1
    end
  end

  describe "get_thread_messages_before/3" do
    test "returns messages before timestamp", %{thread: thread, user1: user1} do
      {:ok, msg1} = create_message(thread.id, user1.id, "First")
      {:ok, msg2} = create_message(thread.id, user1.id, "Second")

      Process.sleep(10)
      {:ok, msg3} = create_message(thread.id, user1.id, "Third")
      timestamp = msg3.inserted_at

      messages = Messages.get_thread_messages_before(thread.id, timestamp)
      message_ids = Enum.map(messages, & &1.id)

      assert length(messages) == 2
      assert msg1.id in message_ids
      assert msg2.id in message_ids
    end

    test "respects limit parameter", %{thread: thread, user1: user1} do
      {:ok, _msg1} = create_message(thread.id, user1.id, "First")
      {:ok, _msg2} = create_message(thread.id, user1.id, "Second")

      Process.sleep(10)
      {:ok, msg3} = create_message(thread.id, user1.id, "Third")
      timestamp = msg3.inserted_at

      messages = Messages.get_thread_messages_before(thread.id, timestamp, 1)
      assert length(messages) == 1
    end
  end

  # Helper functions

  defp create_message(thread_id, sender_id, content) do
    Messages.create_message(thread_id, %{
      sender_id: sender_id,
      content_type: "text",
      content: content
    })
  end

  defp create_image_message(thread_id, sender_id) do
    Messages.create_message(thread_id, %{
      sender_id: sender_id,
      content_type: "image",
      media_url: "https://example.com/image.jpg"
    })
  end

  defp insert(:user) do
    alias GlobalbridgeBackend.Repo
    alias GlobalbridgeBackend.Schemas.User

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
