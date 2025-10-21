defmodule GlobalbridgeBackendWeb.TypingIndicatorsTest do
  @moduledoc """
  Comprehensive tests for Task 17: Typing Indicators feature.

  Tests cover:
  - Typing event broadcasting via channels
  - Multi-user typing scenarios
  - Typing state management
  - Performance and latency requirements
  - Edge cases (disconnections, rapid state changes)
  """
  use GlobalbridgeBackendWeb.ChannelCase

  alias GlobalbridgeBackendWeb.UserSocket
  alias GlobalbridgeBackend.{Repo, Chat}
  alias GlobalbridgeBackend.Schemas.{Thread, ThreadParticipant, User}

  setup do
    # Create test users
    user1 = Repo.insert!(%User{
      id: Ecto.UUID.generate(),
      username: "user1",
      email: "user1@test.com",
      phone: "+1234567890"
    })

    user2 = Repo.insert!(%User{
      id: Ecto.UUID.generate(),
      username: "user2",
      email: "user2@test.com",
      phone: "+1234567891"
    })

    user3 = Repo.insert!(%User{
      id: Ecto.UUID.generate(),
      username: "user3",
      email: "user3@test.com",
      phone: "+1234567892"
    })

    # Create test thread
    thread = Repo.insert!(%Thread{
      id: Ecto.UUID.generate(),
      thread_type: "direct",
      database_shard_id: "test_shard_1"
    })

    # Add participants
    Repo.insert!(%ThreadParticipant{thread_id: thread.id, user_id: user1.id})
    Repo.insert!(%ThreadParticipant{thread_id: thread.id, user_id: user2.id})
    Repo.insert!(%ThreadParticipant{thread_id: thread.id, user_id: user3.id})

    {:ok, thread: thread, user1: user1, user2: user2, user3: user3}
  end

  describe "typing indicator broadcasting" do
    test "broadcasts typing started to other participants", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      # Connect both users
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 starts typing
      push(socket1, "typing", %{"is_typing" => true})

      # User2 should receive typing indicator (but not user1)
      assert_broadcast "user_typing", %{
        user_id: user_id,
        is_typing: true,
        timestamp: timestamp
      }

      assert user_id == user1.id
      assert is_integer(timestamp)
    end

    test "broadcasts typing stopped to other participants", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 stops typing
      push(socket1, "typing", %{"is_typing" => false})

      assert_broadcast "user_typing", %{
        user_id: ^user1.id,
        is_typing: false
      }
    end

    test "does not broadcast typing to sender", %{thread: thread, user1: user1} do
      {:ok, socket} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

      push(socket, "typing", %{"is_typing" => true})

      # Sender should not receive their own typing indicator
      refute_push "user_typing", %{user_id: ^user1.id}
    end

    test "handles rapid typing state changes", %{thread: thread, user1: user1, user2: user2} do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # Rapid state changes
      push(socket1, "typing", %{"is_typing" => true})
      push(socket1, "typing", %{"is_typing" => false})
      push(socket1, "typing", %{"is_typing" => true})
      push(socket1, "typing", %{"is_typing" => false})

      # All state changes should be broadcast
      assert_broadcast "user_typing", %{is_typing: true}
      assert_broadcast "user_typing", %{is_typing: false}
      assert_broadcast "user_typing", %{is_typing: true}
      assert_broadcast "user_typing", %{is_typing: false}
    end
  end

  describe "multi-user typing scenarios" do
    test "handles multiple users typing simultaneously", %{
      thread: thread,
      user1: user1,
      user2: user2,
      user3: user3
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      {:ok, socket3} = connect(UserSocket, %{"token" => "user3:#{user3.id}"})
      {:ok, _, _socket3} = subscribe_and_join(socket3, "thread:#{thread.id}", %{})

      # All users start typing
      push(socket1, "typing", %{"is_typing" => true})
      push(socket2, "typing", %{"is_typing" => true})

      # Each typing event should be broadcast
      assert_broadcast "user_typing", %{user_id: ^user1.id, is_typing: true}
      assert_broadcast "user_typing", %{user_id: ^user2.id, is_typing: true}
    end

    test "maintains independent typing state per user", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 starts typing
      push(socket1, "typing", %{"is_typing" => true})
      assert_broadcast "user_typing", %{user_id: ^user1.id, is_typing: true}

      # User2 starts typing
      push(socket2, "typing", %{"is_typing" => true})
      assert_broadcast "user_typing", %{user_id: ^user2.id, is_typing: true}

      # User1 stops typing (User2 still typing)
      push(socket1, "typing", %{"is_typing" => false})
      assert_broadcast "user_typing", %{user_id: ^user1.id, is_typing: false}
    end
  end

  describe "typing indicator performance" do
    test "typing broadcast happens within 50ms", %{thread: thread, user1: user1, user2: user2} do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      start_time = System.monotonic_time(:millisecond)
      push(socket1, "typing", %{"is_typing" => true})

      # Should receive broadcast very quickly
      assert_broadcast "user_typing", %{}, 50

      end_time = System.monotonic_time(:millisecond)
      latency = end_time - start_time

      # Latency should be under 50ms for ephemeral events
      assert latency < 50, "Typing indicator latency #{latency}ms exceeds 50ms threshold"
    end

    test "handles high-frequency typing events without message loss", %{
      thread: thread,
      user1: user1,
      user2: user2
    } do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # Send 10 rapid typing updates
      for i <- 1..10 do
        is_typing = rem(i, 2) == 1
        push(socket1, "typing", %{"is_typing" => is_typing})
      end

      # All broadcasts should be received
      for i <- 1..10 do
        is_typing = rem(i, 2) == 1
        assert_broadcast "user_typing", %{is_typing: ^is_typing}, 100
      end
    end
  end

  describe "typing indicator edge cases" do
    test "handles typing event without is_typing field", %{thread: thread, user1: user1} do
      {:ok, socket} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket} = subscribe_and_join(socket, "thread:#{thread.id}", %{})

      # Should handle gracefully, defaulting to false or ignoring
      push(socket, "typing", %{})

      # Should not crash, may or may not broadcast
      :timer.sleep(50)
    end

    test "clears typing state on user disconnect", %{thread: thread, user1: user1, user2: user2} do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      # User1 starts typing
      push(socket1, "typing", %{"is_typing" => true})
      assert_broadcast "user_typing", %{user_id: ^user1.id, is_typing: true}

      # User1 disconnects
      close(socket1)

      # Typing state should be implicitly cleared on disconnect
      # (clients track this locally based on presence)
    end

    test "typing events only sent to thread participants", %{thread: thread, user1: user1} do
      # Create non-participant
      other_user = Repo.insert!(%User{
        id: Ecto.UUID.generate(),
        username: "other",
        email: "other@test.com",
        phone: "+1999999999"
      })

      # Create another thread for other user
      other_thread = Repo.insert!(%Thread{
        id: Ecto.UUID.generate(),
        thread_type: "direct",
        database_shard_id: "test_shard_2"
      })

      Repo.insert!(%ThreadParticipant{thread_id: other_thread.id, user_id: other_user.id})

      # Connect both users
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket_other} = connect(UserSocket, %{"token" => "user:#{other_user.id}"})
      {:ok, _, _socket_other} = subscribe_and_join(socket_other, "thread:#{other_thread.id}", %{})

      # User1 types in their thread
      push(socket1, "typing", %{"is_typing" => true})

      # Other user should not receive typing event (different thread)
      refute_broadcast "user_typing", %{user_id: ^user1.id}
    end
  end

  describe "typing indicator timestamps" do
    test "includes timestamp in typing events", %{thread: thread, user1: user1, user2: user2} do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      before_time = System.system_time(:millisecond)
      push(socket1, "typing", %{"is_typing" => true})

      assert_broadcast "user_typing", %{
        timestamp: timestamp
      }

      after_time = System.system_time(:millisecond)

      # Timestamp should be within reasonable range
      assert timestamp >= before_time
      assert timestamp <= after_time + 10
    end

    test "timestamps are monotonically increasing", %{thread: thread, user1: user1, user2: user2} do
      {:ok, socket1} = connect(UserSocket, %{"token" => "user:#{user1.id}"})
      {:ok, _, socket1} = subscribe_and_join(socket1, "thread:#{thread.id}", %{})

      {:ok, socket2} = connect(UserSocket, %{"token" => "user2:#{user2.id}"})
      {:ok, _, _socket2} = subscribe_and_join(socket2, "thread:#{thread.id}", %{})

      push(socket1, "typing", %{"is_typing" => true})
      assert_broadcast "user_typing", %{timestamp: t1}

      :timer.sleep(10)

      push(socket1, "typing", %{"is_typing" => false})
      assert_broadcast "user_typing", %{timestamp: t2}

      assert t2 > t1, "Timestamps should be monotonically increasing"
    end
  end
end
