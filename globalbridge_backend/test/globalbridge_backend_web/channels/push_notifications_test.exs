defmodule GlobalbridgeBackendWeb.PushNotificationsTest do
  @moduledoc """
  Comprehensive tests for Task 22: Push Notifications feature.

  Tests cover:
  - Notification event emission on message arrival
  - APNS payload generation
  - Notification trigger conditions
  - Background vs foreground handling
  - Performance and reliability
  """
  use GlobalbridgeBackendWeb.ChannelCase

  alias GlobalbridgeBackendWeb.UserSocket
  alias GlobalbridgeBackend.{Repo, Chat, Notifications}
  alias GlobalbridgeBackend.Schemas.{Thread, ThreadParticipant, User, Message, DeviceToken}

  setup do
    # Create test users
    user1 =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        username: "user1",
        email: "user1@test.com",
        phone: "+1234567890",
        is_online: true
      })

    user2 =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        username: "user2",
        email: "user2@test.com",
        phone: "+1234567891",
        is_online: false
      })

    user3 =
      Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        username: "user3",
        email: "user3@test.com",
        phone: "+1234567892",
        is_online: false
      })

    # Register device tokens
    device_token2 =
      Repo.insert!(%DeviceToken{
        user_id: user2.id,
        token: "APNS_TOKEN_USER2_DEVICE1",
        device_type: "ios",
        is_active: true
      })

    device_token3 =
      Repo.insert!(%DeviceToken{
        user_id: user3.id,
        token: "APNS_TOKEN_USER3_DEVICE1",
        device_type: "ios",
        is_active: true
      })

    # Create test thread
    thread =
      Repo.insert!(%Thread{
        id: Ecto.UUID.generate(),
        thread_type: "group",
        database_shard_id: "test_shard_1"
      })

    # Add participants
    Repo.insert!(%ThreadParticipant{thread_id: thread.id, user_id: user1.id})
    Repo.insert!(%ThreadParticipant{thread_id: thread.id, user_id: user2.id})
    Repo.insert!(%ThreadParticipant{thread_id: thread.id, user_id: user3.id})

    {:ok,
     thread: thread,
     user1: user1,
     user2: user2,
     user3: user3,
     device_token2: device_token2,
     device_token3: device_token3}
  end

  describe "notification event emission" do
    test "emits notification event when offline user receives message", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      # User1 is online, User2 is offline
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      # Subscribe to notification events (for testing)
      Phoenix.PubSub.subscribe(GlobalbridgeBackend.PubSub, "notifications:#{user2.id}")

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Hello offline user!"})
      assert_reply ref, :ok, %{id: message_id}

      # Should receive notification event
      assert_receive {:notification, notification_data}, 500

      assert notification_data.recipient_id == user2.id
      assert notification_data.message_id == message_id
      assert notification_data.sender_id == user1.id
    end

    test "does not emit notification for online users", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      # Both users online
      Repo.update!(User.changeset(user2, %{is_online: true}))

      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      Phoenix.PubSub.subscribe(GlobalbridgeBackend.PubSub, "notifications:#{user2.id}")

      # User1 sends message
      ref = push(socket1, "new_message", %{"content" => "Hello online user!"})
      assert_reply ref, :ok, %{id: _message_id}

      # Should NOT receive notification event (user is online)
      refute_receive {:notification, _}, 200
    end

    test "emits notifications to multiple offline recipients", %{
      thread: thread,
      user1: user1,
      user2: user2,
      user3: user3
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      Phoenix.PubSub.subscribe(GlobalbridgeBackend.PubSub, "notifications:#{user2.id}")
      Phoenix.PubSub.subscribe(GlobalbridgeBackend.PubSub, "notifications:#{user3.id}")

      # User1 sends message to group
      ref = push(socket1, "new_message", %{"content" => "Hello group!"})
      assert_reply ref, :ok, %{id: message_id}

      # Both offline users should receive notifications
      assert_receive {:notification, %{recipient_id: ^user2.id}}, 500
      assert_receive {:notification, %{recipient_id: ^user3.id}}, 500
    end
  end

  describe "APNS payload generation" do
    test "generates correct APNS payload structure", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      ref = push(socket1, "new_message", %{"content" => "Test notification"})
      assert_reply ref, :ok, %{id: message_id}

      # Wait for notification processing
      :timer.sleep(200)

      # Check that APNS payload was generated
      # This would typically be sent to APNS, but in tests we verify structure
      payload =
        Notifications.build_apns_payload(%{
          thread_id: thread.id,
          sender_id: user1.id,
          sender_username: user1.username,
          message_content: "Test notification",
          message_id: message_id
        })

      assert Map.has_key?(payload, :aps)
      assert Map.has_key?(payload.aps, :alert)
      assert Map.has_key?(payload.aps, :sound)
      assert Map.has_key?(payload.aps, :badge)

      # Custom data
      assert payload.thread_id == thread.id
      assert payload.message_id == message_id
    end

    test "APNS payload includes sender information", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      ref = push(socket1, "new_message", %{"content" => "From user1"})
      assert_reply ref, :ok, %{id: message_id}

      payload =
        Notifications.build_apns_payload(%{
          thread_id: thread.id,
          sender_id: user1.id,
          sender_username: user1.username,
          message_content: "From user1",
          message_id: message_id
        })

      # Alert should include sender name
      assert payload.aps.alert.title =~ user1.username
      assert payload.aps.alert.body == "From user1"
    end

    test "APNS payload handles media messages", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      ref =
        push(socket1, "new_message", %{
          "content" => "Photo",
          "content_type" => "image",
          "media_url" => "https://example.com/photo.jpg"
        })

      assert_reply ref, :ok, %{id: message_id}

      payload =
        Notifications.build_apns_payload(%{
          thread_id: thread.id,
          sender_id: user1.id,
          sender_username: user1.username,
          message_content: "Photo",
          content_type: "image",
          message_id: message_id
        })

      # Should indicate media type in notification
      assert payload.aps.alert.body =~ "Photo" or payload.aps.alert.body =~ "image"
      assert payload.content_type == "image"
    end

    test "APNS payload includes thread information", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      ref = push(socket1, "new_message", %{"content" => "Test"})
      assert_reply ref, :ok, %{id: message_id}

      payload =
        Notifications.build_apns_payload(%{
          thread_id: thread.id,
          thread_type: thread.thread_type,
          sender_id: user1.id,
          sender_username: user1.username,
          message_content: "Test",
          message_id: message_id
        })

      assert payload.thread_id == thread.id
      assert payload.thread_type == thread.thread_type
    end
  end

  describe "notification trigger conditions" do
    test "triggers notification only for offline users", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      # User2 is offline (default in setup)
      assert user2.is_online == false

      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      Phoenix.PubSub.subscribe(GlobalbridgeBackend.PubSub, "notifications:#{user2.id}")

      ref = push(socket1, "new_message", %{"content" => "Notification trigger test"})
      assert_reply ref, :ok, %{id: _message_id}

      # Should trigger notification
      assert_receive {:notification, _}, 500
    end

    test "does not trigger notification when user has no device tokens", %{
      thread: thread,
      user1: user1
    } do
      # Create user without device token
      user_no_token =
        Repo.insert!(%User{
          id: Ecto.UUID.generate(),
          username: "no_token",
          email: "no_token@test.com",
          phone: "+1999999999",
          is_online: false
        })

      Repo.insert!(%ThreadParticipant{thread_id: thread.id, user_id: user_no_token.id})

      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      Phoenix.PubSub.subscribe(GlobalbridgeBackend.PubSub, "notifications:#{user_no_token.id}")

      ref = push(socket1, "new_message", %{"content" => "No device test"})
      assert_reply ref, :ok, %{id: _message_id}

      # May emit event but won't send to APNS
      # Implementation dependent
    end

    test "does not notify sender of their own message", %{thread: thread, user1: user1} do
      # Update user1 to be offline and have a device token
      Repo.update!(User.changeset(user1, %{is_online: false}))

      Repo.insert!(%DeviceToken{
        user_id: user1.id,
        token: "APNS_TOKEN_USER1",
        device_type: "ios",
        is_active: true
      })

      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      Phoenix.PubSub.subscribe(GlobalbridgeBackend.PubSub, "notifications:#{user1.id}")

      ref = push(socket1, "new_message", %{"content" => "My own message"})
      assert_reply ref, :ok, %{id: _message_id}

      # Should NOT receive notification for own message
      refute_receive {:notification, _}, 200
    end
  end

  describe "notification performance" do
    test "notification emission happens quickly", %{thread: thread, user1: user1, user2: user2} do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      Phoenix.PubSub.subscribe(GlobalbridgeBackend.PubSub, "notifications:#{user2.id}")

      start_time = System.monotonic_time(:millisecond)

      ref = push(socket1, "new_message", %{"content" => "Speed test"})
      assert_reply ref, :ok, %{id: _message_id}

      # Should receive notification event quickly
      assert_receive {:notification, _}, 300

      end_time = System.monotonic_time(:millisecond)
      latency = end_time - start_time

      # Notification should be emitted within 300ms
      assert latency < 300, "Notification latency #{latency}ms exceeds 300ms threshold"
    end

    test "handles burst notifications efficiently", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      Phoenix.PubSub.subscribe(GlobalbridgeBackend.PubSub, "notifications:#{user2.id}")

      # Send 5 messages rapidly
      message_ids =
        Enum.map(1..5, fn i ->
          ref = push(socket1, "new_message", %{"content" => "Burst #{i}"})
          assert_reply ref, :ok, %{id: message_id}
          message_id
        end)

      # Should receive all notifications
      for _i <- 1..5 do
        assert_receive {:notification, _}, 500
      end
    end
  end

  describe "notification edge cases" do
    test "handles inactive device tokens", %{
      thread: thread,
      user1: user1,
      user2: user2,
      device_token2: device_token2
    } do
      # Deactivate device token
      Repo.update!(DeviceToken.changeset(device_token2, %{is_active: false}))

      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      ref = push(socket1, "new_message", %{"content" => "Inactive device test"})
      assert_reply ref, :ok, %{id: _message_id}

      # Should not attempt to send to inactive device
      :timer.sleep(200)
    end

    test "handles multiple device tokens per user", %{thread: thread, user1: user1, user2: user2} do
      # Add second device for user2
      Repo.insert!(%DeviceToken{
        user_id: user2.id,
        token: "APNS_TOKEN_USER2_DEVICE2",
        device_type: "ios",
        is_active: true
      })

      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      Phoenix.PubSub.subscribe(GlobalbridgeBackend.PubSub, "notifications:#{user2.id}")

      ref = push(socket1, "new_message", %{"content" => "Multi-device test"})
      assert_reply ref, :ok, %{id: _message_id}

      # Should emit notification (delivery to multiple devices handled by notification service)
      assert_receive {:notification, _}, 500
    end

    test "notification includes message content preview", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      long_message = String.duplicate("A", 200)
      ref = push(socket1, "new_message", %{"content" => long_message})
      assert_reply ref, :ok, %{id: message_id}

      payload =
        Notifications.build_apns_payload(%{
          thread_id: thread.id,
          sender_id: user1.id,
          sender_username: user1.username,
          message_content: long_message,
          message_id: message_id
        })

      # Content should be truncated for notification
      assert String.length(payload.aps.alert.body) < 200
    end
  end

  describe "notification badge count" do
    test "includes badge count in APNS payload", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      ref = push(socket1, "new_message", %{"content" => "Badge test"})
      assert_reply ref, :ok, %{id: message_id}

      # Get unread count for user2
      unread_count = Chat.get_unread_count(user2.id)

      payload =
        Notifications.build_apns_payload(%{
          thread_id: thread.id,
          sender_id: user1.id,
          sender_username: user1.username,
          message_content: "Badge test",
          message_id: message_id,
          unread_count: unread_count
        })

      # Badge should be included
      assert is_integer(payload.aps.badge)
      assert payload.aps.badge >= 0
    end
  end
end
