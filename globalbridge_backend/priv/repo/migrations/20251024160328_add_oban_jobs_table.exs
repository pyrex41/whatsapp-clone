defmodule GlobalbridgeBackend.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12, prefix: false)
  end

  def down do
    Oban.Migration.down(version: 12, prefix: false)
  end
end
