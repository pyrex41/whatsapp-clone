defmodule GlobalbridgeBackend.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :globalbridge_backend

  require Logger

  def migrate do
    load_app()

    for repo <- repos() do
      # First ensure missing columns exist (for existing databases)
      {:ok, _pid, _apps} = Ecto.Migrator.with_repo(repo, fn repo ->
        try_add_missing_columns(repo)
      end)

      # Then run all pending migrations
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp try_add_missing_columns(repo) do
    # Add auth0_metadata and auth0_refresh_token if they don't exist
    # These columns were added in migration 20251022014215 but may be missing
    # in databases created before this migration existed
    try do
      Ecto.Adapters.SQL.query(repo, "ALTER TABLE users ADD COLUMN auth0_metadata TEXT", [])
      Logger.info("✅ Added auth0_metadata column")
    rescue
      _ -> Logger.info("ℹ️  auth0_metadata column already exists")
    end

    try do
      Ecto.Adapters.SQL.query(repo, "ALTER TABLE users ADD COLUMN auth0_refresh_token TEXT", [])
      Logger.info("✅ Added auth0_refresh_token column")
    rescue
      _ -> Logger.info("ℹ️  auth0_refresh_token column already exists")
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
