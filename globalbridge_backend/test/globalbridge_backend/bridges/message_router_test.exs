defmodule GlobalbridgeBackend.Bridges.MessageRouterTest do
  use GlobalbridgeBackend.DataCase, async: true

  alias GlobalbridgeBackend.Bridges.MessageRouter

  describe "convert_to_globalbridge_format/2" do
    test "converts Telegram message to GlobalBridge format" do
      telegram_message = %{
        message_id: 123,
        chat_id: 456,
        text: "Hello from Telegram!",
        from_user: %{id: 789, username: "telegram_user"},
        date: ~U[2024-01-01 12:00:00Z]
      }

      {:ok, result} = MessageRouter.convert_to_globalbridge_format("bridge_123", telegram_message)

      assert result.content == "Hello from Telegram!"
      assert result.message_type == "text"
      assert result.external_message_id == "telegram:123"
      assert result.external_chat_id == "telegram:456"
      assert result.sent_at == ~U[2024-01-01 12:00:00Z]
      assert result.metadata.platform == "telegram"
      assert result.metadata.bridge_id == "bridge_123"
      assert result.metadata.telegram_message_id == 123
      assert result.metadata.telegram_chat_id == 456
    end

    test "handles messages without text" do
      telegram_message = %{
        message_id: 123,
        chat_id: 456,
        from_user: %{id: 789, username: "telegram_user"},
        date: ~U[2024-01-01 12:00:00Z]
      }

      {:ok, result} = MessageRouter.convert_to_globalbridge_format("bridge_123", telegram_message)

      assert result.content == ""
      assert result.message_type == "text"
    end

    test "includes attachments when present" do
      telegram_message = %{
        message_id: 123,
        chat_id: 456,
        text: "Message with photo",
        from_user: %{id: 789, username: "telegram_user"},
        date: ~U[2024-01-01 12:00:00Z],
        attachments: [
          %{type: "photo", url: "https://example.com/photo.jpg", name: "photo.jpg", size: 1024}
        ]
      }

      {:ok, result} = MessageRouter.convert_to_globalbridge_format("bridge_123", telegram_message)

      assert length(result.attachments) == 1
      attachment = hd(result.attachments)
      assert attachment.type == "photo"
      assert attachment.url == "https://example.com/photo.jpg"
      assert attachment.name == "photo.jpg"
      assert attachment.size == 1024
    end

    test "returns error for unsupported message format" do
      unsupported_message = %{unsupported: "format"}

      {:error, :unsupported_message_format} =
        MessageRouter.convert_to_globalbridge_format("bridge_123", unsupported_message)
    end
  end

  describe "convert_from_globalbridge_format/2" do
    test "converts GlobalBridge message to Telegram format" do
      gb_message = %{
        id: "msg_123",
        content: "Hello from GlobalBridge!",
        sender_id: "user_456",
        metadata: %{reply_to_id: "reply_789"}
      }

      {:ok, telegram_message} =
        MessageRouter.convert_from_globalbridge_format("bridge_123", gb_message)

      assert telegram_message.text == "Hello from GlobalBridge!"
      assert telegram_message.reply_to_message_id == "reply_789"
    end

    test "handles messages without metadata" do
      gb_message = %{
        id: "msg_123",
        content: "Simple message",
        sender_id: "user_456"
      }

      {:ok, telegram_message} =
        MessageRouter.convert_from_globalbridge_format("bridge_123", gb_message)

      assert telegram_message.text == "Simple message"
      refute Map.has_key?(telegram_message, :reply_to_message_id)
    end
  end
end
