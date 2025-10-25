defmodule GlobalbridgeBackend.AI.Agents.IdiomAnalyzerAgentTest do
  use ExUnit.Case, async: true

  alias GlobalbridgeBackend.AI.Agents.IdiomAnalyzerAgent

  describe "config/0" do
    test "returns valid agent configuration" do
      config = IdiomAnalyzerAgent.config()

      assert config.name == :idiom_analyzer_agent
      assert config.serving == :openai_serving
      assert config.prompt.identity != nil
      assert config.prompt.context != nil
      assert config.prompt.constraints != nil
    end

    test "prompt includes cultural and idiomatic expression focus" do
      config = IdiomAnalyzerAgent.config()

      assert String.contains?(config.prompt.context, "idiom")
      assert String.contains?(config.prompt.context, "cultural")
      assert String.contains?(config.prompt.context, "expression")
    end

    test "prompt specifies JSON array output format" do
      config = IdiomAnalyzerAgent.config()

      assert String.contains?(config.prompt.constraints, "JSON array")
      assert String.contains?(config.prompt.constraints, "source_phrase")
      assert String.contains?(config.prompt.constraints, "explanation")
      assert String.contains?(config.prompt.constraints, "target_equivalent")
      assert String.contains?(config.prompt.constraints, "cultural_context")
    end
  end

  describe "parse_analysis_result/1" do
    test "parses empty array successfully" do
      assert {:ok, []} == IdiomAnalyzerAgent.parse_analysis_result("[]")
    end

    test "parses single idiom successfully" do
      json = """
      [
        {
          "source_phrase": "Break a leg",
          "explanation": "A theatrical idiom meaning 'good luck'",
          "target_equivalent": "¡Mucha mierda!",
          "cultural_context": "Theater tradition of wishing performers good luck"
        }
      ]
      """

      assert {:ok, [idiom]} = IdiomAnalyzerAgent.parse_analysis_result(json)
      assert idiom.source_phrase == "Break a leg"
      assert idiom.explanation == "A theatrical idiom meaning 'good luck'"
      assert idiom.target_equivalent == "¡Mucha mierda!"
      assert idiom.cultural_context == "Theater tradition of wishing performers good luck"
    end

    test "parses multiple idioms successfully" do
      json = """
      [
        {
          "source_phrase": "Break a leg",
          "explanation": "Good luck",
          "target_equivalent": "¡Mucha mierda!",
          "cultural_context": "Theater tradition"
        },
        {
          "source_phrase": "Piece of cake",
          "explanation": "Very easy",
          "target_equivalent": "Pan comido",
          "cultural_context": "Common English expression"
        }
      ]
      """

      assert {:ok, idioms} = IdiomAnalyzerAgent.parse_analysis_result(json)
      assert length(idioms) == 2
      assert Enum.at(idioms, 0).source_phrase == "Break a leg"
      assert Enum.at(idioms, 1).source_phrase == "Piece of cake"
    end

    test "extracts JSON from code blocks" do
      output = """
      ```json
      [
        {
          "source_phrase": "Test phrase",
          "explanation": "Test explanation",
          "target_equivalent": "Phrase de prueba",
          "cultural_context": "Test context"
        }
      ]
      ```
      """

      assert {:ok, [idiom]} = IdiomAnalyzerAgent.parse_analysis_result(output)
      assert idiom.source_phrase == "Test phrase"
    end

    test "extracts JSON from markdown with extra text" do
      output = """
      Here are the idioms I found:

      ```json
      [{
        "source_phrase": "Test",
        "explanation": "Test",
        "target_equivalent": "Test",
        "cultural_context": "Test"
      }]
      ```

      These are common expressions.
      """

      assert {:ok, [_idiom]} = IdiomAnalyzerAgent.parse_analysis_result(output)
    end

    test "returns error for invalid JSON" do
      assert {:error, _reason} = IdiomAnalyzerAgent.parse_analysis_result("not valid json")
    end

    test "returns error for non-array JSON" do
      json = """
      {
        "not": "an array"
      }
      """

      assert {:error, _reason} = IdiomAnalyzerAgent.parse_analysis_result(json)
    end

    test "returns error for missing required fields" do
      json = """
      [
        {
          "source_phrase": "Test",
          "explanation": "Test"
        }
      ]
      """

      assert {:error, reason} = IdiomAnalyzerAgent.parse_analysis_result(json)
      assert reason =~ "missing required fields"
    end

    test "trims whitespace from fields" do
      json = """
      [
        {
          "source_phrase": "  Break a leg  ",
          "explanation": "  Good luck  ",
          "target_equivalent": "  ¡Mucha mierda!  ",
          "cultural_context": "  Theater tradition  "
        }
      ]
      """

      assert {:ok, [idiom]} = IdiomAnalyzerAgent.parse_analysis_result(json)
      assert idiom.source_phrase == "Break a leg"
      assert idiom.explanation == "Good luck"
      assert idiom.target_equivalent == "¡Mucha mierda!"
      assert idiom.cultural_context == "Theater tradition"
    end
  end

  describe "valid_analysis?/1" do
    test "returns true for valid empty array" do
      assert IdiomAnalyzerAgent.valid_analysis?([])
    end

    test "returns true for valid idiom array" do
      idioms = [
        %{
          source_phrase: "Break a leg",
          explanation: "Good luck",
          target_equivalent: "¡Mucha mierda!",
          cultural_context: "Theater tradition"
        }
      ]

      assert IdiomAnalyzerAgent.valid_analysis?(idioms)
    end

    test "returns false for non-list" do
      refute IdiomAnalyzerAgent.valid_analysis?(%{})
      refute IdiomAnalyzerAgent.valid_analysis?("string")
      refute IdiomAnalyzerAgent.valid_analysis?(nil)
    end

    test "returns false for list with invalid idioms" do
      invalid_idioms = [
        %{
          source_phrase: "Test",
          explanation: "Test"
          # Missing target_equivalent and cultural_context
        }
      ]

      refute IdiomAnalyzerAgent.valid_analysis?(invalid_idioms)
    end

    test "returns false for list with empty strings" do
      invalid_idioms = [
        %{
          source_phrase: "",
          explanation: "Test",
          target_equivalent: "Test",
          cultural_context: "Test"
        }
      ]

      refute IdiomAnalyzerAgent.valid_analysis?(invalid_idioms)
    end
  end

  describe "valid_idiom?/1" do
    test "returns true for valid idiom" do
      idiom = %{
        source_phrase: "Break a leg",
        explanation: "Good luck",
        target_equivalent: "¡Mucha mierda!",
        cultural_context: "Theater tradition"
      }

      assert IdiomAnalyzerAgent.valid_idiom?(idiom)
    end

    test "returns false for missing fields" do
      incomplete = %{
        source_phrase: "Test",
        explanation: "Test"
      }

      refute IdiomAnalyzerAgent.valid_idiom?(incomplete)
    end

    test "returns false for non-string fields" do
      invalid = %{
        source_phrase: "Test",
        explanation: 123,
        target_equivalent: "Test",
        cultural_context: "Test"
      }

      refute IdiomAnalyzerAgent.valid_idiom?(invalid)
    end

    test "returns false for empty strings" do
      empty = %{
        source_phrase: "",
        explanation: "Test",
        target_equivalent: "Test",
        cultural_context: "Test"
      }

      refute IdiomAnalyzerAgent.valid_idiom?(empty)
    end

    test "returns false for whitespace-only strings" do
      whitespace = %{
        source_phrase: "   ",
        explanation: "Test",
        target_equivalent: "Test",
        cultural_context: "Test"
      }

      refute IdiomAnalyzerAgent.valid_idiom?(whitespace)
    end
  end

  describe "edge cases" do
    test "handles JSON with escaped characters" do
      json = """
      [
        {
          "source_phrase": "It's raining cats and dogs",
          "explanation": "It's raining very heavily",
          "target_equivalent": "Llueve a cántaros",
          "cultural_context": "Common English weather idiom"
        }
      ]
      """

      assert {:ok, [idiom]} = IdiomAnalyzerAgent.parse_analysis_result(json)
      assert idiom.source_phrase == "It's raining cats and dogs"
    end

    test "handles JSON with unicode characters" do
      json = """
      [
        {
          "source_phrase": "打草惊蛇",
          "explanation": "To alert the enemy",
          "target_equivalent": "Alertar al enemigo",
          "cultural_context": "Chinese idiom meaning 'beat the grass and startle the snake'"
        }
      ]
      """

      assert {:ok, [idiom]} = IdiomAnalyzerAgent.parse_analysis_result(json)
      assert idiom.source_phrase == "打草惊蛇"
    end

    test "handles very long idiom explanations" do
      long_explanation = String.duplicate("a", 1000)

      json = """
      [
        {
          "source_phrase": "Test",
          "explanation": "#{long_explanation}",
          "target_equivalent": "Test",
          "cultural_context": "Test"
        }
      ]
      """

      assert {:ok, [idiom]} = IdiomAnalyzerAgent.parse_analysis_result(json)
      assert idiom.explanation == long_explanation
    end
  end
end
