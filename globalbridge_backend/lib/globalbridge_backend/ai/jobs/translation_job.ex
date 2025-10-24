defmodule GlobalbridgeBackend.AI.Jobs.TranslationJob do
  @moduledoc """
  Defines the TranslationJob for multi-agent orchestration using Agens.

  This job orchestrates language detection and translation with cultural context analysis.
  Steps:
  1. Detect the source language of the input text.
  2. Translate the text to the target language, incorporating cultural nuances.
  """

  alias Agens.Job

  @doc """
  Returns the job configuration for the TranslationJob.

  This includes the steps for language detection and translation.
  """
  def job_config do
    %Job.Config{
      name: :translation_job,
      description: "Multi-step translation process with language detection and cultural context analysis",
      steps: [
        %Job.Step{
          agent: :language_detection_agent,
          objective: "Detect the source language of the input text and output it in the format 'Detected language: <language>'"
        },
        %Job.Step{
          agent: :translator_agent,
          objective: "Translate the text to the target language using cultural context analysis, ensuring appropriateness and nuance"
        }
      ]
    }
  end
end
