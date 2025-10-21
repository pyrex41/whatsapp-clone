defmodule GlobalbridgeBackendWeb.BootstrapController do
  use GlobalbridgeBackendWeb, :controller

  @doc """
  Bootstrap endpoint for Elm client initial data hydration.
  Returns user profile, threads, and bridge summary.
  """
  def index(conn, _params) do
    # TODO: Implement actual data fetching in Task 4
    # For now, return minimal bootstrap data
    user = conn.assigns.current_user

    json(conn, %{
      user: %{
        id: user.id,
        email: user.email,
        created_at: user.inserted_at
      },
      threads: [],
      bridges: [],
      csrf_token: get_csrf_token()
    })
  end
end
