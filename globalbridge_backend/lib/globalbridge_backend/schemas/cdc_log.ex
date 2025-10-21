defmodule GlobalbridgeBackend.Schemas.CDCLog do
  @moduledoc """
  Change Data Capture log schema for tracking all database changes.
  Stored in sync_state.db (shared database).
  Used for replication and multi-device sync.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "cdc_logs" do
    field :table_name, :string
    field :record_id, :binary_id
    field :operation, :string  # "INSERT", "UPDATE", "DELETE"
    field :old_data, :map
    field :new_data, :map
    field :changed_fields, {:array, :string}
    field :user_id, :binary_id
    field :device_id, :binary_id
    field :timestamp, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Changeset for CDC log creation.
  """
  def create_changeset(log, attrs) do
    log
    |> cast(attrs, [
      :table_name,
      :record_id,
      :operation,
      :old_data,
      :new_data,
      :changed_fields,
      :user_id,
      :device_id,
      :timestamp
    ])
    |> validate_required([:table_name, :record_id, :operation, :new_data])
    |> validate_inclusion(:operation, ["INSERT", "UPDATE", "DELETE"])
    |> put_change(:timestamp, DateTime.utc_now())
  end
end
