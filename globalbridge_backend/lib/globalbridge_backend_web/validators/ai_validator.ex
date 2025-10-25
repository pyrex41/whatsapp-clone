defmodule GlobalbridgeBackendWeb.Validators.AIValidator do
  @moduledoc """
  Input validation for AI endpoints to prevent DoS attacks and ensure data quality.

  This module provides comprehensive validation for all AI endpoint inputs including:
  - Text content validation (length limits)
  - UUID format validation for thread IDs
  - Numeric range validation for limits and parameters
  - String sanitization and format checking
  """

  @max_text_length 10_000
  @max_query_length 1_000
  @min_limit 1
  @max_limit 50
  @min_max_length 1
  @max_max_length 1_000
  @valid_languages ~w(en es fr de it pt ja zh ko ru ar hi)
  @valid_tones ~w(formal informal neutral professional casual)

  @doc """
  Validates text input for general AI operations.

  ## Parameters
    - text: String to validate

  ## Returns
    - {:ok, text} if valid
    - {:error, message} if invalid

  ## Examples
      iex> AIValidator.validate_text("Hello world")
      {:ok, "Hello world"}

      iex> AIValidator.validate_text(nil)
      {:error, "Text must be a non-empty string"}

      iex> AIValidator.validate_text(String.duplicate("a", 10_001))
      {:error, "Text must not exceed 10,000 characters"}
  """
  def validate_text(text) when is_binary(text) do
    cond do
      String.trim(text) == "" ->
        {:error, "Text must be a non-empty string"}

      byte_size(text) > @max_text_length ->
        {:error, "Text must not exceed #{format_number(@max_text_length)} characters"}

      true ->
        {:ok, String.trim(text)}
    end
  end

  def validate_text(nil), do: {:error, "Text must be a non-empty string"}
  def validate_text(_), do: {:error, "Text must be a string"}

  @doc """
  Validates search query input.

  ## Parameters
    - query: Search query string to validate

  ## Returns
    - {:ok, query} if valid
    - {:error, message} if invalid

  ## Examples
      iex> AIValidator.validate_query("project deadline")
      {:ok, "project deadline"}

      iex> AIValidator.validate_query("")
      {:error, "Query must be a non-empty string"}
  """
  def validate_query(query) when is_binary(query) do
    cond do
      String.trim(query) == "" ->
        {:error, "Query must be a non-empty string"}

      byte_size(query) > @max_query_length ->
        {:error, "Query must not exceed #{format_number(@max_query_length)} characters"}

      true ->
        {:ok, String.trim(query)}
    end
  end

  def validate_query(nil), do: {:error, "Query must be a non-empty string"}
  def validate_query(_), do: {:error, "Query must be a string"}

  @doc """
  Validates thread ID format (must be valid UUID).

  ## Parameters
    - id: Thread ID to validate

  ## Returns
    - {:ok, uuid} if valid UUID format
    - {:error, message} if invalid

  ## Examples
      iex> AIValidator.validate_thread_id("123e4567-e89b-12d3-a456-426614174000")
      {:ok, "123e4567-e89b-12d3-a456-426614174000"}

      iex> AIValidator.validate_thread_id("invalid-uuid")
      {:error, "Thread ID must be a valid UUID"}
  """
  def validate_thread_id(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, "Thread ID must be a valid UUID"}
    end
  end

  def validate_thread_id(nil), do: {:error, "Thread ID is required"}
  def validate_thread_id(_), do: {:error, "Thread ID must be a string"}

  @doc """
  Validates optional thread ID (allows nil).

  ## Parameters
    - id: Thread ID to validate (can be nil)

  ## Returns
    - {:ok, uuid | nil} if valid or nil
    - {:error, message} if invalid
  """
  def validate_optional_thread_id(nil), do: {:ok, nil}
  def validate_optional_thread_id(id), do: validate_thread_id(id)

  @doc """
  Validates limit parameter for pagination/results.

  ## Parameters
    - limit: Integer limit value or parseable string

  ## Returns
    - {:ok, limit} if valid (between #{@min_limit} and #{@max_limit})
    - {:error, message} if invalid

  ## Examples
      iex> AIValidator.validate_limit(10)
      {:ok, 10}

      iex> AIValidator.validate_limit("25")
      {:ok, 25}

      iex> AIValidator.validate_limit(100)
      {:error, "Limit must be between 1 and 50"}
  """
  def validate_limit(limit) when is_integer(limit) do
    if limit >= @min_limit and limit <= @max_limit do
      {:ok, limit}
    else
      {:error, "Limit must be between #{@min_limit} and #{@max_limit}"}
    end
  end

  def validate_limit(limit) when is_binary(limit) do
    case Integer.parse(limit) do
      {num, ""} -> validate_limit(num)
      _ -> {:error, "Limit must be a valid integer"}
    end
  end

  def validate_limit(_), do: {:error, "Limit must be an integer"}

  @doc """
  Validates max_length parameter for summaries and text generation.

  ## Parameters
    - max_length: Maximum length value or parseable string

  ## Returns
    - {:ok, max_length} if valid (between #{@min_max_length} and #{@max_max_length})
    - {:error, message} if invalid

  ## Examples
      iex> AIValidator.validate_max_length(200)
      {:ok, 200}

      iex> AIValidator.validate_max_length("500")
      {:ok, 500}
  """
  def validate_max_length(max_length) when is_integer(max_length) do
    if max_length >= @min_max_length and max_length <= @max_max_length do
      {:ok, max_length}
    else
      {:error, "Max length must be between #{@min_max_length} and #{format_number(@max_max_length)}"}
    end
  end

  def validate_max_length(max_length) when is_binary(max_length) do
    case Integer.parse(max_length) do
      {num, ""} -> validate_max_length(num)
      _ -> {:error, "Max length must be a valid integer"}
    end
  end

  def validate_max_length(_), do: {:error, "Max length must be an integer"}

  @doc """
  Validates language code.

  ## Parameters
    - language: Language code (ISO 639-1 format)

  ## Returns
    - {:ok, language} if valid
    - {:error, message} if invalid

  ## Examples
      iex> AIValidator.validate_language("en")
      {:ok, "en"}

      iex> AIValidator.validate_language("invalid")
      {:error, "Language must be one of: en, es, fr, de, it, pt, ja, zh, ko, ru, ar, hi"}
  """
  def validate_language(language) when is_binary(language) do
    lang = String.downcase(language)

    if lang in @valid_languages do
      {:ok, lang}
    else
      {:error, "Language must be one of: #{Enum.join(@valid_languages, ", ")}"}
    end
  end

  def validate_language(_), do: {:error, "Language must be a string"}

  @doc """
  Validates optional language code (allows nil, defaults to "en").
  """
  def validate_optional_language(nil), do: {:ok, "en"}
  def validate_optional_language(language), do: validate_language(language)

  @doc """
  Validates optional target language code (allows nil for auto-detection).
  Returns {:ok, nil} when nil is provided to trigger language detection.
  """
  def validate_optional_target_language(nil), do: {:ok, nil}
  def validate_optional_target_language(language), do: validate_language(language)

  @doc """
  Validates tone parameter.

  ## Parameters
    - tone: Tone identifier

  ## Returns
    - {:ok, tone} if valid
    - {:error, message} if invalid
  """
  def validate_tone(tone) when is_binary(tone) do
    tone_lower = String.downcase(tone)

    if tone_lower in @valid_tones do
      {:ok, tone_lower}
    else
      {:error, "Tone must be one of: #{Enum.join(@valid_tones, ", ")}"}
    end
  end

  def validate_tone(_), do: {:error, "Tone must be a string"}

  @doc """
  Validates optional tone (allows nil).
  """
  def validate_optional_tone(nil), do: {:ok, nil}
  def validate_optional_tone(tone), do: validate_tone(tone)

  @doc """
  Validates boolean parameter.

  ## Parameters
    - value: Boolean value or string representation

  ## Returns
    - {:ok, boolean} if valid
    - {:error, message} if invalid

  ## Examples
      iex> AIValidator.validate_boolean(true)
      {:ok, true}

      iex> AIValidator.validate_boolean("true")
      {:ok, true}

      iex> AIValidator.validate_boolean("false")
      {:ok, false}
  """
  def validate_boolean(value) when is_boolean(value), do: {:ok, value}

  def validate_boolean(value) when is_binary(value) do
    case String.downcase(value) do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, "Value must be true or false"}
    end
  end

  def validate_boolean(_), do: {:error, "Value must be a boolean"}

  @doc """
  Validates optional boolean (allows nil, defaults to false).
  """
  def validate_optional_boolean(value, default \\ false)
  def validate_optional_boolean(nil, default), do: {:ok, default}
  def validate_optional_boolean(value, _default), do: validate_boolean(value)

  @doc """
  Validates a complete request with multiple parameters.
  Returns {:ok, validated_params} or {:error, first_error_message}.

  ## Examples
      iex> alias GlobalbridgeBackendWeb.Validators.AIValidator
      iex> params = %{"text" => "Hello", "thread_id" => "123e4567-e89b-12d3-a456-426614174000"}
      iex> validators = [
      ...>   {:text, &AIValidator.validate_text/1},
      ...>   {:thread_id, &AIValidator.validate_thread_id/1}
      ...> ]
      iex> AIValidator.validate_request(params, validators)
      {:ok, %{text: "Hello", thread_id: "123e4567-e89b-12d3-a456-426614174000"}}
  """
  def validate_request(params, validators) when is_map(params) and is_list(validators) do
    Enum.reduce_while(validators, {:ok, %{}}, fn {key, validator_fn}, {:ok, acc} ->
      param_key = to_string(key)
      value = Map.get(params, param_key)

      case validator_fn.(value) do
        {:ok, validated_value} ->
          {:cont, {:ok, Map.put(acc, key, validated_value)}}

        {:error, message} ->
          {:halt, {:error, message}}
      end
    end)
  end

  @doc """
  Validates and returns default value if parameter is missing.

  ## Examples
      iex> alias GlobalbridgeBackendWeb.Validators.AIValidator
      iex> AIValidator.validate_with_default(10, &AIValidator.validate_limit/1, 20)
      {:ok, 10}

      iex> alias GlobalbridgeBackendWeb.Validators.AIValidator
      iex> AIValidator.validate_with_default(nil, &AIValidator.validate_limit/1, 20)
      {:ok, 20}
  """
  def validate_with_default(nil, _validator_fn, default), do: {:ok, default}
  def validate_with_default(value, validator_fn, _default), do: validator_fn.(value)

  # Private helper to format numbers with commas
  defp format_number(num) when is_integer(num) do
    num
    |> Integer.to_string()
    |> String.reverse()
    |> String.split("", trim: true)
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end
end
