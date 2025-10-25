defmodule GlobalbridgeBackend.Repo.Migrations.AddDetectedLanguageToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :detected_language, :string, size: 10
    end

    create index(:messages, [:detected_language])
  end
end
