defmodule GlobalbridgeBackend.Repo.Migrations.AddPreferredLanguageToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :preferred_language, :string, size: 10, default: "en"
    end

    create index(:users, [:preferred_language])
  end
end
