defmodule GlobalbridgeBackend.Repo.Migrations.AddAuth0FieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:auth0_id, :string)
      add(:email, :string)
    end

    create(unique_index(:users, [:auth0_id]))
    create(unique_index(:users, [:email]))
  end
end
