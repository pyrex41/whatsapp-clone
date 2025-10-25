defmodule GlobalbridgeBackend.Repo.Migrations.AddAuth0MetadataToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:auth0_metadata, :text, default: "{}")
      add(:auth0_refresh_token, :text)
    end
  end
end
