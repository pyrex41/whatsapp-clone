defmodule GlobalbridgeBackend.Repo.Migrations.CreateUserTranslationPreferences do
  use Ecto.Migration

  def change do
    create table(:user_translation_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Global translation preferences
      add :auto_translate_incoming, :boolean, default: true, null: false
      add :auto_translate_outgoing, :boolean, default: true, null: false
      add :show_translation_offers, :boolean, default: true, null: false

      # Default behavior when language mismatch detected
      add :default_translation_behavior, :string, default: "prompt", null: false
      # "prompt" - Show language picker
      # "auto" - Auto-translate to preferred language
      # "off" - Never translate

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_translation_preferences, [:user_id])
  end
end
