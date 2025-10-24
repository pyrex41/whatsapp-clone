defmodule GlobalbridgeBackend.AI.CostOptimizer do
  @moduledoc """
  Cost optimization strategies for AI pipeline operations.

  Implements various techniques to reduce API costs while maintaining performance:
  - Smart caching with TTL optimization
  - Query deduplication
  - Batch processing optimization
  - Model selection based on cost/performance tradeoffs
  """

  alias GlobalbridgeBackend.AI.Cache.EmbeddingCache
  alias GlobalbridgeBackend.AI.Cache.SearchCache

  @doc """
  Determines if a query should be processed based on cost optimization rules.

  Returns {:process, reason} if the query should be processed, or
  {:skip, cached_result, reason} if it can be skipped.
  """
  def should_process_query?(query, operation \\ :search) do
    cond do
      # Check for exact duplicate queries in cache
      has_exact_cache_hit?(query, operation) ->
        cached_result = get_cached_result(query, operation)
        {:skip, cached_result, "exact_cache_hit"}

      # Check for similar queries that could satisfy this request
      similar_query = find_similar_cached_query(query, operation) ->
        cached_result = get_cached_result(similar_query, operation)
        {:skip, cached_result, "similar_query"}

      # Check cost budget limits
      over_cost_budget?() ->
        {:skip, nil, "cost_budget_exceeded"}

      # Process the query
      true ->
        {:process, "no_cache_available"}
    end
  end

  @doc """
  Optimizes batch processing by grouping similar queries and removing duplicates.
  """
  def optimize_batch_queries(queries, operation \\ :embedding) do
    # Remove exact duplicates
    unique_queries = Enum.uniq(queries)

    # Group by similarity (simple length-based grouping for now)
    grouped_queries =
      Enum.group_by(unique_queries, fn query ->
        # Group by rough length
        String.length(query) |> div(10)
      end)

    # For each group, keep only the most representative query
    # This is a simple optimization - in production you'd use more sophisticated similarity
    optimized_queries =
      Enum.flat_map(grouped_queries, fn {_length_group, group_queries} ->
        # Keep the first query from each group as representative
        [List.first(group_queries)]
      end)

    %{
      original_count: length(queries),
      optimized_count: length(optimized_queries),
      savings_percentage:
        calculate_savings_percentage(length(queries), length(optimized_queries)),
      optimized_queries: optimized_queries
    }
  end

  @doc """
  Selects the most cost-effective model for a given operation and context.
  """
  def select_optimal_model(operation, context \\ %{}) do
    case operation do
      :embedding ->
        select_embedding_model(context)

      :completion ->
        select_completion_model(context)

      :search ->
        # Search operations typically use embeddings
        select_embedding_model(context)

      _ ->
        # Default fallback
        "text-embedding-3-large"
    end
  end

  @doc """
  Estimates the cost of processing a batch of queries.
  """
  def estimate_batch_cost(queries, operation \\ :embedding, model \\ nil) do
    model = model || select_optimal_model(operation)
    token_count = estimate_total_tokens(queries)

    case operation do
      :embedding ->
        # OpenAI embedding pricing: $0.0001 per 1K tokens for text-embedding-3-large
        cost_per_1k_tokens = 0.0001
        token_count / 1000 * cost_per_1k_tokens

      :completion ->
        # OpenAI completion pricing (approximate)
        # For GPT-4
        cost_per_1k_tokens = 0.002
        token_count / 1000 * cost_per_1k_tokens

      _ ->
        0.0
    end
  end

  @doc """
  Gets cost optimization statistics.
  """
  def get_cost_stats do
    embedding_cache_stats = EmbeddingCache.stats()
    search_cache_stats = SearchCache.stats()

    %{
      embedding_cache: embedding_cache_stats,
      search_cache: search_cache_stats,
      total_cache_entries:
        (embedding_cache_stats[:entries] || 0) + (search_cache_stats[:entries] || 0),
      estimated_savings: estimate_cache_savings(embedding_cache_stats, search_cache_stats)
    }
  end

  # Private functions

  defp has_exact_cache_hit?(query, :embedding) do
    EmbeddingCache.exists?(query)
  end

  defp has_exact_cache_hit?(query, :search) do
    SearchCache.get_search_results("any_thread", query, []) != nil
  end

  defp has_exact_cache_hit?(_query, _operation), do: false

  defp get_cached_result(query, :embedding) do
    EmbeddingCache.get(query)
  end

  defp get_cached_result(query, :search) do
    SearchCache.get_search_results("any_thread", query, [])
  end

  defp get_cached_result(_query, _operation), do: nil

  defp find_similar_cached_query(_query, _operation) do
    # TODO: Implement similarity search in cache
    # For now, return nil (no similar queries found)
    nil
  end

  defp over_cost_budget? do
    # TODO: Implement cost budget checking
    # For now, always allow processing
    false
  end

  defp select_embedding_model(_context) do
    # Always use the most cost-effective embedding model
    "text-embedding-3-large"
  end

  defp select_completion_model(context) do
    complexity = Map.get(context, :complexity, :medium)

    case complexity do
      :low -> "gpt-3.5-turbo"
      :medium -> "gpt-4o-mini"
      :high -> "gpt-4o"
      _ -> "gpt-4o-mini"
    end
  end

  defp estimate_total_tokens(queries) do
    # Rough estimation: 1 token ≈ 4 characters
    Enum.reduce(queries, 0, fn query, acc ->
      acc + String.length(query) / 4
    end)
    |> round()
  end

  defp calculate_savings_percentage(original, optimized) do
    if original > 0 do
      ((original - optimized) / original * 100) |> Float.round(2)
    else
      0.0
    end
  end

  defp estimate_cache_savings(embedding_stats, search_stats) do
    embedding_hits = embedding_stats[:hits] || 0
    search_hits = search_stats[:hits] || 0

    # Estimate $0.0001 per embedding API call saved
    embedding_savings = embedding_hits * 0.0001

    # Estimate $0.001 per search API call saved (rough estimate)
    search_savings = search_hits * 0.001

    embedding_savings + search_savings
  end
end
