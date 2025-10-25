defmodule GlobalbridgeBackend.AI.Embeddings do
  @moduledoc """
  Real embedding generation using OpenAI's text-embedding-3-large model.

  This module provides production-quality embeddings for:
  - Message content semantic search
  - User style embeddings
  - Suggestion feedback embeddings
  - RAG retrieval

  Uses text-embedding-3-large:
  - Dimension: 3072 (matches our vector store)
  - Cost: ~$0.13 per 1M tokens
  - Quality: State-of-the-art semantic understanding
  """

  require Logger

  @embedding_model "text-embedding-3-large"
  @embedding_dimensions 3072
  @openai_embeddings_url "https://api.openai.com/v1/embeddings"

  @doc """
  Generates a 3072-dimensional embedding vector for the given text.

  ## Parameters
  - text: String to embed
  - opts: Optional parameters
    - model: Override default model (default: text-embedding-3-large)
    - dimensions: Override dimensions (default: 3072)

  ## Returns
  - {:ok, embedding} where embedding is a list of 3072 floats
  - {:error, reason} if the API call fails

  ## Examples

      iex> Embeddings.generate("Hello world")
      {:ok, [0.123, -0.456, 0.789, ...]} # 3072 floats

      iex> Embeddings.generate("")
      {:error, "Text cannot be empty"}
  """
  def generate(text, opts \\ []) when is_binary(text) do
    if String.trim(text) == "" do
      {:error, "Text cannot be empty"}
    else
      model = Keyword.get(opts, :model, @embedding_model)
      dimensions = Keyword.get(opts, :dimensions, @embedding_dimensions)

      call_openai_embeddings(text, model, dimensions)
    end
  end

  @doc """
  Generates embeddings for multiple texts in a single API call.

  More efficient than calling generate/2 multiple times.

  ## Parameters
  - texts: List of strings to embed
  - opts: Optional parameters (same as generate/2)

  ## Returns
  - {:ok, embeddings} where embeddings is a list of embedding vectors
  - {:error, reason} if the API call fails

  ## Examples

      iex> Embeddings.generate_batch(["Hello", "World"])
      {:ok, [[0.1, 0.2, ...], [0.3, 0.4, ...]]}
  """
  def generate_batch(texts, opts \\ []) when is_list(texts) do
    # Filter out empty texts
    valid_texts = Enum.filter(texts, fn text ->
      is_binary(text) && String.trim(text) != ""
    end)

    if length(valid_texts) == 0 do
      {:error, "No valid texts to embed"}
    else
      model = Keyword.get(opts, :model, @embedding_model)
      dimensions = Keyword.get(opts, :dimensions, @embedding_dimensions)

      call_openai_embeddings_batch(valid_texts, model, dimensions)
    end
  end

  # Private functions

  defp call_openai_embeddings(text, model, dimensions) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("OPENAI_API_KEY not set, cannot generate embeddings")
      {:error, "OPENAI_API_KEY environment variable not set"}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{
        input: text,
        model: model,
        dimensions: dimensions
      })

      case HTTPoison.post(@openai_embeddings_url, body, headers, timeout: 30_000, recv_timeout: 30_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          parse_embedding_response(response_body)

        {:ok, %HTTPoison.Response{status_code: status, body: error_body}} ->
          Logger.error("OpenAI embeddings API error #{status}: #{error_body}")
          {:error, "API returned status #{status}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("HTTP error calling OpenAI embeddings: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp call_openai_embeddings_batch(texts, model, dimensions) do
    api_key = get_api_key()

    if is_nil(api_key) do
      Logger.error("OPENAI_API_KEY not set, cannot generate embeddings")
      {:error, "OPENAI_API_KEY environment variable not set"}
    else
      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{
        input: texts,
        model: model,
        dimensions: dimensions
      })

      case HTTPoison.post(@openai_embeddings_url, body, headers, timeout: 60_000, recv_timeout: 60_000) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          parse_batch_embedding_response(response_body)

        {:ok, %HTTPoison.Response{status_code: status, body: error_body}} ->
          Logger.error("OpenAI embeddings API error #{status}: #{error_body}")
          {:error, "API returned status #{status}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          Logger.error("HTTP error calling OpenAI embeddings: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp parse_embedding_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"data" => [%{"embedding" => embedding} | _]}} when is_list(embedding) ->
        {:ok, embedding}

      {:ok, response} ->
        Logger.error("Unexpected OpenAI response format: #{inspect(response)}")
        {:error, "Unexpected response format"}

      {:error, reason} ->
        Logger.error("Failed to parse OpenAI response: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp parse_batch_embedding_response(response_body) do
    case Jason.decode(response_body) do
      {:ok, %{"data" => data}} when is_list(data) ->
        # Sort by index to ensure correct order
        embeddings =
          data
          |> Enum.sort_by(fn item -> item["index"] end)
          |> Enum.map(fn item -> item["embedding"] end)

        {:ok, embeddings}

      {:ok, response} ->
        Logger.error("Unexpected OpenAI batch response format: #{inspect(response)}")
        {:error, "Unexpected response format"}

      {:error, reason} ->
        Logger.error("Failed to parse OpenAI batch response: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_api_key do
    # Use OPENAI_API_KEY environment variable
    System.get_env("OPENAI_API_KEY")
  end

  @doc """
  Calculates cosine similarity between two embedding vectors.

  Used for semantic search and finding similar content.

  ## Parameters
  - embedding1: First embedding vector
  - embedding2: Second embedding vector

  ## Returns
  - Float between -1.0 and 1.0 (1.0 = identical, -1.0 = opposite)

  ## Examples

      iex> Embeddings.cosine_similarity([1.0, 0.0], [1.0, 0.0])
      1.0

      iex> Embeddings.cosine_similarity([1.0, 0.0], [0.0, 1.0])
      0.0
  """
  def cosine_similarity(embedding1, embedding2)
      when is_list(embedding1) and is_list(embedding2) do
    if length(embedding1) != length(embedding2) do
      raise ArgumentError, "Embeddings must have the same dimensions"
    end

    # Calculate dot product
    dot_product =
      Enum.zip(embedding1, embedding2)
      |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)

    # Calculate magnitudes
    magnitude1 = :math.sqrt(Enum.reduce(embedding1, 0.0, fn x, acc -> acc + x * x end))
    magnitude2 = :math.sqrt(Enum.reduce(embedding2, 0.0, fn x, acc -> acc + x * x end))

    # Avoid division by zero
    if magnitude1 == 0.0 or magnitude2 == 0.0 do
      0.0
    else
      dot_product / (magnitude1 * magnitude2)
    end
  end
end
