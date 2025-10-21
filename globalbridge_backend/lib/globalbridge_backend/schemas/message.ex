defmodule GlobalbridgeBackend.Schemas.Message do
  @moduledoc """
  Message schema for chat messages.
  Stored in per-thread database (threads/{thread_id}.db) for sharding.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "messages" do
    field :thread_id, :binary_id
    field :sender_id, :binary_id
    field :content, :string
    field :content_type, :string  # "text", "image", "video", "audio", "file", "location"
    field :media_url, :string
    field :media_size, :integer
    field :media_mime_type, :string
    field :is_encrypted, :boolean, default: false
    field :encryption_key_id, :string
    field :reply_to_id, :binary_id
    field :is_deleted, :boolean, default: false
    field :deleted_at, :utc_datetime
    field :edited_at, :utc_datetime

    # Client-side timestamps for CDC sync
    field :client_created_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for message creation.
  """
  def create_changeset(message, attrs) do
    message
    |> cast(attrs, [
      :thread_id,
      :sender_id,
      :content,
      :content_type,
      :media_url,
      :media_size,
      :media_mime_type,
      :is_encrypted,
      :encryption_key_id,
      :reply_to_id,
      :client_created_at
    ])
    |> validate_required([:thread_id, :sender_id, :content_type])
    |> validate_inclusion(:content_type, ["text", "image", "video", "audio", "file", "location"])
    |> validate_message_content()
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:sender_id)
    |> foreign_key_constraint(:reply_to_id)
  end

  @doc """
  Changeset for message editing.
  """
  def edit_changeset(message, attrs) do
    message
    |> cast(attrs, [:content])
    |> validate_required([:content])
    |> put_change(:edited_at, DateTime.utc_now())
  end

  @doc """
  Changeset for message deletion.
  """
  def delete_changeset(message, _attrs \\ %{}) do
    message
    |> change()
    |> put_change(:is_deleted, true)
    |> put_change(:deleted_at, DateTime.utc_now())
  end

  defp validate_message_content(changeset) do
    content_type = get_field(changeset, :content_type)

    case content_type do
      "text" ->
        changeset
        |> validate_required([:content])
        |> validate_length(:content, min: 1, max: 10_000)

      _ ->
        # Media messages should have media_url
        validate_required(changeset, [:media_url])
    end
  end
end
