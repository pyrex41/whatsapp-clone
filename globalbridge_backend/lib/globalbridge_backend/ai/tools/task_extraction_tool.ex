defmodule GlobalbridgeBackend.AI.Tools.TaskExtractionTool do
  @moduledoc """
  Tool for extracting tasks, deadlines, and decisions from conversation context.

  This tool uses function calling to analyze conversation threads and extract
  structured information including:
  - Tasks with descriptions and assignees
  - Deadlines and due dates
  - Decisions and agreements
  - Action items and commitments

  Each extracted item includes confidence scores and metadata.
  """

  @behaviour Agens.Tool

  alias GlobalbridgeBackend.AI.RAGRetriever

  @type task_item :: %{
          id: String.t(),
          description: String.t(),
          assignee: String.t() | nil,
          priority: String.t(),
          status: String.t(),
          confidence: float(),
          source_message_id: String.t(),
          extracted_at: DateTime.t()
        }

  @type deadline_item :: %{
          id: String.t(),
          description: String.t(),
          due_date: String.t() | nil,
          related_task_id: String.t() | nil,
          confidence: float(),
          source_message_id: String.t(),
          extracted_at: DateTime.t()
        }

  @type decision_item :: %{
          id: String.t(),
          description: String.t(),
          outcome: String.t(),
          participants: [String.t()],
          confidence: float(),
          source_message_id: String.t(),
          extracted_at: DateTime.t()
        }

  @type extraction_result :: %{
          tasks: [task_item()],
          deadlines: [deadline_item()],
          decisions: [decision_item()],
          metadata: %{
            total_messages_analyzed: integer(),
            extraction_timestamp: DateTime.t(),
            confidence_threshold: float()
          }
        }

  @doc """
  Performs RAG-based task extraction from a thread.

  Uses semantic search to find relevant messages, then extracts tasks, deadlines, and decisions.
  """
  @spec extract_from_thread(String.t(), String.t(), keyword()) ::
          {:ok, extraction_result()} | {:error, String.t()}
  def extract_from_thread(
        thread_id,
        query \\ "tasks, deadlines, decisions, commitments",
        opts \\ []
      ) do
    limit = Keyword.get(opts, :limit, 20)
    recency_weight = Keyword.get(opts, :recency_weight, 0.3)

    # Use RAG to retrieve relevant messages
    case RAGRetriever.search_with_recency_bias(thread_id, query,
           limit: limit,
           recency_weight: recency_weight
         ) do
      {:ok, search_results} ->
        if Enum.empty?(search_results) do
          {:ok, empty_extraction_result()}
        else
          # Build context from retrieved messages
          context = RAGRetriever.build_context(search_results, max_length: 8000)

          # Extract tasks from the context
          extract_from_context(context, search_results)
        end

      {:error, reason} ->
        {:error, "RAG retrieval failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Extracts tasks from conversation context using RAG retrieval results.
  """
  @spec extract_from_context(String.t(), [map()]) :: {:ok, extraction_result()}
  def extract_from_context(context, _search_results) do
    # Use the tool's extraction pipeline
    _preprocessed = pre(context)

    # In a real implementation, this would call an LLM with function calling
    # For now, we'll simulate the extraction process
    # TODO: Integrate with actual LLM service for function calling

    # Simulate function calls for demonstration
    simulated_result = simulate_extraction(context)

    case to_args(simulated_result) do
      args when is_list(args) ->
        result = execute(args)
        {:ok, result}

      _ ->
        {:ok, empty_extraction_result()}
    end
  end

  @doc """
  Serializes extraction results to JSON format.

  Returns a standardized JSON structure for API responses or storage.
  """
  @spec to_json(extraction_result()) :: {:ok, String.t()} | {:error, String.t()}
  def to_json(%{tasks: tasks, deadlines: deadlines, decisions: decisions, metadata: metadata}) do
    json_data = %{
      "version" => "1.0",
      "thread_id" => metadata[:thread_id] || "unknown",
      "extraction_timestamp" => DateTime.to_iso8601(metadata.extraction_timestamp),
      "total_messages_analyzed" => metadata.total_messages_analyzed,
      "confidence_threshold" => metadata.confidence_threshold,
      "tasks" => Enum.map(tasks, &serialize_task/1),
      "deadlines" => Enum.map(deadlines, &serialize_deadline/1),
      "decisions" => Enum.map(decisions, &serialize_decision/1),
      "summary" => %{
        "task_count" => length(tasks),
        "deadline_count" => length(deadlines),
        "decision_count" => length(decisions),
        "high_priority_tasks" => Enum.count(tasks, &(&1.priority == "high")),
        "overdue_deadlines" => Enum.count(deadlines, &deadline_overdue?/1)
      }
    }

    case Jason.encode(json_data) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, "JSON encoding failed: #{inspect(reason)}"}
    end
  end

  @doc """
  Serializes extraction results to a structured map format.

  Returns a standardized map structure for internal processing.
  """
  @spec to_structured_map(extraction_result()) :: map()
  def to_structured_map(%{
        tasks: tasks,
        deadlines: deadlines,
        decisions: decisions,
        metadata: metadata
      }) do
    %{
      version: "1.0",
      thread_id: metadata[:thread_id] || "unknown",
      extraction_timestamp: metadata.extraction_timestamp,
      total_messages_analyzed: metadata.total_messages_analyzed,
      confidence_threshold: metadata.confidence_threshold,
      tasks: Enum.map(tasks, &serialize_task/1),
      deadlines: Enum.map(deadlines, &serialize_deadline/1),
      decisions: Enum.map(decisions, &serialize_decision/1),
      summary: %{
        task_count: length(tasks),
        deadline_count: length(deadlines),
        decision_count: length(decisions),
        high_priority_tasks: Enum.count(tasks, &(&1.priority == "high")),
        overdue_deadlines: Enum.count(deadlines, &deadline_overdue?/1)
      }
    }
  end

  @doc """
  Pre-process the input context for task extraction analysis.
  """
  @impl true
  def pre(input) do
    """
    Analyze this conversation context for tasks, deadlines, and decisions:

    #{input}

    Focus on:
    - Explicit and implicit tasks/action items
    - Deadlines, due dates, and time commitments
    - Decisions, agreements, and resolutions
    - Assignments and responsibilities

    Consider:
    - Direct statements ("I will...", "We need to...")
    - Questions that imply tasks ("Who will handle...?")
    - Commitments and promises
    - Time-sensitive information
    - Changes in plans or decisions
    """
  end

  @doc """
  Instructions for the language model on how to use function calling for task extraction.
  """
  @impl true
  def instructions do
    """
    You are a task extraction specialist. Your role is to analyze conversation threads
    and extract structured information about tasks, deadlines, and decisions.

    Use the following functions to extract information:

    1. extract_task(description, assignee, priority, status, confidence, message_id)
       - description: Clear description of the task
       - assignee: Person responsible (if mentioned)
       - priority: "high", "medium", or "low"
       - status: "pending", "in_progress", "completed", or "cancelled"
       - confidence: 0.0-1.0 based on clarity
       - message_id: Source message identifier

    2. extract_deadline(description, due_date, related_task, confidence, message_id)
       - description: What the deadline is for
       - due_date: Date/time in ISO format (if extractable)
       - related_task: Task ID this deadline relates to
       - confidence: 0.0-1.0 based on clarity
       - message_id: Source message identifier

    3. extract_decision(description, outcome, participants, confidence, message_id)
       - description: What decision was made
       - outcome: The result or agreement
       - participants: People involved in the decision
       - confidence: 0.0-1.0 based on clarity
       - message_id: Source message identifier

    Rules:
    - Only extract information that is clearly stated or strongly implied
    - Assign confidence scores based on explicitness (1.0 = very clear, 0.3 = somewhat implied)
    - Generate unique IDs for each extracted item
    - Only call functions when you find actual tasks, deadlines, or decisions
    - If no items are found, do not call any functions
    """
  end

  @doc """
  Parse the LM result into function call arguments.
  """
  @impl true
  def to_args(result) do
    # Parse function calls from the result
    # This would handle the structured function call responses
    # For now, return a basic structure that can be extended
    %{
      function_calls: parse_function_calls(result)
    }
  end

  @doc """
  Execute the task extraction analysis.
  """
  @impl true
  def execute(args) do
    function_calls = Keyword.get(args, :function_calls, [])

    # Process the function calls and build structured results
    results = process_function_calls(function_calls)

    # Add metadata
    %{
      tasks: results.tasks,
      deadlines: results.deadlines,
      decisions: results.decisions,
      metadata: %{
        # Would be calculated from input
        total_messages_analyzed: 1,
        extraction_timestamp: DateTime.utc_now(),
        confidence_threshold: 0.5
      }
    }
  end

  @doc """
  Post-process the execution result into a readable format.
  """
  @impl true
  def post(result) do
    case result do
      %{tasks: tasks, deadlines: deadlines, decisions: decisions, metadata: metadata} ->
        """
        Task Extraction Complete:

        Tasks Found: #{length(tasks)}
        Deadlines Found: #{length(deadlines)}
        Decisions Found: #{length(decisions)}

        #{format_tasks(tasks)}
        #{format_deadlines(deadlines)}
        #{format_decisions(decisions)}

        Extraction completed at: #{DateTime.to_string(metadata.extraction_timestamp)}
        """

      {:error, reason} ->
        "Task extraction failed: #{inspect(reason)}"

      _ ->
        "Task extraction returned unexpected result: #{inspect(result)}"
    end
  end

  # Private functions

  defp parse_function_calls(result) do
    # Parse function calls from the LLM response
    # Supports OpenAI-style tool_calls format
    case Jason.decode(result) do
      {:ok, %{"tool_calls" => tool_calls}} when is_list(tool_calls) ->
        Enum.map(tool_calls, &parse_tool_call/1)

      {:ok, %{"function_call" => function_call}} ->
        # Legacy OpenAI format support
        [parse_legacy_function_call(function_call)]

      _ ->
        # Try to parse as direct JSON function calls
        parse_direct_function_calls(result)
    end
  rescue
    _ -> []
  end

  defp process_function_calls(function_calls) do
    # Process function calls and build structured results
    # Convert the parsed function calls into our structured format
    Enum.reduce(function_calls, %{tasks: [], deadlines: [], decisions: []}, fn call, acc ->
      case call do
        {:extract_task, args} ->
          task = build_task_item(args)
          %{acc | tasks: [task | acc.tasks]}

        {:extract_deadline, args} ->
          deadline = build_deadline_item(args)
          %{acc | deadlines: [deadline | acc.deadlines]}

        {:extract_decision, args} ->
          decision = build_decision_item(args)
          %{acc | decisions: [decision | acc.decisions]}

        _ ->
          acc
      end
    end)
  end

  defp format_tasks(tasks) do
    if Enum.empty?(tasks) do
      ""
    else
      """
      Tasks:
      #{Enum.map_join(tasks, "\n", &format_task/1)}
      """
    end
  end

  defp format_task(task) do
    assignee = if task.assignee, do: " (#{task.assignee})", else: ""

    "• #{task.description}#{assignee} [#{task.priority}] - #{task.status} (#{Float.round(task.confidence * 100, 1)}% confidence)"
  end

  defp format_deadlines(deadlines) do
    if Enum.empty?(deadlines) do
      ""
    else
      """
      Deadlines:
      #{Enum.map_join(deadlines, "\n", &format_deadline/1)}
      """
    end
  end

  defp format_deadline(deadline) do
    due_date = if deadline.due_date, do: " - Due: #{deadline.due_date}", else: ""

    "• #{deadline.description}#{due_date} (#{Float.round(deadline.confidence * 100, 1)}% confidence)"
  end

  defp format_decisions(decisions) do
    if Enum.empty?(decisions) do
      ""
    else
      """
      Decisions:
      #{Enum.map_join(decisions, "\n", &format_decision/1)}
      """
    end
  end

  defp format_decision(decision) do
    participants =
      if length(decision.participants) > 0 do
        " (Participants: #{Enum.join(decision.participants, ", ")})"
      else
        ""
      end

    "• #{decision.description} - #{decision.outcome}#{participants} (#{Float.round(decision.confidence * 100, 1)}% confidence)"
  end

  # Function call parsing helpers

  defp parse_tool_call(%{
         "type" => "function",
         "function" => %{"name" => name, "arguments" => args}
       }) do
    case Jason.decode(args) do
      {:ok, parsed_args} -> {String.to_atom(name), parsed_args}
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp parse_tool_call(_), do: nil

  defp parse_legacy_function_call(%{"name" => name, "arguments" => args}) do
    case Jason.decode(args) do
      {:ok, parsed_args} -> {String.to_atom(name), parsed_args}
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp parse_direct_function_calls(result) do
    # Try to parse as a list of function call objects
    case Jason.decode(result) do
      {:ok, calls} when is_list(calls) ->
        Enum.map(calls, fn
          %{"function" => name, "args" => args} -> {String.to_atom(name), args}
          _ -> nil
        end)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  rescue
    _ -> []
  end

  # Item builders

  defp build_task_item(args) do
    %{
      id: generate_id(),
      description: Map.get(args, "description", ""),
      assignee: Map.get(args, "assignee"),
      priority: Map.get(args, "priority", "medium"),
      status: Map.get(args, "status", "pending"),
      confidence: Map.get(args, "confidence", 0.5),
      source_message_id: Map.get(args, "message_id", ""),
      extracted_at: DateTime.utc_now()
    }
  end

  defp build_deadline_item(args) do
    %{
      id: generate_id(),
      description: Map.get(args, "description", ""),
      due_date: Map.get(args, "due_date"),
      related_task_id: Map.get(args, "related_task"),
      confidence: Map.get(args, "confidence", 0.5),
      source_message_id: Map.get(args, "message_id", ""),
      extracted_at: DateTime.utc_now()
    }
  end

  defp build_decision_item(args) do
    %{
      id: generate_id(),
      description: Map.get(args, "description", ""),
      outcome: Map.get(args, "outcome", ""),
      participants: Map.get(args, "participants", []),
      confidence: Map.get(args, "confidence", 0.5),
      source_message_id: Map.get(args, "message_id", ""),
      extracted_at: DateTime.utc_now()
    }
  end

  defp generate_id do
    # Generate a unique ID for extracted items
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # RAG integration helpers

  defp empty_extraction_result do
    %{
      tasks: [],
      deadlines: [],
      decisions: [],
      metadata: %{
        total_messages_analyzed: 0,
        extraction_timestamp: DateTime.utc_now(),
        confidence_threshold: 0.5
      }
    }
  end

  # TODO: Replace with actual LLM function calling
  defp simulate_extraction(_context) do
    # This is a placeholder for actual LLM function calling
    # In production, this would call an LLM service with function calling enabled

    # For now, return empty result to indicate no function calls
    # The real implementation would parse LLM responses with tool_calls
    "{}"
  end

  # Serialization helpers

  defp serialize_task(task) do
    %{
      "id" => task.id,
      "description" => task.description,
      "assignee" => task.assignee,
      "priority" => task.priority,
      "status" => task.status,
      "confidence" => task.confidence,
      "source_message_id" => task.source_message_id,
      "extracted_at" => DateTime.to_iso8601(task.extracted_at)
    }
  end

  defp serialize_deadline(deadline) do
    %{
      "id" => deadline.id,
      "description" => deadline.description,
      "due_date" => deadline.due_date,
      "related_task_id" => deadline.related_task_id,
      "confidence" => deadline.confidence,
      "source_message_id" => deadline.source_message_id,
      "extracted_at" => DateTime.to_iso8601(deadline.extracted_at),
      "is_overdue" => deadline_overdue?(deadline)
    }
  end

  defp serialize_decision(decision) do
    %{
      "id" => decision.id,
      "description" => decision.description,
      "outcome" => decision.outcome,
      "participants" => decision.participants,
      "confidence" => decision.confidence,
      "source_message_id" => decision.source_message_id,
      "extracted_at" => DateTime.to_iso8601(decision.extracted_at)
    }
  end

  defp deadline_overdue?(deadline) do
    case deadline.due_date do
      nil ->
        false

      due_date ->
        case DateTime.from_iso8601(due_date) do
          {:ok, datetime, _offset} -> DateTime.compare(datetime, DateTime.utc_now()) == :lt
          _ -> false
        end
    end
  end
end
