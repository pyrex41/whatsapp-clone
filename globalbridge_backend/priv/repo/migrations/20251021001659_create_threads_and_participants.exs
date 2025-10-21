defmodule GlobalbridgeBackend.Repo.Migrations.CreateThreadsAndParticipants do
  use Ecto.Migration

  def change do
    create table(:threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :thread_type, :string, null: false
      add :title, :string
      add :avatar_url, :string
      add :last_message_at, :utc_datetime
      add :is_archived, :boolean, default: false
      add :is_muted, :boolean, default: false
      add :database_shard_id, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:threads, [:thread_type])
    create index(:threads, [:last_message_at])
    create unique_index(:threads, [:database_shard_id])

    create table(:thread_participants, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :role, :string, default: "member"
      add :joined_at, :utc_datetime
      add :left_at, :utc_datetime
      add :is_active, :boolean, default: true
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:thread_participants, [:thread_id, :user_id])
    create index(:thread_participants, [:user_id])
    create index(:thread_participants, [:is_active])
  end
end
