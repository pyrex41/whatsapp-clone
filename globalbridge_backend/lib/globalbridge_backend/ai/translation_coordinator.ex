defmodule GlobalbridgeBackend.AI.TranslationCoordinator do
  @moduledoc """
  Coordinates real-time message translation for incoming and outgoing messages.

  Handles:
  - Auto-translation of incoming messages based on user preferences
  - Translation suggestions for outgoing messages
  - Caching and batching for performance
  - Language detection and mismatch handling
  """

  require Logger
  alias GlobalbridgeBackend.AI.{TranslationService, ConversationLanguageDetector}
  alias GlobalbridgeBackend.Contexts.TranslationPreferences
  alias GlobalbridgeBackend.Schemas.Message

  @doc """
  Processes an incoming message for translation.

  If auto-translation is enabled and language differs from user's preference,
  returns a translated version of the message.

  ## Parameters
  - message: The incoming message struct
  - recipient_user_id: ID of the user receiving the message
  - thread_id: ID of the thread

  ## Returns
  - {:ok, translated_message, metadata} if translation occurred
  - {:skip, reason} if translation was not needed
  - {:error, reason} if translation failed
  """
  def process_incoming_message(%Message{} = message, recipient_user_id, thread_id) do
    # Detect message language (from message.detected_language or detect it)
    message_lang = message.detected_language || detect_language(message.content)

    # Check if translation is needed
    prefs = TranslationPreferences.get_effective_preferences(recipient_user_id, thread_id)

    if should_translate_incoming?(prefs, message_lang) do
      # Perform translation
      target_lang = prefs.preferred_language

      case TranslationService.translate(message.content, message_lang, target_lang) do
        {:ok, translated_content} ->
          metadata = %{
            source_language: message_lang,
            target_language: target_lang,
            is_translated: true,
            original_content: message.content
          }

          Logger.info("[TRANSLATION] Translated incoming message #{message.id} (#{message_lang}→#{target_lang})")
          {:ok, translated_content, metadata}

        {:error, reason} ->
          Logger.warning("[TRANSLATION] Failed to translate message #{message.id}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      {:skip, "Translation not enabled or same language"}
    end
  end

  @doc """
  Checks if an outgoing message should offer translation.

  Detects if the user's composed message is in a different language
  than the thread's primary language.

  ## Returns
  - {:suggest, thread_language, available_languages} if translation suggested
  - {:skip, reason} if no translation needed
  """
  def check_outgoing_message(content, user_id, thread_id) do
    prefs = TranslationPreferences.get_effective_preferences(user_id, thread_id)

    if prefs.auto_translate_outgoing && prefs.show_translation_offers do
      # Detect message language
      message_lang = detect_language(content)

      # Get thread's primary language
      thread_lang = ConversationLanguageDetector.get_conversation_language(thread_id)

      # Check if languages differ
      if message_lang != thread_lang && message_lang != nil && thread_lang != nil do
        # Get available target languages (common languages + thread participants' languages)
        available_languages = get_available_languages(thread_id)

        Logger.info("[TRANSLATION] Suggesting translation for outgoing message (#{message_lang}→#{thread_lang})")
        {:suggest, thread_lang, available_languages}
      else
        {:skip, "Same language or cannot detect"}
      end
    else
      {:skip, "Translation offers disabled"}
    end
  end

  @doc """
  Translates an outgoing message to the target language.

  Used when user accepts the translation suggestion.
  """
  def translate_outgoing_message(content, source_lang, target_lang) do
    case TranslationService.translate(content, source_lang, target_lang) do
      {:ok, translated} ->
        metadata = %{
          source_language: source_lang,
          target_language: target_lang,
          is_translated: true,
          original_content: content
        }

        {:ok, translated, metadata}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Translates a message on-demand (for "Show original" / "Show translation" toggle).
  """
  def translate_message_on_demand(content, source_lang, target_lang) do
    TranslationService.translate(content, source_lang, target_lang)
  end

  ## Private Functions

  defp should_translate_incoming?(prefs, message_lang) do
    prefs.auto_translate_incoming &&
      message_lang != prefs.preferred_language &&
      message_lang != nil &&
      message_lang != ""
  end

  defp detect_language(content) do
    # Use OpenAI or simple heuristics to detect language
    # For now, use the ConversationLanguageDetector's language detection
    # In production, you might want a dedicated language detection API

    # Simple heuristic: if content is very short, return nil
    if String.length(content) < 10 do
      nil
    else
      # Use a simple language detection based on character patterns
      cond do
        String.match?(content, ~r/[а-яА-Я]/) -> "ru"
        String.match?(content, ~r/[一-龯]/) -> "zh"
        String.match?(content, ~r/[ぁ-ゔ]/) -> "ja"
        String.match?(content, ~r/[가-힣]/) -> "ko"
        String.match?(content, ~r/[ñáéíóúü]/i) -> "es"
        String.match?(content, ~r/[àâäæçéèêëïîôùûü]/i) -> "fr"
        String.match?(content, ~r/[äöüß]/i) -> "de"
        true -> "en"  # Default to English
      end
    end
  end

  defp get_available_languages(thread_id) do
    # Get thread participants' preferred languages
    # Plus common languages

    common_languages = [
      %{code: "en", name: "English"},
      %{code: "es", name: "Spanish"},
      %{code: "fr", name: "French"},
      %{code: "de", name: "German"},
      %{code: "zh", name: "Chinese"},
      %{code: "ja", name: "Japanese"},
      %{code: "ko", name: "Korean"},
      %{code: "ru", name: "Russian"},
      %{code: "pt", name: "Portuguese"},
      %{code: "it", name: "Italian"}
    ]

    # In production, augment with participant languages
    # For now, return common languages
    common_languages
  end
end
