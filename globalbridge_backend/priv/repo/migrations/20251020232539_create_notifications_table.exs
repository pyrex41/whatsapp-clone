defmodule GlobalbridgeBackend.Repo.Migrations.CreateNotificationsTable do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :message_id, :binary_id

      # Notification type: "message", "mention", "reaction"
      add :notification_type, :string, null: false

      # Delivery tracking
      add :device_token, :string, null: false
      add :platform, :string, null: false  # "apns" or "fcm"
      add :status, :string, null: false, default: "pending"  # "pending", "sent", "delivered", "failed"
      add :sent_at, :utc_datetime
      add :delivered_at, :utc_datetime
      add :failed_at, :utc_datetime
      add :error_message, :text

      # Notification payload
      add :title, :string, null: false
      add :body, :text, null: false
      add :badge_count, :integer, default: 0
      add :sound, :string, default: "default"

      # Retry tracking
      add :retry_count, :integer, default: 0
      add :last_retry_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # Indexes for efficient queries
    create index(:notifications, [:user_id])
    create index(:notifications, [:thread_id])
    create index(:notifications, [:message_id])
    create index(:notifications, [:status])
    create index(:notifications, [:platform])
    create index(:notifications, [:notification_type])
    create index(:notifications, [:inserted_at])

    # Composite index for finding pending notifications to retry
    create index(:notifications, [:status, :retry_count, :last_retry_at])
  end
end
