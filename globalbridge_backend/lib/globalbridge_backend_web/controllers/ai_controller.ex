defmodule GlobalbridgeBackendWeb.AIController do
  use GlobalbridgeBackendWeb, :controller

  require Logger

  alias GlobalbridgeBackend.Auth.Guardian
  alias GlobalbridgeBackend.AI.Authorization
  alias GlobalbridgeBackend.AI.Jobs.TranslationJob
  alias GlobalbridgeBackend.AI.SemanticSearch
  alias GlobalbridgeBackend.AI.Jobs.SummarizationJob
  alias GlobalbridgeBackend.AI.Tools.TaskExtractionTool
  alias GlobalbridgeBackend.Repos.ThreadRepo
  alias GlobalbridgeBackend.Schemas.Thread
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackendWeb.Validators.AIValidator
  alias Agens.Job

  action_fallback(GlobalbridgeBackendWeb.FallbackController)

  @doc """
  Translates text to a target language.

  POST /api/ai/translate
  Body: {"text": "Hello world", "target_language": "es", "source_language": "en"}

  ## Input Validation
    - text: String, max 10,000 characters (required)
    - target_language: Valid language code (required)
    - source_language: Valid language code (optional, defaults to "auto")
  """
  def translate(conn, params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    with {:ok, text} <- AIValidator.validate_text(params["text"]),
         {:ok, target_lang} <- validate_required_language(params["target_language"]),
         {:ok, source_lang} <- validate_source_language(params["source_language"]) do
      # Check rate limits and feature flags (placeholder for now)
      # TODO: Implement rate limiting based on user tier
      # TODO: Check feature flags for translation access

      # Prepare job input
      job_input = %{
        text: text,
        target_language: target_lang,
        source_language: source_lang,
        user_id: user.id
      }

      # Execute translation job
      case Job.run(TranslationJob.job_config(), job_input) do
        {:ok, result} ->
          json(conn, %{
            success: true,
            translation: result,
            source_language: source_lang,
            target_language: target_lang
          })

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
      # Check rate limits and feature flags (placeholder)
      # TODO: Implement rate limiting
      # TODO: Check feature flags

      # Prepare job input (placeholder for future use)
      _job_input = %{
        thread_id: thread_id,
        max_length: max_length,
        user_id: user.id
      }

      # Execute summarization job
      case SummarizationJob.summarize_thread(thread_id, "comprehensive summary",
             max_length: max_length
           ) do
        {:ok, result} ->
          json(conn, %{
            success: true,
            summary: result,
            thread_id: thread_id,
            max_length: max_length
          })

        {:error, reason} ->
          safe_error_response(conn, :unprocessable_entity, "Summarization failed", reason)
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

  defp validate_required_language(nil), do: {:error, "Target language is required"}
  defp validate_required_language(lang), do: AIValidator.validate_language(lang)

  defp validate_source_language(nil), do: {:ok, "auto"}
  defp validate_source_language("auto"), do: {:ok, "auto"}
  defp validate_source_language(lang), do: AIValidator.validate_language(lang)

  defp validate_optional_query(nil), do: {:ok, "tasks, deadlines, decisions, commitments"}
  defp validate_optional_query(query), do: AIValidator.validate_query(query)

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
