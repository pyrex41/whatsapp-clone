defmodule GlobalbridgeBackend.AI.OpenAIServing do
  @moduledoc """
  Agens Serving implementation for OpenAI-compatible APIs.

  This GenServer handles text generation requests using OpenAI-compatible APIs
  including OpenAI, Groq, and XAI (Grok). Provider selection is based on
  environment variables and model names.
  """

  use GenServer
  require Logger

  alias Agens.{Message, Serving}

  @doc """
  Starts the OpenAI Serving GenServer.
  """
  def start_link(%Serving.Config{} = config) do
    GenServer.start_link(__MODULE__, config, name: config.name)
  end

  @doc """
  Initializes the GenServer with the serving configuration.
  """
  @impl true
  def init(%Serving.Config{} = config) do
    {:ok, %{config: config}}
  end

  @doc """
  Handles the run request from Agens.

  Supports provider-specific routing based on model name or environment variables.
  """
  @impl true
  def handle_call({:run, %Message{} = message}, _from, state) do
    # Determine model based on context (agent/job) and environment variables
    model = determine_model_for_message(message)

    case generate_completion(message.prompt, model) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}

      {:error, reason} ->
        Logger.error("API call failed for model #{model}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @doc """
  Public API for generating completions directly.

  Used by SmartReplyGenerator and other AI modules.
  """
  def generate_completion(prompt, model) do
    provider = determine_provider(model)
    Logger.debug("Calling #{provider} API with model: #{model}")

    case provider do
      :groq -> call_groq(prompt, model)
      :xai -> call_xai(prompt, model)
      :openai -> call_openai(prompt, model)
    end
  end

  # Private functions

  defp determine_model_for_message(message) do
    # Check if this is a summarization context (contains specific keywords)
    cond do
      # Summarization context
      message.prompt =~ ~r/summarize|summary|analyze this conversation/i ->
        System.get_env("SUMMARIZER_MODEL") || "grok-2-1212"

      # Translation context
      message.prompt =~ ~r/translate|translation/i ->
        System.get_env("TRANSLATION_MODEL") || "llama-3.1-70b-versatile"

      # Language detection context
      message.prompt =~ ~r/detect.*language|language detection/i ->
        System.get_env("OPENAI_MODEL") || "llama-3.1-70b-versatile"

      # Default
      true ->
        System.get_env("OPENAI_MODEL") || "llama-3.1-70b-versatile"
    end
  end

  defp determine_provider(model) do
    cond do
      String.starts_with?(model, "grok-") -> :xai
      String.contains?(model, "llama") or String.contains?(model, "mixtral") -> :groq
      true -> :openai
    end
  end

  defp call_groq(prompt, model) do
    api_key = System.get_env("GROQ_API_KEY")

    if is_nil(api_key) do
      Logger.error("GROQ_API_KEY not set")
      {:error, "GROQ_API_KEY environment variable not set"}
    else
      url = "https://api.groq.com/openai/v1/chat/completions"

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{
        model: model,
        messages: [%{role: "user", content: prompt}],
        max_tokens: 1000,
        temperature: 0.7
      })

      case HTTPoison.post(url, body, headers, timeout: 30_000, recv_timeout: 30_000) do
        {:ok, %{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
              Logger.debug("Groq API call successful")
              {:ok, content}

            {:ok, response} ->
              Logger.warning("Unexpected Groq response format: #{inspect(response)}")
              {:error, "Unexpected response format"}

            {:error, reason} ->
              Logger.error("Failed to decode Groq response: #{inspect(reason)}")
              {:error, reason}
          end

        {:ok, %{status_code: status_code, body: body}} ->
          Logger.error("Groq API returned status #{status_code}: #{body}")
          {:error, "API returned status #{status_code}"}

        {:error, reason} ->
          Logger.error("Groq API request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp call_xai(prompt, model) do
    api_key = System.get_env("XAI_API_KEY")

    if is_nil(api_key) do
      Logger.error("XAI_API_KEY not set")
      {:error, "XAI_API_KEY environment variable not set"}
    else
      url = "https://api.x.ai/v1/chat/completions"

      headers = [
        {"Authorization", "Bearer #{api_key}"},
        {"Content-Type", "application/json"}
      ]

      body = Jason.encode!(%{
        model: model,
        messages: [%{role: "user", content: prompt}],
        max_tokens: 2000,
        temperature: 0.7
      })

      case HTTPoison.post(url, body, headers, timeout: 30_000, recv_timeout: 30_000) do
        {:ok, %{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
              Logger.debug("XAI API call successful")
              {:ok, content}

            {:ok, response} ->
              Logger.warning("Unexpected XAI response format: #{inspect(response)}")
              {:error, "Unexpected response format"}

            {:error, reason} ->
              Logger.error("Failed to decode XAI response: #{inspect(reason)}")
              {:error, reason}
          end

        {:ok, %{status_code: status_code, body: body}} ->
          Logger.error("XAI API returned status #{status_code}: #{body}")
          {:error, "API returned status #{status_code}"}

        {:error, reason} ->
          Logger.error("XAI API request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp call_openai(prompt, model) do
    Logger.debug("Calling OpenAI API with model: #{model}")

    case OpenAI.chat_completion(
           model: model,
           messages: [
             %{role: "user", content: prompt}
           ],
           max_tokens: 1000,
           temperature: 0.7
         ) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
        Logger.debug("OpenAI API call successful")
        {:ok, content}

      {:ok, response} ->
        Logger.warning("Unexpected OpenAI response format: #{inspect(response)}")
        {:ok, inspect(response)}

      {:error, reason} ->
        Logger.error("OpenAI API call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
