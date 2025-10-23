defmodule GlobalbridgeBackend.Auth.Plugs.RequireThreadAccess do
  @moduledoc """
  Plug to ensure the current authenticated user has access to the requested thread.

  This plug checks if the current user is a participant in the thread specified
  in the conn params. It should be used after authentication plugs to ensure
  proper authorization for thread-specific operations.

  ## Usage

      # In your router or controller
      plug RequireThreadAccess when action in [:show, :update, :delete]

      # Or in a specific pipeline
      pipeline :thread_access do
        plug GlobalbridgeBackend.Auth.Pipeline
        plug RequireThreadAccess
      end

  ## Params

  The plug looks for the thread_id in conn.params in the following order:
  - `thread_id` (from URL params)
  - `id` (for RESTful routes)

  ## Errors

  Returns 403 Forbidden if:
  - User is not a participant in the thread
  - Thread does not exist

  Returns 400 Bad Request if:
  - No thread_id is provided in params
  """

  import Plug.Conn
  import Ecto.Query

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.ThreadParticipant
  alias GlobalbridgeBackend.Auth.Guardian

  def init(opts), do: opts

  def call(conn, _opts) do
    user = Guardian.Plug.current_resource(conn)
    thread_id = get_thread_id(conn)

    cond do
      is_nil(thread_id) ->
        conn
        |> put_status(:bad_request)
        |> Phoenix.Controller.json(%{error: "Thread ID is required"})
        |> halt()

      is_nil(user) ->
        # This should not happen if auth pipeline is in place
        conn
        |> put_status(:unauthorized)
        |> Phoenix.Controller.json(%{error: "Authentication required"})
        |> halt()

      has_thread_access?(user.id, thread_id) ->
        conn

      true ->
        conn
        |> put_status(:forbidden)
        |> Phoenix.Controller.json(%{error: "You do not have access to this thread"})
        |> halt()
    end
  end

  defp get_thread_id(conn) do
    conn.params["thread_id"] || conn.params["id"]
  end

  defp has_thread_access?(user_id, thread_id) do
    query =
      from(tp in ThreadParticipant,
        where: tp.user_id == ^user_id and tp.thread_id == ^thread_id,
        select: count(tp.id)
      )

    case Repo.one(query) do
      nil -> false
      0 -> false
      count when count > 0 -> true
    end
  end
end
