defmodule GlobalbridgeBackend.AI.Agents.LanguageDetectionAgent do
  @moduledoc """
  Agent for detecting the language of input text using OpenAI.

  This agent uses the OpenAI serving to analyze text and identify the source language.
  It is designed for simplicity and efficiency in the translation workflow.
  """

  # Note: This is not a GenServer; it's a configuration module for Agens Agent.
  # The actual agent is started via Agens.Agent.start/1 in AgensSetup.

  alias Agens.Agent

  @doc """
  Returns the configuration for the LanguageDetectionAgent.

  Uses the OpenAI serving with a focused prompt for language detection.
  """
  def config do
    %Agent.Config{
      name: :language_detection_agent,
      serving: :openai_serving,
      prompt: %Agent.Prompt{
        identity: "You are a language detection expert.",
        context: "Your role is to accurately identify the primary language of the provided text.",
        constraints: "Respond only with the detected language in the format 'Detected language: <language>'. If uncertain, default to 'English'."
      }
    }
  end
end
