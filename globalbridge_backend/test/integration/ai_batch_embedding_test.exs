defmodule GlobalbridgeBackend.Integration.AIBatchEmbeddingTest do
  use ExUnit.Case, async: false

  alias GlobalbridgeBackend.AI.EmbeddingService
  alias GlobalbridgeBackend.AI.Cache.EmbeddingCache

  @moduletag :integration
  @moduletag timeout: 120_000

  setup do
    # Clear cache before each test
    EmbeddingCache.clear()
    :ok
  end

  describe "batch embedding with real OpenAI API" do
    @tag :skip
    test "generates embeddings for small batch" do
      texts = [
        "The quick brown fox jumps over the lazy dog",
        "Machine learning is transforming technology",
        "Elixir is a functional programming language"
      ]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 3
      assert Enum.all?(embeddings, &is_list/1)
      assert Enum.all?(embeddings, &(length(&1) == 3072))

      # Verify embeddings are different
      [e1, e2, e3] = embeddings
      assert e1 != e2
      assert e2 != e3
      assert e1 != e3
    end

    @tag :skip
    test "handles duplicates correctly in batch" do
      texts = [
        "Duplicate text",
        "Unique text one",
        "Duplicate text",
        "Unique text two",
        "Duplicate text"
      ]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 5

      # Verify duplicates have same embeddings
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 2)
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 4)
      assert Enum.at(embeddings, 2) == Enum.at(embeddings, 4)
    end

    @tag :skip
    test "handles mixed cached and uncached correctly" do
      # First, cache one text
      text_to_cache = "This text will be cached"
      {:ok, cached_embedding} = EmbeddingService.generate(text_to_cache)

      # Now do a batch with mix of cached and uncached
      texts = [
        text_to_cache,
        "New text one",
        "New text two",
        text_to_cache,
        "New text three"
      ]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 5

      # Verify cached text uses cached embedding
      assert Enum.at(embeddings, 0) == cached_embedding
      assert Enum.at(embeddings, 3) == cached_embedding

      # Verify uncached texts got new embeddings
      assert Enum.at(embeddings, 1) != cached_embedding
      assert Enum.at(embeddings, 2) != cached_embedding
      assert Enum.at(embeddings, 4) != cached_embedding
    end

    @tag :skip
    test "preserves order with complex batch" do
      texts = [
        "First",
        "Second",
        "First",
        "Third",
        "Second",
        "Fourth",
        "First"
      ]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 7

      # Verify order preservation
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 2)
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 6)
      assert Enum.at(embeddings, 1) == Enum.at(embeddings, 4)
    end

    @tag :skip
    test "handles medium-sized batch efficiently" do
      # 30 texts with some duplicates
      texts =
        for i <- 1..30 do
          # Every 3rd text is a duplicate of text 1
          if rem(i, 3) == 0, do: "Repeated text", else: "Unique text #{i}"
        end

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 30

      # Verify all repeated texts have same embedding
      repeated_indices = [2, 5, 8, 11, 14, 17, 20, 23, 26, 29]
      repeated_embeddings = Enum.map(repeated_indices, &Enum.at(embeddings, &1))

      assert Enum.uniq(repeated_embeddings) |> length() == 1
    end

    @tag :skip
    test "validates embedding quality" do
      texts = [
        "Artificial intelligence",
        "Machine learning",
        "Deep learning",
        "Banana fruit"
      ]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)

      # Calculate cosine similarity between AI-related terms
      [ai_emb, ml_emb, dl_emb, banana_emb] = embeddings

      ai_ml_similarity = cosine_similarity(ai_emb, ml_emb)
      ai_dl_similarity = cosine_similarity(ai_emb, dl_emb)
      ai_banana_similarity = cosine_similarity(ai_emb, banana_emb)

      # AI-related terms should be more similar to each other than to banana
      assert ai_ml_similarity > ai_banana_similarity
      assert ai_dl_similarity > ai_banana_similarity
    end
  end

  describe "error handling with real API" do
    @tag :skip
    test "handles API rate limiting gracefully" do
      # This test would need to actually trigger rate limiting
      # Skip in normal test runs
      :ok
    end

    @tag :skip
    test "handles invalid API key" do
      # This test would need to use invalid credentials
      # Skip in normal test runs
      :ok
    end
  end

  # Helper function to calculate cosine similarity
  defp cosine_similarity(vec1, vec2) do
    dot_product = Enum.zip(vec1, vec2) |> Enum.reduce(0, fn {a, b}, acc -> acc + a * b end)

    magnitude1 = :math.sqrt(Enum.reduce(vec1, 0, fn x, acc -> acc + x * x end))
    magnitude2 = :math.sqrt(Enum.reduce(vec2, 0, fn x, acc -> acc + x * x end))

    dot_product / (magnitude1 * magnitude2)
  end
end
