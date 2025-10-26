defmodule GlobalbridgeBackend.Schemas.UserTranslationPreference do
  @moduledoc """
  User-level translation preferences.
  Controls default translation behavior across all threads.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "user_translation_preferences" do
    field(:auto_translate_incoming, :boolean, default: true)
    field(:auto_translate_outgoing, :boolean, default: true)
    field(:show_translation_offers, :boolean, default: true)
    field(:default_translation_behavior, :string, default: "prompt")

    belongs_to(:user, GlobalbridgeBackend.Schemas.User)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating or updating translation preferences.
  """
  def changeset(preference, attrs) do
    preference
    |> cast(attrs, [
      :user_id,
      :auto_translate_incoming,
      :auto_translate_outgoing,
      :show_translation_offers,
      :default_translation_behavior
    ])
    |> validate_required([:user_id])
    |> validate_inclusion(:default_translation_behavior, ["prompt", "auto", "off"])
    |> unique_constraint(:user_id)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Gets or creates default preferences for a user.
  """
  def get_or_create_default(user_id, repo \\ GlobalbridgeBackend.Repo) do
    case repo.get_by(__MODULE__, user_id: user_id) do
      nil ->
        %__MODULE__{}
        |> changeset(%{user_id: user_id})
        |> repo.insert()

      preference ->
        {:ok, preference}
    end
  end
end
