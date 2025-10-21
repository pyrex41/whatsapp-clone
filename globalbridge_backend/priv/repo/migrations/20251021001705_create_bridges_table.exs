defmodule GlobalbridgeBackend.Repo.Migrations.CreateBridgesTable do
  use Ecto.Migration

  def change do
    create table(:bridges, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :bridge_type, :string, null: false
      add :phone_number, :string, null: false
      add :session_data, :map
      add :status, :string, default: "disconnected"
      add :last_connected_at, :utc_datetime
      add :error_message, :text
      add :qr_code, :text
      add :is_active, :boolean, default: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:bridges, [:user_id, :bridge_type])
    create index(:bridges, [:status])
    create index(:bridges, [:is_active])
  end
end
