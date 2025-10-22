defmodule GlobalbridgeBackend.Schemas.ReadReceipt do
  @moduledoc """
  Read receipt schema for message read status.
  Stored in per-thread database (threads/{thread_id}.db).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "read_receipts" do
    field(:message_id, :binary_id)
    field(:user_id, :binary_id)
    field(:read_at, :utc_datetime)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for read receipt creation.
  """
  def create_changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [:message_id, :user_id, :read_at])
    |> validate_required([:message_id, :user_id])
    |> put_change(:read_at, DateTime.utc_now())
    |> unique_constraint([:message_id, :user_id])
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:user_id)
  end
end
