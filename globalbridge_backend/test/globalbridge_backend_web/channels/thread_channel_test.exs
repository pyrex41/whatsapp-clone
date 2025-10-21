defmodule GlobalbridgeBackendWeb.ThreadChannelTest do
  use GlobalbridgeBackendWeb.ChannelCase

  alias GlobalbridgeBackendWeb.UserSocket
  alias GlobalbridgeBackend.{Repo, Chat}
  alias GlobalbridgeBackend.Schemas.{Thread, ThreadParticipant, User}

  setup do
    # Create test users
    user1 =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        username: "user1",
        email: "user1@test.com",
        phone: "+1234567890"
      })

    user2 =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        username: "user2",
        email: "user2@test.com",
        phone: "+1234567891"
      })

    # Create test thread
    thread =
      Repo.insert!(%Thread{
        id: Ecto.UUID.generate(),
        thread_type: "direct",
        database_shard_id: "test_shard_1"
      })

    # Add participants
    Repo.insert!(%ThreadParticipant{
      thread_id: thread.id,
      user_id: user1.id
    })

    Repo.insert!(%ThreadParticipant{
      thread_id: thread.id,
      user_id: user2.id
    })

    {:ok, thread: thread, user1: user1, user2: user2}
  end

  describe "join thread channel" do
    test "allows participant to join thread", %{thread: thread, user1: user1} do
      token = "user:#{user1.id}"
      {:ok, socket} = connect(UserSocket, %{"token" => token})

      {:ok, reply, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

      assert reply.thread_id == thread.id
      assert reply.joined_at
      assert socket.assigns.thread_id == thread.id
    end

    test "denies non-participant from joining thread", %{thread: thread} do
      # Create user not in thread
      other_user =
        Repo.insert!(%User{
          id: Ecto.UUID.generate(),
          username: "other",
          email: "other@test.com",
          phone: "+1234567892"
        })

      token = "user:#{other_user.id}"
      {:ok, socket} = connect(UserSocket, %{"token" => token})

      assert {:error, %{reason: "Not authorized to join this thread"}} =
               subscribe_and_join(socket, "thread:#{thread.id}", %{})
    end

    test "denies join with invalid token" do
      assert :error = connect(UserSocket, %{"token" => "invalid"})
    end

    test "denies join for non-existent thread", %{user1: user1} do
      token = "user:#{user1.id}"
      {:ok, socket} = connect(UserSocket, %{"token" => token})

      fake_thread_id = Ecto.UUID.generate()

      assert {:error, %{reason: "Thread not found"}} =
               subscribe_and_join(socket, "thread:#{fake_thread_id}", %{})
    end
  end

  describe "new_message" do
    test "broadcasts message to all participants", %{thread: thread, user1: user1, user2: user2} do
      # Connect both users
      token1 = "user:#{user1.id}"
      {:ok, socket1} = connect(UserSocket, %{"token" => token1})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      token2 = "user:#{user2.id}"
      {:ok, socket2} = connect(UserSocket, %{"token" => token2})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Hello, World!"})

      assert_reply ref, :ok, %{id: message_id, timestamp: _timestamp}

      # Both users should receive the broadcast
      assert_broadcast "new_message", %{
        id: ^message_id,
        thread_id: thread_id,
        sender_id: sender_id,
        content: "Hello, World!",
        content_type: "text"
      }

      assert thread_id == thread.id
      assert sender_id == user1.id
    end

    test "handles media messages", %{thread: thread, user1: user1} do
      token = "user:#{user1.id}"
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      {:ok, _, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

      ref =
        push(socket, "new_message", %{
          "content" => "Check this out!",
          "content_type" => "image",
          "media_url" => "https://example.com/image.jpg",
          "media_size" => 1024,
          "media_mime_type" => "image/jpeg"
        })

      assert_reply ref, :ok, %{id: message_id}

      assert_broadcast "new_message", %{
        id: ^message_id,
        content_type: "image",
        media_url: "https://example.com/image.jpg"
      }
    end

    test "handles reply to message", %{thread: thread, user1: user1} do
      token = "user:#{user1.id}"
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      {:ok, _, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

      original_message_id = Ecto.UUID.generate()

      ref =
        push(socket, "new_message", %{
          "content" => "This is a reply",
          "reply_to_id" => original_message_id
        })

      assert_reply ref, :ok, %{id: message_id}

      assert_broadcast "new_message", %{
        id: ^message_id,
        reply_to_id: ^original_message_id
      }
    end
  end

  describe "edit_message" do
    test "allows sender to edit their message", %{thread: thread, user1: user1} do
      token = "user:#{user1.id}"
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      {:ok, _, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

      # Send initial message
      ref = push(socket, "new_message", %{"content" => "Original content"})
      assert_reply ref, :ok, %{id: message_id}

      # Edit the message
      ref =
        push(socket, "edit_message", %{
          "message_id" => message_id,
          "content" => "Edited content"
        })

      assert_reply ref, :ok, %{id: ^message_id}

      assert_broadcast "message_edited", %{
        id: ^message_id,
        content: "Edited content",
        edited_at: _edited_at
      }
    end
  end

  describe "delete_message" do
    test "allows sender to delete their message", %{thread: thread, user1: user1} do
      token = "user:#{user1.id}"
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      {:ok, _, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

      # Send initial message
      ref = push(socket, "new_message", %{"content" => "To be deleted"})
      assert_reply ref, :ok, %{id: message_id}

      # Delete the message
      ref = push(socket, "delete_message", %{"message_id" => message_id})

      assert_reply ref, :ok, %{id: ^message_id}

      assert_broadcast "message_deleted", %{
        id: ^message_id,
        deleted_by: deleted_by,
        deleted_at: _deleted_at
      }

      assert deleted_by == user1.id
    end
  end

  describe "typing indicators" do
    test "broadcasts typing status to other participants", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      # Connect both users
      token1 = "user:#{user1.id}"
      {:ok, socket1} = connect(UserSocket, %{"token" => token1})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      token2 = "user:#{user2.id}"
      {:ok, socket2} = connect(UserSocket, %{"token" => token2})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 starts typing
      push(socket1, "typing", %{"is_typing" => true})

      # User2 should receive typing indicator (but not user1)
      assert_broadcast "user_typing", %{
        user_id: user_id,
        is_typing: true
      }

      assert user_id == user1.id
    end
  end

  describe "read receipts" do
    test "broadcasts read status to other participants", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      # Connect both users
      token1 = "user:#{user1.id}"
      {:ok, socket1} = connect(UserSocket, %{"token" => token1})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      token2 = "user:#{user2.id}"
      {:ok, socket2} = connect(UserSocket, %{"token" => token2})
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
        read_at: _read_at
      }

      assert reader_id == user2.id
    end
  end

  describe "latency optimization" do
    test "message broadcast happens before database write", %{thread: thread, user1: user1} do
      token = "user:#{user1.id}"
      {:ok, socket} = connect(UserSocket, %{"token" => token})
      {:ok, _, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

      start_time = System.monotonic_time(:millisecond)

      ref = push(socket, "new_message", %{"content" => "Speed test"})

      # Should receive broadcast very quickly
      assert_broadcast "new_message", %{content: "Speed test"}, 50

      # Should receive reply quickly
      assert_reply ref, :ok, %{id: _message_id}, 50

      end_time = System.monotonic_time(:millisecond)
      latency = end_time - start_time

      # Latency should be well under 100ms for local operations
      assert latency < 100, "Expected latency < 100ms, got #{latency}ms"
    end
  end
end
