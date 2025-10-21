defmodule GlobalbridgeBackendWeb.BootstrapController do
  use GlobalbridgeBackendWeb, :controller
  alias GlobalbridgeBackend.Contexts.Threads

  @doc """
  Bootstrap endpoint for Elm client initial data hydration.
  Returns user profile, threads, and bridge summary.
  """
  def index(conn, _params) do
    user = conn.assigns.current_user

    # Fetch real threads for this user from database
    threads = Threads.list_user_threads(user.id, is_archived: false)

    # Format threads for Elm frontend
    formatted_threads = Enum.map(threads, fn thread ->
      %{
        id: thread.id,
        name: thread.title || "Untitled Thread",
        unread_count: 0,  # TODO: Calculate from read receipts
        created_at: thread.inserted_at,
        updated_at: thread.updated_at,
        last_message: nil,  # TODO: Fetch from thread's message database
        bridge: nil  # TODO: Map bridge data when thread-bridge association is implemented
      }
    end)

    json(conn, %{
      data: %{
        user: %{
          id: user.id,
          username: user.username,
          phone_number: user.phone_number,
          inserted_at: user.inserted_at
        },
        threads: formatted_threads,
        bridges: [],  # TODO: Fetch user's bridge configurations
        csrf_token: get_csrf_token()
      }
    })
  end
end
