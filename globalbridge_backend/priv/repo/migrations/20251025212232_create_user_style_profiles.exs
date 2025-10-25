defmodule GlobalbridgeBackend.Repo.Migrations.CreateUserStyleProfiles do
  use Ecto.Migration

  def change do
    create table(:user_style_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # Core style metrics
      add :avg_sentence_length, :float, default: 0.0
      add :formality_level, :float, default: 0.5
      add :vocabulary_complexity, :float, default: 0.5
      add :emoji_frequency, :float, default: 0.0

      # Flexible metadata for advanced patterns
      add :style_metadata, :map, default: %{}

      # Learning metrics
      add :messages_analyzed, :integer, default: 0
      add :last_updated_at, :utc_datetime
      add :confidence_score, :float, default: 0.0

      timestamps()
    end

    create unique_index(:user_style_profiles, [:user_id])
    create index(:user_style_profiles, [:confidence_score])
  end
end
