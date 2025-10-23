defmodule GlobalbridgeBackendWeb.ThreadJSON do
  @moduledoc """
  JSON rendering helpers for thread resources consumed by mobile clients.
  """

  def index(%{threads: threads}) do
    %{
      data: Enum.map(threads, &thread_to_map/1)
    }
  end

  defp thread_to_map(thread) do
    %{
      id: thread.id,
      title: thread.title,
      thread_type: thread.thread_type,
      database_shard_id: thread.database_shard_id,
      is_archived: thread.is_archived,
      is_muted: thread.is_muted,
      last_message_at: format_timestamp(thread.last_message_at || thread.inserted_at),
      created_at: format_timestamp(thread.inserted_at),
      updated_at: format_timestamp(thread.updated_at),
      participants: Enum.map(thread.thread_participants, &participant_to_map/1)
    }
  end

  defp participant_to_map(participant) do
    %{
      id: participant.id,
      user_id: participant.user_id,
      role: participant.role,
      joined_at: format_timestamp(participant.inserted_at),
      is_active: participant.is_active
    }
  end

  defp format_timestamp(nil), do: nil

  defp format_timestamp(%NaiveDateTime{} = datetime),
    do: DateTime.from_naive!(datetime, "Etc/UTC") |> DateTime.to_iso8601()

  defp format_timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
