defmodule GlobalbridgeBackend.Contexts.TranslationPreferences do
  @moduledoc """
  Context for managing translation preferences at user and thread levels.
  Provides a unified API for checking if translation should occur.
  """

  import Ecto.Query
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{
    UserTranslationPreference,
    ThreadParticipant,
    User
  }

  @doc """
  Gets effective translation preferences for a user in a specific thread.

  Thread-level settings override user-level settings.

  Returns a map with:
  - auto_translate_incoming: boolean
  - auto_translate_outgoing: boolean
  - preferred_language: string
  - show_translation_offers: boolean
  """
  def get_effective_preferences(user_id, thread_id) do
    # Get user's global preferences
    user_prefs = get_user_preferences(user_id)

    # Get thread-specific overrides
    thread_prefs = get_thread_preferences(user_id, thread_id)

    # Get user's preferred language
    user_language = get_user_language(user_id)

    # Merge with thread overrides taking priority
    %{
      auto_translate_incoming: thread_prefs[:auto_translate_incoming] || user_prefs.auto_translate_incoming,
      auto_translate_outgoing: thread_prefs[:auto_translate_outgoing] || user_prefs.auto_translate_outgoing,
      show_translation_offers: user_prefs.show_translation_offers,
      preferred_language: thread_prefs[:preferred_thread_language] || user_language,
      default_translation_behavior: user_prefs.default_translation_behavior
    }
  end

  @doc """
  Checks if incoming message should be auto-translated for this user.
  """
  def should_auto_translate_incoming?(user_id, thread_id, message_language) do
    prefs = get_effective_preferences(user_id, thread_id)

    prefs.auto_translate_incoming &&
      message_language != prefs.preferred_language &&
      message_language != nil &&
      message_language != ""
  end

  @doc """
  Checks if outgoing message should offer translation.
  """
  def should_offer_translation?(user_id, thread_id, thread_language) do
    prefs = get_effective_preferences(user_id, thread_id)

    prefs.auto_translate_outgoing &&
      prefs.show_translation_offers &&
      thread_language != prefs.preferred_language &&
      thread_language != nil &&
      thread_language != ""
  end

  @doc """
  Updates user's global translation preferences.
  """
  def update_user_preferences(user_id, attrs) do
    case Repo.get_by(UserTranslationPreference, user_id: user_id) do
      nil ->
        %UserTranslationPreference{}
        |> UserTranslationPreference.changeset(Map.put(attrs, :user_id, user_id))
        |> Repo.insert()

      preference ->
        preference
        |> UserTranslationPreference.changeset(attrs)
        |> Repo.update()
    end
  end

  @doc """
  Updates thread-specific translation preferences.
  """
  def update_thread_preferences(user_id, thread_id, attrs) do
    query = from tp in ThreadParticipant,
      where: tp.user_id == ^user_id and tp.thread_id == ^thread_id

    case Repo.one(query) do
      nil ->
        {:error, "Thread participant not found"}

      participant ->
        participant
        |> ThreadParticipant.translation_changeset(attrs)
        |> Repo.update()
    end
  end

  ## Private Functions

  defp get_user_preferences(user_id) do
    case Repo.get_by(UserTranslationPreference, user_id: user_id) do
      nil ->
        # Return defaults if no preferences set
        %UserTranslationPreference{
          auto_translate_incoming: true,
          auto_translate_outgoing: true,
          show_translation_offers: true,
          default_translation_behavior: "prompt"
        }

      prefs ->
        prefs
    end
  end

  defp get_thread_preferences(user_id, thread_id) do
    query = from tp in ThreadParticipant,
      where: tp.user_id == ^user_id and tp.thread_id == ^thread_id,
      select: %{
        auto_translate_incoming: tp.auto_translate_incoming,
        auto_translate_outgoing: tp.auto_translate_outgoing,
        preferred_thread_language: tp.preferred_thread_language
      }

    Repo.one(query) || %{}
  end

  defp get_user_language(user_id) do
    case Repo.get(User, user_id) do
      %User{preferred_language: lang} when not is_nil(lang) -> lang
      _ -> "en"
    end
  end
end
