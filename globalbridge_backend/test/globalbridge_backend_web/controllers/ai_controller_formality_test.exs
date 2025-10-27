defmodule GlobalbridgeBackendWeb.AIControllerFormalityTest do
  use GlobalbridgeBackendWeb.ConnCase, async: true
  import Mox

  @moduletag :integration

  setup :verify_on_exit!

  describe "POST /api/v1/ai/translate with formality levels" do
    setup [:create_user_and_auth]

    test "informal formality produces casual greeting in Spanish", %{conn: conn} do
      params = %{
        "text" => "Hello",
        "target_language" => "es",
        "source_language" => "en",
        "formality" => "informal"
      }

      conn = post(conn, ~p"/api/v1/ai/translate", params)

      assert %{"success" => true, "translation" => translation} = json_response(conn, 200)

      # Informal Spanish should use casual greetings
      # Common informal options: "Hola", "¿Qué tal?", "Ey", "Buenas"
      assert translation =~ ~r/(hola|qué tal|ey|buenas)/i
      # Should NOT include formal markers
      refute translation =~ ~r/(señor|usted|buenos días)/i
    end

    test "formal formality produces polite greeting in Spanish", %{conn: conn} do
      params = %{
        "text" => "Hello",
        "target_language" => "es",
        "source_language" => "en",
        "formality" => "formal"
      }

      conn = post(conn, ~p"/api/v1/ai/translate", params)

      assert %{"success" => true, "translation" => translation} = json_response(conn, 200)

      # Formal Spanish should include respectful language
      # Common formal options: "Buenos días", "Buenas tardes", includes "señor/señora", uses "usted"
      assert translation =~ ~r/(buenos|buenas|señor|estimado)/i
    end

    test "neutral formality produces standard greeting in Spanish", %{conn: conn} do
      params = %{
        "text" => "Hello",
        "target_language" => "es",
        "source_language" => "en",
        "formality" => "neutral"
      }

      conn = post(conn, ~p"/api/v1/ai/translate", params)

      assert %{"success" => true, "translation" => translation} = json_response(conn, 200)

      # Neutral should be balanced - "Hola" is acceptable
      assert String.length(translation) > 0
    end

    test "formality affects pronoun choice in French", %{conn: conn} do
      informal_params = %{
        "text" => "How are you?",
        "target_language" => "fr",
        "source_language" => "en",
        "formality" => "informal"
      }

      formal_params = %{
        "text" => "How are you?",
        "target_language" => "fr",
        "source_language" => "en",
        "formality" => "formal"
      }

      # Informal should use "tu"
      informal_conn = post(conn, ~p"/api/v1/ai/translate", informal_params)
      assert %{"success" => true, "translation" => informal_translation} = json_response(informal_conn, 200)
      assert informal_translation =~ ~r/(tu|t')/i

      # Formal should use "vous"
      formal_conn = post(conn, ~p"/api/v1/ai/translate", formal_params)
      assert %{"success" => true, "translation" => formal_translation} = json_response(formal_conn, 200)
      assert formal_translation =~ ~r/vous/i
    end

    test "formality affects greeting complexity", %{conn: conn} do
      informal_params = %{
        "text" => "Good morning",
        "target_language" => "es",
        "formality" => "informal"
      }

      formal_params = %{
        "text" => "Good morning",
        "target_language" => "es",
        "formality" => "formal"
      }

      # Test that formal is typically longer/more elaborate
      informal_conn = post(conn, ~p"/api/v1/ai/translate", informal_params)
      formal_conn = post(conn, ~p"/api/v1/ai/translate", formal_params)

      assert %{"translation" => informal} = json_response(informal_conn, 200)
      assert %{"translation" => formal} = json_response(formal_conn, 200)

      # Both should be valid but likely different
      assert informal != formal
    end

    test "complex sentence maintains formality in German", %{conn: conn} do
      params = %{
        "text" => "Could you please help me with this?",
        "target_language" => "de",
        "formality" => "formal"
      }

      conn = post(conn, ~p"/api/v1/ai/translate", params)

      assert %{"success" => true, "translation" => translation} = json_response(conn, 200)

      # Formal German should use "Sie" not "du"
      assert translation =~ ~r/Sie/
      refute translation =~ ~r/\bdu\b/i
    end

    test "formality is optional and defaults to neutral", %{conn: conn} do
      params = %{
        "text" => "Hello",
        "target_language" => "es",
        "source_language" => "en"
        # No formality parameter
      }

      conn = post(conn, ~p"/api/v1/ai/translate", params)

      assert %{"success" => true, "translation" => translation} = json_response(conn, 200)
      assert String.length(translation) > 0
    end

    test "preserves emojis and punctuation across formality levels", %{conn: conn} do
      params = %{
        "text" => "Hello! 👋",
        "target_language" => "es",
        "formality" => "informal"
      }

      conn = post(conn, ~p"/api/v1/ai/translate", params)

      assert %{"success" => true, "translation" => translation} = json_response(conn, 200)
      assert translation =~ "👋"
    end
  end

  describe "translation formality with different AI providers" do
    @tag :provider_comparison
    test "compares formality handling across providers" do
      test_cases = [
        %{text: "Hello", target: "es", formality: "informal", expected_pattern: ~r/hola|qué/i},
        %{text: "Hello", target: "es", formality: "formal", expected_pattern: ~r/buenos|señor/i},
        %{text: "How are you?", target: "fr", formality: "informal", expected_pattern: ~r/tu|t'/i},
        %{text: "How are you?", target: "fr", formality: "formal", expected_pattern: ~r/vous/i}
      ]

      providers = get_available_providers()

      for provider <- providers do
        IO.puts("\n=== Testing provider: #{provider} ===")

        for test_case <- test_cases do
          result = translate_with_provider(
            test_case.text,
            test_case.target,
            test_case.formality,
            provider
          )

          IO.puts("""
          Text: #{test_case.text}
          Target: #{test_case.target}
          Formality: #{test_case.formality}
          Result: #{result}
          Match: #{Regex.match?(test_case.expected_pattern, result)}
          """)
        end
      end
    end
  end

  # Private helper functions

  defp create_user_and_auth(%{conn: conn}) do
    user = insert(:user)
    token = generate_valid_jwt_for_user(user)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")

    {:ok, conn: conn, user: user}
  end

  defp generate_valid_jwt_for_user(user) do
    # Generate a valid JWT token for testing
    # This would use your actual JWT generation logic
    "test_token_#{user.id}"
  end

  defp get_available_providers do
    [
      :groq_llama,
      :openai_gpt4,
      :anthropic_claude
    ]
    |> Enum.filter(fn provider ->
      case provider do
        :groq_llama -> System.get_env("GROQ_API_KEY") != nil
        :openai_gpt4 -> System.get_env("OPENAI_API_KEY") != nil
        :anthropic_claude -> System.get_env("ANTHROPIC_API_KEY") != nil
      end
    end)
  end

  defp translate_with_provider(text, target_lang, formality, provider) do
    # This would call the appropriate provider's API
    # For now, returns a placeholder
    case provider do
      :groq_llama ->
        # Use current Groq implementation
        translate_via_api(text, target_lang, formality)

      :openai_gpt4 ->
        # Would implement OpenAI GPT-4 translation
        "#{text} [via OpenAI]"

      :anthropic_claude ->
        # Would implement Claude translation
        "#{text} [via Claude]"
    end
  end

  defp translate_via_api(text, target_lang, formality) do
    # Simulate API call
    "Translated: #{text} (#{formality})"
  end
end
