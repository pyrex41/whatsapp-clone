defmodule GlobalbridgeBackend.Repo.Migrations.CreateSuggestionFeedbacks do
  use Ecto.Migration

  def change do
    create table(:suggestion_feedbacks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all)

      # Type of suggestion (smart_reply, confusion_clarification, complexity_simplification)
      add :suggestion_type, :string, null: false

      # The actual suggestion content that was presented
      add :suggestion_content, :string, null: false

      # Whether the user accepted the suggestion (clicked/used it)
      add :accepted, :boolean, default: false, null: false

      # Optional: user's modified version (if they edited before accepting)
      add :user_modified_content, :string

      # Optional: reason for rejection (if provided)
      add :rejection_reason, :string

      # Context at time of suggestion
      add :context_metadata, :map, default: %{}

      # Response time metrics
      add :time_to_response_ms, :integer
      add :suggestion_position, :integer

      # Confidence score of the suggestion when generated
      add :confidence_score, :float

      timestamps()
    end

    create index(:suggestion_feedbacks, [:user_id])
    create index(:suggestion_feedbacks, [:thread_id])
    create index(:suggestion_feedbacks, [:suggestion_type])
    create index(:suggestion_feedbacks, [:accepted])
    create index(:suggestion_feedbacks, [:user_id, :suggestion_type])
    create index(:suggestion_feedbacks, [:user_id, :accepted])
  end
end
