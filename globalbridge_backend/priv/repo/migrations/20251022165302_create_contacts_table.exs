defmodule GlobalbridgeBackend.Repo.Migrations.CreateContactsTable do
  use Ecto.Migration

  def change do
    create table(:contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :contact_user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :display_name_override, :string  # Optional custom name for this contact
      add :is_favorite, :boolean, default: false
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    # Ensure a user can't add the same contact twice
    create unique_index(:contacts, [:user_id, :contact_user_id])
    create index(:contacts, [:user_id])
    create index(:contacts, [:contact_user_id])
    create index(:contacts, [:updated_at])
  end
end
