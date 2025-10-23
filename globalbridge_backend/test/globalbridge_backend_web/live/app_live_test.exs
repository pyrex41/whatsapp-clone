defmodule GlobalbridgeBackendWeb.AppLiveTest do
  use GlobalbridgeBackendWeb.ConnCase
  import Phoenix.LiveViewTest

  alias GlobalbridgeBackend.Contexts.{Auth, Threads, Messages}

  describe "mount/3" do
    test "redirects when no session token", %{conn: conn} do
      # No session token should redirect to login
      assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/app")
    end

    test "loads user data with valid Guardian token", %{conn: conn} do
      # Create test user
      {:ok, user, tokens} = Auth.signup(%{
        username: "testuser",
        phone_number: "+15555551234",
        password: "password123"
      })

      # Create a test thread for this user
      {:ok, thread} = Threads.create_thread(%{
        name: "Test Thread",
        creator_id: user.id
      })

      # Set Guardian token in session
      conn = conn |> init_test_session(%{"guardian_token" => tokens.access})

      # Mount LiveView
      {:ok, _view, html} = live(conn, "/app")

      # Verify thread is displayed
      assert html =~ "Test Thread"
    end
  end

  describe "handle_event send_message" do
    setup %{conn: conn} do
      # Create test user and thread
      {:ok, user, tokens} = Auth.signup(%{
        username: "messageuser",
        phone_number: "+15555555678",
        password: "password123"
      })

      {:ok, thread} = Threads.create_thread(%{
        name: "Chat Thread",
        creator_id: user.id
      })

      # Initialize session and mount LiveView
      conn = conn |> init_test_session(%{"guardian_token" => tokens.access})
      {:ok, view, _html} = live(conn, "/app/threads/#{thread.id}")

      %{view: view, user: user, thread: thread}
    end

    test "persists message to database", %{view: view, thread: thread, user: user} do
      # Send a message via form
      view
      |> form("form", %{content: "Hello, World!"})
      |> render_submit()

      # Verify message was persisted to database
      messages = Messages.list_messages(thread.id)
      assert length(messages) == 1
      assert hd(messages).content == "Hello, World!"
      assert hd(messages).sender_id == user.id
    end

    test "updates UI with sent message", %{view: view} do
      # Send a message
      view
      |> form("form", %{content: "Test message"})
      |> render_submit()

      # Verify UI contains the message
      html = render(view)
      assert html =~ "Test message"
    end

    test "shows error when message creation fails", %{view: view} do
      # Attempt to send empty message (should fail validation)
      view
      |> form("form", %{content: ""})
      |> render_submit()

      # Check for error flash
      html = render(view)
      assert html =~ "Failed to send message" or html =~ "error"
    end
  end

  describe "handle_event select_thread" do
    test "navigates to selected thread", %{conn: conn} do
      {:ok, user, tokens} = Auth.signup(%{
        username: "navuser",
        phone_number: "+15555559999",
        password: "password123"
      })

      {:ok, thread} = Threads.create_thread(%{
        name: "Navigation Thread",
        creator_id: user.id
      })

      conn = conn |> init_test_session(%{"guardian_token" => tokens.access})
      {:ok, view, _html} = live(conn, "/app")

      # Select the thread
      view
      |> element("[phx-click='select_thread'][phx-value-thread_id='#{thread.id}']")
      |> render_click()

      # Verify navigation occurred
      assert_patched(view, "/app/threads/#{thread.id}")
    end
  end

  describe "handle_info new_message broadcast" do
    test "adds new messages from broadcasts to UI", %{conn: conn} do
      {:ok, user, tokens} = Auth.signup(%{
        username: "broadcastuser",
        phone_number: "+15555550000",
        password: "password123"
      })

      {:ok, thread} = Threads.create_thread(%{
        name: "Broadcast Thread",
        creator_id: user.id
      })

      conn = conn |> init_test_session(%{"guardian_token" => tokens.access})
      {:ok, view, _html} = live(conn, "/app/threads/#{thread.id}")

      # Simulate a broadcast from another user
      send(view.pid, %Phoenix.Socket.Broadcast{
        topic: "thread:#{thread.id}",
        event: "new_message",
        payload: %{
          id: "msg-123",
          content: "Broadcast message",
          sender_id: user.id,
          thread_id: thread.id,
          inserted_at: DateTime.utc_now()
        }
      })

      # Wait for message to render
      :timer.sleep(50)

      # Verify broadcast message appears in UI
      html = render(view)
      assert html =~ "Broadcast message"
    end
  end
end
