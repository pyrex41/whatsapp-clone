defmodule GlobalbridgeBackendWeb.ThreadControllerTest do
  use GlobalbridgeBackendWeb.ConnCase

  alias GlobalbridgeBackend.Contexts.{Auth, Threads}

  setup %{conn: conn} do
    {:ok, user, tokens} =
      Auth.signup(%{
        "username" => "thread_user",
        "phone_number" => "+11234567890",
        "password" => "password123",
        "display_name" => "Thread User"
      })

    {:ok, _thread} = Threads.create_thread(%{
      thread_type: "direct",
      participant_ids: [user.id]
    })

    authed_conn = put_req_header(conn, "authorization", "Bearer #{tokens.access_token}")

    {:ok, conn: authed_conn, user: user}
  end

  test "GET /api/v1/threads returns thread list", %{conn: conn} do
    conn = get(conn, ~p"/api/v1/threads")

    assert %{"data" => threads} = json_response(conn, 200)
    assert length(threads) >= 1

    first = hd(threads)
    assert Map.has_key?(first, "id")
    assert Map.has_key?(first, "thread_type")
    assert Map.has_key?(first, "database_shard_id")
  end
end
