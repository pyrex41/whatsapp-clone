defmodule GlobalbridgeBackend.Repo.Migrations.CreateReadReceiptsTable do
  use Ecto.Migration

  def change do
    create table(:read_receipts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:message_id, references(:messages, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:read_at, :utc_datetime, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:read_receipts, [:message_id, :user_id]))
    create(index(:read_receipts, [:user_id]))
    create(index(:read_receipts, [:read_at]))
  end
end
