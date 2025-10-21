defmodule GlobalbridgeBackend.Notifications do
  @moduledoc """
  Context module for push notification management.

  Handles notification creation, delivery, and tracking for both
  APNS (iOS) and FCM (Android) platforms.

  ## Features
  - APNS integration for iOS devices
  - FCM integration for Android devices
  - Retry logic for failed deliveries
  - Delivery status tracking
  - Badge count management

  ## Usage

      # Send notification for new message
      Notifications.send_message_notification(
        user_id: "user-123",
        thread_id: "thread-456",
        message: "Hello!",
        sender_name: "Alice"
      )
  """

  require Logger
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{Notification, Device, User}
  import Ecto.Query

  @max_retry_attempts 3

  @doc """
  Send push notification for a new message.

  Automatically handles:
  - Fetching user's devices
  - Determining platform (APNS/FCM)
  - Creating notification records
  - Queueing delivery
  """
  def send_message_notification(attrs) do
    user_id = attrs[:user_id]
    thread_id = attrs[:thread_id]
    message_id = attrs[:message_id]
    sender_name = attrs[:sender_name] || "Someone"
    message_content = attrs[:message_content] || "New message"

    # Get all devices for the user
    case get_user_devices(user_id) do
      [] ->
        Logger.info("No devices registered for user #{user_id}")
        {:ok, []}

      devices ->
        # Create notification for each device
        notifications =
          Enum.map(devices, fn device ->
            create_and_send_notification(%{
              user_id: user_id,
              thread_id: thread_id,
              message_id: message_id,
              device_token: device.device_token,
              platform: device.platform,
              notification_type: "message",
              title: sender_name,
              body: message_content,
              badge_count: get_user_badge_count(user_id),
              sound: "default"
            })
          end)

        {:ok, notifications}
    end
  end

  @doc """
  Create a notification record and queue it for delivery.
  """
  def create_and_send_notification(attrs) do
    with {:ok, notification} <- create_notification(attrs),
         {:ok, notification} <- send_notification(notification) do
      {:ok, notification}
    else
      {:error, reason} ->
        Logger.error("Failed to create/send notification: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Create a notification record in the database.
  """
  def create_notification(attrs) do
    %Notification{}
    |> Notification.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Send notification via APNS or FCM based on platform.
  """
  def send_notification(%Notification{platform: "apns"} = notification) do
    send_apns_notification(notification)
  end

  def send_notification(%Notification{platform: "fcm"} = notification) do
    send_fcm_notification(notification)
  end

  @doc """
  Send notification via Apple Push Notification Service (APNS).

  Uses Pigeon library for APNS communication.
  """
  defp send_apns_notification(notification) do
    # Build APNS notification payload
    payload = %{
      aps: %{
        alert: %{
          title: notification.title,
          body: notification.body
        },
        badge: notification.badge_count,
        sound: notification.sound,
        "thread-id": notification.thread_id
      },
      # Custom data
      message_id: notification.message_id,
      notification_type: notification.notification_type
    }

    # TODO: Integrate with Pigeon APNS
    # For now, simulate async delivery
    Task.Supervisor.start_child(GlobalbridgeBackend.TaskSupervisor, fn ->
      simulate_apns_delivery(notification, payload)
    end)

    # Mark as sent immediately (async)
    notification
    |> Notification.sent_changeset()
    |> Repo.update()
  end

  @doc """
  Send notification via Firebase Cloud Messaging (FCM).
  """
  defp send_fcm_notification(notification) do
    # Build FCM notification payload
    payload = %{
      notification: %{
        title: notification.title,
        body: notification.body,
        sound: notification.sound
      },
      data: %{
        thread_id: notification.thread_id,
        message_id: notification.message_id,
        notification_type: notification.notification_type
      },
      android: %{
        notification: %{
          channel_id: "messages",
          priority: "high"
        }
      }
    }

    # TODO: Integrate with FCM HTTP v1 API
    # For now, simulate async delivery
    Task.Supervisor.start_child(GlobalbridgeBackend.TaskSupervisor, fn ->
      simulate_fcm_delivery(notification, payload)
    end)

    # Mark as sent immediately (async)
    notification
    |> Notification.sent_changeset()
    |> Repo.update()
  end

  @doc """
  Simulate APNS delivery for testing purposes.
  Replace this with actual Pigeon integration in production.
  """
  defp simulate_apns_delivery(notification, _payload) do
    # Simulate network delay
    Process.sleep(100)

    # Simulate 95% success rate
    if :rand.uniform(100) <= 95 do
      notification
      |> Notification.delivered_changeset()
      |> Repo.update()

      Logger.info("APNS notification delivered: #{notification.id}")
    else
      notification
      |> Notification.failed_changeset("Simulated APNS delivery failure")
      |> Repo.update()

      Logger.error("APNS notification failed: #{notification.id}")

      # Retry if under max attempts
      if notification.retry_count < @max_retry_attempts do
        retry_notification(notification)
      end
    end
  end

  @doc """
  Simulate FCM delivery for testing purposes.
  Replace this with actual FCM HTTP v1 API integration in production.
  """
  defp simulate_fcm_delivery(notification, _payload) do
    # Simulate network delay
    Process.sleep(100)

    # Simulate 95% success rate
    if :rand.uniform(100) <= 95 do
      notification
      |> Notification.delivered_changeset()
      |> Repo.update()

      Logger.info("FCM notification delivered: #{notification.id}")
    else
      notification
      |> Notification.failed_changeset("Simulated FCM delivery failure")
      |> Repo.update()

      Logger.error("FCM notification failed: #{notification.id}")

      # Retry if under max attempts
      if notification.retry_count < @max_retry_attempts do
        retry_notification(notification)
      end
    end
  end

  @doc """
  Retry failed notification delivery with exponential backoff.
  """
  defp retry_notification(notification) do
    # Calculate backoff delay: 2^retry_count seconds
    delay = :math.pow(2, notification.retry_count) |> trunc() |> :timer.seconds()

    # Schedule retry
    Process.send_after(self(), {:retry_notification, notification.id}, delay)
  end

  @doc """
  Get all active devices for a user.
  """
  defp get_user_devices(user_id) do
    query =
      from(d in Device,
        where: d.user_id == ^user_id and d.is_active == true,
        select: d
      )

    Repo.all(query)
  end

  @doc """
  Get total unread message count for badge display.
  """
  defp get_user_badge_count(user_id) do
    # TODO: Implement actual unread count from messages
    # For now, return 0
    0
  end

  @doc """
  Handle notification retry from scheduled process message.
  """
  def handle_info({:retry_notification, notification_id}, state) do
    case Repo.get(Notification, notification_id) do
      nil ->
        Logger.warn("Notification not found for retry: #{notification_id}")

      notification ->
        send_notification(notification)
    end

    {:noreply, state}
  end

  @doc """
  Get notification delivery statistics for a user.
  """
  def get_delivery_stats(user_id) do
    query =
      from(n in Notification,
        where: n.user_id == ^user_id,
        group_by: n.status,
        select: {n.status, count(n.id)}
      )

    Repo.all(query)
    |> Map.new()
  end

  @doc """
  Get recent notifications for a user.
  """
  def list_user_notifications(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    query =
      from(n in Notification,
        where: n.user_id == ^user_id,
        order_by: [desc: n.inserted_at],
        limit: ^limit
      )

    Repo.all(query)
  end
end
