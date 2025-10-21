defmodule GlobalbridgeBackend.Schemas.ThreadParticipant do
  @moduledoc """
  Join table for thread participants.
  Stored in users.db (shared database).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "thread_participants" do
    field :role, :string  # "admin", "member"
    field :joined_at, :utc_datetime
    field :left_at, :utc_datetime
    field :is_active, :boolean, default: true

    belongs_to :thread, GlobalbridgeBackend.Schemas.Thread
    belongs_to :user, GlobalbridgeBackend.Schemas.User

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for adding participant.
  """
  def create_changeset(participant, attrs) do
    participant
    |> cast(attrs, [:thread_id, :user_id, :role])
    |> validate_required([:thread_id, :user_id])
    |> validate_inclusion(:role, ["admin", "member"])
    |> put_change(:joined_at, DateTime.utc_now())
    |> put_change(:is_active, true)
    |> unique_constraint([:thread_id, :user_id])
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for participant removal.
  """
  def remove_changeset(participant, attrs \\ %{}) do
    participant
    |> cast(attrs, [:left_at, :is_active])
    |> put_change(:left_at, DateTime.utc_now())
    |> put_change(:is_active, false)
  end
end
