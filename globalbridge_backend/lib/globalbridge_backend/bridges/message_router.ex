defmodule GlobalbridgeBackend.Bridges.MessageRouter do
  @moduledoc """
  Message Router for converting between external bridge formats and GlobalBridge internal format.

  This module handles:
  - Converting Telegram messages to GlobalBridge format
  - Converting GlobalBridge messages to Telegram format
  - Message deduplication and routing logic
  - User mapping between external platforms and GlobalBridge
  """

  require Logger

  alias GlobalbridgeBackend.Contexts.Messaging
  alias GlobalbridgeBackend.Schemas.Message
  alias GlobalbridgeBackend.Bridges.UserMapper

  @doc """
  Routes an incoming message from a bridge to GlobalBridge.

  Takes a parsed message from a bridge and converts it to GlobalBridge format,
  then creates the message in the appropriate thread.

  Returns {:ok, globalbridge_message} or {:error, reason}.
  """
  def route_incoming_message(bridge_id, parsed_message) do
    Logger.debug("Routing incoming message from bridge #{bridge_id}")

    try do
      # Check for message deduplication
      external_message_id = get_external_message_id(parsed_message)

      if external_message_id && message_already_processed?(external_message_id) do
        Logger.debug("Skipping duplicate message: #{external_message_id}")
        {:ok, :duplicate}
      else
        # Convert to GlobalBridge format
        case convert_to_globalbridge_format(bridge_id, parsed_message) do
          {:ok, gb_message_attrs} ->
            # Find or create thread for this conversation
            case find_or_create_thread(gb_message_attrs) do
              {:ok, thread} ->
                # Create the message
                case Messaging.create_message(thread.id, gb_message_attrs) do
                  {:ok, message} ->
                    # Broadcast the message to Phoenix channels
                    broadcast_message_to_channels(message, thread.id)

                    Logger.info(
                      "Created GlobalBridge message #{message.id} from bridge #{bridge_id}"
                    )

                    {:ok, message}

                  {:error, reason} ->
                    Logger.error("Failed to create GlobalBridge message: #{inspect(reason)}")
                    {:error, {:message_creation_failed, reason}}
                end

              {:error, reason} ->
                Logger.error("Failed to find/create thread: #{inspect(reason)}")
                {:error, {:thread_error, reason}}
            end

          {:error, reason} ->
            Logger.error("Failed to convert message format: #{inspect(reason)}")
            {:error, {:conversion_error, reason}}
        end
      end
    rescue
      error ->
        Logger.error("Exception in message routing: #{inspect(error)}")
        {:error, {:routing_exception, error}}
    end
  end

  @doc """
  Routes an outgoing message from GlobalBridge to a bridge.

  Takes a GlobalBridge message and converts it to the appropriate bridge format,
  then sends it via the bridge.

  Returns {:ok, bridge_response} or {:error, reason}.
  """
  def route_outgoing_message(bridge_id, globalbridge_message) do
    Logger.debug("Routing outgoing message to bridge #{bridge_id}")

    try do
      # Convert to bridge format
      case convert_from_globalbridge_format(bridge_id, globalbridge_message) do
        {:ok, bridge_message} ->
          # Send via bridge
          send_via_bridge(bridge_id, bridge_message)

        {:error, reason} ->
          Logger.error("Failed to convert message for bridge: #{inspect(reason)}")
          {:error, {:conversion_error, reason}}
      end
    rescue
      error ->
        Logger.error("Exception in outgoing message routing: #{inspect(error)}")
        {:error, {:routing_exception, error}}
    end
  end

  @doc """
  Converts a parsed bridge message to GlobalBridge message format.

  Returns {:ok, message_attrs} or {:error, reason}.
  """
  def convert_to_globalbridge_format(bridge_id, parsed_message) do
    case parsed_message do
      # Telegram message format
      %{message_id: telegram_id, chat_id: chat_id, text: text, from_user: from_user, date: date} ->
        # Map Telegram user to GlobalBridge user
        case UserMapper.map_telegram_user_to_globalbridge(from_user, bridge_id) do
          {:ok, gb_user_id} ->
            # Create message attributes
            message_attrs = %{
              content: text || "",
              message_type: "text",
              sender_id: gb_user_id,
              external_message_id: "telegram:#{telegram_id}",
              external_chat_id: "telegram:#{chat_id}",
              sent_at: date,
              metadata: %{
                bridge_id: bridge_id,
                platform: "telegram",
                telegram_message_id: telegram_id,
                telegram_chat_id: chat_id
              }
            }

            # Add attachments if present
            message_attrs =
              add_attachments_to_message(message_attrs, parsed_message[:attachments] || [])

            {:ok, message_attrs}

          {:error, reason} ->
            {:error, {:user_mapping_failed, reason}}
        end

      # Unknown format
      _ ->
        {:error, :unsupported_message_format}
    end
  end

  @doc """
  Converts a GlobalBridge message to bridge-specific format.

  Returns {:ok, bridge_message} or {:error, reason}.
  """
  def convert_from_globalbridge_format(bridge_id, %Message{} = gb_message) do
    # For now, only support Telegram
    case get_bridge_type(bridge_id) do
      "telegram" ->
        # Map GlobalBridge user to Telegram user
        case UserMapper.map_globalbridge_user_to_telegram(gb_message.sender_id, bridge_id) do
          {:ok, telegram_user_id} ->
            # Extract chat ID from message metadata or find appropriate chat
            chat_id = get_telegram_chat_id(gb_message)

            if chat_id do
              telegram_message = %{
                chat_id: chat_id,
                text: gb_message.content,
                # Could be implemented later
                reply_to_message_id: nil
              }

              {:ok, telegram_message}
            else
              {:error, :no_chat_id_found}
            end

          {:error, reason} ->
            {:error, {:user_mapping_failed, reason}}
        end

      _ ->
        {:error, :unsupported_bridge_type}
    end
  end

  # Private functions

  defp find_or_create_thread(message_attrs) do
    # Extract chat information from message
    external_chat_id = message_attrs[:external_chat_id]

    if external_chat_id do
      # Try to find existing thread for this chat
      case find_thread_by_external_chat_id(external_chat_id) do
        {:ok, thread} ->
          {:ok, thread}

        {:error, :not_found} ->
          # Create new thread for this chat
          create_thread_for_external_chat(message_attrs)
      end
    else
      {:error, :no_external_chat_id}
    end
  end

  defp find_thread_by_external_chat_id(external_chat_id) do
    # This would need to be implemented - search threads by external_chat_id
    # For now, return not found
    {:error, :not_found}
  end

  defp create_thread_for_external_chat(message_attrs) do
    # Create a new thread for the external chat
    # This is a simplified implementation
    thread_attrs = %{
      # Assume group chat for external chats
      thread_type: "group",
      # Would need better title extraction
      title: "Bridge Chat",
      # Add the sender as initial participant
      participant_ids: [message_attrs.sender_id]
    }

    Messaging.create_thread(thread_attrs)
  end

  defp add_attachments_to_message(message_attrs, attachments) do
    if Enum.empty?(attachments) do
      message_attrs
    else
      # Convert attachments to GlobalBridge format
      gb_attachments = Enum.map(attachments, &convert_attachment/1)

      Map.put(message_attrs, :attachments, gb_attachments)
    end
  end

  defp convert_attachment(attachment) do
    case attachment[:type] do
      :photo ->
        %{
          type: "image",
          # Would need actual file handling
          url: "placeholder",
          filename: "telegram_photo.jpg",
          size: attachment[:file_size] || 0
        }

      :document ->
        %{
          type: "file",
          url: "placeholder",
          filename: attachment[:file_name] || "telegram_document",
          size: attachment[:file_size] || 0
        }

      :audio ->
        %{
          type: "audio",
          url: "placeholder",
          filename: attachment[:file_name] || "telegram_audio",
          size: attachment[:file_size] || 0
        }

      _ ->
        %{
          type: "unknown",
          url: "placeholder",
          filename: "telegram_attachment",
          size: 0
        }
    end
  end

  defp send_via_bridge(bridge_id, bridge_message) do
    # Get the bridge server PID
    case GlobalbridgeBackend.Bridges.Registry.lookup_bridge(bridge_id) do
      {:ok, server_pid} ->
        case get_bridge_type(bridge_id) do
          "telegram" ->
            # Send via Telegram server
            case bridge_message do
              %{chat_id: chat_id, text: text} ->
                GlobalbridgeBackend.Bridges.Telegram.Server.send_message(
                  server_pid,
                  chat_id,
                  text
                )

              _ ->
                {:error, :unsupported_message_format}
            end

          _ ->
            {:error, :unsupported_bridge_type}
        end

      {:error, :not_found} ->
        {:error, :bridge_not_found}
    end
  end

  defp get_bridge_type(bridge_id) do
    # Use Cachex to prevent N+1 queries when routing multiple messages
    cache_key = "bridge_type:#{bridge_id}"

    case Cachex.get(:ai_cache, cache_key) do
      {:ok, nil} ->
        # Cache miss - fetch from database
        case GlobalbridgeBackend.Contexts.Bridges.get_bridge(bridge_id) do
          nil ->
            Logger.warning("Bridge #{bridge_id} not found in database")
            nil

          bridge ->
            # Cache for 5 minutes to prevent N+1 queries
            Cachex.put(:ai_cache, cache_key, bridge.bridge_type, ttl: :timer.minutes(5))
            bridge.bridge_type
        end

      {:ok, bridge_type} ->
        # Cache hit
        bridge_type

      {:error, reason} ->
        Logger.error("Cache error for bridge #{bridge_id}: #{inspect(reason)}")
        # Fallback to database query
        case GlobalbridgeBackend.Contexts.Bridges.get_bridge(bridge_id) do
          nil -> nil
          bridge -> bridge.bridge_type
        end
    end
  end

  defp get_telegram_chat_id(gb_message) do
    # Extract Telegram chat ID from message metadata
    # This would need proper implementation
    # Placeholder
    nil
  end

  defp get_external_message_id(parsed_message) do
    # Extract external message ID for deduplication
    case parsed_message do
      %{message_id: telegram_id} -> "telegram:#{telegram_id}"
      _ -> nil
    end
  end

  defp message_already_processed?(external_message_id) do
    # Check if message was already processed
    # Use a simple cache with TTL
    cache_key = "processed_message:#{external_message_id}"

    case :persistent_term.get(cache_key, nil) do
      nil -> false
      _ -> true
    end
  end

  defp mark_message_processed(external_message_id) do
    # Mark message as processed with TTL
    cache_key = "processed_message:#{external_message_id}"
    :persistent_term.put(cache_key, true)

    # In a real implementation, this would have a TTL
    # For now, messages stay "processed" indefinitely
  end

  defp broadcast_message_to_channels(message, thread_id) do
    # Broadcast message to Phoenix channels
    broadcast_message = %{
      id: message.id,
      thread_id: thread_id,
      sender_id: message.sender_id,
      content: message.content,
      content_type: message.message_type || "text",
      media_url: message.media_url,
      reply_to_id: message.reply_to_id,
      created_at: message.inserted_at,
      updated_at: message.updated_at,
      external_message_id: message.external_message_id,
      # Mark as coming from a bridge
      bridge_source: true
    }

    # Broadcast to the thread channel
    topic = "thread:#{thread_id}"
    event = "new_message"

    try do
      Phoenix.PubSub.broadcast(GlobalbridgeBackend.PubSub, topic, {event, broadcast_message})
      Logger.debug("Broadcast message #{message.id} to topic #{topic}")
    rescue
      error ->
        Logger.error("Failed to broadcast message #{message.id}: #{inspect(error)}")
    end
  end
end
