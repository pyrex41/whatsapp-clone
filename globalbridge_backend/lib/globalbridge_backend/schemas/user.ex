defmodule GlobalbridgeBackend.Schemas.User do
  @moduledoc """
  User schema for authentication and profile management.
  Stored in users.db (shared database).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field(:username, :string)
    field(:phone_number, :string)
    field(:password_hash, :string)
    field(:display_name, :string)
    field(:avatar_url, :string)
    field(:status_message, :string)
    field(:public_key, :string)
    field(:last_seen_at, :utc_datetime)
    field(:is_online, :boolean, default: false)
    field(:tier, :string, default: "free")
    field(:auth0_id, :string)
    field(:email, :string)
    field(:auth0_metadata, :map, default: %{})
    field(:auth0_refresh_token, :string)

    # Language preference for AI translation
    field(:preferred_language, :string, default: "en")

    # Associations
    has_many(:devices, GlobalbridgeBackend.Schemas.Device)
    has_many(:thread_participants, GlobalbridgeBackend.Schemas.ThreadParticipant)
    has_many(:threads, through: [:thread_participants, :thread])

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for user creation.
  """
  def create_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :username,
      :phone_number,
      :password_hash,
      :display_name,
      :avatar_url,
      :status_message,
      :public_key,
      :preferred_language,
      :auth0_id,
      :email,
      :auth0_metadata,
      :auth0_refresh_token
    ])
    |> validate_required([:username])
    |> validate_format(:phone_number, ~r/^\+[1-9]\d{1,14}$/,
      message: "must be valid E.164 format"
    )
    |> validate_length(:username, min: 3, max: 30)
    |> validate_length(:display_name, max: 50)
    |> validate_length(:status_message, max: 139)
    |> unique_constraint(:username)
    |> unique_constraint(:phone_number)
    |> unique_constraint(:auth0_id)
    |> unique_constraint(:email)
  end

  @doc """
  Changeset for user updates.
  """
  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [
      :display_name,
      :avatar_url,
      :status_message,
      :public_key,
      :preferred_language,
      :last_seen_at,
      :is_online,
      :tier
    ])
    |> validate_length(:display_name, max: 50)
    |> validate_length(:status_message, max: 139)
    |> validate_inclusion(:tier, ["free", "pro", "enterprise"])
  end

  @doc """
  Changeset for password updates.
  """
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password_hash])
    |> validate_required([:password_hash])
  end
end
