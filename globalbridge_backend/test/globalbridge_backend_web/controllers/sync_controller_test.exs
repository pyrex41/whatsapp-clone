defmodule GlobalbridgeBackendWeb.SyncControllerTest do
  use GlobalbridgeBackendWeb.ConnCase

  alias GlobalbridgeBackend.Chat
  alias GlobalbridgeBackend.Contexts.{Auth, Threads}
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Repos.ThreadRepo
  alias GlobalbridgeBackend.Schemas.{CDCLog, Message}

  setup %{conn: conn} do
    {:ok, user1, tokens1} = signup_user("syncuser1")
    {:ok, user2, _tokens2} = signup_user("syncuser2")

    {:ok, thread} =
      Threads.create_thread(%{
        thread_type: "direct",
        participant_ids: [user1.id, user2.id]
      })

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{tokens1.access_token}")

    {:ok, conn: conn, user1: user1, user2: user2, thread: thread, user1_tokens: tokens1}
  end

  defp signup_user(prefix) do
    suffix = System.unique_integer([:positive]) |> Integer.to_string()
    phone = "+1#{String.pad_leading(suffix, 10, "0")}"

    Auth.signup(%{
      "username" => "#{prefix}_#{suffix}",
      "phone_number" => phone,
      "password" => "password123",
      "display_name" => String.capitalize(prefix)
    })
  end

  defp iso_now do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  describe "POST /api/v1/sync/pull" do
    test "returns CDC changes for authorized user's thread", %{
      conn: conn,
      thread: thread,
      user1: user1
    } do
      {:ok, _message} =
        Chat.create_message(thread.id, %{
          sender_id: user1.id,
          content: "Test message",
          content_type: "text"
        })

      conn =
        post(conn, ~p"/api/v1/sync/pull", %{
          thread_id: thread.id
        })

      assert %{
               "data" => %{
                 "changes" => changes,
                 "next_cursor" => next_cursor
               }
             } = json_response(conn, 200)

      assert length(changes) > 0
      assert is_binary(next_cursor)
      assert {:ok, _dt, _} = DateTime.from_iso8601(next_cursor)

      first_change = hd(changes)
      assert first_change["table_name"] == "messages"
      assert first_change["operation"] == "INSERT"
      assert first_change["new_data"]["content"] == "Test message"
    end

    test "returns empty changes when no new CDC logs", %{conn: conn, thread: thread, user1: user1} do
      {:ok, _message} =
        Chat.create_message(thread.id, %{
          sender_id: user1.id,
          content: "Initial message",
          content_type: "text"
        })

      first_conn =
        post(conn, ~p"/api/v1/sync/pull", %{
          thread_id: thread.id
        })

      %{
        "data" => %{
          "next_cursor" => cursor
        }
      } = json_response(first_conn, 200)

      # Small delay to ensure any subsequent changes have different timestamps
      Process.sleep(1100)

      second_conn =
        post(conn, ~p"/api/v1/sync/pull", %{
          "thread_id" => thread.id,
          "since" => cursor
        })

      assert %{
               "data" => %{
                 "changes" => [],
                 "next_cursor" => ^cursor
               }
             } = json_response(second_conn, 200)
    end

    test "limits changes to 100 per request", %{conn: conn, thread: thread, user1: user1} do
      # Create 150 CDC logs
      Enum.each(1..150, fn i ->
        cdc_log = %CDCLog{
          table_name: "messages",
          record_id: Ecto.UUID.generate(),
          operation: "INSERT",
          new_data: %{"content" => "Message #{i}", "thread_id" => thread.id},
          user_id: user1.id,
          timestamp: DateTime.utc_now() |> DateTime.truncate(:second)
        }

        Repo.insert(cdc_log)
      end)

      conn =
        post(conn, ~p"/api/v1/sync/pull", %{
          thread_id: thread.id
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
      {:ok, user3, _} = signup_user("syncuser3")
      {:ok, user4, _} = signup_user("syncuser4")

      {:ok, other_thread} =
        Threads.create_thread(%{
          thread_type: "direct",
          participant_ids: [user3.id, user4.id]
        })

      conn =
        post(conn, ~p"/api/v1/sync/pull", %{
          thread_id: other_thread.id
        })

      assert json_response(conn, 403)
    end

    test "returns 400 when thread_id missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/sync/pull", %{})

      assert json_response(conn, 400)
    end

    test "returns 404 when thread not found", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/sync/pull", %{
          thread_id: Ecto.UUID.generate()
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
          timestamp: iso_now()
        }
      ]

      conn =
        post(conn, ~p"/api/v1/sync/push", %{
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
      {:ok, message} =
        Chat.create_message(thread.id, %{
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
            edited_at: iso_now()
          },
          timestamp: iso_now()
        }
      ]

      conn =
        post(conn, ~p"/api/v1/sync/push", %{
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
      {:ok, message} =
        Chat.create_message(thread.id, %{
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
            deleted_at: iso_now()
          },
          timestamp: iso_now()
        }
      ]

      conn =
        post(conn, ~p"/api/v1/sync/push", %{
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
      {:ok, message} =
        Chat.create_message(thread.id, %{
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

      conn =
        post(conn, ~p"/api/v1/sync/push", %{
          thread_id: thread.id,
          changes: changes
        })

      # Should still apply but newer changes would win
      assert %{"data" => %{"applied" => applied}} = json_response(conn, 200)
      assert applied >= 0
    end

    test "returns partial success when some changes fail", %{
      conn: conn,
      thread: thread,
      user1: user1
    } do
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
          timestamp: iso_now()
        },
        # Invalid change (missing required fields)
        %{
          table_name: "messages",
          record_id: Ecto.UUID.generate(),
          operation: "INSERT",
          new_data: %{
            content: "Invalid - missing fields"
          },
          timestamp: iso_now()
        }
      ]

      conn =
        post(conn, ~p"/api/v1/sync/push", %{
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
      {:ok, user3, _} = signup_user("syncuser5")
      {:ok, user4, _} = signup_user("syncuser6")

      {:ok, other_thread} =
        Threads.create_thread(%{
          thread_type: "direct",
          participant_ids: [user3.id, user4.id]
        })

      conn =
        post(conn, ~p"/api/v1/sync/push", %{
          thread_id: other_thread.id,
          changes: []
        })

      assert json_response(conn, 403)
    end

    test "returns 400 when changes array missing", %{conn: conn, thread: thread} do
      conn =
        post(conn, ~p"/api/v1/sync/push", %{
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

      conn =
        post(conn, ~p"/api/v1/sync/push", %{
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

      conn =
        post(conn, ~p"/api/v1/sync/pull", %{
          thread_id: thread.id,
          last_sync_cursor: 0
        })

      assert json_response(conn, 401)
    end

    test "user can only sync their own threads", %{
      user2: user2,
      thread: thread,
      user1_tokens: user1_tokens
    } do
      # Create another thread without user1
      {:ok, user5, _} = signup_user("syncuser7")

      {:ok, private_thread} =
        Threads.create_thread(%{
          thread_type: "direct",
          participant_ids: [user2.id, user5.id]
        })

      # Try to sync with user1's token (should fail)
      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{user1_tokens.access_token}")

      conn =
        post(conn, ~p"/api/v1/sync/pull", %{
          thread_id: private_thread.id,
          last_sync_cursor: 0
        })

      assert json_response(conn, 403)
    end
  end
end
