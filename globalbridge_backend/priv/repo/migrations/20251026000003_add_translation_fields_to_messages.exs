defmodule GlobalbridgeBackend.Repo.Migrations.AddTranslationFieldsToMessages do
  use Ecto.Migration

  def change do
    # Note: This migration needs to be applied to BOTH:
    # 1. The message table template in new thread databases
    # 2. All existing thread databases

    # This will be handled by the dynamic migration runner
    :ok
  end

  # Migration SQL to be applied to thread databases
  def thread_database_migration_sql do
    """
    ALTER TABLE messages ADD COLUMN original_content TEXT;
    ALTER TABLE messages ADD COLUMN translated_content TEXT;
    ALTER TABLE messages ADD COLUMN source_language TEXT;
    ALTER TABLE messages ADD COLUMN target_language TEXT;
    ALTER TABLE messages ADD COLUMN is_translated BOOLEAN DEFAULT 0;
    """
  end
end
