defmodule GlobalbridgeBackendWeb.AIController do
  use GlobalbridgeBackendWeb, :controller

  alias GlobalbridgeBackend.Auth.Guardian
  alias GlobalbridgeBackend.AI.Jobs.TranslationJob
  alias GlobalbridgeBackend.AI.SemanticSearch
  alias GlobalbridgeBackend.AI.Jobs.SummarizationJob
  alias GlobalbridgeBackend.AI.Tools.TaskExtractionTool
  alias GlobalbridgeBackend.Repos.ThreadRepo
  alias GlobalbridgeBackend.Schemas.Thread
  alias GlobalbridgeBackend.Repo
  alias Agens.Job

  action_fallback(GlobalbridgeBackendWeb.FallbackController)

  @doc """
  Translates text to a target language.

  POST /api/ai/translate
  Body: {"text": "Hello world", "target_language": "es", "source_language": "en"}
  """
  def translate(conn, %{"text" => text, "target_language" => target_lang} = params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    # Check rate limits and feature flags (placeholder for now)
    # TODO: Implement rate limiting based on user tier
    # TODO: Check feature flags for translation access

    source_lang = Map.get(params, "source_language", "auto")

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
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Translation failed", details: reason})
    end
  end

  def translate(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: text and target_language"})
  end

  @doc """
  Analyzes the tone of given text.

  POST /api/ai/analyze_tone
  Body: {"text": "This is great!", "language": "en"}
  """
  def analyze_tone(conn, %{"text" => text} = params) do
    _user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    # Check rate limits and feature flags (placeholder)
    # TODO: Implement rate limiting
    # TODO: Check feature flags

    language = Map.get(params, "language", "en")

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
  end

  def analyze_tone(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: text"})
  end

  @doc """
  Summarizes a message thread using RAG-based summarization.

  POST /api/ai/summarize_thread
  Body: {"thread_id": "uuid", "max_length": 200}
  """
  def summarize_thread(conn, %{"thread_id" => thread_id} = params) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    # Check rate limits and feature flags (placeholder)
    # TODO: Implement rate limiting
    # TODO: Check feature flags
    # TODO: Verify user has access to the thread

    max_length = Map.get(params, "max_length", 200)

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
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Summarization failed", details: reason})
    end
  end

  def summarize_thread(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: thread_id"})
  end

  @doc """
  Performs semantic search across messages in threads.

  POST /api/ai/search_semantic
  Body: {"query": "project deadline", "thread_id": "uuid", "limit": 10, "translate": true}
  """
  def search_semantic(conn, %{"query" => query} = params) do
    _user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    # Check rate limits and feature flags (placeholder)
    # TODO: Implement rate limiting
    # TODO: Check feature flags

    thread_id = Map.get(params, "thread_id")
    limit = Map.get(params, "limit", 10)
    use_recency_bias = Map.get(params, "recency_bias", true)
    translate = Map.get(params, "translate", false)

    search_opts = [
      limit: limit,
      recency_bias: use_recency_bias,
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
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Search failed", details: reason})
    end
  end

  def search_semantic(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: query"})
  end

  @doc """
  Extracts actionable tasks from a message thread.

  POST /api/ai/extract_tasks
  Body: {"thread_id": "uuid", "query": "tasks, deadlines, decisions"}
  """
  def extract_tasks(conn, %{"thread_id" => thread_id} = params) do
    _user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    # Check rate limits and feature flags (placeholder)
    # TODO: Implement rate limiting
    # TODO: Check feature flags
    # TODO: Verify user has access to the thread

    query = Map.get(params, "query", "tasks, deadlines, decisions, commitments")

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
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Task extraction failed", details: reason})
    end
  end

  def extract_tasks(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: thread_id"})
  end

  @doc """
  Checks sqlite-vec availability and vector table health for a thread's shard database.

  POST /api/ai/vec_health
  Body: {"thread_id": "uuid"}
  """
  def vec_health(conn, %{"thread_id" => thread_id}) do
    _user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    shard_id = resolve_shard_id(thread_id)
    repo = ThreadRepo.get_repo(shard_id)

    # 1) Verify vec0 module is usable by creating and dropping a temp virtual table
    temp_name = "__vec_health_" <> Integer.to_string(:rand.uniform(1_000_000))
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
  end

  def vec_health(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: thread_id"})
  end

  defp resolve_shard_id(thread_id) do
    case Repo.get(Thread, thread_id) do
      %Thread{database_shard_id: shard_id} when is_binary(shard_id) and shard_id != "" -> shard_id
      _ -> thread_id
    end
  end
end
