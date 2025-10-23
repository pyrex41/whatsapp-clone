# Add Alice and Bob to all existing threads for testing
alias GlobalbridgeBackend.Repo
alias GlobalbridgeBackend.Schemas.{User, Thread, ThreadParticipant}
import Ecto.Query

# Get alice and bob
alice = Repo.get_by!(User, username: "alice")
bob = Repo.get_by!(User, username: "bob")
testuser = Repo.get_by!(User, username: "testuser")

IO.puts("Found users:")
IO.puts("  Alice: #{alice.id}")
IO.puts("  Bob: #{bob.id}")
IO.puts("  Testuser: #{testuser.id}")

# Get all threads
threads = Repo.all(Thread)
IO.puts("\nFound #{length(threads)} threads:")

for thread <- threads do
  IO.puts("\n📋 Thread: #{thread.title} (#{thread.id})")

  # Get current participants
  current_participants =
    from(tp in ThreadParticipant,
      where: tp.thread_id == ^thread.id,
      join: u in User,
      on: tp.user_id == u.id,
      select: u.username
    )
    |> Repo.all()

  IO.puts("   Current participants: #{inspect(current_participants)}")

  # Add alice if not already a participant
  unless Enum.member?(current_participants, "alice") do
    %ThreadParticipant{}
    |> ThreadParticipant.create_changeset(%{
      thread_id: thread.id,
      user_id: alice.id,
      role: "member"
    })
    |> Repo.insert!()

    IO.puts("   ✓ Added alice")
  end

  # Add bob if not already a participant
  unless Enum.member?(current_participants, "bob") do
    %ThreadParticipant{}
    |> ThreadParticipant.create_changeset(%{
      thread_id: thread.id,
      user_id: bob.id,
      role: "member"
    })
    |> Repo.insert!()

    IO.puts("   ✓ Added bob")
  end

  # Add testuser if not already a participant
  unless Enum.member?(current_participants, "testuser") do
    %ThreadParticipant{}
    |> ThreadParticipant.create_changeset(%{
      thread_id: thread.id,
      user_id: testuser.id,
      role: "member"
    })
    |> Repo.insert!()

    IO.puts("   ✓ Added testuser")
  end
end

IO.puts("\n✅ All test users added to all threads!")
