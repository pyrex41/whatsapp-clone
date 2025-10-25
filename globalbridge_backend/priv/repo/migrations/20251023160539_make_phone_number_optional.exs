defmodule GlobalbridgeBackend.Repo.Migrations.MakePhoneNumberOptional do
  use Ecto.Migration

  def up do
    # SQLite doesn't support ALTER COLUMN directly
    # We need to recreate the table

    # Step 1: Create new table with nullable phone_number
    create table(:users_new, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:username, :string, null: false)
      # Changed to nullable
      add(:phone_number, :string, null: true)
      add(:password_hash, :string, null: false)
      add(:display_name, :string)
      add(:avatar_url, :string)
      add(:status_message, :string)
      add(:public_key, :text)
      add(:last_seen_at, :utc_datetime)
      add(:is_online, :boolean, default: false)
      add(:tier, :string, default: "free")
      add(:auth0_id, :string)
      add(:email, :string)
      # Auth0 fields from previous migration
      add(:auth0_metadata, :text, default: "{}")
      add(:auth0_refresh_token, :text)

      timestamps(type: :utc_datetime)
    end

    # Step 2: Copy data from old table to new table
    # For Auth0 users with hardcoded phone number, set to NULL
    execute("""
      INSERT INTO users_new (
        id, username, phone_number, password_hash, display_name, avatar_url,
        status_message, public_key, last_seen_at, is_online, tier, auth0_id,
        email, auth0_metadata, auth0_refresh_token, inserted_at, updated_at
      )
      SELECT
        id, username,
        CASE
          WHEN phone_number = '+10000000000' AND auth0_id IS NOT NULL THEN NULL
          ELSE phone_number
        END,
        password_hash, display_name, avatar_url,
        status_message, public_key, last_seen_at, is_online, tier, auth0_id,
        email, auth0_metadata, auth0_refresh_token, inserted_at, updated_at
      FROM users
    """)

    # Step 3: Drop old table
    drop(table(:users))

    # Step 4: Rename new table to users
    rename(table(:users_new), to: table(:users))

    # Step 5: Recreate indexes
    create(unique_index(:users, [:username]))
    create(unique_index(:users, [:phone_number]))
    create(unique_index(:users, [:auth0_id]))
    create(unique_index(:users, [:email]))
    create(index(:users, [:is_online]))
  end

  def down do
    # Recreate table with NOT NULL constraint
    create table(:users_old, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:username, :string, null: false)
      # Back to NOT NULL
      add(:phone_number, :string, null: false)
      add(:password_hash, :string, null: false)
      add(:display_name, :string)
      add(:avatar_url, :string)
      add(:status_message, :string)
      add(:public_key, :text)
      add(:last_seen_at, :utc_datetime)
      add(:is_online, :boolean, default: false)
      add(:tier, :string, default: "free")
      add(:auth0_id, :string)
      add(:email, :string)
      # Auth0 fields from previous migration
      add(:auth0_metadata, :text, default: "{}")
      add(:auth0_refresh_token, :text)

      timestamps(type: :utc_datetime)
    end

    # Copy data back, setting placeholder for NULL phone numbers
    execute("""
      INSERT INTO users_old (
        id, username, phone_number, password_hash, display_name, avatar_url,
        status_message, public_key, last_seen_at, is_online, tier, auth0_id,
        email, auth0_metadata, auth0_refresh_token, inserted_at, updated_at
      )
      SELECT
        id, username,
        COALESCE(phone_number, '+10000000000'),
        password_hash, display_name, avatar_url,
        status_message, public_key, last_seen_at, is_online, tier, auth0_id,
        email, auth0_metadata, auth0_refresh_token, inserted_at, updated_at
      FROM users
    """)

    drop(table(:users))
    rename(table(:users_old), to: table(:users))

    create(unique_index(:users, [:username]))
    create(unique_index(:users, [:phone_number]))
    create(unique_index(:users, [:auth0_id]))
    create(unique_index(:users, [:email]))
    create(index(:users, [:is_online]))
  end
end
