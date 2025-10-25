defmodule GlobalbridgeBackendWeb.Validators.AIValidatorTest do
  use ExUnit.Case, async: true

  alias GlobalbridgeBackendWeb.Validators.AIValidator

  doctest AIValidator

  describe "validate_text/1" do
    test "accepts valid text" do
      assert {:ok, "Hello world"} = AIValidator.validate_text("Hello world")
    end

    test "trims whitespace from valid text" do
      assert {:ok, "Hello world"} = AIValidator.validate_text("  Hello world  ")
    end

    test "rejects nil" do
      assert {:error, "Text must be a non-empty string"} = AIValidator.validate_text(nil)
    end

    test "rejects empty string" do
      assert {:error, "Text must be a non-empty string"} = AIValidator.validate_text("")
    end

    test "rejects whitespace-only string" do
      assert {:error, "Text must be a non-empty string"} = AIValidator.validate_text("   ")
    end

    test "rejects non-string" do
      assert {:error, "Text must be a string"} = AIValidator.validate_text(123)
      assert {:error, "Text must be a string"} = AIValidator.validate_text(%{})
    end

    test "rejects text exceeding max length" do
      long_text = String.duplicate("a", 10_001)
      assert {:error, "Text must not exceed 10,000 characters"} = AIValidator.validate_text(long_text)
    end

    test "accepts text at max length boundary" do
      max_text = String.duplicate("a", 10_000)
      assert {:ok, ^max_text} = AIValidator.validate_text(max_text)
    end

    test "accepts unicode text" do
      unicode_text = "Hello 世界 🌍"
      assert {:ok, ^unicode_text} = AIValidator.validate_text(unicode_text)
    end
  end

  describe "validate_query/1" do
    test "accepts valid query" do
      assert {:ok, "project deadline"} = AIValidator.validate_query("project deadline")
    end

    test "trims whitespace from valid query" do
      assert {:ok, "search term"} = AIValidator.validate_query("  search term  ")
    end

    test "rejects nil" do
      assert {:error, "Query must be a non-empty string"} = AIValidator.validate_query(nil)
    end

    test "rejects empty string" do
      assert {:error, "Query must be a non-empty string"} = AIValidator.validate_query("")
    end

    test "rejects non-string" do
      assert {:error, "Query must be a string"} = AIValidator.validate_query(123)
    end

    test "rejects query exceeding max length" do
      long_query = String.duplicate("a", 1_001)
      assert {:error, "Query must not exceed 1,000 characters"} = AIValidator.validate_query(long_query)
    end

    test "accepts query at max length boundary" do
      max_query = String.duplicate("a", 1_000)
      assert {:ok, ^max_query} = AIValidator.validate_query(max_query)
    end
  end

  describe "validate_thread_id/1" do
    test "accepts valid UUID" do
      uuid = "123e4567-e89b-12d3-a456-426614174000"
      assert {:ok, ^uuid} = AIValidator.validate_thread_id(uuid)
    end

    test "accepts UUID in different formats" do
      uuid = "123E4567-E89B-12D3-A456-426614174000"
      assert {:ok, _} = AIValidator.validate_thread_id(uuid)
    end

    test "rejects invalid UUID format" do
      assert {:error, "Thread ID must be a valid UUID"} = AIValidator.validate_thread_id("invalid-uuid")
    end

    test "rejects nil" do
      assert {:error, "Thread ID is required"} = AIValidator.validate_thread_id(nil)
    end

    test "rejects non-string" do
      assert {:error, "Thread ID must be a string"} = AIValidator.validate_thread_id(123)
    end

    test "rejects empty string" do
      assert {:error, "Thread ID must be a valid UUID"} = AIValidator.validate_thread_id("")
    end
  end

  describe "validate_optional_thread_id/1" do
    test "accepts valid UUID" do
      uuid = "123e4567-e89b-12d3-a456-426614174000"
      assert {:ok, ^uuid} = AIValidator.validate_optional_thread_id(uuid)
    end

    test "accepts nil" do
      assert {:ok, nil} = AIValidator.validate_optional_thread_id(nil)
    end

    test "rejects invalid UUID" do
      assert {:error, "Thread ID must be a valid UUID"} = AIValidator.validate_optional_thread_id("invalid")
    end
  end

  describe "validate_limit/1" do
    test "accepts valid integer limit" do
      assert {:ok, 10} = AIValidator.validate_limit(10)
    end

    test "accepts valid string limit" do
      assert {:ok, 25} = AIValidator.validate_limit("25")
    end

    test "accepts minimum limit" do
      assert {:ok, 1} = AIValidator.validate_limit(1)
    end

    test "accepts maximum limit" do
      assert {:ok, 50} = AIValidator.validate_limit(50)
    end

    test "rejects limit below minimum" do
      assert {:error, "Limit must be between 1 and 50"} = AIValidator.validate_limit(0)
    end

    test "rejects limit above maximum" do
      assert {:error, "Limit must be between 1 and 50"} = AIValidator.validate_limit(51)
    end

    test "rejects negative limit" do
      assert {:error, "Limit must be between 1 and 50"} = AIValidator.validate_limit(-5)
    end

    test "rejects invalid string" do
      assert {:error, "Limit must be a valid integer"} = AIValidator.validate_limit("abc")
    end

    test "rejects float" do
      assert {:error, "Limit must be an integer"} = AIValidator.validate_limit(10.5)
    end

    test "rejects non-numeric types" do
      assert {:error, "Limit must be an integer"} = AIValidator.validate_limit(%{})
    end
  end

  describe "validate_max_length/1" do
    test "accepts valid integer max_length" do
      assert {:ok, 200} = AIValidator.validate_max_length(200)
    end

    test "accepts valid string max_length" do
      assert {:ok, 500} = AIValidator.validate_max_length("500")
    end

    test "accepts minimum max_length" do
      assert {:ok, 1} = AIValidator.validate_max_length(1)
    end

    test "accepts maximum max_length" do
      assert {:ok, 1_000} = AIValidator.validate_max_length(1_000)
    end

    test "rejects max_length below minimum" do
      assert {:error, "Max length must be between 1 and 1,000"} = AIValidator.validate_max_length(0)
    end

    test "rejects max_length above maximum" do
      assert {:error, "Max length must be between 1 and 1,000"} = AIValidator.validate_max_length(1_001)
    end

    test "rejects invalid string" do
      assert {:error, "Max length must be a valid integer"} = AIValidator.validate_max_length("abc")
    end

    test "rejects non-numeric types" do
      assert {:error, "Max length must be an integer"} = AIValidator.validate_max_length(nil)
    end
  end

  describe "validate_language/1" do
    test "accepts valid language codes" do
      assert {:ok, "en"} = AIValidator.validate_language("en")
      assert {:ok, "es"} = AIValidator.validate_language("es")
      assert {:ok, "fr"} = AIValidator.validate_language("fr")
    end

    test "converts to lowercase" do
      assert {:ok, "en"} = AIValidator.validate_language("EN")
      assert {:ok, "es"} = AIValidator.validate_language("Es")
    end

    test "rejects invalid language code" do
      assert {:error, msg} = AIValidator.validate_language("invalid")
      assert msg =~ "Language must be one of"
    end

    test "rejects non-string" do
      assert {:error, "Language must be a string"} = AIValidator.validate_language(123)
    end
  end

  describe "validate_optional_language/1" do
    test "accepts valid language" do
      assert {:ok, "es"} = AIValidator.validate_optional_language("es")
    end

    test "defaults nil to 'en'" do
      assert {:ok, "en"} = AIValidator.validate_optional_language(nil)
    end
  end

  describe "validate_optional_target_language/1" do
    test "accepts valid language codes" do
      assert {:ok, "es"} = AIValidator.validate_optional_target_language("es")
      assert {:ok, "fr"} = AIValidator.validate_optional_target_language("fr")
      assert {:ok, "de"} = AIValidator.validate_optional_target_language("de")
    end

    test "returns {:ok, nil} for nil (triggers auto-detection)" do
      assert {:ok, nil} = AIValidator.validate_optional_target_language(nil)
    end

    test "converts to lowercase" do
      assert {:ok, "en"} = AIValidator.validate_optional_target_language("EN")
      assert {:ok, "es"} = AIValidator.validate_optional_target_language("Es")
    end

    test "rejects invalid language code" do
      assert {:error, msg} = AIValidator.validate_optional_target_language("invalid")
      assert msg =~ "Language must be one of"
    end

    test "rejects non-string non-nil values" do
      assert {:error, "Language must be a string"} =
               AIValidator.validate_optional_target_language(123)
    end
  end

  describe "validate_tone/1" do
    test "accepts valid tones" do
      assert {:ok, "formal"} = AIValidator.validate_tone("formal")
      assert {:ok, "informal"} = AIValidator.validate_tone("informal")
      assert {:ok, "neutral"} = AIValidator.validate_tone("neutral")
    end

    test "converts to lowercase" do
      assert {:ok, "formal"} = AIValidator.validate_tone("FORMAL")
      assert {:ok, "informal"} = AIValidator.validate_tone("Informal")
    end

    test "rejects invalid tone" do
      assert {:error, msg} = AIValidator.validate_tone("invalid")
      assert msg =~ "Tone must be one of"
    end

    test "rejects non-string" do
      assert {:error, "Tone must be a string"} = AIValidator.validate_tone(123)
    end
  end

  describe "validate_optional_tone/1" do
    test "accepts valid tone" do
      assert {:ok, "formal"} = AIValidator.validate_optional_tone("formal")
    end

    test "accepts nil" do
      assert {:ok, nil} = AIValidator.validate_optional_tone(nil)
    end
  end

  describe "validate_boolean/1" do
    test "accepts boolean true" do
      assert {:ok, true} = AIValidator.validate_boolean(true)
    end

    test "accepts boolean false" do
      assert {:ok, false} = AIValidator.validate_boolean(false)
    end

    test "accepts string 'true'" do
      assert {:ok, true} = AIValidator.validate_boolean("true")
    end

    test "accepts string 'false'" do
      assert {:ok, false} = AIValidator.validate_boolean("false")
    end

    test "converts string case insensitively" do
      assert {:ok, true} = AIValidator.validate_boolean("TRUE")
      assert {:ok, false} = AIValidator.validate_boolean("False")
    end

    test "rejects invalid string" do
      assert {:error, "Value must be true or false"} = AIValidator.validate_boolean("yes")
    end

    test "rejects non-boolean types" do
      assert {:error, "Value must be a boolean"} = AIValidator.validate_boolean(1)
    end
  end

  describe "validate_optional_boolean/1" do
    test "accepts boolean" do
      assert {:ok, true} = AIValidator.validate_optional_boolean(true)
    end

    test "defaults nil to false" do
      assert {:ok, false} = AIValidator.validate_optional_boolean(nil)
    end

    test "accepts custom default" do
      assert {:ok, true} = AIValidator.validate_optional_boolean(nil, true)
    end
  end

  describe "validate_request/2" do
    test "validates all parameters successfully" do
      params = %{
        "text" => "Hello world",
        "thread_id" => "123e4567-e89b-12d3-a456-426614174000",
        "limit" => "10"
      }

      validators = [
        {:text, &AIValidator.validate_text/1},
        {:thread_id, &AIValidator.validate_thread_id/1},
        {:limit, &AIValidator.validate_limit/1}
      ]

      assert {:ok, result} = AIValidator.validate_request(params, validators)
      assert result.text == "Hello world"
      assert result.thread_id == "123e4567-e89b-12d3-a456-426614174000"
      assert result.limit == 10
    end

    test "returns first error encountered" do
      params = %{
        "text" => "Valid text",
        "thread_id" => "invalid-uuid",
        "limit" => "100"
      }

      validators = [
        {:text, &AIValidator.validate_text/1},
        {:thread_id, &AIValidator.validate_thread_id/1},
        {:limit, &AIValidator.validate_limit/1}
      ]

      assert {:error, "Thread ID must be a valid UUID"} = AIValidator.validate_request(params, validators)
    end

    test "handles missing parameters" do
      params = %{"text" => "Hello"}

      validators = [
        {:text, &AIValidator.validate_text/1},
        {:thread_id, &AIValidator.validate_thread_id/1}
      ]

      assert {:error, "Thread ID is required"} = AIValidator.validate_request(params, validators)
    end
  end

  describe "validate_with_default/3" do
    test "uses provided value if present" do
      assert {:ok, 10} = AIValidator.validate_with_default(10, &AIValidator.validate_limit/1, 20)
    end

    test "uses default if value is nil" do
      assert {:ok, 20} = AIValidator.validate_with_default(nil, &AIValidator.validate_limit/1, 20)
    end

    test "validates provided value" do
      assert {:error, _} = AIValidator.validate_with_default(100, &AIValidator.validate_limit/1, 20)
    end
  end

  describe "security and DoS prevention" do
    test "prevents extremely long text attacks" do
      # Try to create a DoS with massive text
      huge_text = String.duplicate("a", 100_000)
      assert {:error, msg} = AIValidator.validate_text(huge_text)
      assert msg =~ "must not exceed"
    end

    test "prevents malformed UUID enumeration attacks" do
      malformed_uuids = [
        "' OR 1=1 --",
        "../../../etc/passwd",
        "<script>alert('xss')</script>",
        "123; DROP TABLE messages;--"
      ]

      for uuid <- malformed_uuids do
        assert {:error, "Thread ID must be a valid UUID"} = AIValidator.validate_thread_id(uuid)
      end
    end

    test "prevents integer overflow attacks on limit" do
      assert {:error, _} = AIValidator.validate_limit(999_999_999)
      assert {:error, _} = AIValidator.validate_limit(-999_999_999)
    end

    test "prevents resource exhaustion via limit parameter" do
      assert {:error, "Limit must be between 1 and 50"} = AIValidator.validate_limit(1_000_000)
    end

    test "handles unicode normalization attacks" do
      # Unicode characters that might bypass length checks
      unicode_attack = "a\u0301\u0301\u0301\u0301\u0301"
      assert {:ok, _} = AIValidator.validate_text(unicode_attack)
    end

    test "prevents empty string attacks after whitespace trimming" do
      whitespace_strings = [
        "   ",
        "\t\t\t",
        "\n\n\n",
        "\r\n\r\n"
      ]

      for ws <- whitespace_strings do
        assert {:error, "Text must be a non-empty string"} = AIValidator.validate_text(ws)
      end
    end
  end
end
