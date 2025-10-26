defmodule GlobalbridgeBackend.Repo.Migrations.AddTranslationFieldsToThreadParticipants do
  use Ecto.Migration

  def change do
    alter table(:thread_participants) do
      # Per-thread translation overrides (null = use global preference)
      add :auto_translate_incoming, :boolean, default: nil
      add :auto_translate_outgoing, :boolean, default: nil

      # Preferred language for this specific thread (overrides user's global preferred_language)
      add :preferred_thread_language, :string, default: nil
    end
  end
end
