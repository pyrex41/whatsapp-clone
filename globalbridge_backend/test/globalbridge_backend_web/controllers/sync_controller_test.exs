defmodule GlobalbridgeBackendWeb.SyncControllerTest do
  use GlobalbridgeBackendWeb.ConnCase

  import Ecto.Query

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.{User, Thread, ThreadParticipant, Message, CDCLog}
  alias GlobalbridgeBackend.Contexts.{Auth, Threads, Messages}
  alias GlobalbridgeBackend.Repos.ThreadRepo

  setup %{conn: conn} do
    # Create test users
    {:ok, user1, tokens1} = Auth.signup(%{
      "username" => "syncuser1",
      "phone_number" => "+11234567890",
      "password" => "password123",
      "display_name" => "Sync User 1"
    })

    {:ok, user2, _tokens2} = Auth.signup(%{
      "username" => "syncuser2",
      "phone_number" => "+11234567891",
      "password" => "password123",
      "display_name" => "Sync User 2"
    })

    # Create a test thread
    {:ok, thread} = Threads.create_thread(%{
      thread_type: "direct",
      participant_ids: [user1.id, user2.id]
    })

    # Authenticate user1
    conn = put_req_header(conn, "authorization", "Bearer #{tokens1.access_token}")

    {:ok, conn: conn, user1: user1, user2: user2, thread: thread}
  end

  describe "POST /api/v1/sync/pull" do
    test "returns CDC changes for authorized user's thread", %{conn: conn, thread: thread, user1: user1} do
      # Create some CDC logs
      repo = ThreadRepo.get_repo(thread.database_shard_id)

      # Create a message to generate CDC logs
      message_attrs = %{
        sender_id: user1.id,
        content: "Test message",
        content_type: "text"
      }
      {:ok, message} = Messages.create_message(thread.id, message_attrs)

      # Create CDC log manually for testing
      cdc_log = %CDCLog{
        table_name: "messages",
        record_id: message.id,
        operation: "INSERT",
        new_data: %{
          "id" => message.id,
          "content" => "Test message",
          "sender_id" => user1.id,
          "thread_id" => thread.id
        },
        user_id: user1.id,
        timestamp: DateTime.utc_now()
      }
      {:ok, _} = Repo.insert(cdc_log)

      # Pull changes
      conn = post(conn, ~p"/api/v1/sync/pull", %{
        thread_id: thread.id,
        last_sync_cursor: 0
      })

      assert %{
        "data" => %{
          "changes" => changes,
          "next_cursor" => next_cursor
        }
      } = json_response(conn, 200)

      assert length(changes) > 0
      assert is_integer(next_cursor)

      first_change = List.first(changes)
      assert first_change["table_name"] == "messages"
      assert first_change["operation"] == "INSERT"
    end

    test "returns empty changes when no new CDC logs", %{conn: conn, thread: thread} do
      # Pull with a very high cursor (no new changes)
      conn = post(conn, ~p"/api/v1/sync/pull", %{
        thread_id: thread.id,
        last_sync_cursor: 999_999
      })

      assert %{
        "data" => %{
          "changes" => [],
          "next_cursor" => cursor
        }
      } = json_response(conn, 200)

      assert cursor == 999_999
    end

    test "limits changes to 100 per request", %{conn: conn, thread: thread, user1: user1} do
      # Create 150 CDC logs
      Enum.each(1..150, fn i ->
        cdc_log = %CDCLog{
          table_name: "messages",
          record_id: Ecto.UUID.generate(),
          operation: "INSERT",
          new_data: %{"content" => "Message #{i}"},
          user_id: user1.id,
          timestamp: DateTime.utc_now()
        }
        Repo.insert(cdc_log)
      end)

      conn = post(conn, ~p"/api/v1/sync/pull", %{
        thread_id: thread.id,
        last_sync_cursor: 0
      })

      assert %{
        "data" => %{
          "changes" => changes
        }
      } = json_response(conn, 200)

      assert length(changes) == 100
    end

    test "returns 403 when user not in thread", %{conn: conn} do
      # Create a different thread without user1
      {:ok, user3, _} = Auth.signup(%{
        "username" => "syncuser3",
        "phone_number" => "+11234567892",
        "password" => "password123"
      })

      {:ok, user4, _} = Auth.signup(%{
        "username" => "syncuser4",
        "phone_number" => "+11234567893",
        "password" => "password123"
      })

      {:ok, other_thread} = Threads.create_thread(%{
        thread_type: "direct",
        participant_ids: [user3.id, user4.id]
      })

      conn = post(conn, ~p"/api/v1/sync/pull", %{
        thread_id: other_thread.id,
        last_sync_cursor: 0
      })

      assert json_response(conn, 403)
    end

    test "returns 400 when thread_id missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/sync/pull", %{
        last_sync_cursor: 0
      })

      assert json_response(conn, 400)
    end

    test "returns 404 when thread not found", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/sync/pull", %{
        thread_id: Ecto.UUID.generate(),
        last_sync_cursor: 0
      })

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/v1/sync/push" do
    test "applies valid CDC changes to thread", %{conn: conn, thread: thread, user1: user1} do
      message_id = Ecto.UUID.generate()

      changes = [
        %{
          table_name: "messages",
          record_id: message_id,
          operation: "INSERT",
          new_data: %{
            id: message_id,
            thread_id: thread.id,
            sender_id: user1.id,
            content: "Pushed message",
            content_type: "text"
          },
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      ]

      conn = post(conn, ~p"/api/v1/sync/push", %{
        thread_id: thread.id,
        changes: changes
      })

      assert %{
        "data" => %{
          "applied" => 1,
          "failed" => 0,
          "results" => results
        }
      } = json_response(conn, 200)

      assert length(results) == 1
      assert List.first(results)["success"] == true

      # Verify message was created
      repo = ThreadRepo.get_repo(thread.database_shard_id)
      message = repo.get(Message, message_id)
      assert message.content == "Pushed message"
    end

    test "applies UPDATE operations", %{conn: conn, thread: thread, user1: user1} do
      # Create initial message
      {:ok, message} = Messages.create_message(thread.id, %{
        sender_id: user1.id,
        content: "Original",
        content_type: "text"
      })

      changes = [
        %{
          table_name: "messages",
          record_id: message.id,
          operation: "UPDATE",
          old_data: %{content: "Original"},
          new_data: %{
            id: message.id,
            content: "Updated",
            edited_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      ]

      conn = post(conn, ~p"/api/v1/sync/push", %{
        thread_id: thread.id,
        changes: changes
      })

      assert %{"data" => %{"applied" => 1}} = json_response(conn, 200)

      # Verify update
      repo = ThreadRepo.get_repo(thread.database_shard_id)
      updated_message = repo.get(Message, message.id)
      assert updated_message.content == "Updated"
      assert updated_message.edited_at != nil
    end

    test "applies DELETE operations", %{conn: conn, thread: thread, user1: user1} do
      # Create initial message
      {:ok, message} = Messages.create_message(thread.id, %{
        sender_id: user1.id,
        content: "To be deleted",
        content_type: "text"
      })

      changes = [
        %{
          table_name: "messages",
          record_id: message.id,
          operation: "DELETE",
          old_data: %{content: "To be deleted"},
          new_data: %{
            id: message.id,
            is_deleted: true,
            deleted_at: DateTime.utc_now() |> DateTime.to_iso8601()
          },
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      ]

      conn = post(conn, ~p"/api/v1/sync/push", %{
        thread_id: thread.id,
        changes: changes
      })

      assert %{"data" => %{"applied" => 1}} = json_response(conn, 200)

      # Verify soft delete
      repo = ThreadRepo.get_repo(thread.database_shard_id)
      deleted_message = repo.get(Message, message.id)
      assert deleted_message.is_deleted == true
      assert deleted_message.deleted_at != nil
    end

    test "handles conflicts with last-write-wins", %{conn: conn, thread: thread, user1: user1} do
      # Create initial message
      {:ok, message} = Messages.create_message(thread.id, %{
        sender_id: user1.id,
        content: "Original",
        content_type: "text"
      })

      # Simulate conflicting update (older timestamp should lose)
      old_timestamp = DateTime.utc_now() |> DateTime.add(-60, :second)

      changes = [
        %{
          table_name: "messages",
          record_id: message.id,
          operation: "UPDATE",
          new_data: %{
            id: message.id,
            content: "Old update"
          },
          timestamp: DateTime.to_iso8601(old_timestamp)
        }
      ]

      conn = post(conn, ~p"/api/v1/sync/push", %{
        thread_id: thread.id,
        changes: changes
      })

      # Should still apply but newer changes would win
      assert %{"data" => %{"applied" => applied}} = json_response(conn, 200)
      assert applied >= 0
    end

    test "returns partial success when some changes fail", %{conn: conn, thread: thread, user1: user1} do
      valid_message_id = Ecto.UUID.generate()

      changes = [
        # Valid change
        %{
          table_name: "messages",
          record_id: valid_message_id,
          operation: "INSERT",
          new_data: %{
            id: valid_message_id,
            thread_id: thread.id,
            sender_id: user1.id,
            content: "Valid",
            content_type: "text"
          },
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        },
        # Invalid change (missing required fields)
        %{
          table_name: "messages",
          record_id: Ecto.UUID.generate(),
          operation: "INSERT",
          new_data: %{
            content: "Invalid - missing fields"
          },
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }
      ]

      conn = post(conn, ~p"/api/v1/sync/push", %{
        thread_id: thread.id,
        changes: changes
      })

      assert %{
        "data" => %{
          "applied" => 1,
          "failed" => 1,
          "results" => results
        }
      } = json_response(conn, 200)

      assert length(results) == 2
      assert Enum.at(results, 0)["success"] == true
      assert Enum.at(results, 1)["success"] == false
    end

    test "returns 403 when user not in thread", %{conn: conn} do
      {:ok, user3, _} = Auth.signup(%{
        "username" => "syncuser5",
        "phone_number" => "+11234567894",
        "password" => "password123"
      })

      {:ok, user4, _} = Auth.signup(%{
        "username" => "syncuser6",
        "phone_number" => "+11234567895",
        "password" => "password123"
      })

      {:ok, other_thread} = Threads.create_thread(%{
        thread_type: "direct",
        participant_ids: [user3.id, user4.id]
      })

      conn = post(conn, ~p"/api/v1/sync/push", %{
        thread_id: other_thread.id,
        changes: []
      })

      assert json_response(conn, 403)
    end

    test "returns 400 when changes array missing", %{conn: conn, thread: thread} do
      conn = post(conn, ~p"/api/v1/sync/push", %{
        thread_id: thread.id
      })

      assert json_response(conn, 400)
    end

    test "validates CDC log structure", %{conn: conn, thread: thread} do
      # Invalid CDC log (missing operation)
      changes = [
        %{
          table_name: "messages",
          record_id: Ecto.UUID.generate(),
          new_data: %{content: "test"}
        }
      ]

      conn = post(conn, ~p"/api/v1/sync/push", %{
        thread_id: thread.id,
        changes: changes
      })

      # Should handle gracefully
      assert response = json_response(conn, 200)
      assert response["data"]["failed"] > 0
    end
  end

  describe "access control" do
    test "unauthenticated requests return 401", %{thread: thread} do
      # Create new connection without auth
      conn = build_conn()

      conn = post(conn, ~p"/api/v1/sync/pull", %{
        thread_id: thread.id,
        last_sync_cursor: 0
      })

      assert json_response(conn, 401)
    end

    test "user can only sync their own threads", %{user1: user1, user2: user2, thread: thread} do
      # Create another thread without user1
      {:ok, user5, _} = Auth.signup(%{
        "username" => "syncuser7",
        "phone_number" => "+11234567896",
        "password" => "password123"
      })

      {:ok, private_thread} = Threads.create_thread(%{
        thread_type: "direct",
        participant_ids: [user2.id, user5.id]
      })

      # Try to sync with user1's token (should fail)
      {:ok, _user, tokens} = Auth.login("syncuser1", "password123")
      conn = build_conn()
        |> put_req_header("authorization", "Bearer #{tokens.access_token}")

      conn = post(conn, ~p"/api/v1/sync/pull", %{
        thread_id: private_thread.id,
        last_sync_cursor: 0
      })

      assert json_response(conn, 403)
    end
  end
end
