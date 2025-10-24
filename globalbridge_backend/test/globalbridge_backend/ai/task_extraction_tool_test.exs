defmodule GlobalbridgeBackend.AI.Tools.TaskExtractionToolTest do
  use ExUnit.Case, async: true

  alias GlobalbridgeBackend.AI.Tools.TaskExtractionTool

  describe "extract_from_context/2" do
    test "processes context and returns extraction result structure" do
      context =
        "I need to finish the project report by Friday and schedule a meeting with the team next week."

      search_results = [%{content: context, score: 0.9, inserted_at: DateTime.utc_now()}]

      result = TaskExtractionTool.extract_from_context(context, search_results)

      assert {:ok, extraction} = result
      assert is_map(extraction)
      assert Map.has_key?(extraction, :tasks)
      assert Map.has_key?(extraction, :deadlines)
      assert Map.has_key?(extraction, :decisions)
      assert Map.has_key?(extraction, :metadata)
    end

    test "handles empty input gracefully" do
      context = ""
      search_results = []

      result = TaskExtractionTool.extract_from_context(context, search_results)

      assert {:ok, extraction} = result
      assert extraction.tasks == []
      assert extraction.deadlines == []
      assert extraction.decisions == []
    end

    test "processes decision context" do
      context = "We decided to use PostgreSQL for the database and deploy on AWS."
      search_results = [%{content: context, score: 0.9, inserted_at: DateTime.utc_now()}]

      result = TaskExtractionTool.extract_from_context(context, search_results)

      assert {:ok, extraction} = result
      assert is_list(extraction.decisions)
    end

    test "formats results correctly" do
      context = "Complete the documentation"
      search_results = [%{content: context, score: 0.9, inserted_at: DateTime.utc_now()}]

      {:ok, result} = TaskExtractionTool.extract_from_context(context, search_results)

      formatted = TaskExtractionTool.post(result)
      assert is_binary(formatted)
      assert String.length(formatted) > 0
    end
  end

  describe "pre/1" do
    test "preprocesses input text" do
      input = "  Some   messy   text   "

      result = TaskExtractionTool.pre(input)

      assert is_binary(result)
      # Should return formatted prompt containing the input
      assert String.contains?(result, "Some   messy   text")
      assert String.contains?(result, "tasks, deadlines, and decisions")
    end
  end

  describe "to_args/1" do
    test "converts result to arguments format" do
      result = "mock llm response"

      args = TaskExtractionTool.to_args(result)

      assert is_map(args)
      assert Map.has_key?(args, :function_calls)
    end
  end

  describe "to_json/1" do
    test "serializes extraction results to JSON" do
      result = %{
        tasks: [
          %{
            id: "task-1",
            description: "Test task",
            assignee: nil,
            priority: "high",
            status: "pending",
            confidence: 0.9,
            source_message_id: "msg-1",
            extracted_at: DateTime.utc_now()
          }
        ],
        deadlines: [],
        decisions: [],
        metadata: %{
          total_messages_analyzed: 10,
          extraction_timestamp: DateTime.utc_now(),
          confidence_threshold: 0.5
        }
      }

      {:ok, json} = TaskExtractionTool.to_json(result)

      assert is_binary(json)
      assert String.contains?(json, "Test task")
      assert String.contains?(json, "task-1")
    end
  end

  describe "to_structured_map/1" do
    test "converts results to structured map" do
      result = %{
        tasks: [
          %{
            id: "task-1",
            description: "Test",
            assignee: nil,
            priority: "medium",
            status: "pending",
            confidence: 0.8,
            source_message_id: "msg-1",
            extracted_at: DateTime.utc_now()
          }
        ],
        deadlines: [],
        decisions: [],
        metadata: %{
          total_messages_analyzed: 5,
          extraction_timestamp: DateTime.utc_now(),
          confidence_threshold: 0.5
        }
      }

      structured = TaskExtractionTool.to_structured_map(result)

      assert is_map(structured)
      assert structured.version == "1.0"
      assert structured.summary.task_count == 1
    end
  end
end
