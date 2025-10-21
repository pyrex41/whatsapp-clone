defmodule GlobalbridgeBackendWeb.SyncJSON do
  @moduledoc """
  JSON rendering for sync controller responses.
  """

  alias GlobalbridgeBackend.Sync

  @doc """
  Renders successful pull response with CDC changes.
  """
  def pull_success(%{changes: changes, cursor: cursor}) do
    %{
      data: %{
        changes: Enum.map(changes, &Sync.format_change/1),
        next_cursor: format_timestamp(cursor)
      }
    }
  end

  @doc """
  Renders successful push response with application results.
  """
  def push_success(%{applied: applied, failed: failed, results: results}) do
    %{
      data: %{
        applied: applied,
        failed: failed,
        results: results
      }
    }
  end

  defp format_timestamp(nil), do: nil
  defp format_timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_timestamp(timestamp), do: timestamp
end
