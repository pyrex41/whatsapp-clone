defmodule GlobalbridgeBackend.Schemas.UserStyleProfile do
  @moduledoc """
  Schema for storing user writing style profiles for AI-powered smart replies.

  This schema captures patterns in how users write messages, including:
  - Common phrases and vocabulary
  - Sentence structure preferences
  - Tone and formality level
  - Emoji usage patterns
  - Average message length

  These profiles are used by the SmartReplyGenerator to create authentic-sounding
  suggestions that match each user's natural writing style.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_style_profiles" do
    belongs_to :user, GlobalbridgeBackend.Schemas.User, type: :binary_id

    # Core style metrics
    field :avg_sentence_length, :float, default: 0.0
    field :formality_level, :float, default: 0.5  # 0.0 = casual, 1.0 = formal
    field :vocabulary_complexity, :float, default: 0.5  # 0.0 = simple, 1.0 = complex
    field :emoji_frequency, :float, default: 0.0  # emojis per message

    # Flexible metadata for advanced patterns
    # Stores: {common_phrases: [...], tone_markers: [...], punctuation_style: {...}}
    field :style_metadata, :map, default: %{}

    # Learning metrics
    field :messages_analyzed, :integer, default: 0
    field :last_updated_at, :utc_datetime
    field :confidence_score, :float, default: 0.0  # 0.0 = low confidence, 1.0 = high

    timestamps()
  end

  @doc """
  Changeset for creating or updating a user style profile.

  ## Parameters
  - user_style_profile: The struct to update (or %__MODULE__{} for new)
  - attrs: Map of attributes to update

  ## Required Fields
  - user_id

  ## Optional Fields
  - avg_sentence_length
  - formality_level
  - vocabulary_complexity
  - emoji_frequency
  - style_metadata
  - messages_analyzed
  - confidence_score
  """
  def changeset(user_style_profile, attrs) do
    user_style_profile
    |> cast(attrs, [
      :user_id,
      :avg_sentence_length,
      :formality_level,
      :vocabulary_complexity,
      :emoji_frequency,
      :style_metadata,
      :messages_analyzed,
      :last_updated_at,
      :confidence_score
    ])
    |> validate_required([:user_id])
    |> validate_number(:formality_level, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:vocabulary_complexity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:emoji_frequency, greater_than_or_equal_to: 0.0)
    |> validate_number(:confidence_score, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:messages_analyzed, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
    |> unique_constraint(:user_id)
  end

  @doc """
  Incremental update changeset for learning from new messages.

  Updates the profile with new data while maintaining running averages.
  """
  def update_from_message(user_style_profile, message_analysis) do
    current_count = user_style_profile.messages_analyzed
    new_count = current_count + 1

    # Calculate running averages
    new_avg_sentence_length =
      running_average(
        user_style_profile.avg_sentence_length,
        message_analysis.sentence_length,
        current_count,
        new_count
      )

    new_formality =
      running_average(
        user_style_profile.formality_level,
        message_analysis.formality,
        current_count,
        new_count
      )

    new_complexity =
      running_average(
        user_style_profile.vocabulary_complexity,
        message_analysis.complexity,
        current_count,
        new_count
      )

    new_emoji_freq =
      running_average(
        user_style_profile.emoji_frequency,
        message_analysis.emoji_count,
        current_count,
        new_count
      )

    # Update metadata (merge new patterns)
    updated_metadata = merge_style_metadata(
      user_style_profile.style_metadata,
      message_analysis.patterns
    )

    # Calculate new confidence (more messages = higher confidence, capped at 1.0)
    new_confidence = min(1.0, new_count / 100.0)

    changeset(user_style_profile, %{
      avg_sentence_length: new_avg_sentence_length,
      formality_level: new_formality,
      vocabulary_complexity: new_complexity,
      emoji_frequency: new_emoji_freq,
      style_metadata: updated_metadata,
      messages_analyzed: new_count,
      last_updated_at: DateTime.utc_now(),
      confidence_score: new_confidence
    })
  end

  # Private helpers

  defp running_average(current_avg, new_value, current_count, new_count) do
    (current_avg * current_count + new_value) / new_count
  end

  defp merge_style_metadata(current_metadata, new_patterns) do
    # Merge common phrases (keep top 50 most frequent)
    current_phrases = Map.get(current_metadata, "common_phrases", %{})
    new_phrases = Map.get(new_patterns, :common_phrases, %{})

    merged_phrases =
      Map.merge(current_phrases, new_phrases, fn _k, v1, v2 -> v1 + v2 end)
      |> Enum.sort_by(fn {_phrase, count} -> count end, :desc)
      |> Enum.take(50)
      |> Enum.into(%{})

    # Merge tone markers
    current_tone = Map.get(current_metadata, "tone_markers", %{})
    new_tone = Map.get(new_patterns, :tone_markers, %{})

    merged_tone =
      Map.merge(current_tone, new_tone, fn _k, v1, v2 -> v1 + v2 end)

    # Merge punctuation style
    current_punct = Map.get(current_metadata, "punctuation_style", %{})
    new_punct = Map.get(new_patterns, :punctuation_style, %{})

    merged_punct =
      Map.merge(current_punct, new_punct, fn _k, v1, v2 -> v1 + v2 end)

    %{
      "common_phrases" => merged_phrases,
      "tone_markers" => merged_tone,
      "punctuation_style" => merged_punct
    }
  end
end
