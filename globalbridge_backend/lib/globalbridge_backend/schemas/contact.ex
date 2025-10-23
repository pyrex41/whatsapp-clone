defmodule GlobalbridgeBackend.Schemas.Contact do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "contacts" do
    belongs_to(:user, GlobalbridgeBackend.Schemas.User)
    belongs_to(:contact_user, GlobalbridgeBackend.Schemas.User)
    field(:display_name_override, :string)
    field(:is_favorite, :boolean, default: false)
    field(:notes, :string)

    timestamps(type: :utc_datetime)
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [:user_id, :contact_user_id, :display_name_override, :is_favorite, :notes])
    |> validate_required([:user_id, :contact_user_id])
    |> unique_constraint([:user_id, :contact_user_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:contact_user_id)
    |> validate_not_self_contact()
  end

  defp validate_not_self_contact(changeset) do
    user_id = get_field(changeset, :user_id)
    contact_user_id = get_field(changeset, :contact_user_id)

    if user_id && contact_user_id && user_id == contact_user_id do
      add_error(changeset, :contact_user_id, "cannot add yourself as a contact")
    else
      changeset
    end
  end
end
