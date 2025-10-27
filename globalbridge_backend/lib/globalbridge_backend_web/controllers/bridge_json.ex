defmodule GlobalbridgeBackendWeb.BridgeJSON do
  @moduledoc """
  JSON rendering helpers for bridge resources consumed by mobile clients.
  """

  def index(%{bridges: bridges}) do
    %{
      data: Enum.map(bridges, &bridge_to_map/1)
    }
  end

  def show(%{bridge: bridge}) do
    %{
      data: bridge_to_map(bridge)
    }
  end

  defp bridge_to_map(bridge) do
    %{
      id: bridge.id,
      user_id: bridge.user_id,
      bridge_type: bridge.bridge_type,
      phone_number: bridge.phone_number,
      status: bridge.status,
      last_connected_at: format_timestamp(bridge.last_connected_at),
      error_message: bridge.error_message,
      qr_code: bridge.qr_code,
      is_active: bridge.is_active,
      created_at: format_timestamp(bridge.inserted_at),
      updated_at: format_timestamp(bridge.updated_at)
    }
  end

  defp format_timestamp(nil), do: nil

  defp format_timestamp(%NaiveDateTime{} = datetime),
    do: DateTime.from_naive!(datetime, "Etc/UTC") |> DateTime.to_iso8601()

  defp format_timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
end
