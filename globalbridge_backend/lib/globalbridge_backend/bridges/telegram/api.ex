defmodule GlobalbridgeBackend.Bridges.Telegram.API do
  @moduledoc """
  Telegram Bot API client using Req.

  Handles HTTP requests to the Telegram Bot API with proper error handling,
  rate limiting, and response parsing.
  """

  require Logger

  @base_url "https://api.telegram.org/bot"

  @doc """
  Gets bot information.

  Returns {:ok, bot_info} or {:error, reason}.
  """
  def get_me(token) do
    request(token, "getMe")
  end

  @doc """
  Gets updates from the Telegram API.

  offset: Identifier of the first update to be returned
  Returns {:ok, updates} or {:error, reason}.
  """
  def get_updates(token, offset \\ nil, opts \\ []) do
    params = %{}
    params = if offset, do: Map.put(params, :offset, offset), else: params
    params = Map.merge(params, Map.new(opts))

    request(token, "getUpdates", params)
  end

  @doc """
  Sends a message to a chat.

  Returns {:ok, message} or {:error, reason}.
  """
  def send_message(token, chat_id, text, opts \\ []) do
    params = %{
      chat_id: chat_id,
      text: text
    }

    params = Map.merge(params, Map.new(opts))

    request(token, "sendMessage", params)
  end

  @doc """
  Sends a photo to a chat.

  Returns {:ok, message} or {:error, reason}.
  """
  def send_photo(token, chat_id, photo, opts \\ []) do
    params = %{
      chat_id: chat_id,
      photo: photo
    }

    params = Map.merge(params, Map.new(opts))

    request(token, "sendPhoto", params)
  end

  @doc """
  Sends a document to a chat.

  Returns {:ok, message} or {:error, reason}.
  """
  def send_document(token, chat_id, document, opts \\ []) do
    params = %{
      chat_id: chat_id,
      document: document
    }

    params = Map.merge(params, Map.new(opts))

    request(token, "sendDocument", params)
  end

  @doc """
  Sets a webhook for receiving updates.

  Returns {:ok, result} or {:error, reason}.
  """
  def set_webhook(token, url, opts \\ []) do
    params = %{url: url}
    params = Map.merge(params, Map.new(opts))

    request(token, "setWebhook", params)
  end

  @doc """
  Deletes a webhook.

  Returns {:ok, result} or {:error, reason}.
  """
  def delete_webhook(token) do
    request(token, "deleteWebhook")
  end

  @doc """
  Gets webhook info.

  Returns {:ok, webhook_info} or {:error, reason}.
  """
  def get_webhook_info(token) do
    request(token, "getWebhookInfo")
  end

  @doc """
  Parses a Telegram message into a standardized format.

  Returns {:ok, parsed_message} or {:error, reason}.
  """
  def parse_message(message) do
    try do
      parsed = %{
        message_id: message["message_id"],
        chat_id: message["chat"]["id"],
        chat_type: message["chat"]["type"],
        chat_title: message["chat"]["title"],
        from_user: parse_user(message["from"]),
        date: DateTime.from_unix!(message["date"]),
        text: message["text"],
        entities: message["entities"] || [],
        attachments: parse_attachments(message)
      }

      {:ok, parsed}
    rescue
      error ->
        Logger.error("Failed to parse Telegram message: #{inspect(error)}")
        {:error, :parse_error}
    end
  end

  @doc """
  Parses a Telegram user into a standardized format.
  """
  def parse_user(nil), do: nil

  def parse_user(user) do
    %{
      id: user["id"],
      first_name: user["first_name"],
      last_name: user["last_name"],
      username: user["username"],
      is_bot: user["is_bot"]
    }
  end

  # Private functions

  defp request(token, method, params \\ %{}) do
    url = "#{@base_url}#{token}/#{method}"

    # Apply rate limiting
    case apply_rate_limit(token, method) do
      :ok ->
        case Req.post(url, json: params) do
          {:ok, %Req.Response{status: 200, body: %{"ok" => true, "result" => result}}} ->
            {:ok, result}

          {:ok, %Req.Response{status: 200, body: %{"ok" => false, "description" => description}}} ->
            {:error, description}

          {:ok, %Req.Response{status: status, body: body}} ->
            Logger.error("Telegram API error: status=#{status}, body=#{inspect(body)}")
            {:error, "HTTP #{status}"}

          {:error, error} ->
            Logger.error("Telegram API request failed: #{inspect(error)}")
            {:error, :network_error}
        end

      {:error, :rate_limited} ->
        Logger.warning("Rate limited for Telegram API call: #{method}")
        {:error, :rate_limited}
    end
  end

  defp apply_rate_limit(token, method) do
    # Use a simple token bucket approach
    # Telegram allows 30 requests per second globally
    key = "telegram_api:#{token}"

    case :persistent_term.get(key, {0, 0}) do
      {count, timestamp} ->
        now = System.monotonic_time(:millisecond)
        time_diff = now - timestamp

        # Reset counter if more than 1 second has passed
        {new_count, new_timestamp} =
          if time_diff > 1000 do
            {1, now}
          else
            {count + 1, timestamp}
          end

        :persistent_term.put(key, {new_count, new_timestamp})

        if new_count > 30 do
          # Calculate backoff time
          backoff_ms = min(1000, 100 * (new_count - 30))
          Process.sleep(backoff_ms)
          :ok
        else
          :ok
        end

      _ ->
        :persistent_term.put(key, {1, System.monotonic_time(:millisecond)})
        :ok
    end
  end

  defp retry_strategy({req, %{resp_headers: resp_headers}}) do
    # Check for rate limiting or server errors
    status = req.status

    cond do
      status == 429 ->
        # Rate limited - exponential backoff
        retry_count = req.retry_count || 0
        # 1s, 2s, 4s, 8s...
        delay = trunc(:math.pow(2, retry_count) * 1000)
        {req, delay}

      status >= 500 ->
        # Server error - retry with backoff
        retry_count = req.retry_count || 0

        if retry_count < 3 do
          delay = trunc(:math.pow(2, retry_count) * 1000)
          {req, delay}
        else
          :error
        end

      true ->
        :error
    end
  end

  defp parse_attachments(message) do
    attachments = []

    # Parse photos
    attachments =
      if message["photo"] do
        # Get highest resolution
        photo = List.last(message["photo"])

        [
          %{
            type: :photo,
            file_id: photo["file_id"],
            width: photo["width"],
            height: photo["height"]
          }
          | attachments
        ]
      else
        attachments
      end

    # Parse documents
    attachments =
      if message["document"] do
        doc = message["document"]

        [
          %{
            type: :document,
            file_id: doc["file_id"],
            file_name: doc["file_name"],
            mime_type: doc["mime_type"]
          }
          | attachments
        ]
      else
        attachments
      end

    # Parse audio
    attachments =
      if message["audio"] do
        audio = message["audio"]

        [
          %{
            type: :audio,
            file_id: audio["file_id"],
            duration: audio["duration"],
            title: audio["title"]
          }
          | attachments
        ]
      else
        attachments
      end

    # Parse voice messages
    attachments =
      if message["voice"] do
        voice = message["voice"]
        [%{type: :voice, file_id: voice["file_id"], duration: voice["duration"]} | attachments]
      else
        attachments
      end

    # Parse videos
    attachments =
      if message["video"] do
        video = message["video"]

        [
          %{
            type: :video,
            file_id: video["file_id"],
            duration: video["duration"],
            width: video["width"],
            height: video["height"]
          }
          | attachments
        ]
      else
        attachments
      end

    attachments
  end

  defp apply_rate_limit(token, method) do
    # Use a simple token bucket approach
    # Telegram allows 30 requests per second globally
    key = "telegram_api:#{token}"

    case :persistent_term.get(key, {0, 0}) do
      {count, timestamp} ->
        now = System.monotonic_time(:millisecond)
        time_diff = now - timestamp

        # Reset counter if more than 1 second has passed
        {new_count, new_timestamp} =
          if time_diff > 1000 do
            {1, now}
          else
            {count + 1, timestamp}
          end

        :persistent_term.put(key, {new_count, new_timestamp})

        if new_count > 30 do
          # Calculate backoff time
          backoff_ms = min(1000, 100 * (new_count - 30))
          Process.sleep(backoff_ms)
          :ok
        else
          :ok
        end

      _ ->
        :persistent_term.put(key, {1, System.monotonic_time(:millisecond)})
        :ok
    end
  end
end
