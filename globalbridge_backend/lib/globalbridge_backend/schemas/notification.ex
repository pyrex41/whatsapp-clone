defmodule GlobalbridgeBackend.Schemas.Notification do
  @moduledoc """
  Notification schema for tracking push notification delivery.

  Stores notification events and their delivery status to APNS/FCM.
  Used for analytics and retry logic.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "notifications" do
    field(:user_id, :binary_id)
    field(:thread_id, :binary_id)
    field(:message_id, :binary_id)
    field(:bridge_id, :binary_id)

    # Notification type: "message", "mention", "reaction", "bridge_connected", "bridge_disconnected", "bridge_error"
    field(:notification_type, :string)

    # Delivery tracking
    field(:device_token, :string)
    # "apns" or "fcm"
    field(:platform, :string)
    # "pending", "sent", "delivered", "failed"
    field(:status, :string)
    field(:sent_at, :utc_datetime)
    field(:delivered_at, :utc_datetime)
    field(:failed_at, :utc_datetime)
    field(:error_message, :string)

    # Notification payload
    field(:title, :string)
    field(:body, :string)
    field(:badge_count, :integer)
    field(:sound, :string, default: "default")

    # Retry tracking
    field(:retry_count, :integer, default: 0)
    field(:last_retry_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for notification creation.
  """
  def create_changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :user_id,
      :thread_id,
      :message_id,
      :bridge_id,
      :notification_type,
      :device_token,
      :platform,
      :title,
      :body,
      :badge_count,
      :sound
    ])
    |> validate_required([
      :user_id,
      :notification_type,
      :device_token,
      :platform,
      :title,
      :body
    ])
    |> validate_inclusion(:notification_type, [
      "message",
      "mention",
      "reaction",
      "bridge_connected",
      "bridge_disconnected",
      "bridge_error"
    ])
    |> validate_inclusion(:platform, ["apns", "fcm"])
    |> put_change(:status, "pending")
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:bridge_id)
  end

  @doc """
  Changeset for marking notification as sent.
  """
  def sent_changeset(notification) do
    notification
    |> change()
    |> put_change(:status, "sent")
    |> put_change(:sent_at, DateTime.utc_now())
  end

  @doc """
  Changeset for marking notification as delivered.
  """
  def delivered_changeset(notification) do
    notification
    |> change()
    |> put_change(:status, "delivered")
    |> put_change(:delivered_at, DateTime.utc_now())
  end

  @doc """
  Changeset for marking notification as failed.
  """
  def failed_changeset(notification, error_message) do
    notification
    |> change()
    |> put_change(:status, "failed")
    |> put_change(:failed_at, DateTime.utc_now())
    |> put_change(:error_message, error_message)
    |> increment_retry_count()
  end

  defp increment_retry_count(changeset) do
    retry_count = get_field(changeset, :retry_count, 0)

    changeset
    |> put_change(:retry_count, retry_count + 1)
    |> put_change(:last_retry_at, DateTime.utc_now())
  end
end
