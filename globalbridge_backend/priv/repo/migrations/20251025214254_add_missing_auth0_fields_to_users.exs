defmodule GlobalbridgeBackend.Repo.Migrations.AddMissingAuth0FieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:auth0_metadata, :map, default: %{})
      add(:auth0_refresh_token, :text)
    end
  end
end
