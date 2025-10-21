defmodule GlobalbridgeBackendWeb.SyncJSON do
  @moduledoc """
  JSON rendering for sync controller responses.
  """

  @doc """
  Renders successful pull response with CDC changes.
  """
  def pull_success(%{changes: changes, next_cursor: next_cursor}) do
    %{
      data: %{
        changes: Enum.map(changes, &render_cdc_change/1),
        next_cursor: next_cursor
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

  # Private rendering functions

  defp render_cdc_change(change) do
    %{
      id: change.id,
      table_name: change.table_name,
      record_id: change.record_id,
      operation: change.operation,
      old_data: change.old_data,
      new_data: change.new_data,
      changed_fields: change.changed_fields,
      timestamp: format_timestamp(change.timestamp)
    }
  end

  defp format_timestamp(nil), do: nil
  defp format_timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp format_timestamp(timestamp), do: timestamp
end
