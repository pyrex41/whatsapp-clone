defmodule GlobalbridgeBackend.Repo.Migrations.CreateSyncAndCdcTables do
  use Ecto.Migration

  def change do
    create table(:sync_states, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, :binary_id, null: false
      add :thread_id, :binary_id
      add :entity_type, :string, null: false
      add :entity_id, :binary_id, null: false
      add :operation, :string, null: false
      add :last_sync_at, :utc_datetime
      add :sync_cursor, :integer
      add :is_synced, :boolean, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:sync_states, [:device_id])
    create index(:sync_states, [:thread_id])
    create index(:sync_states, [:entity_type, :entity_id])
    create index(:sync_states, [:is_synced])

    create table(:cdc_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :table_name, :string, null: false
      add :record_id, :binary_id, null: false
      add :operation, :string, null: false
      add :old_data, :map
      add :new_data, :map, null: false
      add :changed_fields, {:array, :string}
      add :user_id, :binary_id
      add :device_id, :binary_id
      add :timestamp, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:cdc_logs, [:table_name, :record_id])
    create index(:cdc_logs, [:timestamp])
    create index(:cdc_logs, [:user_id])
  end
end
