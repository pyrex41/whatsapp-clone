defmodule GlobalbridgeBackend.Schemas.SuggestionFeedback do
  @moduledoc """
  Schema for tracking user feedback on AI-generated suggestions.

  Stores whether users accepted or rejected suggestions, enabling the system
  to learn from feedback and improve future suggestions. This creates a
  continuous learning loop where the AI gets better at understanding each
  user's preferences over time.

  Feedback data is used by:
  - FeedbackLearner: Analyzes patterns in accepted vs rejected suggestions
  - SmartReplyGenerator: Adjusts suggestion strategies based on success rates
  - ConversationMonitor: Improves confusion/complexity detection thresholds
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "suggestion_feedbacks" do
    belongs_to :user, GlobalbridgeBackend.Schemas.User, type: :binary_id
    belongs_to :thread, GlobalbridgeBackend.Schemas.Thread, type: :binary_id

    # Type of suggestion (smart_reply, confusion_clarification, complexity_simplification)
    field :suggestion_type, :string

    # The actual suggestion content that was presented
    field :suggestion_content, :string

    # Whether the user accepted the suggestion (clicked/used it)
    field :accepted, :boolean, default: false

    # Optional: user's modified version (if they edited before accepting)
    field :user_modified_content, :string

    # Optional: reason for rejection (if provided)
    field :rejection_reason, :string

    # Context at time of suggestion
    field :context_metadata, :map, default: %{}

    # Response time metrics
    field :time_to_response_ms, :integer  # How long until user responded
    field :suggestion_position, :integer  # Which suggestion (1st, 2nd, 3rd) if multiple

    # Confidence score of the suggestion when generated
    field :confidence_score, :float

    timestamps()
  end

  @valid_suggestion_types ~w(smart_reply confusion_clarification complexity_simplification)

  @doc """
  Changeset for creating suggestion feedback.

  ## Required Fields
  - user_id
  - suggestion_type
  - suggestion_content
  - accepted

  ## Optional Fields
  - thread_id
  - user_modified_content
  - rejection_reason
  - context_metadata
  - time_to_response_ms
  - suggestion_position
  - confidence_score
  """
  def changeset(suggestion_feedback, attrs) do
    suggestion_feedback
    |> cast(attrs, [
      :user_id,
      :thread_id,
      :suggestion_type,
      :suggestion_content,
      :accepted,
      :user_modified_content,
      :rejection_reason,
      :context_metadata,
      :time_to_response_ms,
      :suggestion_position,
      :confidence_score
    ])
    |> validate_required([:user_id, :suggestion_type, :suggestion_content, :accepted])
    |> validate_inclusion(:suggestion_type, @valid_suggestion_types)
    |> validate_length(:suggestion_content, max: 5000)
    |> validate_length(:user_modified_content, max: 5000)
    |> validate_length(:rejection_reason, max: 500)
    |> validate_number(:confidence_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:time_to_response_ms, greater_than_or_equal_to: 0)
    |> validate_number(:suggestion_position, greater_than: 0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:thread_id)
  end

  @doc """
  Creates a feedback record for an accepted suggestion.

  ## Parameters
  - user_id: The user who accepted the suggestion
  - suggestion: Map containing suggestion details
  - opts: Optional parameters (thread_id, time_to_response_ms, etc.)

  ## Returns
  - Changeset ready for insertion
  """
  def create_accepted(user_id, suggestion, opts \\ []) do
    attrs = %{
      user_id: user_id,
      thread_id: Keyword.get(opts, :thread_id),
      suggestion_type: suggestion.type,
      suggestion_content: suggestion.content,
      accepted: true,
      user_modified_content: Keyword.get(opts, :modified_content),
      context_metadata: suggestion.context || %{},
      time_to_response_ms: Keyword.get(opts, :time_to_response_ms),
      suggestion_position: suggestion.position,
      confidence_score: suggestion.confidence
    }

    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc """
  Creates a feedback record for a rejected suggestion.

  ## Parameters
  - user_id: The user who rejected the suggestion
  - suggestion: Map containing suggestion details
  - reason: Optional reason for rejection
  - opts: Optional parameters (thread_id, time_to_response_ms, etc.)

  ## Returns
  - Changeset ready for insertion
  """
  def create_rejected(user_id, suggestion, reason \\ nil, opts \\ []) do
    attrs = %{
      user_id: user_id,
      thread_id: Keyword.get(opts, :thread_id),
      suggestion_type: suggestion.type,
      suggestion_content: suggestion.content,
      accepted: false,
      rejection_reason: reason,
      context_metadata: suggestion.context || %{},
      time_to_response_ms: Keyword.get(opts, :time_to_response_ms),
      suggestion_position: suggestion.position,
      confidence_score: suggestion.confidence
    }

    %__MODULE__{}
    |> changeset(attrs)
  end

  @doc """
  Query helper to get acceptance rate for a user.

  Returns the percentage of accepted suggestions for a specific user.
  """
  def acceptance_rate_query(user_id) do
    import Ecto.Query

    from f in __MODULE__,
      where: f.user_id == ^user_id,
      select: %{
        total: count(f.id),
        accepted: sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", f.accepted)),
        rate: fragment("CAST(SUM(CASE WHEN ? THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)", f.accepted)
      }
  end

  @doc """
  Query helper to get acceptance rate by suggestion type.

  Returns acceptance rates broken down by suggestion type (smart_reply, etc.)
  """
  def acceptance_by_type_query(user_id) do
    import Ecto.Query

    from f in __MODULE__,
      where: f.user_id == ^user_id,
      group_by: f.suggestion_type,
      select: %{
        type: f.suggestion_type,
        total: count(f.id),
        accepted: sum(fragment("CASE WHEN ? THEN 1 ELSE 0 END", f.accepted)),
        rate: fragment("CAST(SUM(CASE WHEN ? THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)", f.accepted)
      }
  end

  @doc """
  Query helper to get recent feedback for learning.

  Returns recent feedback records for analysis by the FeedbackLearner.
  """
  def recent_feedback_query(user_id, limit \\ 100) do
    import Ecto.Query

    from f in __MODULE__,
      where: f.user_id == ^user_id,
      order_by: [desc: f.inserted_at],
      limit: ^limit
  end
end
