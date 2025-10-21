defmodule GlobalbridgeBackend.Repo.Migrations.AddTierToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :tier, :string, default: "free", null: false
    end

    # Add index for queries filtering by tier
    create index(:users, [:tier])
  end
end
