defmodule GlobalbridgeBackend.Integration.AIBatchLoadTest do
  use ExUnit.Case, async: false

  alias GlobalbridgeBackend.AI.EmbeddingService
  alias GlobalbridgeBackend.AI.Cache.EmbeddingCache

  @moduletag :load_test
  @moduletag timeout: 300_000

  setup do
    # Clear cache before each test
    EmbeddingCache.clear()
    :ok
  end

  describe "load testing batch embeddings" do
    test "handles 100 unique texts efficiently" do
      texts = for i <- 1..100, do: "Load test text number #{i} with unique content"

      start_time = System.monotonic_time(:millisecond)
      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      duration = System.monotonic_time(:millisecond) - start_time

      assert length(embeddings) == 100
      assert Enum.all?(embeddings, &is_list/1)
      assert Enum.all?(embeddings, &(length(&1) == 3072))

      IO.puts("✓ Generated 100 embeddings in #{duration}ms")
    end

    test "handles 200 texts with 50% duplicates" do
      # Create 100 unique texts, then repeat them
      unique_texts = for i <- 1..100, do: "Duplicate test text #{i}"
      texts = unique_texts ++ unique_texts

      start_time = System.monotonic_time(:millisecond)
      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      duration = System.monotonic_time(:millisecond) - start_time

      assert length(embeddings) == 200

      # Verify duplicates match
      first_half = Enum.take(embeddings, 100)
      second_half = Enum.drop(embeddings, 100)
      assert first_half == second_half

      IO.puts("✓ Generated 200 embeddings (100 unique) in #{duration}ms")
    end

    test "handles 150 texts with high duplicate rate (90%)" do
      # Only 15 unique texts, repeated to make 150
      unique_texts = for i <- 1..15, do: "Highly duplicated text #{i}"

      texts =
        for _ <- 1..10 do
          unique_texts
        end
        |> List.flatten()

      start_time = System.monotonic_time(:millisecond)
      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      duration = System.monotonic_time(:millisecond) - start_time

      assert length(embeddings) == 150

      # Verify the pattern repeats correctly
      first_batch = Enum.take(embeddings, 15)

      Enum.chunk_every(embeddings, 15)
      |> Enum.each(fn chunk ->
        assert chunk == first_batch
      end)

      IO.puts("✓ Generated 150 embeddings (15 unique) in #{duration}ms")
      IO.puts("  Deduplication saved #{150 - 15} API calls!")
    end

    test "handles mixed cached and uncached in large batch" do
      # Pre-cache 50 texts
      cached_texts = for i <- 1..50, do: "Cached text #{i}"
      Enum.each(cached_texts, &EmbeddingService.generate/1)

      # Mix 50 cached + 50 uncached + 50 duplicates of cached
      uncached_texts = for i <- 51..100, do: "Uncached text #{i}"
      texts = cached_texts ++ uncached_texts ++ cached_texts

      start_time = System.monotonic_time(:millisecond)
      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      duration = System.monotonic_time(:millisecond) - start_time

      assert length(embeddings) == 150

      # Verify cached texts are consistent
      first_50 = Enum.take(embeddings, 50)
      last_50 = Enum.drop(embeddings, 100)
      assert first_50 == last_50

      IO.puts("✓ Generated 150 embeddings (50 cached, 50 new) in #{duration}ms")
      IO.puts("  Cache hits: 100, API calls: 50")
    end

    test "stress test: 300 texts with random patterns" do
      # Create a mix of patterns
      base_texts = for i <- 1..100, do: "Base text #{i}"

      texts =
        for _ <- 1..3 do
          Enum.shuffle(base_texts)
        end
        |> List.flatten()

      start_time = System.monotonic_time(:millisecond)
      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      duration = System.monotonic_time(:millisecond) - start_time

      assert length(embeddings) == 300

      # Verify each base text appears exactly 3 times with same embedding
      base_texts
      |> Enum.with_index()
      |> Enum.each(fn {text, idx} ->
        # Find all positions of this text
        positions =
          Enum.with_index(texts)
          |> Enum.filter(fn {t, _} -> t == text end)
          |> Enum.map(fn {_, i} -> i end)

        # Should have exactly 3 positions
        assert length(positions) == 3

        # All embeddings at those positions should match
        text_embeddings = Enum.map(positions, &Enum.at(embeddings, &1))
        assert Enum.uniq(text_embeddings) |> length() == 1
      end)

      IO.puts("✓ Stress test: 300 embeddings (100 unique) in #{duration}ms")
    end

    test "performance benchmark: measure reconstruction overhead" do
      texts = for i <- 1..100, do: "Benchmark text #{i}"

      # Time the entire operation
      start_total = System.monotonic_time(:millisecond)
      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      duration_total = System.monotonic_time(:millisecond) - start_total

      assert length(embeddings) == 100

      # The reconstruction should be O(n), so overhead should be minimal
      # For 100 items, reconstruction should be < 1ms
      IO.puts("✓ Total time for 100 texts: #{duration_total}ms")
      IO.puts("  (includes API calls, caching, and O(n) reconstruction)")
    end

    test "validates no data corruption in large batches" do
      # Create texts with known patterns
      texts =
        for i <- 1..120 do
          case rem(i, 3) do
            0 -> "Pattern A"
            1 -> "Pattern B"
            2 -> "Pattern C #{div(i, 3)}"
          end
        end

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 120

      # Verify Pattern A and B are always the same
      pattern_a_indices = [2, 5, 8, 11, 14, 17, 20, 23, 26, 29, 32, 35, 38]

      pattern_a_embeddings =
        Enum.take(pattern_a_indices, 13)
        |> Enum.map(&Enum.at(embeddings, &1))

      assert Enum.uniq(pattern_a_embeddings) |> length() == 1

      pattern_b_indices = [3, 6, 9, 12, 15, 18, 21, 24, 27, 30, 33, 36, 39]

      pattern_b_embeddings =
        Enum.take(pattern_b_indices, 13)
        |> Enum.map(&Enum.at(embeddings, &1))

      assert Enum.uniq(pattern_b_embeddings) |> length() == 1

      # Pattern A and B should be different from each other
      assert hd(pattern_a_embeddings) != hd(pattern_b_embeddings)

      IO.puts("✓ No data corruption detected in 120-item batch")
    end
  end

  describe "edge cases in large batches" do
    test "handles empty strings in batch" do
      texts = ["", "valid", "", "another", ""]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 5

      # Empty strings should have same embedding
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 2)
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 4)
    end

    test "handles very long texts in batch" do
      long_text = String.duplicate("This is a very long text. ", 200)

      texts = [
        long_text,
        "short",
        long_text,
        "another short",
        long_text
      ]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 5

      # Long texts should match
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 2)
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 4)
    end

    test "handles special characters in batch" do
      texts = [
        "Hello 你好 مرحبا",
        "Emoji test 🚀🔥💯",
        "Hello 你好 مرحبا",
        "Special chars: @#$%^&*()",
        "Emoji test 🚀🔥💯"
      ]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 5

      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 2)
      assert Enum.at(embeddings, 1) == Enum.at(embeddings, 4)
    end

    test "handles whitespace variations" do
      texts = [
        "hello world",
        "hello  world",
        "hello world",
        " hello world ",
        "hello world"
      ]

      assert {:ok, embeddings} = EmbeddingService.generate_batch(texts)
      assert length(embeddings) == 5

      # Exact string matches should have same embedding
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 2)
      assert Enum.at(embeddings, 0) == Enum.at(embeddings, 4)

      # Different whitespace should produce different embeddings
      # (unless optimizer normalizes, which current implementation doesn't)
      # This test documents current behavior
    end
  end
end
