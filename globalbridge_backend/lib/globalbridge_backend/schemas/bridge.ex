defmodule GlobalbridgeBackend.Schemas.Bridge do
  @moduledoc """
  Bridge schema for WhatsApp bridge configurations.
  Stored in bridges.db (shared database).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bridges" do
    field(:user_id, :binary_id)
    # "whatsapp", "telegram", etc.
    field(:bridge_type, :string)
    field(:phone_number, :string)
    # Encrypted session data
    field(:session_data, :map)
    # "connected", "disconnected", "error"
    field(:status, :string)
    field(:last_connected_at, :utc_datetime)
    field(:error_message, :string)
    # For initial connection
    field(:qr_code, :string)
    field(:is_active, :boolean, default: true)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for bridge creation.
  """
  def create_changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:user_id, :bridge_type, :phone_number])
    |> validate_required([:user_id, :bridge_type, :phone_number])
    |> validate_inclusion(:bridge_type, ["whatsapp", "telegram"])
    |> validate_format(:phone_number, ~r/^\+[1-9]\d{1,14}$/)
    |> put_change(:status, "disconnected")
    |> unique_constraint([:user_id, :bridge_type])
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for bridge session update.
  """
  def session_changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:session_data, :status, :last_connected_at, :error_message, :qr_code])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["connected", "disconnected", "error", "connecting"])
  end

  @doc """
  Changeset for bridge activation toggle.
  """
  def toggle_changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:is_active])
    |> validate_required([:is_active])
  end
end
