#!/usr/bin/env elixir

# Simple script to seed test data for development
Mix.install([
  {:ecto_sql, "~> 3.12"},
  {:ecto_sqlite3, "~> 0.18"},
  {:bcrypt_elixir, "~> 3.0"}
])

defmodule SeedData do
  def run do
    # Configure database
    Application.put_env(:globalbridge_backend, GlobalbridgeBackend.Repo,
      database: "./priv/shared_dbs/users.db",
      pool_size: 1
    )

    # Start dependencies
    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)

    # Define schemas
    defmodule User do
      use Ecto.Schema

      schema "users" do
        field(:username, :string)
        field(:email, :string)
        field(:display_name, :string)
        field(:password_hash, :string)
        field(:auth0_id, :string)
        timestamps()
      end
    end

    defmodule Thread do
      use Ecto.Schema

      schema "threads" do
        field(:title, :string)
        field(:thread_type, :string, default: "direct")
        field(:database_shard_id, :string)
        timestamps()
      end
    end

    defmodule ThreadParticipant do
      use Ecto.Schema

      schema "thread_participants" do
        field(:thread_id, :string)
        field(:user_id, :string)
        timestamps()
      end
    end

    # Create users
    users = [
      %{
        username: "alice",
        email: "alice@example.com",
        display_name: "Alice",
        auth0_id: "auth0_alice"
      },
      %{username: "bob", email: "bob@example.com", display_name: "Bob", auth0_id: "auth0_bob"}
    ]

    # Insert users
    Enum.each(users, fn user_attrs ->
      user = %User{
        username: user_attrs.username,
        email: user_attrs.email,
        display_name: user_attrs.display_name,
        auth0_id: user_attrs.auth0_id,
        password_hash: Bcrypt.hash_pwd_salt("password"),
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      GlobalbridgeBackend.Repo.insert!(user)
      IO.puts("Created user: #{user.username}")
    end)

    # Create a thread
    thread = %Thread{
      title: "Alice and Bob Chat",
      thread_type: "direct",
      database_shard_id: "shard_1",
      inserted_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    thread = GlobalbridgeBackend.Repo.insert!(thread)
    IO.puts("Created thread: #{thread.title}")

    # Add participants
    alice = GlobalbridgeBackend.Repo.get_by!(User, username: "alice")
    bob = GlobalbridgeBackend.Repo.get_by!(User, username: "bob")

    participants = [
      %{thread_id: thread.id, user_id: alice.id},
      %{thread_id: thread.id, user_id: bob.id}
    ]

    Enum.each(participants, fn participant_attrs ->
      participant = %ThreadParticipant{
        thread_id: participant_attrs.thread_id,
        user_id: participant_attrs.user_id,
        inserted_at: DateTime.utc_now(),
        updated_at: DateTime.utc_now()
      }

      GlobalbridgeBackend.Repo.insert!(participant)
    end)

    IO.puts("Added participants to thread")
    IO.puts("Seeding complete!")
  end
end

# Run the seeder
SeedData.run()
