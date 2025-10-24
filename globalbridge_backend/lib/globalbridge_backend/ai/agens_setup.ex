defmodule GlobalbridgeBackend.AI.AgensSetup do
  @moduledoc """
  Sets up Agens components for multi-agent workflows.

  This module initializes:
  - OpenAI Serving for language model inference
  - LanguageDetectionAgent for language identification
  - TranslatorAgent with CulturalContextTool
  - TranslationJob for processing translation requests
  """

  alias Agens.{Serving, Agent, Job}
  alias GlobalbridgeBackend.AI.Jobs.TranslationJob
  alias GlobalbridgeBackend.AI.Agents.LanguageDetectionAgent
  alias GlobalbridgeBackend.AI.Agents.TranslatorAgent

  @doc """
  Starts all Agens components.
  """
  def start_components do
    # Start OpenAI Serving
    serving_config = %Serving.Config{
      name: :openai_serving,
      serving: GlobalbridgeBackend.AI.OpenAIServing
    }

    {:ok, _serving_pid} = Serving.start(serving_config)

    # Start Language Detection Agent
    {:ok, _detection_agent_pid} = Agent.start(LanguageDetectionAgent.config())

    # Start Translator Agent using the TranslatorAgent module's config
    {:ok, _agent_pid} = Agent.start(TranslatorAgent.config())

    # Start Translation Job using the module's config
    {:ok, _job_pid} = Job.start(TranslationJob.job_config())

    :ok
  end

  @doc """
  Runs a translation job with the given input.
  """
  def translate(text, target_language \\ "Spanish") do
    input = "Translate the following text to #{target_language}: #{text}"

    case Job.run(:translation_job, input) do
      {:ok, result} -> result
      {:error, reason} -> "Translation failed: #{inspect(reason)}"
    end
  end
end
