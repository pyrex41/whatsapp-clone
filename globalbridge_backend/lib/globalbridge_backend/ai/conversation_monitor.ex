defmodule GlobalbridgeBackend.AI.ConversationMonitor do
  @moduledoc """
  Event-driven GenServer that monitors conversations in real-time.

  This module:
  - Subscribes to Phoenix PubSub for new messages in threads
  - Maintains sliding window of recent messages per thread
  - Triggers AI analysis when detecting confusion or complexity
  - Broadcasts suggestions to ThreadChannel subscribers
  - Coordinates with multi-step agents for comprehensive analysis

  ## Event Flow
  1. ThreadChannel broadcasts `{:new_message, message}` to `"thread:<thread_id>"`
  2. ConversationMonitor receives event and adds to sliding window
  3. Triggers confusion/complexity detection (fast <8s)
  4. If issues detected, broadcasts suggestions back to thread subscribers
  5. Tracks suggestion delivery for learning loop

  ## Performance Targets
  - Detection: <8s per message
  - Suggestion generation: <8s
  - Total response: <15s from message to suggestion
  """

  use GenServer
  require Logger

  alias Phoenix.PubSub
  alias GlobalbridgeBackend.AI.{Cache, VectorStore}
  alias GlobalbridgeBackend.Repos.ThreadRepo

  @pubsub GlobalbridgeBackend.PubSub

  # Configuration
  @message_window_size 20
  @confusion_check_interval 2_000
  @complexity_threshold 0.7
  @confusion_threshold 0.6

  # State structure:
  # %{
  #   thread_monitors: %{
  #     thread_id => %{
  #       messages: [%{id, content, user_id, timestamp, analyzed}],
  #       last_check: DateTime,
  #       pending_analysis: boolean
  #     }
  #   }
  # }

  ## Client API

  @doc """
  Starts the ConversationMonitor GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Subscribes to monitor a specific thread.

  This should be called when a user joins a thread channel.
  """
  def monitor_thread(thread_id) do
    GenServer.cast(__MODULE__, {:monitor_thread, thread_id})
  end

  @doc """
  Unsubscribes from monitoring a thread.

  Called when all users leave a thread or thread is closed.
  """
  def unmonitor_thread(thread_id) do
    GenServer.cast(__MODULE__, {:unmonitor_thread, thread_id})
  end

  @doc """
  Handles a new message event for analysis.

  This is called by the PubSub subscription when messages arrive.
  """
  def handle_new_message(thread_id, message) do
    GenServer.cast(__MODULE__, {:new_message, thread_id, message})
  end

  @doc """
  Forces immediate analysis of a thread's recent messages.

  Useful for testing or manual triggering.
  """
  def analyze_now(thread_id) do
    GenServer.cast(__MODULE__, {:analyze_now, thread_id})
  end

  @doc """
  Gets the current state of a monitored thread.

  Returns recent messages and analysis status.
  """
  def get_thread_state(thread_id) do
    GenServer.call(__MODULE__, {:get_thread_state, thread_id})
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    Logger.info("ConversationMonitor started")

    # Schedule periodic cleanup of old thread data
    schedule_cleanup()

    {:ok, %{thread_monitors: %{}}}
  end

  @impl true
  def handle_cast({:monitor_thread, thread_id}, state) do
    # Subscribe to thread's PubSub topic
    topic = "thread:#{thread_id}"
    :ok = PubSub.subscribe(@pubsub, topic)

    Logger.debug("Monitoring thread: #{thread_id}")

    # Initialize thread state if not already present
    thread_monitors =
      Map.put_new(state.thread_monitors, thread_id, %{
        messages: [],
        last_check: DateTime.utc_now(),
        pending_analysis: false
      })

    {:noreply, %{state | thread_monitors: thread_monitors}}
  end

  @impl true
  def handle_cast({:unmonitor_thread, thread_id}, state) do
    # Unsubscribe from PubSub topic
    topic = "thread:#{thread_id}"
    :ok = PubSub.unsubscribe(@pubsub, topic)

    Logger.debug("Stopped monitoring thread: #{thread_id}")

    # Remove thread from state
    thread_monitors = Map.delete(state.thread_monitors, thread_id)

    {:noreply, %{state | thread_monitors: thread_monitors}}
  end

  @impl true
  def handle_cast({:new_message, thread_id, message}, state) do
    # Add message to sliding window
    thread_state = Map.get(state.thread_monitors, thread_id)

    if thread_state do
      updated_thread_state = add_message_to_window(thread_state, message)

      # Schedule analysis if not already pending
      if not updated_thread_state.pending_analysis do
        Process.send_after(self(), {:check_thread, thread_id}, @confusion_check_interval)
        updated_thread_state = %{updated_thread_state | pending_analysis: true}
      end

      thread_monitors = Map.put(state.thread_monitors, thread_id, updated_thread_state)
      {:noreply, %{state | thread_monitors: thread_monitors}}
    else
      # Thread not monitored, ignore
      Logger.debug("Received message for unmonitored thread: #{thread_id}")
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:analyze_now, thread_id}, state) do
    send(self(), {:check_thread, thread_id})
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_thread_state, thread_id}, _from, state) do
    thread_state = Map.get(state.thread_monitors, thread_id, %{messages: [], last_check: nil})
    {:reply, thread_state, state}
  end

  @impl true
  def handle_info({:check_thread, thread_id}, state) do
    thread_state = Map.get(state.thread_monitors, thread_id)

    if thread_state do
      # Get unanalyzed messages
      unanalyzed_messages =
        Enum.filter(thread_state.messages, fn msg -> not Map.get(msg, :analyzed, false) end)

      if length(unanalyzed_messages) > 0 do
        # Trigger async analysis
        Task.Supervisor.async_nolink(GlobalbridgeBackend.TaskSupervisor, fn ->
          analyze_messages(thread_id, unanalyzed_messages, thread_state.messages)
        end)
      end

      # Update state
      updated_thread_state = %{
        thread_state
        | last_check: DateTime.utc_now(),
          pending_analysis: false
      }

      thread_monitors = Map.put(state.thread_monitors, thread_id, updated_thread_state)
      {:noreply, %{state | thread_monitors: thread_monitors}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({ref, result}, state) when is_reference(ref) do
    # Handle async task completion
    case result do
      {:suggestions, thread_id, suggestions} ->
        # Broadcast suggestions to thread subscribers
        broadcast_suggestions(thread_id, suggestions)

      {:error, thread_id, reason} ->
        Logger.error("Analysis failed for thread #{thread_id}: #{inspect(reason)}")

      _ ->
        :ok
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Task completed or crashed, ignore
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_old_threads, state) do
    # Remove threads that haven't had activity in 1 hour
    cutoff = DateTime.add(DateTime.utc_now(), -3600, :second)

    thread_monitors =
      Enum.reject(state.thread_monitors, fn {_id, thread_state} ->
        DateTime.compare(thread_state.last_check, cutoff) == :lt
      end)
      |> Enum.into(%{})

    schedule_cleanup()
    {:noreply, %{state | thread_monitors: thread_monitors}}
  end

  ## Private Functions

  defp add_message_to_window(thread_state, message) do
    # Add new message to window
    new_message = %{
      id: message.id,
      content: message.content,
      user_id: message.sender_id,  # Message schema uses sender_id, not user_id
      timestamp: message.inserted_at || DateTime.utc_now(),
      analyzed: false
    }

    messages = [new_message | thread_state.messages]

    # Keep only last N messages (sliding window)
    messages = Enum.take(messages, @message_window_size)

    %{thread_state | messages: messages}
  end

  defp analyze_messages(thread_id, unanalyzed_messages, all_messages) do
    start_time = System.monotonic_time(:millisecond)

    try do
      # Detect confusion in recent messages
      confusion_detected = detect_confusion(unanalyzed_messages, all_messages)

      # Detect complexity in recent messages
      complexity_detected = detect_complexity(unanalyzed_messages)

      suggestions = []

      # Generate confusion clarification if needed
      suggestions =
        if confusion_detected do
          case generate_confusion_suggestions(thread_id, unanalyzed_messages, all_messages) do
            {:ok, confusion_suggestions} -> suggestions ++ confusion_suggestions
            {:error, _} -> suggestions
          end
        else
          suggestions
        end

      # Generate complexity simplification if needed
      suggestions =
        if complexity_detected do
          case generate_complexity_suggestions(thread_id, unanalyzed_messages) do
            {:ok, complexity_suggestions} -> suggestions ++ complexity_suggestions
            {:error, _} -> suggestions
          end
        else
          suggestions
        end

      elapsed = System.monotonic_time(:millisecond) - start_time
      Logger.info("Analysis completed in #{elapsed}ms for thread #{thread_id}")

      if length(suggestions) > 0 do
        {:suggestions, thread_id, suggestions}
      else
        :ok
      end
    rescue
      e ->
        Logger.error("Analysis error: #{inspect(e)}")
        {:error, thread_id, e}
    end
  end

  defp detect_confusion(unanalyzed_messages, _all_messages) do
    # Confusion indicators:
    # - Question marks in rapid succession
    # - Repeated questions about same topic
    # - Short messages with uncertainty markers ("idk", "not sure", "confused")
    # - Back-and-forth without resolution

    question_count =
      Enum.count(unanalyzed_messages, fn msg -> String.contains?(msg.content, "?") end)

    uncertainty_markers = [
      "idk",
      "i don't know",
      "not sure",
      "confused",
      "what do you mean",
      "huh",
      "??",
      "don't understand"
    ]

    uncertainty_count =
      Enum.count(unanalyzed_messages, fn msg ->
        content_lower = String.downcase(msg.content)
        Enum.any?(uncertainty_markers, fn marker -> String.contains?(content_lower, marker) end)
      end)

    # Threshold: 2+ questions or 1+ uncertainty marker in recent messages
    question_count >= 2 or uncertainty_count >= 1
  end

  defp detect_complexity(unanalyzed_messages) do
    # Complexity indicators:
    # - Very long messages (>200 chars)
    # - Technical jargon or multiple concepts
    # - Multiple sentences with complex structure

    long_message_count =
      Enum.count(unanalyzed_messages, fn msg -> String.length(msg.content) > 200 end)

    # Average word count
    avg_word_count =
      if length(unanalyzed_messages) > 0 do
        total_words =
          Enum.reduce(unanalyzed_messages, 0, fn msg, acc ->
            acc + length(String.split(msg.content))
          end)

        total_words / length(unanalyzed_messages)
      else
        0
      end

    # Threshold: 1+ long message or average >30 words
    long_message_count >= 1 or avg_word_count > 30
  end

  defp generate_confusion_suggestions(_thread_id, unanalyzed_messages, all_messages) do
    # Use LLM to generate helpful clarification suggestions
    Logger.debug("🚨 Generating confusion clarification suggestions with LLM")

    last_message = List.first(unanalyzed_messages)
    recent_context = Enum.take(all_messages, -5)
      |> Enum.map(fn msg -> "- #{msg.content}" end)
      |> Enum.join("\n")

    prompt = """
    The user seems confused in this conversation. Generate 2 helpful clarifying questions or responses.

    Recent conversation:
    #{recent_context}

    Last message (confused): "#{last_message.content}"

    Generate 2 brief, empathetic responses that help clarify the confusion. Format as:
    1. [first suggestion]
    2. [second suggestion]

    Keep each under 60 characters.
    """

    model = System.get_env("TRANSLATION_MODEL") || "llama-3.1-8b-instant"

    case GlobalbridgeBackend.AI.OpenAIServing.generate_completion(prompt, model) do
      {:ok, ai_response} ->
        suggestions = parse_numbered_suggestions(ai_response, "confusion_clarification", last_message.id)
        {:ok, suggestions}

      {:error, _reason} ->
        # Fallback to template
        {:ok, [
          %{
            type: "confusion_clarification",
            content: "Could you clarify what you mean?",
            confidence: 0.8,
            position: 1,
            context: %{trigger: "confusion_detected", message_id: last_message.id, ai_generated: false}
          }
        ]}
    end
  end

  defp generate_complexity_suggestions(_thread_id, unanalyzed_messages) do
    # Use LLM to generate simplification suggestions
    Logger.debug("🔧 Generating complexity simplification suggestions with LLM")

    last_message = List.first(unanalyzed_messages)

    prompt = """
    The user just sent a complex message. Generate 2 brief responses that acknowledge understanding or offer to simplify.

    Complex message: "#{last_message.content}"

    Generate 2 helpful responses. Format as:
    1. [first suggestion]
    2. [second suggestion]

    Keep each under 60 characters.
    """

    model = System.get_env("TRANSLATION_MODEL") || "llama-3.1-8b-instant"

    case GlobalbridgeBackend.AI.OpenAIServing.generate_completion(prompt, model) do
      {:ok, ai_response} ->
        suggestions = parse_numbered_suggestions(ai_response, "complexity_simplification", last_message.id)
        {:ok, suggestions}

      {:error, _reason} ->
        # Fallback to template
        {:ok, [
          %{
            type: "complexity_simplification",
            content: "Let me break that down...",
            confidence: 0.75,
            position: 1,
            context: %{trigger: "complexity_detected", message_id: last_message.id, ai_generated: false}
          }
        ]}
    end
  end

  defp parse_numbered_suggestions(ai_response, suggestion_type, message_id) do
    ai_response
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(fn line -> String.match?(line, ~r/^\d+\./) end)
    |> Enum.map(fn line ->
      line
      |> String.replace(~r/^\d+\.\s*/, "")
      |> String.trim()
    end)
    |> Enum.with_index(1)
    |> Enum.map(fn {content, position} ->
      %{
        type: suggestion_type,
        content: content,
        confidence: 0.9 - (position * 0.05),
        position: position,
        context: %{trigger: "#{suggestion_type}_detected", message_id: message_id, ai_generated: true}
      }
    end)
  end

  defp broadcast_suggestions(thread_id, suggestions) do
    # Broadcast to thread subscribers via PubSub
    topic = "thread:#{thread_id}"

    PubSub.broadcast(@pubsub, topic, {:ai_suggestions, suggestions})

    Logger.debug(
      "Broadcasted #{length(suggestions)} suggestions to thread #{thread_id}: #{inspect(suggestions)}"
    )
  end

  defp schedule_cleanup do
    # Cleanup old thread data every 15 minutes
    Process.send_after(self(), :cleanup_old_threads, 15 * 60 * 1000)
  end
end
