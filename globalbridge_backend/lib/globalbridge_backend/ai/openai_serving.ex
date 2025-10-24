defmodule GlobalbridgeBackend.AI.OpenAIServing do
  @moduledoc """
  Agens Serving implementation for OpenAI API.

  This GenServer handles text generation requests using OpenAI's chat completions API.
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
  """
  @impl true
  def handle_call({:run, %Message{} = message}, _from, state) do
    # TODO: Add tools/function calling support when Message struct includes tools field
    case generate_completion(message.prompt) do
      {:ok, result} ->
        {:reply, {:ok, result}, state}

      {:error, reason} ->
        Logger.error("OpenAI API call failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  # Private functions

  defp generate_completion(prompt) do
    # Get configurable model name, default to gpt-4o-mini
    model = System.get_env("OPENAI_MODEL") || "gpt-4o-mini"

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
        # Fallback for unexpected response format
        Logger.warning("Unexpected OpenAI response format: #{inspect(response)}")
        {:ok, inspect(response)}

      {:error, reason} ->
        Logger.error("OpenAI API call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
