defmodule GlobalbridgeBackend.AI.SemanticSearch do
  @moduledoc """
  Semantic search API that integrates EmbeddingService and RAGRetriever.

  This module provides high-level semantic search functionality by:
  - Generating embeddings for search queries using EmbeddingService
  - Performing vector similarity search using RAGRetriever
  - Supporting both basic and recency-biased search modes
  - Providing context building for LLM consumption
  - Implementing caching to avoid redundant embedding generation
  """

  alias GlobalbridgeBackend.AI.EmbeddingService
  alias GlobalbridgeBackend.AI.RAGRetriever
  alias GlobalbridgeBackend.AI.Cache.EmbeddingCache
  alias GlobalbridgeBackend.AI.Cache.SearchCache
  alias GlobalbridgeBackend.AI.Agents.LanguageDetectionAgent
  alias GlobalbridgeBackend.AI.Agents.TranslatorAgent
  alias Agens.Agent
  alias GlobalbridgeBackend.{Repo}
  alias GlobalbridgeBackend.Schemas.Thread

  require Logger

  @doc """
  Performs semantic search for messages in a thread.

  Generates an embedding for the query (with caching) and searches for similar messages.
  Returns enriched results with message content and metadata.
  """
  def search(thread_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    use_recency_bias = Keyword.get(opts, :recency_bias, false)
    recency_weight = Keyword.get(opts, :recency_weight, 0.3)

    Logger.debug("Performing semantic search for thread #{thread_id}: #{query}")

    # Check cache first
    cached_results = SearchCache.get_search_results(thread_id, query, opts)

    if cached_results do
      Logger.debug("Returning cached search results for thread #{thread_id}")
      {:ok, cached_results}
    else
      # Generate embedding for the query (with caching)
      case EmbeddingService.generate(query) do
        {:ok, query_embedding} ->
          # Perform search based on options
          shard_id = resolve_shard_id(thread_id)

          search_result =
            if use_recency_bias do
              RAGRetriever.search_with_recency_bias(shard_id, query_embedding,
                limit: limit,
                recency_weight: recency_weight
              )
            else
              RAGRetriever.search_by_embedding(shard_id, query_embedding, limit: limit)
            end

          case search_result do
            {:ok, results} ->
              Logger.debug("Found #{length(results)} semantic search results")
              # Cache the results
              SearchCache.put_search_results(thread_id, query, results, opts)
              {:ok, results}

            error ->
              Logger.error("Semantic search failed: #{inspect(error)}")
              error
          end

        {:error, error} ->
          Logger.error("Failed to generate query embedding: #{inspect(error)}")
          {:error, error}
      end
    end
  end

  @doc """
  Performs semantic search and builds context for LLM consumption.

  This is a convenience function that performs search and immediately builds
  formatted context suitable for LLM input.
  """
  def search_with_context(thread_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    max_context_length = Keyword.get(opts, :max_context_length, 4000)
    include_metadata = Keyword.get(opts, :include_metadata, true)

    case search(thread_id, query, limit: limit) do
      {:ok, results} ->
        context =
          RAGRetriever.build_context(results,
            max_length: max_context_length,
            include_metadata: include_metadata
          )

        {:ok, %{results: results, context: context}}

      error ->
        error
    end
  end

  @doc """
  Performs semantic search with recency bias enabled.

  Recent messages are boosted in the results based on their age.
  """
  def search_with_recency(thread_id, query, opts \\ []) do
    search(thread_id, query, Keyword.put(opts, :recency_bias, true))
  end

  @doc """
  Checks if a query embedding exists in cache.

  Useful for determining if embedding generation can be skipped.
  """
  def query_cached?(query) do
    EmbeddingCache.exists?(query, EmbeddingService.embedding_model())
  end

  @doc """
  Gets cached embedding for a query if it exists.
  """
  def get_cached_query_embedding(query) do
    EmbeddingCache.get(query, EmbeddingService.embedding_model())
  end

  @doc """
  Pre-generates and caches embeddings for common search queries.

  Useful for warming up the cache with frequently searched terms.
  """
  def warmup_cache(queries) when is_list(queries) do
    Logger.info("Warming up semantic search cache with #{length(queries)} queries")

    results =
      Enum.map(queries, fn query ->
        case EmbeddingService.generate(query) do
          {:ok, _embedding} -> {:ok, query}
          error -> {error, query}
        end
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    Logger.info("Cache warmup complete: #{successful}/#{length(queries)} queries cached")

    {:ok, %{successful: successful, total: length(queries)}}
  end

  @doc """
  Performs multilingual semantic search with optional translation.

  Detects the query language and optionally translates search results.
  Returns results in the requested target language with confidence scores.
  """
  def search_multilingual(thread_id, query, opts \\ []) do
    translate_results = Keyword.get(opts, :translate, false)
    target_language = Keyword.get(opts, :target_language, "English")

    Logger.debug("Performing multilingual search for thread #{thread_id}: #{query}")

    # First, detect the query language
    case detect_query_language(query) do
      {:ok, source_language} ->
        Logger.debug("Detected query language: #{source_language}")

        # Perform regular semantic search
        case search(thread_id, query, opts) do
          {:ok, results} ->
            if translate_results && source_language != target_language do
              # Translate the results
              translate_search_results(results, source_language, target_language)
            else
              {:ok, results}
            end

          error ->
            error
        end

      {:error, error} ->
        Logger.warning(
          "Language detection failed: #{inspect(error)}, falling back to regular search"
        )

        search(thread_id, query, opts)
    end
  end

  @doc """
  Performs multilingual search and builds context with optional translation.

  Combines multilingual search with context building for LLM consumption.
  """
  def search_multilingual_with_context(thread_id, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)
    max_context_length = Keyword.get(opts, :max_context_length, 4000)
    include_metadata = Keyword.get(opts, :include_metadata, true)

    case search_multilingual(thread_id, query, limit: limit) do
      {:ok, results} ->
        context =
          RAGRetriever.build_context(results,
            max_length: max_context_length,
            include_metadata: include_metadata
          )

        {:ok, %{results: results, context: context}}

      error ->
        error
    end
  end

  @doc """
  Gets search statistics for a thread.

  Returns information about the number of searchable messages and embeddings.
  """
  def get_search_stats(thread_id) do
    alias GlobalbridgeBackend.AI.VectorStore
    alias GlobalbridgeBackend.Repos.ThreadRepo

    # Get embedding count from vector store
    shard_id = resolve_shard_id(thread_id)
    total_embeddings = VectorStore.count_embeddings(shard_id)

    # Get message count from thread database
    repo = ThreadRepo.get_repo(shard_id)
    message_count_query = "SELECT COUNT(*) FROM messages WHERE is_deleted = 0"

    searchable_messages =
      case Ecto.Adapters.SQL.query(repo, message_count_query, []) do
        {:ok, %{rows: [[count]]}} -> count
        _ -> 0
      end

    {:ok,
     %{
       thread_id: thread_id,
       searchable_messages: searchable_messages,
       total_embeddings: total_embeddings
     }}
  end

  # Private functions

  defp detect_query_language(query) do
    # Start the language detection agent if not already started
    case Agent.start(LanguageDetectionAgent.config()) do
      {:ok, _pid} ->
        Logger.debug("Started language detection agent")

      {:error, {:already_started, _pid}} ->
        # Agent already running
        :ok

      {:error, reason} ->
        Logger.error("Failed to start language detection agent: #{inspect(reason)}")
        {:error, reason}
    end

    # Run language detection
    case GenServer.call(:language_detection_agent, {:run, %Agens.Message{input: query}}) do
      {:ok, result} ->
        # Parse the result to extract language
        case Regex.run(~r/Detected language:\s*(.+)/i, result) do
          [_, language] ->
            {:ok, String.trim(language)}

          _ ->
            Logger.warning("Could not parse language detection result: #{result}")
            # Default fallback
            {:ok, "English"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp translate_search_results(results, source_language, target_language) do
    Logger.debug(
      "Translating #{length(results)} search results from #{source_language} to #{target_language}"
    )

    # Translate each result
    translated_results =
      Enum.map(results, fn result ->
        case translate_message(result, source_language, target_language) do
          {:ok, translated_result} ->
            translated_result

          {:error, error} ->
            Logger.warning("Failed to translate result #{result.message_id}: #{inspect(error)}")
            # Return original result if translation fails
            result
        end
      end)

    {:ok, translated_results}
  end

  defp translate_message(result, source_language, target_language) do
    # Use the TranslatorAgent to translate the message content
    case TranslatorAgent.translate(result.content, source_language, target_language) do
      {:ok, %{translation: translated_text, confidence: confidence}} ->
        # Add translation metadata to the result
        result
        |> Map.put(:translated_content, translated_text)
        |> Map.put(:translation_confidence, confidence)
        |> Map.put(:source_language, source_language)
        |> Map.put(:target_language, target_language)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_shard_id(nil), do: nil
  defp resolve_shard_id(thread_id) do
    case Repo.get(Thread, thread_id) do
      %Thread{database_shard_id: shard_id} -> shard_id
      _ -> thread_id
    end
  end
end
