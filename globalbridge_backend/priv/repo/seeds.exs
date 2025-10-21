# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     GlobalbridgeBackend.Repo.insert!(%GlobalbridgeBackend.SomeSchema{})
#

alias GlobalbridgeBackend.Repo
alias GlobalbridgeBackend.Schemas.User

# Clear existing data in development
if Mix.env() == :dev do
  IO.puts("Clearing existing users...")
  Repo.delete_all(User)
end

# Create test users for development
IO.puts("Creating test users...")

# Test User 1 - Standard user
{:ok, test_user} = %User{}
|> User.create_changeset(%{
  username: "testuser",
  phone_number: "+11234567890",
  password_hash: Bcrypt.hash_pwd_salt("password123"),
  display_name: "Test User",
  status_message: "Available for testing",
  is_online: false,
  tier: "free"
})
|> Repo.insert()

IO.puts("✓ Created test user: #{test_user.username} (#{test_user.phone_number})")

# Test User 2 - Demo user
{:ok, demo_user} = %User{}
|> User.create_changeset(%{
  username: "demo",
  phone_number: "+19876543210",
  password_hash: Bcrypt.hash_pwd_salt("demo123"),
  display_name: "Demo User",
  status_message: "Demo account",
  is_online: false,
  tier: "free"
})
|> Repo.insert()

IO.puts("✓ Created demo user: #{demo_user.username} (#{demo_user.phone_number})")

# Test User 3 - Alice
{:ok, alice} = %User{}
|> User.create_changeset(%{
  username: "alice",
  phone_number: "+15551234567",
  password_hash: Bcrypt.hash_pwd_salt("alice123"),
  display_name: "Alice Smith",
  status_message: "Hey there! I'm using GlobalBridge",
  is_online: false,
  tier: "free"
})
|> Repo.insert()

IO.puts("✓ Created user: #{alice.username} (#{alice.display_name})")

# Test User 4 - Bob
{:ok, bob} = %User{}
|> User.create_changeset(%{
  username: "bob",
  phone_number: "+15559876543",
  password_hash: Bcrypt.hash_pwd_salt("bob123"),
  display_name: "Bob Johnson",
  status_message: "Busy",
  is_online: false,
  tier: "free"
})
|> Repo.insert()

IO.puts("✓ Created user: #{bob.username} (#{bob.display_name})")

# Create test threads for development
alias GlobalbridgeBackend.Repo
alias GlobalbridgeBackend.Schemas.{Thread, ThreadParticipant}

IO.puts("Creating test threads...")

# Helper to create thread with participants without complex preloading
create_thread_simple = fn attrs, participant_ids ->
  attrs =
    attrs
    |> Map.put(:database_shard_id, Ecto.UUID.generate())
    |> Map.put(:last_message_at, DateTime.utc_now() |> DateTime.truncate(:second))

  {:ok, thread} = %Thread{}
  |> Thread.create_changeset(attrs)
  |> Repo.insert()

  # Add participants
  Enum.each(participant_ids, fn user_id ->
    %ThreadParticipant{}
    |> ThreadParticipant.create_changeset(%{
      thread_id: thread.id,
      user_id: user_id,
      role: "member"
    })
    |> Repo.insert!()
  end)

  thread
end

# Thread 1: Direct message between testuser and alice
thread1 = create_thread_simple.(%{
  thread_type: "direct",
  title: "Chat with Alice"
}, [test_user.id, alice.id])
IO.puts("✓ Created thread: #{thread1.title}")

# Thread 2: Group chat
thread2 = create_thread_simple.(%{
  thread_type: "group",
  title: "Team Discussion"
}, [test_user.id, alice.id, bob.id])
IO.puts("✓ Created thread: #{thread2.title}")

# Thread 3: Direct message between testuser and bob
thread3 = create_thread_simple.(%{
  thread_type: "direct",
  title: "Chat with Bob"
}, [test_user.id, bob.id])
IO.puts("✓ Created thread: #{thread3.title}")

# Thread 4: Another group with demo user
thread4 = create_thread_simple.(%{
  thread_type: "group",
  title: "Project Planning"
}, [test_user.id, demo_user.id, alice.id])
IO.puts("✓ Created thread: #{thread4.title}")

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("Database seeding complete!")
IO.puts(String.duplicate("=", 60))
IO.puts("\nTest Credentials:")
IO.puts("─────────────────────────────────────────────────────────────")
IO.puts("User 1:")
IO.puts("  Username: testuser")
IO.puts("  Phone:    +11234567890")
IO.puts("  Password: password123")
IO.puts("\nUser 2:")
IO.puts("  Username: demo")
IO.puts("  Phone:    +19876543210")
IO.puts("  Password: demo123")
IO.puts("\nUser 3:")
IO.puts("  Username: alice")
IO.puts("  Phone:    +15551234567")
IO.puts("  Password: alice123")
IO.puts("\nUser 4:")
IO.puts("  Username: bob")
IO.puts("  Phone:    +15559876543")
IO.puts("  Password: bob123")
IO.puts("─────────────────────────────────────────────────────────────")
IO.puts("\nYou can log in with either username OR phone number")
IO.puts("\n4 test threads have been created for 'testuser'")
IO.puts(String.duplicate("=", 60) <> "\n")
