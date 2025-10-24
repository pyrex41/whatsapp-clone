defmodule GlobalbridgeBackend.AI.Tools.CulturalContextTool do
  @moduledoc """
  Tool for providing cultural context in translations.

  This tool helps ensure translations are culturally appropriate by providing
  context about idioms, cultural references, and regional variations.
  """

  @behaviour Agens.Tool

  @doc """
  Pre-process the input text for cultural context analysis.
  """
  @impl true
  def pre(input) do
    """
    Analyze this text for cultural context and translation needs: #{input}

    Consider:
    - Idioms and colloquial expressions
    - Cultural references
    - Regional dialects or slang
    - Contextual appropriateness
    """
  end

  @doc """
  Instructions for the language model on how to use this tool.
  """
  @impl true
  def instructions do
    """
    You are a cultural context analysis tool. When given text to translate, analyze it for:

    1. Idiomatic expressions that may not translate literally
    2. Cultural references specific to the source culture
    3. Regional slang or dialects
    4. Contextual nuances that affect translation

    Provide your analysis in the following JSON format:
    {
      "cultural_elements": ["list", "of", "cultural", "elements"],
      "translation_notes": "specific guidance for translator",
      "target_culture_adaptations": ["suggested", "adaptations"]
    }

    Focus on elements that could be lost or misinterpreted in translation.
    """
  end

  @doc """
  Parse the LM result into arguments for execution.
  """
  @impl true
  def to_args(result) do
    case Jason.decode(result) do
      {:ok,
       %{
         "cultural_elements" => elements,
         "translation_notes" => notes,
         "target_culture_adaptations" => adaptations
       }} ->
        [
          cultural_elements: elements,
          translation_notes: notes,
          target_culture_adaptations: adaptations
        ]

      _ ->
        # Fallback parsing
        [
          cultural_elements: [],
          translation_notes: "Unable to parse cultural analysis",
          target_culture_adaptations: []
        ]
    end
  end

  @doc """
  Execute the cultural context analysis.
  """
  @impl true
  def execute(args) do
    # In a real implementation, this might call external APIs or databases
    # For now, we'll just return the analyzed data
    %{
      cultural_elements: Keyword.get(args, :cultural_elements, []),
      translation_notes: Keyword.get(args, :translation_notes, ""),
      target_culture_adaptations: Keyword.get(args, :target_culture_adaptations, []),
      analysis_timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Post-process the execution result into a string for the next step.
  """
  @impl true
  def post(result) do
    case result do
      %{
        cultural_elements: elements,
        translation_notes: notes,
        target_culture_adaptations: adaptations
      } ->
        """
        Cultural Context Analysis Complete:

        Cultural Elements Identified:
        #{Enum.map(elements, &"- #{&1}") |> Enum.join("\n")}

        Translation Notes:
        #{notes}

        Suggested Adaptations:
        #{Enum.map(adaptations, &"- #{&1}") |> Enum.join("\n")}

        Use this context to ensure the translation is culturally appropriate and natural.
        """

      {:error, reason} ->
        "Cultural context analysis failed: #{inspect(reason)}"

      _ ->
        "Cultural context analysis returned unexpected result: #{inspect(result)}"
    end
  end
end
