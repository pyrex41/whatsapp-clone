defmodule GlobalbridgeBackendWeb.AIController do
  use GlobalbridgeBackendWeb, :controller

  require Logger

  alias GlobalbridgeBackend.Auth.Guardian
  alias GlobalbridgeBackend.AI.Authorization
  alias GlobalbridgeBackend.AI.Jobs.TranslationJob
  alias GlobalbridgeBackend.AI.SemanticSearch
  alias GlobalbridgeBackend.AI.Jobs.SummarizationJob
  alias GlobalbridgeBackend.AI.Tools.TaskExtractionTool
  alias GlobalbridgeBackend.AI.LanguageDetectionService
  alias GlobalbridgeBackend.AI.SmartReplyGenerator
  alias GlobalbridgeBackend.AI.ConversationMonitor
  alias GlobalbridgeBackend.Repos.ThreadRepo
  alias GlobalbridgeBackend.Schemas.{Thread, Message}
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackendWeb.Validators.AIValidator
  alias Agens.Job

  action_fallback(GlobalbridgeBackendWeb.FallbackController)

  @doc """
  Translates text to a target language with idiom analysis and cultural context.

  POST /api/ai/translate
  Body: {"text": "Hello world", "target_language": "es", "source_language": "en"}

  ## Input Validation
    - text: String, max 10,000 characters (required)
    - target_language: Valid language code (optional - if not provided, auto-detects and translates to English)
    - source_language: Valid language code (optional, defaults to "auto")
    - detection_strategy: "dedicated" or "combined" (optional, defaults to configured strategy)

  ## Language Detection
    When target_language is not provided:
    - "dedicated" strategy: Makes separate language detection call, then translates
    - "combined" strategy: Detects language and translates in single LLM call (faster, slightly less accurate)
    - Configure default with LANGUAGE_DETECTION_STRATEGY env var

  ## Response Format
    - translation: The translated text
    - confidence: Translation confidence score (0.0-1.0)
    - cultural_notes: Array of idiom analyses with cultural context (may be empty)
    - source_language: Detected or provided source language (full name)
    - source_language_code: Source language ISO code
    - target_language: Target language (full name)
    - target_language_code: Target language ISO code
    - detection_strategy: Strategy used ("dedicated", "combined", or "none" if target provided)

  ## Examples

  With target language provided:
  ```json
  {
    "success": true,
    "translation": "¡Buena suerte en tu examen!",
    "confidence": 0.95,
    "cultural_notes": [...],
    "source_language": "English",
    "source_language_code": "en",
    "target_language": "Spanish",
    "target_language_code": "es",
    "detection_strategy": "none"
  }
  ```

  Without target language (auto-detection):
  ```json
  {
    "success": true,
    "translation": "Hello world",
    "confidence": 0.98,
    "cultural_notes": [],
    "source_language": "Spanish",
    "source_language_code": "es",
    "target_language": "English",
    "target_language_code": "en",
    "detection_strategy": "combined"
  }
  ```
  """
  def translate(conn, params) do
    _user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with {:ok, text} <- AIValidator.validate_text(params["text"]),
         {:ok, target_lang} <- AIValidator.validate_optional_target_language(params["target_language"]),
         {:ok, _source_lang} <- validate_source_language(params["source_language"]) do
      # Check rate limits and feature flags (placeholder for now)
      # TODO: Implement rate limiting based on user tier
      # TODO: Check feature flags for translation access

      # Get detection strategy from params or use configured default
      detection_strategy = get_detection_strategy(params["detection_strategy"])

      # Get formality level from params (informal, neutral, formal)
      formality = params["formality"]

      # Execute translation with optional language detection and formality
      case execute_translation(text, target_lang, detection_strategy, formality) do
        {:ok, result} ->
          json(conn, Map.merge(%{success: true}, result))

        {:error, reason} ->
          safe_error_response(conn, :unprocessable_entity, "Translation failed", reason)
      end
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  rescue
    exception ->
      safe_error_response(conn, :internal_server_error, "An error occurred during translation", exception)
  end

  @doc """
  Analyzes the tone of given text.

  POST /api/ai/analyze_tone
  Body: {"text": "This is great!", "language": "en"}

  ## Input Validation
    - text: String, max 10,000 characters (required)
    - language: Valid language code (optional, defaults to "en")
  """
  def analyze_tone(conn, params) do
    _user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with {:ok, text} <- AIValidator.validate_text(params["text"]),
         {:ok, language} <- AIValidator.validate_optional_language(params["language"]) do
      # Check rate limits and feature flags (placeholder)
      # TODO: Implement rate limiting
      # TODO: Check feature flags

      # For now, return a placeholder response
      # TODO: Implement actual tone analysis job
      tone_analysis = %{
        tone: "positive",
        confidence: 0.85,
        emotions: ["joy", "enthusiasm"],
        language: language
      }

      json(conn, %{
        success: true,
        analysis: tone_analysis,
        text: text
      })
    else
      {:error, message} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})
    end
  end

  @doc """
  Summarizes a message thread using RAG-based summarization.

  POST /api/ai/summarize_thread
  Body: {"thread_id": "uuid", "max_length": 200}

  ## Input Validation
    - thread_id: Valid UUID (required)
    - max_length: Integer between 1 and 1,000 (optional, defaults to 200)
  """
  def summarize_thread(conn, params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- AIValidator.validate_thread_id(params["thread_id"]),
         {:ok, max_length} <- AIValidator.validate_with_default(params["max_length"], &AIValidator.validate_max_length/1, 200),
         :ok <- verify_thread_access(user.id, thread_id) do

      # Get current message count for this thread
      current_message_count = count_thread_messages(thread_id)

      # Check if force refresh is requested
      force_refresh = params["force_refresh"] == true

      # Check cache and determine strategy (skip cache if force_refresh is true)
      case force_refresh do
        true ->
          # Force full regeneration, bypass cache
          Logger.info("Force refresh requested for thread #{thread_id}, bypassing cache")
          :full_regenerate

        false ->
          GlobalbridgeBackend.AI.SummaryCache.should_update_incrementally?(thread_id, current_message_count)
      end
      |> case do
        {:use_cached, cached_summary} ->
          # Return cached summary
          Logger.info("Using cached summary for thread #{thread_id}")
          json(conn, Map.merge(%{success: true, cached: true}, format_summary_response(cached_summary, thread_id, current_message_count, max_length)))

        {:incremental, old_summary, old_message_count, delta} ->
          # Incremental update: fetch only new messages and update summary
          Logger.info("Incremental summary update for thread #{thread_id}: #{delta} new messages")

          case SummarizationJob.summarize_thread_incremental(thread_id, old_summary, old_message_count, max_length: max_length) do
            {:ok, %{summary: summary_data} = result} ->
              # Cache the updated summary
              GlobalbridgeBackend.AI.SummaryCache.put(thread_id, summary_data, current_message_count)

              json(conn, Map.merge(%{success: true, cached: false, incremental: true},
                format_summary_response(summary_data, thread_id, current_message_count, max_length)))

            {:error, reason} ->
              safe_error_response(conn, :unprocessable_entity, "Incremental summarization failed", reason)
          end

        :full_regenerate ->
          # Full regeneration: fetch all messages and generate fresh summary
          Logger.info("Full summary regeneration for thread #{thread_id}")

          case SummarizationJob.summarize_thread(thread_id, "comprehensive summary", max_length: max_length) do
            {:ok, %{summary: summary_data} = result} ->
              # Cache the new summary
              GlobalbridgeBackend.AI.SummaryCache.put(thread_id, summary_data, current_message_count)

              json(conn, Map.merge(%{success: true, cached: false, incremental: false},
                format_summary_response(summary_data, thread_id, result[:retrieved_messages] || current_message_count, max_length)))

            {:error, reason} ->
              safe_error_response(conn, :unprocessable_entity, "Summarization failed", reason)
          end
      end
    else
      {:error, message} when is_binary(message) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied to this thread"})
    end
  rescue
    exception ->
      Logger.error("Summarization exception: #{inspect(exception)}")
      Logger.error("Stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
      safe_error_response(conn, :internal_server_error, "An error occurred during summarization", exception)
  end

  @doc """
  Performs semantic search across messages in threads.

  POST /api/ai/search_semantic
  Body: {"query": "project deadline", "thread_id": "uuid", "limit": 10, "translate": true}

  ## Input Validation
    - query: Search query string, max 1,000 characters (required)
    - thread_id: Valid UUID (optional)
    - limit: Integer between 1 and 50 (optional, defaults to 10)
    - recency_bias: Boolean (optional, defaults to true)
    - translate: Boolean (optional, defaults to false)
  """
  def search_semantic(conn, params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with {:ok, query} <- AIValidator.validate_query(params["query"]),
         {:ok, thread_id} <- AIValidator.validate_optional_thread_id(params["thread_id"]),
         {:ok, limit} <- AIValidator.validate_with_default(params["limit"], &AIValidator.validate_limit/1, 10),
         {:ok, recency_bias} <- AIValidator.validate_optional_boolean(params["recency_bias"], true),
         {:ok, translate} <- AIValidator.validate_optional_boolean(params["translate"], false),
         :ok <- verify_optional_thread_access(user.id, thread_id) do
      # Check rate limits and feature flags (placeholder)
      # TODO: Implement rate limiting
      # TODO: Check feature flags

      search_opts = [
        limit: limit,
        recency_bias: recency_bias,
        recency_weight: 0.3
      ]

      # Perform semantic search
      case SemanticSearch.search(thread_id, query, search_opts) do
        {:ok, results} ->
          # Optionally translate results if requested
          processed_results =
            if translate do
              # TODO: Implement translation of search results
              results
            else
              results
            end

          json(conn, %{
            success: true,
            query: query,
            results: processed_results,
            total_results: length(processed_results),
            thread_id: thread_id
          })

        {:error, reason} ->
          safe_error_response(conn, :unprocessable_entity, "Search failed", reason)
      end
    else
      {:error, message} when is_binary(message) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied to this thread"})
    end
  rescue
    exception ->
      safe_error_response(conn, :internal_server_error, "An error occurred during search", exception)
  end

  @doc """
  Extracts actionable tasks from a message thread.

  POST /api/ai/extract_tasks
  Body: {"thread_id": "uuid", "query": "tasks, deadlines, decisions"}

  ## Input Validation
    - thread_id: Valid UUID (required)
    - query: Search query string, max 1,000 characters (optional, defaults to standard query)
  """
  def extract_tasks(conn, params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- AIValidator.validate_thread_id(params["thread_id"]),
         {:ok, query} <- validate_optional_query(params["query"]),
         :ok <- verify_thread_access(user.id, thread_id) do
      # Check rate limits and feature flags (placeholder)
      # TODO: Implement rate limiting
      # TODO: Check feature flags

      # Extract tasks using RAG-based approach
      case TaskExtractionTool.extract_from_thread(thread_id, query) do
        {:ok, extraction_result} ->
          json(conn, %{
            success: true,
            extraction: extraction_result,
            thread_id: thread_id,
            query: query
          })

        {:error, reason} ->
          safe_error_response(conn, :unprocessable_entity, "Task extraction failed", reason)
      end
    else
      {:error, message} when is_binary(message) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied to this thread"})
    end
  rescue
    exception ->
      safe_error_response(conn, :internal_server_error, "An error occurred during task extraction", exception)
  end

  @doc """
  Generates smart reply suggestions based on conversation context and user writing style.

  POST /api/v1/ai/suggest_replies
  Body: {"thread_id": "uuid", "count": 3, "style_match": true}

  ## Input Validation
    - thread_id: Valid UUID (required)
    - count: Integer between 1 and 10 (optional, defaults to 3)
    - style_match: Boolean (optional, defaults to true)

  ## Response Format
    - suggestions: Array of suggestion objects with:
      - type: "smart_reply"
      - content: The suggested reply text
      - confidence: 0.0-1.0 confidence score
      - position: Position in suggestion list (1, 2, 3, etc.)
      - context: Metadata about the suggestion

  ## Example Response
  ```json
  {
    "success": true,
    "suggestions": [
      {
        "type": "smart_reply",
        "content": "Got it, thanks!",
        "confidence": 0.92,
        "position": 1,
        "context": {"matched_style": true, "formality_level": 0.3}
      }
    ],
    "thread_id": "uuid",
    "count": 3
  }
  ```
  """
  def suggest_replies(conn, params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- AIValidator.validate_thread_id(params["thread_id"]),
         {:ok, count} <- validate_suggestion_count(params["count"]),
         {:ok, style_match} <- AIValidator.validate_optional_boolean(params["style_match"], true),
         :ok <- verify_thread_access(user.id, thread_id) do

      # Get recent messages from thread for context
      recent_messages = get_recent_messages(thread_id, 10)

      if length(recent_messages) == 0 do
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "No messages in thread to generate suggestions from"})
      else
        # Generate suggestions
        case SmartReplyGenerator.generate_suggestions(
               user.id,
               thread_id,
               recent_messages,
               count: count,
               style_match: style_match
             ) do
          {:ok, suggestions} ->
            json(conn, %{
              success: true,
              suggestions: suggestions,
              thread_id: thread_id,
              count: length(suggestions)
            })

          {:error, reason} ->
            safe_error_response(conn, :unprocessable_entity, "Failed to generate suggestions", reason)
        end
      end
    else
      {:error, message} when is_binary(message) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied to this thread"})
    end
  rescue
    exception ->
      safe_error_response(conn, :internal_server_error, "An error occurred generating suggestions", exception)
  end

  @doc """
  Records user feedback on an AI suggestion (accepted or rejected).

  POST /api/v1/ai/record_feedback
  Body: {
    "thread_id": "uuid",
    "suggestion": {...},
    "accepted": true,
    "modified_content": "edited version",
    "rejection_reason": "not my style",
    "time_to_response_ms": 2500
  }

  ## Input Validation
    - thread_id: Valid UUID (required)
    - suggestion: Suggestion object from suggest_replies (required)
    - accepted: Boolean (required)
    - modified_content: String (optional)
    - rejection_reason: String (optional)
    - time_to_response_ms: Integer (optional)

  ## Example Response
  ```json
  {
    "success": true,
    "message": "Feedback recorded successfully"
  }
  ```
  """
  def record_feedback(conn, params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- AIValidator.validate_thread_id(params["thread_id"]),
         {:ok, suggestion} <- validate_suggestion(params["suggestion"]),
         {:ok, accepted} <- validate_accepted(params["accepted"]),
         :ok <- verify_thread_access(user.id, thread_id) do

      # Build feedback options
      opts = [
        modified_content: params["modified_content"],
        rejection_reason: params["rejection_reason"],
        time_to_response_ms: params["time_to_response_ms"]
      ]

      # Record feedback
      case SmartReplyGenerator.record_feedback(user.id, thread_id, suggestion, accepted, opts) do
        :ok ->
          json(conn, %{
            success: true,
            message: "Feedback recorded successfully"
          })

        {:error, reason} ->
          safe_error_response(conn, :unprocessable_entity, "Failed to record feedback", reason)
      end
    else
      {:error, message} when is_binary(message) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied to this thread"})
    end
  rescue
    exception ->
      safe_error_response(conn, :internal_server_error, "An error occurred recording feedback", exception)
  end

  @doc """
  Gets conversation insights including acceptance statistics and recent activity.

  GET /api/v1/ai/conversation_insights?thread_id=uuid

  ## Input Validation
    - thread_id: Valid UUID (optional)

  ## Response Format
    - acceptance_stats: Stats by suggestion type
    - thread_state: Current conversation monitoring state
    - user_style_profile: User's writing style metrics

  ## Example Response
  ```json
  {
    "success": true,
    "acceptance_stats": [
      {
        "suggestion_type": "smart_reply",
        "total": 45,
        "accepted": 32,
        "acceptance_rate": 0.71
      }
    ],
    "thread_state": {
      "messages": 15,
      "last_check": "2025-01-15T10:30:00Z",
      "pending_analysis": false
    },
    "user_style_profile": {
      "formality_level": 0.45,
      "emoji_frequency": 1.2,
      "messages_analyzed": 120,
      "confidence_score": 0.87
    }
  }
  ```
  """
  def conversation_insights(conn, params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- AIValidator.validate_optional_thread_id(params["thread_id"]),
         :ok <- verify_optional_thread_access(user.id, thread_id) do

      # Get acceptance statistics
      acceptance_stats =
        case SmartReplyGenerator.get_user_acceptance_stats(user.id) do
          {:ok, stats} -> stats
          {:error, _} -> []
        end

      # Get thread monitoring state if thread_id provided
      thread_state =
        if thread_id do
          ConversationMonitor.get_thread_state(thread_id)
        else
          nil
        end

      # Get user's style profile
      user_style_profile =
        case Repo.get_by(GlobalbridgeBackend.Schemas.UserStyleProfile, user_id: user.id) do
          nil -> nil
          profile ->
            %{
              formality_level: profile.formality_level,
              vocabulary_complexity: profile.vocabulary_complexity,
              emoji_frequency: profile.emoji_frequency,
              messages_analyzed: profile.messages_analyzed,
              confidence_score: profile.confidence_score,
              last_updated_at: profile.last_updated_at
            }
        end

      json(conn, %{
        success: true,
        acceptance_stats: acceptance_stats,
        thread_state: thread_state,
        user_style_profile: user_style_profile
      })
    else
      {:error, message} when is_binary(message) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied"})
    end
  rescue
    exception ->
      safe_error_response(conn, :internal_server_error, "An error occurred retrieving insights", exception)
  end

  @doc """
  Checks sqlite-vec availability and vector table health for a thread's shard database.

  POST /api/ai/vec_health
  Body: {"thread_id": "uuid"}

  ## Input Validation
    - thread_id: Valid UUID (required)
  """
  def vec_health(conn, params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with {:ok, thread_id} <- AIValidator.validate_thread_id(params["thread_id"]),
         :ok <- verify_thread_access(user.id, thread_id) do
      perform_vec_health_check(conn, thread_id)
    else
      {:error, message} when is_binary(message) ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: message})

      {:error, :unauthorized} ->
        conn
        |> put_status(:forbidden)
        |> json(%{error: "Access denied to this thread"})
    end
  end

  # Private helper to perform the actual health check
  defp perform_vec_health_check(conn, thread_id) do
    shard_id = resolve_shard_id(thread_id)
    repo = ThreadRepo.get_repo(shard_id)

    # 1) Verify vec0 module is usable by creating and dropping a temp virtual table
    # Use cryptographically secure random bytes for unpredictable table name
    temp_suffix = Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
    temp_name = "vec_health_#{temp_suffix}"
    create_sql = "CREATE VIRTUAL TABLE temp.#{temp_name} USING vec0(embedding float[4])"
    drop_sql = "DROP TABLE IF EXISTS temp.#{temp_name}"

    vec_ok =
      case Ecto.Adapters.SQL.query(repo, create_sql, []) do
        {:ok, _} ->
          _ = Ecto.Adapters.SQL.query(repo, drop_sql, [])
          true

        {:error, _} ->
          false
      end

    # 2) Check message_embeddings table existence and row count
    table_exists =
      case Ecto.Adapters.SQL.query(repo, "SELECT name FROM sqlite_schema WHERE name = 'message_embeddings'", []) do
        {:ok, %{rows: rows}} -> length(rows) > 0
        _ -> false
      end

    count =
      if table_exists do
        case Ecto.Adapters.SQL.query(repo, "SELECT COUNT(*) FROM message_embeddings", []) do
          {:ok, %{rows: [[c]]}} -> c
          _ -> 0
        end
      else
        0
      end

    json(conn, %{
      success: true,
      thread_id: thread_id,
      shard_id: shard_id,
      vec_extension_available: vec_ok,
      embeddings_table_exists: table_exists,
      embeddings_count: count
    })
  rescue
    exception ->
      safe_error_response(conn, :internal_server_error, "An error occurred during health check", exception)
  end

  # Private helper functions

  @doc """
  Executes translation with optional language detection based on whether
  target_language is provided and which detection strategy is selected.
  """
  defp execute_translation(text, nil, detection_strategy, formality) do
    # No target language provided - auto-detect and translate to English
    Logger.info("AIController: Auto-detecting language and translating to English using #{detection_strategy} strategy")

    case detection_strategy do
      :combined ->
        # Single LLM call for detection + translation
        case LanguageDetectionService.detect_and_translate(text, "en") do
          {:ok, result} ->
            {:ok, Map.put(result, :detection_strategy, "combined")}
          {:error, reason} ->
            {:error, reason}
        end

      :dedicated ->
        # Two-step: dedicated detection, then translation
        with {:ok, detection} <- LanguageDetectionService.detect_language_dedicated(text),
             {:ok, translation} <- simple_translate(text, "en", formality) do
          result = Map.merge(translation, %{
            source_language: detection.language,
            source_language_code: detection.language_code,
            detection_strategy: "dedicated"
          })
          {:ok, result}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp execute_translation(text, target_lang, _detection_strategy, formality) when is_binary(target_lang) do
    # Target language provided - use simple translation
    Logger.info("AIController: Translating to #{target_lang} with formality=#{inspect(formality)}")

    case simple_translate(text, target_lang, formality) do
      {:ok, result} ->
        {:ok, Map.put(result, :detection_strategy, "none")}
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the detection strategy from params or environment configuration.
  """
  defp get_detection_strategy(nil) do
    LanguageDetectionService.get_detection_strategy()
  end

  defp get_detection_strategy("combined"), do: :combined
  defp get_detection_strategy("dedicated"), do: :dedicated
  defp get_detection_strategy(_), do: LanguageDetectionService.get_detection_strategy()

  defp simple_translate(text, target_lang, formality \\ nil) do
    # Direct translation using Groq API, bypassing the buggy Agens framework
    groq_api_key = System.get_env("GROQ_API_KEY")

    if !groq_api_key do
      {:error, "GROQ_API_KEY not configured"}
    else
      # Convert language code to full name for clarity
      target_language_name = LanguageDetectionService.get_language_name(target_lang)

      # Build formality instruction
      formality_instruction = case formality do
        "informal" -> """
        FORMALITY LEVEL: INFORMAL/CASUAL
        - Use casual, friendly language as if speaking to a close friend
        - Choose informal greetings and expressions (e.g., Spanish: "¿Qué tal?" instead of "¿Cómo está?")
        - Use informal pronouns (e.g., Spanish: "tú" instead of "usted", French: "tu" instead of "vous")
        - Opt for conversational slang and colloquialisms when appropriate
        - Keep the tone warm and relaxed
        """

        "formal" -> """
        FORMALITY LEVEL: FORMAL/PROFESSIONAL
        - Use polite, respectful language as if speaking to a business contact or elder
        - Choose formal greetings and expressions (e.g., Spanish: "Buenos días, señor" instead of "Hola")
        - Use formal pronouns (e.g., Spanish: "usted", French: "vous", German: "Sie")
        - Include appropriate titles and honorifics
        - Maintain a professional, courteous tone
        """

        _ -> """
        FORMALITY LEVEL: NEUTRAL/STANDARD
        - Use balanced language appropriate for everyday conversation
        - Choose standard greetings and expressions
        - Use neutral pronouns appropriate for the context
        - Maintain a friendly but respectful tone
        """
      end

      # Build the translation prompt
      prompt = """
      You are an expert translator who understands nuance, tone, and cultural context.

      #{formality_instruction}

      CRITICAL INSTRUCTIONS:
      1. DO NOT translate word-for-word. Instead, find the most natural way to express the INTENT and FEELING in #{target_language_name}.
      2. Adjust the formality to match the specified level - this may mean choosing completely different words or phrases.
      3. For simple greetings like "Hello", adjust based on formality:
         - Informal: Use casual greetings (e.g., "Hola" / "¿Qué tal?" / "Salut")
         - Formal: Use polite greetings with honorifics (e.g., "Buenos días, señor" / "Bonjour, monsieur")
      4. Preserve emojis and punctuation exactly as they appear.
      5. If an idiom or cultural phrase doesn't translate well, find an equivalent expression in the target language.

      Text to translate: #{text}

      Respond in JSON format:
      {
        "source_language": "detected source language full name (e.g., Spanish, French)",
        "translation": "the translated text with appropriate formality",
        "confidence": 0.95,
        "cultural_notes": []
      }

      The cultural_notes should be an array of objects with this structure:
      {
        "source_phrase": "the idiom or cultural phrase",
        "explanation": "what it means",
        "target_equivalent": "best translation in target language",
        "cultural_context": "cultural background information"
      }

      Only return the JSON, nothing else.
      """

      # Make the API call to Groq
      url = "https://api.groq.com/openai/v1/chat/completions"
      headers = [
        {"Authorization", "Bearer #{groq_api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{
        model: System.get_env("GROQ_MODEL") || "llama-3.3-70b-versatile",
        messages: [
          %{role: "system", content: "You are a professional translator. Always respond with valid JSON."},
          %{role: "user", content: prompt}
        ],
        temperature: 0.3,
        response_format: %{type: "json_object"}
      })

      case HTTPoison.post(url, body, headers, recv_timeout: 30_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
              case Jason.decode(content) do
                {:ok, result} ->
                  source_language = result["source_language"] || "Unknown"
                  source_language_code = LanguageDetectionService.get_language_code(source_language) || "unknown"

                  {:ok, %{
                    translation: result["translation"],
                    confidence: result["confidence"] || 0.9,
                    cultural_notes: result["cultural_notes"] || [],
                    source_language: source_language,
                    source_language_code: source_language_code,
                    target_language: target_language_name,
                    target_language_code: target_lang
                  }}
                {:error, _} ->
                  {:error, "Failed to parse translation result"}
              end
            _ ->
              {:error, "Invalid API response format"}
          end

        {:ok, %HTTPoison.Response{status_code: status_code, body: error_body}} ->
          Logger.error("Groq API error: #{status_code} - #{error_body}")
          {:error, "Translation API error: #{status_code}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("HTTP error calling Groq: #{inspect(reason)}")
          {:error, "Translation service unavailable"}
      end
    end
  end

  defp resolve_shard_id(thread_id) do
    case Repo.get(Thread, thread_id) do
      %Thread{database_shard_id: shard_id} when is_binary(shard_id) and shard_id != "" -> shard_id
      _ -> thread_id
    end
  end

  defp verify_thread_access(user_id, thread_id) do
    try do
      Authorization.ensure_thread_access!(user_id, thread_id)
      :ok
    rescue
      _ -> {:error, :unauthorized}
    end
  end

  defp verify_optional_thread_access(_user_id, nil), do: :ok
  defp verify_optional_thread_access(user_id, thread_id), do: verify_thread_access(user_id, thread_id)


  defp validate_source_language(nil), do: {:ok, "auto"}
  defp validate_source_language("auto"), do: {:ok, "auto"}
  defp validate_source_language(lang), do: AIValidator.validate_language(lang)

  defp validate_optional_query(nil), do: {:ok, "tasks, deadlines, decisions, commitments"}
  defp validate_optional_query(query), do: AIValidator.validate_query(query)

  defp validate_suggestion_count(nil), do: {:ok, 3}
  defp validate_suggestion_count(count) when is_integer(count) and count >= 1 and count <= 10, do: {:ok, count}
  defp validate_suggestion_count(_), do: {:error, "count must be an integer between 1 and 10"}

  defp validate_suggestion(nil), do: {:error, "suggestion is required"}
  defp validate_suggestion(suggestion) when is_map(suggestion) do
    required_fields = ["type", "content", "confidence", "position"]
    missing_fields = Enum.filter(required_fields, fn field -> !Map.has_key?(suggestion, field) end)

    if length(missing_fields) > 0 do
      {:error, "suggestion missing required fields: #{Enum.join(missing_fields, ", ")}"}
    else
      # Convert string keys to atoms for internal use
      {:ok, %{
        type: suggestion["type"],
        content: suggestion["content"],
        confidence: suggestion["confidence"],
        position: suggestion["position"],
        context: suggestion["context"] || %{}
      }}
    end
  end
  defp validate_suggestion(_), do: {:error, "suggestion must be an object"}

  defp validate_accepted(nil), do: {:error, "accepted field is required"}
  defp validate_accepted(accepted) when is_boolean(accepted), do: {:ok, accepted}
  defp validate_accepted(_), do: {:error, "accepted must be a boolean"}

  defp get_recent_messages(thread_id, limit) do
    require Logger
    alias GlobalbridgeBackend.Chat

    # Get thread to find its database shard
    thread = Chat.get_thread(thread_id)

    if is_nil(thread) do
      Logger.warning("⚠️ [SMART_REPLY] Thread not found: #{thread_id}")
      []
    else

    # Get thread's repo using the correct shard_id
    repo = ThreadRepo.get_repo(thread.database_shard_id)
    Logger.info("🔍 [SMART_REPLY] get_recent_messages for thread: #{thread_id}, shard: #{thread.database_shard_id}, repo: #{inspect(repo)}")

    # Query recent messages
    import Ecto.Query

    query =
      from m in Message,
        order_by: [desc: m.inserted_at],
        limit: ^limit,
        select: m

    messages = case repo.all(query) do
      messages when is_list(messages) ->
        Logger.info("📨 [SMART_REPLY] Found #{length(messages)} messages in database")
        Enum.reverse(messages)
      result ->
        Logger.warning("⚠️ [SMART_REPLY] Unexpected result from query: #{inspect(result)}")
        []
    end

    Logger.info("✅ [SMART_REPLY] Returning #{length(messages)} messages")
    messages
    end
  rescue
    error ->
      Logger.error("❌ [SMART_REPLY] Error querying messages: #{inspect(error)}")
      []
  end

  # Helper to count messages in a thread
  defp count_thread_messages(thread_id) do
    require Logger
    alias GlobalbridgeBackend.Chat

    # Get thread to find its database shard
    thread = Chat.get_thread(thread_id)

    if is_nil(thread) do
      Logger.warning("⚠️  [SUMMARY] Thread not found: #{thread_id}")
      0
    else
      # Get thread's repo using the correct shard_id
      repo = ThreadRepo.get_repo(thread.database_shard_id)

      # Count messages
      import Ecto.Query
      query = from m in Message, select: count(m.id)

      case repo.one(query) do
        count when is_integer(count) -> count
        _ -> 0
      end
    end
  rescue
    error ->
      Logger.error("❌ [SUMMARY] Error counting messages: #{inspect(error)}")
      0
  end

  # Helper to format summary response
  defp format_summary_response(summary_data, thread_id, message_count, max_length) do
    # Get real thread participants from database
    participants = get_thread_participants(thread_id)

    %{
      summary: summary_data.summary,
      thread_id: thread_id,
      max_length: max_length,
      key_topics: summary_data.key_points || [],
      decisions: summary_data.decisions || [],
      action_items: format_action_items(summary_data.action_items || []),
      participants: participants,
      message_count: message_count,
      provider: System.get_env("SUMMARIZER_MODEL") || "grok-2-1212",
      confidence_score: summary_data.confidence_score
    }
  end

  # Get actual thread participants from database
  defp get_thread_participants(thread_id) do
    require Logger
    alias GlobalbridgeBackend.Chat
    alias GlobalbridgeBackend.Accounts.User

    case Chat.get_thread(thread_id) do
      nil ->
        Logger.warning("Thread not found when fetching participants: #{thread_id}")
        []

      thread ->
        # Preload thread participants
        thread = Repo.preload(thread, [:thread_participants])

        # Get user info for each participant
        thread.thread_participants
        |> Enum.map(fn tp ->
          case Repo.get(GlobalbridgeBackend.Schemas.User, tp.user_id) do
            nil -> nil
            user ->
              %{
                user_id: user.id,
                username: user.username,
                display_name: user.display_name,
                message_count: nil  # Could be calculated if needed
              }
          end
        end)
        |> Enum.reject(&is_nil/1)
    end
  rescue
    error ->
      Logger.error("Error fetching thread participants: #{inspect(error)}")
      []
  end

  # Helper to format action items from simple strings to structured objects
  defp format_action_items(action_items) when is_list(action_items) do
    Enum.map(action_items, fn item ->
      # Action items are strings like "John needs to complete the report by Friday"
      # Try to extract assignee if present in the format "Name needs to..." or "Name should..."
      assignee = extract_assignee(item)

      %{
        description: item,
        assignee: assignee,
        due_date: nil,  # We don't parse dates from text for now
        priority: nil   # Could be enhanced to detect priority keywords
      }
    end)
  end

  defp format_action_items(_), do: []

  # Helper to format participants from simple strings to structured objects

  # Extract assignee from action item text (simple heuristic)
  defp extract_assignee(text) when is_binary(text) do
    # Look for patterns like "John needs to", "Sarah should", etc.
    case Regex.run(~r/^([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)\s+(?:needs? to|should|must|will)/i, text) do
      [_, name] -> String.trim(name)
      _ -> nil
    end
  end

  defp extract_assignee(_), do: nil

  # Security helper: sanitize error responses to prevent information leakage
  defp safe_error_response(conn, status, user_message, error_details) do
    # Log the detailed error for debugging
    Logger.error("AI endpoint error: #{user_message}",
      error: inspect(error_details),
      status: status
    )

    # Return sanitized error to client (no internal details)
    conn
    |> put_status(status)
    |> json(%{error: user_message})
  end
end
