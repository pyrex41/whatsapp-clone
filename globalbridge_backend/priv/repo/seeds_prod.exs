# Production seed script - idempotent, safe to run multiple times
# Populates test users (Alice, Bob, testuser, demo) and sample threads
#
# Run with: bin/globalbridge_backend eval "Code.eval_file(\"priv/repo/seeds_prod.exs\")"

require Logger

alias GlobalbridgeBackend.Repo
alias GlobalbridgeBackend.Schemas.{User, Thread, ThreadParticipant}

Logger.info("🌱 Starting production database seeding...")

# Helper function to find or create a user
create_or_find_user = fn attrs ->
  username = attrs.username
  phone_number = attrs.phone_number

  case Repo.get_by(User, username: username) do
    nil ->
      Logger.info("Creating user: #{username}")

      {:ok, user} =
        %User{}
        |> User.create_changeset(%{
          username: username,
          phone_number: phone_number,
          password_hash: Bcrypt.hash_pwd_salt(attrs.password),
          display_name: attrs.display_name,
          status_message: attrs.status_message || "",
          is_online: false,
          tier: "free"
        })
        |> Repo.insert()

      Logger.info("✓ Created user: #{username} (#{user.id})")
      user

    existing_user ->
      Logger.info("✓ User already exists: #{username} (#{existing_user.id})")
      existing_user
  end
end

# Create test users
Logger.info("Creating/checking test users...")

test_user =
  create_or_find_user.(%{
    username: "testuser",
    phone_number: "+11234567890",
    password: "password123",
    display_name: "Test User",
    status_message: "Available for testing"
  })

demo_user =
  create_or_find_user.(%{
    username: "demo",
    phone_number: "+19876543210",
    password: "demo123",
    display_name: "Demo User",
    status_message: "Demo account"
  })

alice =
  create_or_find_user.(%{
    username: "alice",
    phone_number: "+15551234567",
    password: "alice123",
    display_name: "Alice Smith",
    status_message: "Hey there! I'm using GlobalBridge"
  })

bob =
  create_or_find_user.(%{
    username: "bob",
    phone_number: "+15559876543",
    password: "bob123",
    display_name: "Bob Johnson",
    status_message: "Busy"
  })

# Helper to create thread with participants (idempotent)
create_or_find_thread = fn attrs, participant_ids ->
  # Check if thread already exists with these exact participants
  existing_thread =
    Thread
    |> Repo.all()
    |> Enum.find(fn thread ->
      participant_user_ids =
        ThreadParticipant
        |> Repo.all()
        |> Enum.filter(fn tp -> tp.thread_id == thread.id end)
        |> Enum.map(fn tp -> tp.user_id end)
        |> Enum.sort()

      sorted_participant_ids = Enum.sort(participant_ids)
      participant_user_ids == sorted_participant_ids && thread.title == attrs.title
    end)

  case existing_thread do
    nil ->
      Logger.info("Creating thread: #{attrs.title}")

      thread_attrs =
        attrs
        |> Map.put(:database_shard_id, Ecto.UUID.generate())
        |> Map.put(:last_message_at, DateTime.utc_now() |> DateTime.truncate(:second))

      {:ok, thread} =
        %Thread{}
        |> Thread.create_changeset(thread_attrs)
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

      Logger.info("✓ Created thread: #{thread.title} (#{thread.id})")
      thread

    existing_thread ->
      Logger.info("✓ Thread already exists: #{existing_thread.title} (#{existing_thread.id})")
      existing_thread
  end
end

# Create test threads
Logger.info("Creating/checking test threads...")

_thread1 =
  create_or_find_thread.(
    %{
      thread_type: "direct",
      title: "Chat with Alice"
    },
    [test_user.id, alice.id]
  )

_thread2 =
  create_or_find_thread.(
    %{
      thread_type: "group",
      title: "Team Discussion"
    },
    [test_user.id, alice.id, bob.id]
  )

_thread3 =
  create_or_find_thread.(
    %{
      thread_type: "direct",
      title: "Chat with Bob"
    },
    [test_user.id, bob.id]
  )

_thread4 =
  create_or_find_thread.(
    %{
      thread_type: "group",
      title: "Project Planning"
    },
    [test_user.id, demo_user.id, alice.id]
  )

Logger.info("")
Logger.info(String.duplicate("=", 60))
Logger.info("🎉 Production seeding complete!")
Logger.info(String.duplicate("=", 60))
Logger.info("")
Logger.info("Test Credentials:")
Logger.info("─────────────────────────────────────────────────────────────")
Logger.info("User 1: testuser / +11234567890 / password123")
Logger.info("User 2: demo     / +19876543210 / demo123")
Logger.info("User 3: alice    / +15551234567 / alice123")
Logger.info("User 4: bob      / +15559876543 / bob123")
Logger.info("─────────────────────────────────────────────────────────────")
Logger.info("")
Logger.info("Data stored in: #{System.get_env("DATABASE_PATH", "/mnt/data/users.db")}")
Logger.info(String.duplicate("=", 60))
Logger.info("")
