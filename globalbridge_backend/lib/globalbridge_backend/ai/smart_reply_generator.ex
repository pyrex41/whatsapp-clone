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

  alias GlobalbridgeBackend.AI.{VectorStore, ConversationLanguageDetector, TranslationService}
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

  NEW: Now includes automatic translation support for multilingual conversations.

  ## Parameters
  - user_id: The user who will send the reply
  - thread_id: The conversation thread
  - recent_messages: List of recent messages (last 5-10) for context
  - opts: Optional parameters
    - count: Number of suggestions to generate (default: 3)
    - style_match: Whether to match user's style (default: true)
    - include_translations: Pre-translate suggestions (default: true)

  ## Returns
  - {:ok, [suggestions]} where each suggestion is:
    %{
      type: "smart_reply",
      content: "suggested reply text",  # In user's language
      confidence: 0.85,
      position: 1,
      context: %{matched_style: true, ...},
      translation: %{  # NEW: Translation metadata
        enabled: true,
        target_language: "es",
        target_language_name: "Spanish",
        translated_content: "¡Suena bien!",
        user_can_toggle: true,
        auto_translate_on_send: true
      }
    }
  """
  def generate_suggestions(user_id, thread_id, recent_messages, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    count = Keyword.get(opts, :count, 3)
    style_match = Keyword.get(opts, :style_match, true)
    include_translations = Keyword.get(opts, :include_translations, true)

    try do
      # Get user's preferred language
      user_language = ConversationLanguageDetector.get_user_language(user_id)

      # Detect conversation language
      conversation_language = ConversationLanguageDetector.get_conversation_language(thread_id)

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

      # Generate suggestions using AI (in user's language)
      base_suggestions = generate_replies_with_ai(context, user_profile, similar_suggestions, count)

      # Add translation metadata if needed
      suggestions = if include_translations && ConversationLanguageDetector.translation_needed?(user_language, conversation_language) do
        add_translation_metadata(base_suggestions, user_language, conversation_language)
      else
        add_no_translation_metadata(base_suggestions, user_language)
      end

      elapsed = System.monotonic_time(:millisecond) - start_time
      Logger.info("Generated #{length(suggestions)} suggestions with translation support in #{elapsed}ms")

      {:ok, suggestions}
    rescue
      e ->
        Logger.error("Suggestion generation error: #{inspect(e)}")
        {:error, e}
    end
  end

  @doc """
  Eagerly generates and caches the query embedding for a thread.

  This should be called in the background when a thread opens, BEFORE the user
  taps the composer. This way, when the user is ready to see suggestions, the
  expensive embedding generation has already completed.

  ## Performance Impact
  - Without eager generation: 5-7s wait when user taps composer
  - With eager generation: <1s (embedding already cached)

  ## Parameters
  - thread_id: The thread to generate embeddings for
  - recent_messages: Last 5-10 messages for context

  ## Returns
  - :ok if embedding was generated and cached
  - {:error, reason} on failure
  """
  def prepare_embeddings_for_thread(thread_id, recent_messages) do
    try do
      # Build conversation context
      context = build_conversation_context(recent_messages)

      # Check if embedding is already cached
      case GlobalbridgeBackend.AI.EmbeddingCache.get(thread_id) do
        {:ok, _embedding} ->
          Logger.debug("[EAGER_EMBED] Already cached for thread #{thread_id}, skipping")
          :ok

        :miss ->
          Logger.info("[EAGER_EMBED] Generating query embedding for thread #{thread_id}")
          start_time = System.monotonic_time(:millisecond)

          # Generate embedding for context
          query_embedding = generate_embedding(context.context_text)

          # Store in cache with 10-minute TTL
          GlobalbridgeBackend.AI.EmbeddingCache.put(thread_id, query_embedding)

          elapsed = System.monotonic_time(:millisecond) - start_time
          Logger.info("[EAGER_EMBED] Cached query embedding for thread #{thread_id} in #{elapsed}ms")

          :ok
      end
    rescue
      e ->
        Logger.error("[EAGER_EMBED] Failed for thread #{thread_id}: #{inspect(e)}")
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
        "#{msg.sender_id}: #{msg.content}"
      end)

    context = Enum.join(context_parts, "\n")

    %{
      recent_messages: recent_messages,
      context_text: context,
      last_message: List.last(recent_messages)
    }
  end

  defp get_similar_accepted_suggestions(thread_id, user_id, context) do
    # OPTIMIZATION: Check if there's any feedback data before generating expensive embeddings
    # This saves 5-7 seconds of OpenAI API latency when dataset is empty
    repo = GlobalbridgeBackend.Repos.ThreadRepo.get_repo(thread_id)
    count_sql = "SELECT COUNT(*) FROM feedback_embeddings WHERE user_id = ? AND accepted = 1"

    case Ecto.Adapters.SQL.query(repo, count_sql, [user_id]) do
      {:ok, %{rows: [[count]]}} when count > 0 ->
        # We have feedback data, proceed with RAG search
        Logger.debug("Found #{count} feedback embeddings, performing RAG search")

        # Try to get cached embedding first, otherwise generate
        query_embedding = case GlobalbridgeBackend.AI.EmbeddingCache.get(thread_id) do
          {:ok, cached_embedding} ->
            Logger.debug("[RAG] Using cached query embedding")
            cached_embedding

          :miss ->
            Logger.debug("[RAG] Cache miss, generating embedding on-demand")
            embedding = generate_embedding(context.context_text)
            # Cache for future use
            GlobalbridgeBackend.AI.EmbeddingCache.put(thread_id, embedding)
            embedding
        end

        # Search for similar accepted suggestions using real RAG semantic search
        feedback_results = case VectorStore.search_accepted_suggestions(thread_id, user_id, query_embedding, limit: 5) do
          results when is_list(results) ->
            Logger.debug("Found #{length(results)} similar accepted suggestions via RAG")
            Enum.each(results, fn result ->
              Logger.debug("  - Feedback #{result.feedback_id}: similarity=#{Float.round(result.similarity, 3)}, type=#{result.suggestion_type}")
            end)
            results

          {:error, reason} ->
            Logger.warning("RAG feedback search failed: #{inspect(reason)}")
            []
        end

        # ALSO search user style embeddings for personalization
        style_results = case VectorStore.get_user_styles(thread_id, user_id) do
          {:ok, styles} when length(styles) > 0 ->
            Logger.debug("Found #{length(styles)} user style embeddings")
            # Calculate similarity for each style aspect
            Enum.map(styles, fn style ->
              similarity = GlobalbridgeBackend.AI.Embeddings.cosine_similarity(
                query_embedding,
                style.embedding
              )
              %{
                type: :style,
                aspect: style.style_aspect,
                similarity: similarity
              }
            end)
            |> Enum.sort_by(& &1.similarity, :desc)
            |> Enum.take(3)

          _ ->
            Logger.debug("No user style embeddings found")
            []
        end

        # Combine feedback and style results
        feedback_results ++ style_results

      {:ok, %{rows: [[0]]}} ->
        # No feedback data yet, skip RAG entirely
        Logger.debug("No feedback embeddings found, skipping RAG (saves 5-7s)")
        []

      {:error, _} ->
        # Table doesn't exist or query failed, skip RAG
        Logger.debug("Feedback table query failed, skipping RAG")
        []
    end
  end

  defp generate_replies_with_ai(context, user_profile, similar_suggestions, count) do
    # Use llama-3.1-8b-instant for fast, context-aware suggestion generation
    # Can also use: llama-3.2-3b-preview (faster, smaller), mixtral-8x7b-32768 (better quality)
    model = System.get_env("SMART_REPLY_MODEL") || System.get_env("TRANSLATION_MODEL") || "llama-3.2-3b-preview"

    # Build prompt with conversation context and user style
    prompt = build_suggestion_prompt(context, user_profile, similar_suggestions, count)

    # Call LLM via OpenAIServing with optimized parameters for speed
    case GlobalbridgeBackend.AI.OpenAIServing.generate_completion(prompt, model, max_tokens: 150, temperature: 0.3) do
      {:ok, ai_response} ->
        # Parse AI response into suggestion objects
        parse_ai_suggestions(ai_response, user_profile, context, count)

      {:error, reason} ->
        Logger.warning("LLM call failed: #{inspect(reason)}, using fallback templates")
        fallback_suggestions(context, user_profile, count)
    end
  end

  defp build_suggestion_prompt(context, user_profile, similar_suggestions, count) do
    style_description = if user_profile do
      """
      User's writing style:
      - Formality level: #{user_profile.formality_level} (0=very casual, 1=very formal)
      - Emoji frequency: #{user_profile.emoji_frequency} emojis per message
      - Average sentence length: #{user_profile.avg_sentence_length} words
      - Messages analyzed: #{user_profile.messages_analyzed}
      """
    else
      "No style profile available - use neutral tone."
    end

    similar_examples = if length(similar_suggestions) > 0 do
      examples = Enum.map_join(similar_suggestions, "\n", fn s -> "- \"#{s}\"" end)
      """

      Previously accepted suggestions by this user:
      #{examples}
      """
    else
      ""
    end

    """
    You are generating smart reply suggestions for a messaging app. Generate #{count} brief, natural reply suggestions based on this conversation.

    Recent conversation:
    #{context.context_text}

    Last message received: "#{context.last_message.content}"

    #{style_description}#{similar_examples}

    REQUIREMENTS:
    1. Generate exactly #{count} distinct reply suggestions
    2. Match the user's formality level and emoji usage
    3. Keep replies under 50 characters when possible
    4. Make replies contextually appropriate to the last message
    5. Return ONLY the suggestions, one per line, numbered 1., 2., 3., etc.
    6. Do NOT include explanations or commentary

    Example format:
    1. Sounds good!
    2. Thanks for letting me know
    3. Got it, appreciate it
    """
  end

  defp parse_ai_suggestions(ai_response, user_profile, context, count) do
    # Parse numbered list from AI response
    lines = ai_response
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(fn line ->
        String.match?(line, ~r/^\d+\./)
      end)
      |> Enum.map(fn line ->
        line
        |> String.replace(~r/^\d+\.\s*/, "")
        |> String.trim()
      end)
      |> Enum.take(count)

    # If parsing fails, use fallback
    suggestions = if length(lines) >= count do
      lines
    else
      Logger.warning("AI returned insufficient suggestions, using fallback")
      ["I understand", "That makes sense", "Thanks for sharing"][0..count-1]
    end

    # Format as suggestion objects
    suggestions
    |> Enum.with_index(1)
    |> Enum.map(fn {content, position} ->
      # Generate unique ID for each suggestion
      suggestion_id = Ecto.UUID.generate()

      # Format context as JSON string for iOS compatibility
      context_map = %{
        matched_style: not is_nil(user_profile),
        last_message_id: context.last_message.id,
        formality_level: if(user_profile, do: user_profile.formality_level, else: 0.5),
        ai_generated: true
      }
      context_string = Jason.encode!(context_map)

      %{
        id: suggestion_id,
        type: "smart_reply",
        content: content,
        confidence: calculate_suggestion_confidence(user_profile, position),
        position: position,
        context: context_string,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
      }
    end)
  end

  defp fallback_suggestions(context, user_profile, count) do
    # Fallback to template-based suggestions if LLM fails
    last_message = context.last_message

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
      # Generate unique ID for each suggestion
      suggestion_id = Ecto.UUID.generate()

      # Format context as JSON string for iOS compatibility
      context_map = %{
        matched_style: not is_nil(user_profile),
        last_message_id: last_message.id,
        formality_level: if(user_profile, do: user_profile.formality_level, else: 0.5),
        ai_generated: false
      }
      context_string = Jason.encode!(context_map)

      %{
        id: suggestion_id,
        type: "smart_reply",
        content: content,
        confidence: calculate_suggestion_confidence(user_profile, position),
        position: position,
        context: context_string,
        timestamp: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
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
    # Use real OpenAI text-embedding-3-small model (1536 dims, 2-3x faster)
    case GlobalbridgeBackend.AI.Embeddings.generate(text) do
      {:ok, embedding} ->
        embedding

      {:error, reason} ->
        Logger.warning("Embedding generation failed: #{inspect(reason)}, using fallback")
        # Fallback to zero vector to avoid breaking the flow
        # In production, you might want to retry or use a different strategy
        List.duplicate(0.0, 1536)
    end
  end

  ## Translation Support Functions

  defp add_translation_metadata(suggestions, user_language, conversation_language) do
    # Extract content for batch translation
    contents = Enum.map(suggestions, & &1.content)

    # Batch translate all suggestions at once (much faster)
    case TranslationService.translate_batch_safe(contents, user_language, conversation_language) do
      {:ok, translations} ->
        # Zip suggestions with their translations
        Enum.zip(suggestions, translations)
        |> Enum.map(fn {suggestion, translated_content} ->
          Map.put(suggestion, :translation, %{
            enabled: true,
            target_language: conversation_language,
            target_language_name: ConversationLanguageDetector.language_name(conversation_language),
            translated_content: translated_content,
            user_can_toggle: true,
            auto_translate_on_send: true,
            original_language: user_language
          })
        end)

      {:error, _reason} ->
        # Fallback: no translation if it fails
        Logger.warning("Translation failed, returning suggestions without translation")
        add_no_translation_metadata(suggestions, user_language)
    end
  end

  defp add_no_translation_metadata(suggestions, user_language) do
    # No translation needed - same language
    Enum.map(suggestions, fn suggestion ->
      Map.put(suggestion, :translation, %{
        enabled: false,
        target_language: user_language,
        user_can_toggle: false,
        auto_translate_on_send: false
      })
    end)
  end
end
