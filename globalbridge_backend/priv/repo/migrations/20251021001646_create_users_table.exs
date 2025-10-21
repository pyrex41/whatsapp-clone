defmodule GlobalbridgeBackend.Repo.Migrations.CreateUsersTable do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :username, :string, null: false
      add :phone_number, :string, null: false
      add :password_hash, :string, null: false
      add :display_name, :string
      add :avatar_url, :string
      add :status_message, :string
      add :public_key, :text
      add :last_seen_at, :utc_datetime
      add :is_online, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:username])
    create unique_index(:users, [:phone_number])
    create index(:users, [:is_online])
  end
end
