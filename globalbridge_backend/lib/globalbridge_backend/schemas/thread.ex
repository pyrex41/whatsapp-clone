defmodule GlobalbridgeBackend.Schemas.Thread do
  @moduledoc """
  Thread schema for conversations.
  Metadata stored in users.db, actual messages in per-thread database (threads/{thread_id}.db).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "threads" do
    # "direct", "group"
    field(:thread_type, :string)
    field(:title, :string)
    field(:avatar_url, :string)
    field(:last_message_at, :utc_datetime)
    field(:is_archived, :boolean, default: false)
    field(:is_muted, :boolean, default: false)

    # For sharding - indicates which database file this thread uses
    field(:database_shard_id, :string)

    # Associations
    has_many(:thread_participants, GlobalbridgeBackend.Schemas.ThreadParticipant)
    has_many(:participants, through: [:thread_participants, :user])

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for thread creation.
  """
  def create_changeset(thread, attrs) do
    thread
    |> cast(attrs, [:thread_type, :title, :avatar_url, :database_shard_id])
    |> validate_required([:thread_type, :database_shard_id])
    |> validate_inclusion(:thread_type, ["direct", "group"])
    |> validate_length(:title, max: 100)
    |> put_change(:last_message_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc """
  Changeset for thread updates.
  """
  def update_changeset(thread, attrs) do
    thread
    |> cast(attrs, [:title, :avatar_url, :last_message_at, :is_archived, :is_muted])
    |> validate_length(:title, max: 100)
  end
end
