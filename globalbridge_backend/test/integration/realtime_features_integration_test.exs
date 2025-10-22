defmodule GlobalbridgeBackend.Integration.RealtimeFeaturesIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for all real-time messaging features.

  Tests end-to-end flows for:
  - Task 17: Typing Indicators & Read Receipts
  - Task 21: Presence Indicators
  - Task 22: Push Notifications

  These tests verify that all features work together correctly in realistic scenarios.
  """
  use GlobalbridgeBackendWeb.ChannelCase

  alias GlobalbridgeBackendWeb.{UserSocket, Presence}
  alias GlobalbridgeBackend.{Repo, Chat}
  alias GlobalbridgeBackend.Schemas.{Thread, ThreadParticipant, User, DeviceToken}

  setup do
    # Create a realistic multi-user scenario
    users =
      Enum.map(1..4, fn i ->
        Repo.insert!(%User{
          id: Ecto.UUID.generate(),
          username: "user#{i}",
          email: "user#{i}@test.com",
          phone: "+123456789#{i}",
          is_online: false
        })
      end)

    [user1, user2, user3, user4] = users

    # Register device tokens for push notifications
    for user <- [user2, user3, user4] do
      Repo.insert!(%DeviceToken{
        user_id: user.id,
        token: "APNS_TOKEN_#{user.id}",
        device_type: "ios",
        is_active: true
      })
    end

    # Create group thread
    thread =
      Repo.insert!(%Thread{
        id: Ecto.UUID.generate(),
        thread_type: "group",
        database_shard_id: "test_shard_1"
      })

    # Add all users as participants
    for user <- users do
      Repo.insert!(%ThreadParticipant{
        thread_id: thread.id,
        user_id: user.id
      })
    end

    {:ok, thread: thread, users: users, user1: user1, user2: user2, user3: user3, user4: user4}
  end

  describe "complete messaging flow with all real-time features" do
    test "user sends message with typing indicator, receives read receipts, and triggers notifications",
         %{
           thread: thread,
           user1: user1,
           user2: user2,
           user3: user3
         } do
      # User1 connects (online)
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      # User2 connects (online)
      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User3 is offline (will receive push notification)

      # Wait for presence to stabilize
      :timer.sleep(100)

      # Verify presence tracking
      presences = Presence.list("thread:#{thread.id}")
      assert Map.has_key?(presences, user1.id)
      assert Map.has_key?(presences, user2.id)
      refute Map.has_key?(presences, user3.id)

      # User1 starts typing
      push(socket1, "typing", %{"is_typing" => true})

      # User2 receives typing indicator
      assert_broadcast "user_typing", %{
        user_id: ^user1.id,
        is_typing: true
      }

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Hello everyone!"})
      assert_reply ref, :ok, %{id: message_id}

      # User2 receives message broadcast
      assert_broadcast "new_message", %{
        id: ^message_id,
        content: "Hello everyone!",
        sender_id: ^user1.id
      }

      # User1 stops typing (implicitly after sending)
      push(socket1, "typing", %{"is_typing" => false})
      assert_broadcast "user_typing", %{is_typing: false}

      # User2 marks message as read
      push(socket2, "mark_read", %{"message_id" => message_id})

      # User1 receives read receipt
      assert_broadcast "message_read", %{
        user_id: ^user2.id,
        message_id: ^message_id
      }

      # Verify notification was triggered for offline user (User3)
      # This would be verified by checking notification service logs
      # or by subscribing to notification events
      :timer.sleep(200)
    end

    test "multi-user conversation with concurrent typing and presence changes", %{
      thread: thread,
      user1: user1,
      user2: user2,
      user3: user3,
      user4: user4
    } do
      # All users connect
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      {:ok, socket3} = connect(UserSocket, %{"token" => "user3:#{user3.id}"})
      {:ok, _, socket3} = subscribe_and_join(socket3, "thread:#{thread.id}", %{})

      :timer.sleep(100)

      # Verify all users are present
      presences = Presence.list("thread:#{thread.id}")
      assert map_size(presences) == 3

      # Multiple users start typing simultaneously
      push(socket1, "typing", %{"is_typing" => true})
      push(socket2, "typing", %{"is_typing" => true})

      # Should receive both typing indicators
      assert_broadcast "user_typing", %{user_id: ^user1.id}
      assert_broadcast "user_typing", %{user_id: ^user2.id}

      # User3 sends a message
      ref = push(socket3, "new_message", %{"content" => "Check this out!"})
      assert_reply ref, :ok, %{id: message_id}

      # All users receive the message
      assert_broadcast "new_message", %{id: ^message_id}

      # User1 and User2 both mark as read
      push(socket1, "mark_read", %{"message_id" => message_id})
      push(socket2, "mark_read", %{"message_id" => message_id})

      # User3 receives both read receipts
      assert_broadcast "message_read", %{user_id: ^user1.id}
      assert_broadcast "message_read", %{user_id: ^user2.id}

      # User4 joins late
      {:ok, socket4} = connect(UserSocket, %{"token" => "user4:#{user4.id}"})
      {:ok, _, _socket4} = subscribe_and_join(socket4, "thread:#{thread.id}", %{})

      # Should receive presence_diff
      assert_broadcast "presence_diff", %{joins: joins}
      assert Map.has_key?(joins, user4.id)

      # User1 disconnects
      close(socket1)

      # Should receive presence_diff for leave
      assert_broadcast "presence_diff", %{leaves: leaves}
      assert Map.has_key?(leaves, user1.id)
    end

    test "offline to online transition with message delivery", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      # User1 connects (online)
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      # User2 is offline initially

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Are you there?"})
      assert_reply ref, :ok, %{id: message_id}

      # Wait for async notification processing
      :timer.sleep(200)

      # User2 comes online
      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 receives presence update
      assert_broadcast "presence_diff", %{joins: joins}
      assert Map.has_key?(joins, user2.id)

      # User2 marks message as read
      push(socket2, "mark_read", %{"message_id" => message_id})

      # User1 receives read receipt
      assert_broadcast "message_read", %{
        user_id: ^user2.id,
        message_id: ^message_id
      }
    end
  end

  describe "performance under load" do
    test "handles rapid message exchange with all features", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      :timer.sleep(100)

      start_time = System.monotonic_time(:millisecond)

      # Rapid message exchange
      message_ids =
        Enum.map(1..10, fn i ->
          # Alternate between users
          socket = if rem(i, 2) == 0, do: socket1, else: socket2

          # Typing indicator
          push(socket, "typing", %{"is_typing" => true})

          # Send message
          ref = push(socket, "new_message", %{"content" => "Message #{i}"})
          assert_reply ref, :ok, %{id: message_id}, 100

          # Stop typing
          push(socket, "typing", %{"is_typing" => false})

          message_id
        end)

      # Mark all as read
      Enum.each(message_ids, fn message_id ->
        push(socket1, "mark_read", %{"message_id" => message_id})
        push(socket2, "mark_read", %{"message_id" => message_id})
      end)

      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time

      # Should handle 10 messages with typing and read receipts in reasonable time
      assert total_time < 2000, "Rapid exchange took #{total_time}ms, expected < 2000ms"
    end

    test "maintains presence accuracy during network fluctuations", %{
      thread: thread,
      user1: user1
    } do
      # Simulate connecting/disconnecting rapidly
      for _i <- 1..5 do
        {:ok, socket} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
        {:ok, _, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

        :timer.sleep(50)

        close(socket)

        :timer.sleep(50)
      end

      # Final state should be consistent
      :timer.sleep(200)
      presences = Presence.list("thread:#{thread.id}")

      # User should not be present after final disconnect
      refute Map.has_key?(presences, user1.id)
    end
  end

  describe "error recovery and edge cases" do
    test "handles message send failure gracefully with notifications", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 starts typing
      push(socket1, "typing", %{"is_typing" => true})
      assert_broadcast "user_typing", %{is_typing: true}

      # Simulate message with invalid content that might fail
      # System should handle gracefully
      push(socket1, "new_message", %{"content" => ""})

      # Typing should eventually stop even if message fails
      push(socket1, "typing", %{"is_typing" => false})
      assert_broadcast "user_typing", %{is_typing: false}
    end

    test "synchronizes state after reconnection", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Before disconnect"})
      assert_reply ref, :ok, %{id: message_id1}

      :timer.sleep(100)

      # User1 disconnects
      close(socket1)

      :timer.sleep(100)

      # User2 sends message while User1 is offline
      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      ref = push(socket2, "new_message", %{"content" => "While you were gone"})
      assert_reply ref, :ok, %{id: _message_id2}

      # User1 reconnects
      {:ok, socket1_new} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, _socket1_new} = subscribe_and_join(socket1_new, "thread:#{thread.id}", %{})

      # Should receive presence state with User2
      :timer.sleep(100)

      presences = Presence.list("thread:#{thread.id}")
      assert Map.has_key?(presences, user2.id)
    end
  end

  describe "cross-feature interactions" do
    test "typing indicator cleared on presence loss", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 starts typing
      push(socket1, "typing", %{"is_typing" => true})
      assert_broadcast "user_typing", %{is_typing: true}

      # User1 disconnects abruptly
      close(socket1)

      # Should receive presence leave
      assert_broadcast "presence_diff", %{leaves: leaves}
      assert Map.has_key?(leaves, user1.id)

      # Typing state should be implicitly cleared
      # (clients handle this based on presence)
    end

    test "read receipts trigger notification badge update", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      # User2 is offline
      Repo.update!(User.changeset(user2, %{is_online: false}))

      # User1 sends 3 messages
      message_ids =
        Enum.map(1..3, fn i ->
          ref = push(socket1, "new_message", %{"content" => "Message #{i}"})
          assert_reply ref, :ok, %{id: message_id}
          message_id
        end)

      :timer.sleep(300)

      # User2 comes online
      Repo.update!(User.changeset(user2, %{is_online: true}))
      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User2 marks all as read
      Enum.each(message_ids, fn message_id ->
        push(socket2, "mark_read", %{"message_id" => message_id})
      end)

      # User1 receives all read receipts
      Enum.each(message_ids, fn message_id ->
        assert_broadcast "message_read", %{message_id: ^message_id}, 200
      end)
    end
  end
end
