defmodule GlobalbridgeBackendWeb.ThreadController do
  use GlobalbridgeBackendWeb, :controller

  alias GlobalbridgeBackend.Auth.Guardian
  alias GlobalbridgeBackend.Contexts.Threads

  action_fallback GlobalbridgeBackendWeb.FallbackController

  @doc """
  Lists threads for the authenticated user.
  """
  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)

    threads =
      Threads.list_user_threads(user.id, is_archived: false)

    render(conn, :index, threads: threads)
  end
end
