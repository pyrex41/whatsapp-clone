defmodule GlobalbridgeBackend.Schemas.Device do
  @moduledoc """
  Device schema for multi-device support.
  Stored in users.db (shared database).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "devices" do
    field :device_id, :string
    field :device_name, :string
    field :device_type, :string  # "ios", "android", "web", "desktop"
    field :push_token, :string
    field :last_active_at, :utc_datetime
    field :is_active, :boolean, default: true

    belongs_to :user, GlobalbridgeBackend.Schemas.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for device registration.
  """
  def create_changeset(device, attrs) do
    device
    |> cast(attrs, [:device_id, :device_name, :device_type, :push_token, :user_id])
    |> validate_required([:device_id, :device_name, :device_type, :user_id])
    |> validate_inclusion(:device_type, ["ios", "android", "web", "desktop"])
    |> unique_constraint(:device_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for device updates.
  """
  def update_changeset(device, attrs) do
    device
    |> cast(attrs, [:device_name, :push_token, :last_active_at, :is_active])
    |> validate_required([:device_name])
  end
end
