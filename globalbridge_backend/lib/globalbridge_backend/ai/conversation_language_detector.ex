defmodule GlobalbridgeBackend.AI.ConversationLanguageDetector do
  @moduledoc """
  Detects the primary language of a conversation thread.
  Used to determine if smart replies need translation.

  ## Usage

      # Detect thread's primary language
      {:ok, "es", 0.95} = detect_thread_language(thread_id)

      # Check if user needs translation
      true = needs_translation?(thread_id, user_id)

  ## Language Detection Strategy

  1. Analyze recent messages (default: last 20)
  2. Use stored `detected_language` from messages
  3. Calculate primary language by frequency
  4. Return confidence score based on consistency
  """

  require Logger
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{Message, User}
  alias GlobalbridgeBackend.Repos.ThreadRepo
  import Ecto.Query

  @doc """
  Determines the conversation's primary language based on recent messages.

  ## Parameters
  - thread_id: The thread to analyze
  - recent_count: Number of recent messages to analyze (default: 20)

  ## Returns
  - {:ok, language_code, confidence} - e.g. {:ok, "es", 0.95}
  - {:mixed, languages} - Multiple languages detected with no clear majority
  - {:unknown, []} - Cannot determine (no messages with language data)

  ## Examples

      iex> detect_thread_language("thread-123")
      {:ok, "es", 0.85}

      iex> detect_thread_language("multilingual-thread")
      {:mixed, ["en", "es", "fr"]}

      iex> detect_thread_language("new-thread")
      {:unknown, []}
  """
  def detect_thread_language(thread_id, recent_count \\ 20) do
    messages = get_recent_messages(thread_id, recent_count)

    # Extract languages from messages
    language_counts = messages
      |> Enum.map(& &1.detected_language)
      |> Enum.filter(&(&1 != nil && &1 != ""))
      |> Enum.frequencies()

    analyze_language_distribution(language_counts)
  end

  @doc """
  Checks if a user needs translation for this conversation.

  Returns true if:
  - User's preferred language != thread's primary language
  - Thread has mixed languages requiring translation support

  ## Examples

      iex> needs_translation?("spanish-thread", "english-user")
      true

      iex> needs_translation?("english-thread", "english-user")
      false
  """
  def needs_translation?(thread_id, user_id) do
    user_language = get_user_language(user_id)

    case detect_thread_language(thread_id) do
      {:ok, thread_lang, _confidence} ->
        # User needs translation if their language differs from thread
        user_language != thread_lang

      {:mixed, _languages} ->
        # Mixed conversation always needs translation support
        true

      {:unknown, []} ->
        # No translation if we can't detect language
        false
    end
  end

  @doc """
  Gets the conversation language for a specific thread, with fallback.

  Returns a language code string, never an error tuple.
  Falls back to "en" if detection fails.

  ## Examples

      iex> get_conversation_language("thread-123")
      "es"

      iex> get_conversation_language("unknown-thread")
      "en"
  """
  def get_conversation_language(thread_id) do
    case detect_thread_language(thread_id) do
      {:ok, lang, _confidence} -> lang
      {:mixed, [primary | _]} -> primary
      {:unknown, []} -> "en"  # Default to English
    end
  end

  @doc """
  Gets the user's preferred language with fallback to English.

  ## Examples

      iex> get_user_language(user_id)
      "en"
  """
  def get_user_language(user_id) do
    case Repo.get(User, user_id) do
      %User{preferred_language: lang} when lang != nil and lang != "" -> lang
      _ -> "en"
    end
  end

  @doc """
  Determines if translation is needed between two languages.

  Returns false if languages are the same or if either is nil/empty.
  """
  def translation_needed?(source_lang, target_lang) do
    source_lang != nil &&
    target_lang != nil &&
    source_lang != "" &&
    target_lang != "" &&
    source_lang != target_lang
  end

  ## Private Functions

  defp get_recent_messages(thread_id, count) do
    # Try to get thread repo (SQLite)
    try do
      repo = ThreadRepo.get_repo(thread_id)

      query = from m in Message,
        order_by: [desc: m.inserted_at],
        limit: ^count,
        select: m

      repo.all(query)
    rescue
      _ ->
        # Fallback: thread might not exist or repo not initialized
        Logger.debug("Could not get messages from thread repo #{thread_id}")
        []
    end
  end

  defp analyze_language_distribution(language_counts) do
    case language_counts do
      counts when map_size(counts) == 0 ->
        # No messages with language data
        {:unknown, []}

      counts when map_size(counts) == 1 ->
        # Single language - 100% confidence
        [{lang, _}] = Enum.to_list(counts)
        {:ok, lang, 1.0}

      counts ->
        # Multiple languages - calculate majority
        sorted = Enum.sort_by(counts, fn {_lang, count} -> count end, :desc)
        [{primary_lang, primary_count} | rest] = sorted

        total = Enum.sum(Map.values(counts))
        confidence = primary_count / total

        # Consider it a clear primary language if >60% of messages
        if confidence > 0.6 do
          {:ok, primary_lang, confidence}
        else
          # Too mixed - return all languages
          all_languages = Enum.map(sorted, fn {lang, _} -> lang end)
          {:mixed, all_languages}
        end
    end
  end

  @doc """
  Returns human-readable language name for a language code.

  ## Examples

      iex> language_name("en")
      "English"

      iex> language_name("es")
      "Spanish"
  """
  def language_name("en"), do: "English"
  def language_name("es"), do: "Spanish"
  def language_name("fr"), do: "French"
  def language_name("de"), do: "German"
  def language_name("it"), do: "Italian"
  def language_name("pt"), do: "Portuguese"
  def language_name("ru"), do: "Russian"
  def language_name("zh"), do: "Chinese"
  def language_name("ja"), do: "Japanese"
  def language_name("ko"), do: "Korean"
  def language_name("ar"), do: "Arabic"
  def language_name("hi"), do: "Hindi"
  def language_name("nl"), do: "Dutch"
  def language_name("pl"), do: "Polish"
  def language_name("tr"), do: "Turkish"
  def language_name("vi"), do: "Vietnamese"
  def language_name("th"), do: "Thai"
  def language_name("sv"), do: "Swedish"
  def language_name("da"), do: "Danish"
  def language_name("no"), do: "Norwegian"
  def language_name("fi"), do: "Finnish"
  def language_name(code), do: String.upcase(code)
end
