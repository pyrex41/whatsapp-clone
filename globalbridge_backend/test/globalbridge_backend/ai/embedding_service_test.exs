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
      assert Enum.all?(embeddings, &(length(&1) == 3072))
    end

    test "handles mixed cached and uncached texts" do
      # Pre-cache one text
      {:ok, cached_embedding} = EmbeddingService.generate("cached")

      texts = ["cached", "uncached1", "uncached2"]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 3
      # First embedding should match the cached one
      assert hd(embeddings) == cached_embedding
    end

    test "handles all cached texts" do
      # Pre-cache all texts
      texts = ["text1", "text2", "text3"]
      Enum.each(texts, &EmbeddingService.generate/1)

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 3
      assert Enum.all?(embeddings, &is_list/1)
    end

    test "handles all uncached texts" do
      # Clear cache
      EmbeddingCache.clear()

      texts = ["new1", "new2", "new3"]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 3
      assert Enum.all?(embeddings, &is_list/1)
    end

    test "handles duplicate texts correctly" do
      texts = ["hello", "world", "hello", "test", "world"]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 5

      # Duplicates should have the same embedding
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 2)
      assert Enum.at(embeddings, 1) == Enum.at(embeddings, 4)
    end

    test "handles duplicate texts with some cached" do
      # Pre-cache one text
      {:ok, cached_embedding} = EmbeddingService.generate("cached")

      texts = ["cached", "new", "cached", "another", "new"]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 5

      # All "cached" instances should match
      assert Enum.at(embeddings, 0) == cached_embedding
      assert Enum.at(embeddings, 2) == cached_embedding

      # All "new" instances should match each other
      assert Enum.at(embeddings, 1) == Enum.at(embeddings, 4)
    end

    test "handles empty batch" do
      assert {:ok, []} = EmbeddingService.generate_batch([])
    end

    test "handles single text batch" do
      assert {:ok, [embedding]} = EmbeddingService.generate_batch(["single"])
      assert is_list(embedding)
      assert length(embedding) == 3072
    end

    test "preserves order of results" do
      texts = ["first", "second", "third"]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)

      # Generate individually to compare
      {:ok, first_individual} = EmbeddingService.generate("first")
      {:ok, second_individual} = EmbeddingService.generate("second")
      {:ok, third_individual} = EmbeddingService.generate("third")

      assert Enum.at(embeddings, 0) == first_individual
      assert Enum.at(embeddings, 1) == second_individual
      assert Enum.at(embeddings, 2) == third_individual
    end

    test "handles large batches efficiently" do
      # Generate 50 unique texts
      texts = for i <- 1..50, do: "text_#{i}"

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 50
      assert Enum.all?(embeddings, &is_list/1)
    end

    test "handles large batches with many duplicates" do
      # 100 texts but only 10 unique
      texts =
        for _ <- 1..10 do
          for i <- 1..10, do: "unique_#{i}"
        end
        |> List.flatten()

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 100

      # Verify duplicates have same embeddings
      first_batch = Enum.take(embeddings, 10)
      second_batch = Enum.slice(embeddings, 10, 10)
      assert first_batch == second_batch
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
