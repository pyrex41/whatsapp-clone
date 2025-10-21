defmodule GlobalbridgeBackend.Repo.Migrations.CreateDevicesTable do
  use Ecto.Migration

  def change do
    create table(:devices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, :string, null: false
      add :device_name, :string, null: false
      add :device_type, :string, null: false
      add :push_token, :string
      add :last_active_at, :utc_datetime
      add :is_active, :boolean, default: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:devices, [:device_id])
    create index(:devices, [:user_id])
    create index(:devices, [:is_active])
  end
end
