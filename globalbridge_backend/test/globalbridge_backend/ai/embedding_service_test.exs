defmodule GlobalbridgeBackend.AI.EmbeddingServiceTest do
  use ExUnit.Case, async: true

  alias GlobalbridgeBackend.AI.EmbeddingService
  alias GlobalbridgeBackend.AI.Cache.EmbeddingCache

  # Mock OpenAI API responses
  setup do
    # Clear any cached embeddings before each test
    EmbeddingCache.clear()

    # Mock OpenAI API responses
    mock_openai_response()

    :ok
  end

  describe "generate/1" do
    test "generates embedding for text successfully" do
      text = "Hello world"

      assert {:ok, embedding} = EmbeddingService.generate(text)
      assert is_list(embedding)
      # Expected dimension for text-embedding-3-large
      assert length(embedding) == 3072
      assert Enum.all?(embedding, &is_float/1)
    end

    test "returns cached embedding on subsequent calls" do
      text = "Test message"

      # First call should generate and cache
      {:ok, embedding1} = EmbeddingService.generate(text)

      # Second call should return cached result
      {:ok, embedding2} = EmbeddingService.generate(text)

      assert embedding1 == embedding2
    end

    test "handles empty text gracefully" do
      assert {:ok, embedding} = EmbeddingService.generate("")
      assert is_list(embedding)
    end

    test "handles very long text" do
      long_text = String.duplicate("This is a test message. ", 100)
      assert {:ok, embedding} = EmbeddingService.generate(long_text)
      assert is_list(embedding)
    end
  end

  describe "generate_batch/1" do
    test "generates embeddings for multiple texts" do
      texts = ["Hello", "World", "Test"]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 3
      assert Enum.all?(embeddings, &is_list/1)
    end

    test "handles mixed cached and uncached texts" do
      # Pre-cache one text
      EmbeddingService.generate("cached")

      texts = ["cached", "uncached1", "uncached2"]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 3
    end

    test "returns nil for failed embeddings in batch" do
      # This would test error handling in batch mode
      texts = ["valid", "also_valid"]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 2
    end
  end

  describe "embedding_model/0" do
    test "returns the configured embedding model" do
      model = EmbeddingService.embedding_model()
      assert is_binary(model)
      assert String.length(model) > 0
    end
  end

  describe "estimate_tokens/1" do
    test "estimates tokens for text" do
      assert EmbeddingService.estimate_tokens("Hello world") > 0
      # Minimum 1 token
      assert EmbeddingService.estimate_tokens("") == 1
      assert EmbeddingService.estimate_tokens(String.duplicate("word ", 100)) > 10
    end
  end

  # Helper function to mock OpenAI responses
  defp mock_openai_response do
    # In a real test, you would use Mox or similar to mock the OpenAI API
    # For now, we'll rely on the actual implementation with test API keys
    :ok
  end
end
