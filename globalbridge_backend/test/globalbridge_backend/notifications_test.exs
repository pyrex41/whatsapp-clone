defmodule GlobalbridgeBackend.NotificationsTest do
  use GlobalbridgeBackend.DataCase, async: true

  alias GlobalbridgeBackend.{Notifications, Repo}
  alias GlobalbridgeBackend.Schemas.{Notification, User, Device, Thread, ThreadParticipant}

  describe "notification creation" do
    setup do
      # Create test user
      user =
        %User{
          id: Ecto.UUID.generate(),
          phone_number: "+1234567890",
          password_hash: "test_hash"
        }
        |> Repo.insert!()

      # Create test device
      device =
        %Device{
          id: Ecto.UUID.generate(),
          user_id: user.id,
          device_token: "test_apns_token_123",
          device_type: "ios",
          platform: "apns",
          is_active: true
        }
        |> Repo.insert!()

      # Create test thread
      thread =
        %Thread{
          id: Ecto.UUID.generate(),
          thread_type: "direct",
          database_shard_id: "main"
        }
        |> Repo.insert!()

      message_id = Ecto.UUID.generate()

      {:ok, user: user, device: device, thread: thread, message_id: message_id}
    end

    test "creates notification record", %{
      user: user,
      device: device,
      thread: thread,
      message_id: message_id
    } do
      attrs = %{
        user_id: user.id,
        thread_id: thread.id,
        message_id: message_id,
        device_token: device.device_token,
        platform: "apns",
        notification_type: "message",
        title: "Alice",
        body: "Hello there!",
        badge_count: 1
      }

      assert {:ok, notification} = Notifications.create_notification(attrs)

      assert notification.user_id == user.id
      assert notification.thread_id == thread.id
      assert notification.status == "pending"
      assert notification.platform == "apns"
      assert notification.notification_type == "message"
    end

    test "validates required fields" do
      attrs = %{
        user_id: Ecto.UUID.generate(),
        thread_id: Ecto.UUID.generate()
        # Missing required fields
      }

      assert {:error, changeset} = Notifications.create_notification(attrs)
      assert changeset.errors[:notification_type] != nil
      assert changeset.errors[:device_token] != nil
      assert changeset.errors[:platform] != nil
    end

    test "validates notification_type enum" do
      attrs = %{
        user_id: Ecto.UUID.generate(),
        thread_id: Ecto.UUID.generate(),
        notification_type: "invalid_type",
        device_token: "token",
        platform: "apns",
        title: "Test",
        body: "Test"
      }

      assert {:error, changeset} = Notifications.create_notification(attrs)
      assert changeset.errors[:notification_type] != nil
    end

    test "validates platform enum" do
      attrs = %{
        user_id: Ecto.UUID.generate(),
        thread_id: Ecto.UUID.generate(),
        notification_type: "message",
        device_token: "token",
        platform: "invalid_platform",
        title: "Test",
        body: "Test"
      }

      assert {:error, changeset} = Notifications.create_notification(attrs)
      assert changeset.errors[:platform] != nil
    end
  end

  describe "notification sending" do
    setup do
      user =
        %User{
          id: Ecto.UUID.generate(),
          phone_number: "+1234567890",
          password_hash: "test_hash"
        }
        |> Repo.insert!()

      device =
        %Device{
          id: Ecto.UUID.generate(),
          user_id: user.id,
          device_token: "test_token",
          device_type: "ios",
          platform: "apns",
          is_active: true
        }
        |> Repo.insert!()

      thread =
        %Thread{
          id: Ecto.UUID.generate(),
          thread_type: "direct",
          database_shard_id: "main"
        }
        |> Repo.insert!()

      {:ok, user: user, device: device, thread: thread}
    end

    test "sends APNS notification", %{user: user, device: device, thread: thread} do
      notification =
        %Notification{
          user_id: user.id,
          thread_id: thread.id,
          message_id: Ecto.UUID.generate(),
          device_token: device.device_token,
          platform: "apns",
          notification_type: "message",
          title: "Test",
          body: "Test message",
          badge_count: 1,
          status: "pending"
        }
        |> Repo.insert!()

      assert {:ok, updated} = Notifications.send_notification(notification)
      assert updated.status == "sent"
      assert updated.sent_at != nil
    end

    test "sends FCM notification", %{user: user, thread: thread} do
      notification =
        %Notification{
          user_id: user.id,
          thread_id: thread.id,
          message_id: Ecto.UUID.generate(),
          device_token: "fcm_token",
          platform: "fcm",
          notification_type: "message",
          title: "Test",
          body: "Test message",
          badge_count: 1,
          status: "pending"
        }
        |> Repo.insert!()

      assert {:ok, updated} = Notifications.send_notification(notification)
      assert updated.status == "sent"
      assert updated.sent_at != nil
    end
  end

  describe "notification delivery tracking" do
    test "marks notification as delivered" do
      notification =
        %Notification{
          user_id: Ecto.UUID.generate(),
          thread_id: Ecto.UUID.generate(),
          message_id: Ecto.UUID.generate(),
          device_token: "token",
          platform: "apns",
          notification_type: "message",
          title: "Test",
          body: "Test",
          status: "sent"
        }
        |> Repo.insert!()

      updated =
        notification
        |> Notification.delivered_changeset()
        |> Repo.update!()

      assert updated.status == "delivered"
      assert updated.delivered_at != nil
    end

    test "marks notification as failed with retry count" do
      notification =
        %Notification{
          user_id: Ecto.UUID.generate(),
          thread_id: Ecto.UUID.generate(),
          message_id: Ecto.UUID.generate(),
          device_token: "token",
          platform: "apns",
          notification_type: "message",
          title: "Test",
          body: "Test",
          status: "sent",
          retry_count: 0
        }
        |> Repo.insert!()

      updated =
        notification
        |> Notification.failed_changeset("Connection timeout")
        |> Repo.update!()

      assert updated.status == "failed"
      assert updated.failed_at != nil
      assert updated.error_message == "Connection timeout"
      assert updated.retry_count == 1
      assert updated.last_retry_at != nil
    end
  end

  describe "notification queries" do
    setup do
      user =
        %User{
          id: Ecto.UUID.generate(),
          phone_number: "+1234567890",
          password_hash: "test_hash"
        }
        |> Repo.insert!()

      thread =
        %Thread{
          id: Ecto.UUID.generate(),
          thread_type: "direct",
          database_shard_id: "main"
        }
        |> Repo.insert!()

      {:ok, user: user, thread: thread}
    end

    test "retrieves user notifications with limit", %{user: user, thread: thread} do
      # Create multiple notifications
      for i <- 1..10 do
        %Notification{
          user_id: user.id,
          thread_id: thread.id,
          message_id: Ecto.UUID.generate(),
          device_token: "token_#{i}",
          platform: "apns",
          notification_type: "message",
          title: "Test #{i}",
          body: "Body #{i}",
          status: "sent"
        }
        |> Repo.insert!()
      end

      # Get with default limit
      notifications = Notifications.list_user_notifications(user.id)
      assert length(notifications) <= 50

      # Get with custom limit
      notifications = Notifications.list_user_notifications(user.id, limit: 5)
      assert length(notifications) == 5
    end

    test "gets delivery statistics", %{user: user, thread: thread} do
      # Create notifications with different statuses
      statuses = ["sent", "sent", "delivered", "failed", "pending"]

      for status <- statuses do
        %Notification{
          user_id: user.id,
          thread_id: thread.id,
          message_id: Ecto.UUID.generate(),
          device_token: "token",
          platform: "apns",
          notification_type: "message",
          title: "Test",
          body: "Test",
          status: status
        }
        |> Repo.insert!()
      end

      stats = Notifications.get_delivery_stats(user.id)

      assert stats["sent"] == 2
      assert stats["delivered"] == 1
      assert stats["failed"] == 1
      assert stats["pending"] == 1
    end
  end
end
