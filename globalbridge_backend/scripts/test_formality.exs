# Manual test script for translation formality
# Run with: mix run scripts/test_formality.exs

defmodule FormalityTester do
  @moduledoc """
  Tests translation formality levels with the actual translation API.
  """

  def run do
    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TRANSLATION FORMALITY TEST")
    IO.puts(String.duplicate("=", 80) <> "\n")

    test_cases = [
      # Simple greetings - should show clear differences
      %{
        text: "Hello",
        target: "es",
        name: "Simple greeting in Spanish"
      },
      %{
        text: "Hello",
        target: "fr",
        name: "Simple greeting in French"
      },
      %{
        text: "Hello",
        target: "de",
        name: "Simple greeting in German"
      },

      # Questions - pronoun differences
      %{
        text: "How are you?",
        target: "es",
        name: "Question in Spanish"
      },
      %{
        text: "How are you?",
        target: "fr",
        name: "Question in French"
      },

      # More complex
      %{
        text: "Could you help me?",
        target: "es",
        name: "Polite request in Spanish"
      },

      # Casual expression
      %{
        text: "What's up?",
        target: "es",
        name: "Casual expression in Spanish"
      }
    ]

    formality_levels = ["informal", "neutral", "formal"]

    for test_case <- test_cases do
      IO.puts("\n#{String.duplicate("-", 80)}")
      IO.puts("TEST: #{test_case.name}")
      IO.puts("Original: \"#{test_case.text}\"")
      IO.puts(String.duplicate("-", 80))

      for formality <- formality_levels do
        result = translate(test_case.text, test_case.target, formality)

        case result do
          {:ok, translation} ->
            IO.puts("""
            [#{String.upcase(formality)}]
              Translation: #{translation}
            """)

          {:error, reason} ->
            IO.puts("""
            [#{String.upcase(formality)}]
              ERROR: #{inspect(reason)}
            """)
        end
      end
    end

    IO.puts("\n" <> String.duplicate("=", 80))
    IO.puts("TEST COMPLETE")
    IO.puts(String.duplicate("=", 80) <> "\n")
  end

  defp translate(text, target_lang, formality) do
    # Call the actual translation function
    # This simulates what the controller does

    try do
      groq_api_key = System.get_env("GROQ_API_KEY")

      if !groq_api_key do
        {:error, "GROQ_API_KEY not configured"}
      else
        target_language_name = get_language_name(target_lang)

        formality_instruction = get_formality_instruction(formality)

        prompt = """
        You are an expert translator who understands nuance, tone, and cultural context.

        #{formality_instruction}

        CRITICAL INSTRUCTIONS:
        1. DO NOT translate word-for-word. Instead, find the most natural way to express the INTENT and FEELING in #{target_language_name}.
        2. Adjust the formality to match the specified level - this may mean choosing completely different words or phrases.
        3. For simple greetings like "Hello", adjust based on formality:
           - Informal: Use casual greetings (e.g., "Hola" / "¿Qué tal?" / "Salut")
           - Formal: Use polite greetings with honorifics (e.g., "Buenos días, señor" / "Bonjour, monsieur")
        4. Preserve emojis and punctuation exactly as they appear.
        5. If an idiom or cultural phrase doesn't translate well, find an equivalent expression in the target language.

        Text to translate: #{text}

        Respond in JSON format:
        {
          "source_language": "detected source language full name",
          "translation": "the translated text with appropriate formality",
          "confidence": 0.95
        }

        Only return the JSON, nothing else.
        """

        # Make API call
        url = "https://api.groq.com/openai/v1/chat/completions"
        headers = [
          {"Authorization", "Bearer #{groq_api_key}"},
          {"Content-Type", "application/json"}
        ]

        body = Jason.encode!(%{
          model: "llama-3.3-70b-versatile",
          messages: [
            %{role: "system", content: "You are a professional translator. Always respond with valid JSON."},
            %{role: "user", content: prompt}
          ],
          temperature: 0.3,
          response_format: %{type: "json_object"}
        })

        case HTTPoison.post(url, body, headers, recv_timeout: 30_000) do
          {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
            case Jason.decode(response_body) do
              {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}} ->
                case Jason.decode(content) do
                  {:ok, %{"translation" => translation}} ->
                    {:ok, translation}
                  _ ->
                    {:error, "Failed to parse translation"}
                end
              _ ->
                {:error, "Invalid API response"}
            end

          {:error, reason} ->
            {:error, "API call failed: #{inspect(reason)}"}
        end
      end
    rescue
      error ->
        {:error, "Exception: #{inspect(error)}"}
    end
  end

  defp get_formality_instruction("informal") do
    """
    FORMALITY LEVEL: INFORMAL/CASUAL
    - Use casual, friendly language as if speaking to a close friend
    - Choose informal greetings and expressions (e.g., Spanish: "¿Qué tal?" instead of "¿Cómo está?")
    - Use informal pronouns (e.g., Spanish: "tú" instead of "usted", French: "tu" instead of "vous")
    - Opt for conversational slang and colloquialisms when appropriate
    - Keep the tone warm and relaxed
    """
  end

  defp get_formality_instruction("formal") do
    """
    FORMALITY LEVEL: FORMAL/PROFESSIONAL
    - Use polite, respectful language as if speaking to a business contact or elder
    - Choose formal greetings and expressions (e.g., Spanish: "Buenos días, señor" instead of "Hola")
    - Use formal pronouns (e.g., Spanish: "usted", French: "vous", German: "Sie")
    - Include appropriate titles and honorifics
    - Maintain a professional, courteous tone
    """
  end

  defp get_formality_instruction(_) do
    """
    FORMALITY LEVEL: NEUTRAL/STANDARD
    - Use balanced language appropriate for everyday conversation
    - Choose standard greetings and expressions
    - Use neutral pronouns appropriate for the context
    - Maintain a friendly but respectful tone
    """
  end

  defp get_language_name("es"), do: "Spanish"
  defp get_language_name("fr"), do: "French"
  defp get_language_name("de"), do: "German"
  defp get_language_name("it"), do: "Italian"
  defp get_language_name("pt"), do: "Portuguese"
  defp get_language_name(code), do: code
end

# Run the tests
FormalityTester.run()
