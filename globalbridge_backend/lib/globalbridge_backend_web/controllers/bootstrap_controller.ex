defmodule GlobalbridgeBackendWeb.BootstrapController do
  use GlobalbridgeBackendWeb, :controller
  alias GlobalbridgeBackend.Contexts.Threads

  @doc """
  Bootstrap endpoint for Elm client initial data hydration.
  Returns user profile, threads, and bridge summary.
  """
  def index(conn, params) do
    user = conn.assigns.current_user

    # Add pagination to prevent loading too many threads at once
    # Max 50 threads
    limit = min(String.to_integer(params["limit"] || "20"), 50)
    offset = String.to_integer(params["offset"] || "0")

    # Fetch threads with pagination and optimized query
    threads =
      Threads.list_user_threads(user.id,
        is_archived: false,
        limit: limit,
        offset: offset,
        order_by: {:last_message_at, :desc}
      )

    # Format threads for Elm frontend (keep lightweight for now)
    formatted_threads =
      Enum.map(threads, fn thread ->
        %{
          id: thread.id,
          name: thread.title || "Untitled Thread",
          # TODO: Calculate from read receipts (cached)
          unread_count: 0,
          created_at: thread.inserted_at,
          updated_at: thread.updated_at,
          # TODO: Fetch from thread's message database (cached)
          last_message: nil,
          # TODO: Map bridge data when thread-bridge association is implemented
          bridge: nil
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
        pagination: %{
          limit: limit,
          offset: offset,
          has_more: length(threads) == limit
        },
        # TODO: Fetch user's bridge configurations
        bridges: [],
        csrf_token: get_csrf_token()
      }
    })
  end
end
