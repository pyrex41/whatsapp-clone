defmodule GlobalbridgeBackend.Schemas.SyncState do
  @moduledoc """
  Sync state schema for CDC (Change Data Capture) tracking.
  Stored in sync_state.db (shared database).
  Used for multi-device synchronization.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "sync_states" do
    field(:device_id, :binary_id)
    field(:thread_id, :binary_id)
    # "message", "thread", "user"
    field(:entity_type, :string)
    field(:entity_id, :binary_id)
    # "insert", "update", "delete"
    field(:operation, :string)
    field(:last_sync_at, :utc_datetime)
    field(:sync_cursor, :integer)
    field(:is_synced, :boolean, default: false)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for sync state creation.
  """
  def create_changeset(sync_state, attrs) do
    sync_state
    |> cast(attrs, [:device_id, :thread_id, :entity_type, :entity_id, :operation, :sync_cursor])
    |> validate_required([:device_id, :entity_type, :entity_id, :operation])
    |> validate_inclusion(:entity_type, ["message", "thread", "user", "read_receipt"])
    |> validate_inclusion(:operation, ["insert", "update", "delete"])
    |> foreign_key_constraint(:device_id)
    |> foreign_key_constraint(:thread_id)
  end

  @doc """
  Changeset for marking as synced.
  """
  def synced_changeset(sync_state, attrs \\ %{}) do
    sync_state
    |> cast(attrs, [:last_sync_at, :is_synced])
    |> put_change(:last_sync_at, DateTime.utc_now())
    |> put_change(:is_synced, true)
  end
end
