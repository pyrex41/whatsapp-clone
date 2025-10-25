defmodule GlobalbridgeBackend.AI.SmartReplyGenerator do
  @moduledoc """
  Generates context-aware smart reply suggestions that match user writing style.

  This module:
  - Analyzes user writing patterns to build style profiles
  - Generates 3+ reply suggestions tailored to conversation context
  - Matches each user's vocabulary, tone, and formality level
  - Learns from feedback to improve future suggestions
  - Uses RAG database for semantic search of similar conversations

  ## Performance Targets
  - Style analysis: <5s
  - Reply generation: <8s
  - Total: <15s for full suggestion cycle

  ## Learning Loop
  1. User sends messages → analyze style → update profile
  2. Generate suggestions → user accepts/rejects → store feedback
  3. Use feedback embeddings to improve future suggestions
  """

  require Logger

  alias GlobalbridgeBackend.AI.{Cache, VectorStore, Agents}
  alias GlobalbridgeBackend.Schemas.{UserStyleProfile, SuggestionFeedback}
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Repos.ThreadRepo

  @doc """
  Analyzes a user's message and updates their style profile.

  This should be called whenever a user sends a message to build/update
  their writing style profile incrementally.

  ## Parameters
  - user_id: The user whose style is being learned
  - message: The message struct containing content and metadata
  - thread_id: For storing style embeddings in thread database

  ## Returns
  - {:ok, updated_profile} on success
  - {:error, reason} on failure
  """
  def learn_user_style(user_id, message, thread_id) do
    start_time = System.monotonic_time(:millisecond)

    try do
      # Get or create user style profile
      profile =
        case Repo.get_by(UserStyleProfile, user_id: user_id) do
          nil -> %UserStyleProfile{user_id: user_id}
          existing -> existing
        end

      # Analyze the message
      message_analysis = analyze_message(message.content)

      # Update profile with running averages
      changeset = UserStyleProfile.update_from_message(profile, message_analysis)

      # Save to database
      result =
        case profile.id do
          nil -> Repo.insert(changeset)
          _id -> Repo.update(changeset)
        end

      case result do
        {:ok, updated_profile} ->
          # Store style embedding in vector database
          store_style_embedding(thread_id, user_id, message.content, message_analysis)

          elapsed = System.monotonic_time(:millisecond) - start_time
          Logger.debug("Style learning completed in #{elapsed}ms for user #{user_id}")

          {:ok, updated_profile}

        {:error, changeset} ->
          Logger.error("Failed to update style profile: #{inspect(changeset.errors)}")
          {:error, :profile_update_failed}
      end
    rescue
      e ->
        Logger.error("Style learning error: #{inspect(e)}")
        {:error, e}
    end
  end

  @doc """
  Generates smart reply suggestions based on conversation context and user style.

  ## Parameters
  - user_id: The user who will send the reply
  - thread_id: The conversation thread
  - recent_messages: List of recent messages (last 5-10) for context
  - opts: Optional parameters
    - count: Number of suggestions to generate (default: 3)
    - style_match: Whether to match user's style (default: true)

  ## Returns
  - {:ok, [suggestions]} where each suggestion is:
    %{
      type: "smart_reply",
      content: "suggested reply text",
      confidence: 0.85,
      position: 1,
      context: %{matched_style: true, ...}
    }
  """
  def generate_suggestions(user_id, thread_id, recent_messages, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    count = Keyword.get(opts, :count, 3)
    style_match = Keyword.get(opts, :style_match, true)

    try do
      # Get user's style profile
      user_profile =
        if style_match do
          Repo.get_by(UserStyleProfile, user_id: user_id)
        else
          nil
        end

      # Get conversation context
      context = build_conversation_context(recent_messages)

      # Retrieve similar accepted suggestions from RAG
      similar_suggestions =
        if user_profile do
          get_similar_accepted_suggestions(thread_id, user_id, context)
        else
          []
        end

      # Generate suggestions using AI
      suggestions = generate_replies_with_ai(context, user_profile, similar_suggestions, count)

      elapsed = System.monotonic_time(:millisecond) - start_time
      Logger.info("Generated #{length(suggestions)} suggestions in #{elapsed}ms")

      {:ok, suggestions}
    rescue
      e ->
        Logger.error("Suggestion generation error: #{inspect(e)}")
        {:error, e}
    end
  end

  @doc """
  Records feedback on a suggestion (accepted or rejected).

  This creates a learning loop where the system improves based on user choices.

  ## Parameters
  - user_id: The user who provided feedback
  - thread_id: The conversation thread
  - suggestion: The suggestion that was shown
  - accepted: Whether user accepted (true) or rejected (false)
  - opts: Optional parameters
    - modified_content: If user edited before accepting
    - rejection_reason: Why suggestion was rejected
    - time_to_response_ms: How long until user responded

  ## Returns
  - :ok on success
  - {:error, reason} on failure
  """
  def record_feedback(user_id, thread_id, suggestion, accepted, opts \\ []) do
    try do
      # Create feedback record
      feedback_attrs = %{
        user_id: user_id,
        thread_id: thread_id,
        suggestion_type: suggestion.type,
        suggestion_content: suggestion.content,
        accepted: accepted,
        user_modified_content: Keyword.get(opts, :modified_content),
        rejection_reason: Keyword.get(opts, :rejection_reason),
        context_metadata: suggestion.context || %{},
        time_to_response_ms: Keyword.get(opts, :time_to_response_ms),
        suggestion_position: suggestion.position,
        confidence_score: suggestion.confidence
      }

      changeset = SuggestionFeedback.changeset(%SuggestionFeedback{}, feedback_attrs)

      case Repo.insert(changeset) do
        {:ok, feedback} ->
          # Store feedback embedding for future retrieval
          store_feedback_embedding(thread_id, feedback, suggestion.content)
          :ok

        {:error, changeset} ->
          Logger.error("Failed to record feedback: #{inspect(changeset.errors)}")
          {:error, :feedback_insert_failed}
      end
    rescue
      e ->
        Logger.error("Feedback recording error: #{inspect(e)}")
        {:error, e}
    end
  end

  @doc """
  Gets acceptance statistics for a user's suggestion types.

  Useful for understanding which types of suggestions work best for each user.
  """
  def get_user_acceptance_stats(user_id) do
    try do
      query = SuggestionFeedback.acceptance_by_type_query(user_id)
      stats = Repo.all(query)

      {:ok, stats}
    rescue
      e ->
        Logger.error("Failed to get acceptance stats: #{inspect(e)}")
        {:error, e}
    end
  end

  ## Private Functions

  defp analyze_message(content) do
    # Analyze various aspects of the message
    words = String.split(content)
    sentences = String.split(content, ~r/[.!?]+/)

    # Calculate metrics
    sentence_length =
      if length(sentences) > 0 do
        length(words) / length(sentences)
      else
        0.0
      end

    # Formality detection (simplified)
    formality = calculate_formality(content, words)

    # Complexity based on word length and vocabulary
    complexity = calculate_complexity(words)

    # Emoji detection
    emoji_count = count_emojis(content)

    # Extract patterns
    patterns = extract_patterns(content, words)

    %{
      sentence_length: sentence_length,
      formality: formality,
      complexity: complexity,
      emoji_count: emoji_count,
      patterns: patterns
    }
  end

  defp calculate_formality(content, words) do
    # Formality indicators
    casual_markers = ["lol", "omg", "btw", "tbh", "idk", "yeah", "gonna", "wanna"]
    formal_markers = ["therefore", "however", "furthermore", "regarding", "sincerely"]

    content_lower = String.downcase(content)

    casual_count = Enum.count(casual_markers, fn marker -> String.contains?(content_lower, marker) end)
    formal_count = Enum.count(formal_markers, fn marker -> String.contains?(content_lower, marker) end)

    # Has punctuation and capitalization
    has_proper_caps = content =~ ~r/^[A-Z]/ and content =~ ~r/[.!?]$/
    has_contractions = String.contains?(content, "'")

    # Calculate score (0.0 = casual, 1.0 = formal)
    score = 0.5

    score = score + (formal_count * 0.15)
    score = score - (casual_count * 0.15)
    score = if has_proper_caps, do: score + 0.1, else: score
    score = if has_contractions, do: score - 0.05, else: score

    # Clamp between 0 and 1
    max(0.0, min(1.0, score))
  end

  defp calculate_complexity(words) do
    # Complexity based on average word length
    if length(words) > 0 do
      avg_word_length = Enum.reduce(words, 0, fn word, acc -> acc + String.length(word) end) / length(words)

      # Normalize to 0.0-1.0 scale (3 chars = simple, 8+ chars = complex)
      complexity = (avg_word_length - 3.0) / 5.0
      max(0.0, min(1.0, complexity))
    else
      0.5
    end
  end

  defp count_emojis(content) do
    # Simplified emoji detection
    emoji_pattern = ~r/[\x{1F600}-\x{1F64F}\x{1F300}-\x{1F5FF}\x{1F680}-\x{1F6FF}\x{2600}-\x{26FF}\x{2700}-\x{27BF}]/u
    matches = Regex.scan(emoji_pattern, content)
    length(matches)
  end

  defp extract_patterns(content, words) do
    # Extract common phrases (2-3 word combinations)
    common_phrases = extract_ngrams(words, 2)

    # Extract tone markers (exclamation marks, question marks)
    tone_markers = %{
      exclamations: (String.graphemes(content) |> Enum.count(fn c -> c == "!" end)),
      questions: (String.graphemes(content) |> Enum.count(fn c -> c == "?" end)),
      ellipsis: if(String.contains?(content, "..."), do: 1, else: 0)
    }

    # Extract punctuation style
    punctuation_style = %{
      uses_commas: String.contains?(content, ","),
      uses_semicolons: String.contains?(content, ";"),
      uses_dashes: String.contains?(content, "-") or String.contains?(content, "—")
    }

    %{
      common_phrases: common_phrases,
      tone_markers: tone_markers,
      punctuation_style: punctuation_style
    }
  end

  defp extract_ngrams(words, n) do
    words
    |> Enum.chunk_every(n, 1, :discard)
    |> Enum.map(fn chunk -> Enum.join(chunk, " ") end)
    |> Enum.frequencies()
  end

  defp store_style_embedding(thread_id, user_id, content, _analysis) do
    # Generate embedding for the message (placeholder - would use real embedding model)
    embedding = generate_embedding(content)

    # Store in vector database
    VectorStore.insert_user_style(thread_id, user_id, "general", embedding)
  end

  defp build_conversation_context(recent_messages) do
    # Build context string from recent messages
    context_parts =
      recent_messages
      |> Enum.take(-5)
      |> Enum.map(fn msg ->
        "#{msg.user_id}: #{msg.content}"
      end)

    context = Enum.join(context_parts, "\n")

    %{
      recent_messages: recent_messages,
      context_text: context,
      last_message: List.last(recent_messages)
    }
  end

  defp get_similar_accepted_suggestions(thread_id, user_id, context) do
    # Get embedding for current context
    query_embedding = generate_embedding(context.context_text)

    # Search for similar accepted suggestions
    case VectorStore.search_accepted_suggestions(thread_id, user_id, query_embedding, limit: 5) do
      results when is_list(results) ->
        results

      {:error, _} ->
        []
    end
  end

  defp generate_replies_with_ai(context, user_profile, _similar_suggestions, count) do
    # For now, generate placeholder suggestions
    # In production, this would call an AI model (llama-3.1-8b-instant)
    # to generate context-aware replies matching the user's style

    last_message = context.last_message

    # Base suggestions
    base_suggestions = [
      "I understand what you're saying.",
      "That makes sense to me.",
      "Thanks for explaining that."
    ]

    # Adjust for user style if profile exists
    suggestions =
      if user_profile do
        adjust_suggestions_for_style(base_suggestions, user_profile)
      else
        base_suggestions
      end

    # Format as suggestion objects
    suggestions
    |> Enum.take(count)
    |> Enum.with_index(1)
    |> Enum.map(fn {content, position} ->
      %{
        type: "smart_reply",
        content: content,
        confidence: calculate_suggestion_confidence(user_profile, position),
        position: position,
        context: %{
          matched_style: not is_nil(user_profile),
          last_message_id: last_message.id,
          formality_level: if(user_profile, do: user_profile.formality_level, else: 0.5)
        }
      }
    end)
  end

  defp adjust_suggestions_for_style(suggestions, profile) do
    # Adjust formality
    suggestions =
      if profile.formality_level < 0.3 do
        # Make more casual
        Enum.map(suggestions, fn s ->
          s
          |> String.replace("I understand", "Got it")
          |> String.replace("That makes sense", "Yeah, makes sense")
          |> String.replace("Thanks for explaining", "Thanks!")
        end)
      else
        suggestions
      end

    # Add emojis if user uses them
    suggestions =
      if profile.emoji_frequency > 0.5 do
        Enum.map(suggestions, fn s -> s <> " 👍" end)
      else
        suggestions
      end

    suggestions
  end

  defp calculate_suggestion_confidence(user_profile, position) do
    # Base confidence decreases with position
    base_confidence = 1.0 - (position - 1) * 0.1

    # Increase confidence if we have a good style profile
    if user_profile && user_profile.confidence_score > 0.5 do
      min(1.0, base_confidence + 0.1)
    else
      base_confidence
    end
  end

  defp store_feedback_embedding(thread_id, feedback, suggestion_content) do
    # Generate embedding for the suggestion
    embedding = generate_embedding(suggestion_content)

    # Store in vector database
    VectorStore.insert_feedback(
      thread_id,
      feedback.id,
      feedback.user_id,
      feedback.suggestion_type,
      feedback.accepted,
      embedding
    )
  end

  defp generate_embedding(text) do
    # Placeholder: In production, this would call a real embedding model
    # For now, generate a random 3072-dimensional vector
    # This matches the embedding size used in VectorStore

    # Check cache first
    cache_key = "embedding:#{:erlang.phash2(text)}"

    case Cache.get(cache_key) do
      {:ok, embedding} ->
        embedding

      _ ->
        # Generate placeholder embedding
        embedding = for _ <- 1..3072, do: :rand.uniform() * 2.0 - 1.0

        # Cache it
        Cache.put(cache_key, embedding)

        embedding
    end
  end
end
