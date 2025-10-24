defmodule GlobalbridgeBackend.Repo.Migrations.AddEmbeddingsToMessages do
  use Ecto.Migration

  def change do
    # Add embedding support to messages table
    alter table(:messages) do
      # Store embeddings as binary data (3072 floats * 4 bytes = ~12KB per message)
      add(:embedding, :binary)
      # Track which embedding model was used
      add(:embedding_model, :string, default: "text-embedding-3-large")
      # When the embedding was generated
      add(:embedding_generated_at, :integer)
    end

    # Create index for messages without embeddings (for background job processing)
    create(
      index(:messages, [:id], where: "embedding IS NULL", name: "messages_no_embedding_index")
    )

    # Note: vec0 virtual table creation is handled at runtime in ThreadRepo
    # since it requires per-thread database management
  end
end
