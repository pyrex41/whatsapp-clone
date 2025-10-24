defmodule GlobalbridgeBackend.Contexts.Messaging do
  @moduledoc """
  The Messaging context provides business logic for threads, messages, and bridges.
  Handles both thread metadata (in users.db), per-thread message sharding (in threads/{thread_id}.db),
  and bridge configurations (in bridges.db).
  """

  alias GlobalbridgeBackend.Contexts.{Threads, Messages, Bridges}

  @doc """
  Delegates to Threads context.
  """
  defdelegate list_threads(filters \\ []), to: Threads
  defdelegate get_thread!(id), to: Threads
  defdelegate get_thread(id), to: Threads
  defdelegate create_thread(attrs), to: Threads
  defdelegate update_thread(thread, attrs), to: Threads
  defdelegate delete_thread(thread), to: Threads
  defdelegate archive_thread(thread), to: Threads
  defdelegate unarchive_thread(thread), to: Threads
  defdelegate mute_thread(thread), to: Threads
  defdelegate unmute_thread(thread), to: Threads
  defdelegate add_participant(thread, user_id, role \\ "member"), to: Threads
  defdelegate remove_participant(thread, user_id), to: Threads
  defdelegate list_participants(thread), to: Threads
  defdelegate get_thread_for_direct_message(user_id_1, user_id_2), to: Threads
  defdelegate list_user_threads(user_id, filters \\ []), to: Threads
  defdelegate search_threads(query, filters \\ []), to: Threads

  @doc """
  Delegates to Messages context.
  """
  defdelegate list_messages(thread_id, filters \\ []), to: Messages
  defdelegate get_message!(thread_id, message_id), to: Messages
  defdelegate get_message(thread_id, message_id), to: Messages
  defdelegate create_message(thread_id, attrs), to: Messages
  defdelegate update_message(thread_id, message, attrs), to: Messages
  defdelegate edit_message(thread_id, message, content), to: Messages
  defdelegate delete_message(thread_id, message), to: Messages
  defdelegate mark_as_read(thread_id, message_id, user_id), to: Messages
  defdelegate get_unread_count(thread_id, user_id), to: Messages
  defdelegate search_messages(thread_id, query, filters \\ []), to: Messages
  defdelegate get_thread_messages_after(thread_id, timestamp, limit \\ 50), to: Messages
  defdelegate get_thread_messages_before(thread_id, timestamp, limit \\ 50), to: Messages

  @doc """
  Delegates to Bridges context.
  """
  defdelegate list_bridges(filters \\ []), to: Bridges
  defdelegate get_bridge!(id), to: Bridges
  defdelegate get_bridge(id), to: Bridges
  defdelegate get_bridge_by_user_and_type(user_id, bridge_type), to: Bridges
  defdelegate create_bridge(attrs), to: Bridges
  defdelegate update_bridge_session(bridge, attrs), to: Bridges
  defdelegate toggle_bridge_active(bridge, attrs), to: Bridges
  defdelegate update_bridge(bridge, attrs), to: Bridges
  defdelegate delete_bridge(bridge), to: Bridges
  defdelegate list_user_bridges(user_id, filters \\ []), to: Bridges
  defdelegate list_active_user_bridges(user_id), to: Bridges
  defdelegate count_bridges_by_status(user_id), to: Bridges
end
