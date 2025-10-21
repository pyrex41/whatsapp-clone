defmodule GlobalbridgeBackend.Repo.Migrations.CreateMessagesTable do
  use Ecto.Migration

  def change do
    create table(:messages, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false)
      add(:sender_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:content, :text)
      add(:content_type, :string, null: false)
      add(:media_url, :string)
      add(:media_size, :integer)
      add(:media_mime_type, :string)
      add(:is_encrypted, :boolean, default: false)
      add(:encryption_key_id, :string)
      add(:reply_to_id, references(:messages, type: :binary_id, on_delete: :nilify_all))
      add(:is_deleted, :boolean, default: false)
      add(:deleted_at, :utc_datetime)
      add(:edited_at, :utc_datetime)
      add(:client_created_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:messages, [:thread_id]))
    create(index(:messages, [:sender_id]))
    create(index(:messages, [:inserted_at]))
    create(index(:messages, [:is_deleted]))
  end
end
