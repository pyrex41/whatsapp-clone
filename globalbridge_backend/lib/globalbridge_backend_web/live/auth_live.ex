defmodule GlobalbridgeBackendWeb.AuthLive do
  use GlobalbridgeBackendWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("login", _params, socket) do
    # Redirect to Auth0 login
    auth0_url = build_auth0_login_url()
    {:noreply, redirect(socket, external: auth0_url)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-gray-50 py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-8">
        <div>
          <h2 class="mt-6 text-center text-3xl font-extrabold text-gray-900">
            Sign in to GlobalBridge
          </h2>
          <p class="mt-2 text-center text-sm text-gray-600">
            Secure messaging platform
          </p>
        </div>
        <div class="mt-8">
          <button
            phx-click="login"
            class="group relative w-full flex justify-center py-2 px-4 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
          >
            <span class="absolute left-0 inset-y-0 flex items-center pl-3">
              <svg class="h-5 w-5 text-blue-500 group-hover:text-blue-400" fill="currentColor" viewBox="0 0 20 20">
                <path fill-rule="evenodd" d="M5 9V7a5 5 0 0110 0v2a2 2 0 012 2v5a2 2 0 01-2 2H5a2 2 0 01-2-2v-5a2 2 0 012-2zm8-2v2H7V7a3 3 0 016 0z" clip-rule="evenodd" />
              </svg>
            </span>
            Sign in with Auth0
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp build_auth0_login_url do
    domain = System.get_env("AUTH0_DOMAIN")
    client_id = System.get_env("AUTH0_CLIENT_ID")
    audience = System.get_env("AUTH0_AUDIENCE", "globalbridge-api")

    redirect_uri = "#{GlobalbridgeBackendWeb.Endpoint.url()}/api/auth/auth0/callback"

    params = %{
      client_id: client_id,
      redirect_uri: redirect_uri,
      scope: "openid profile email offline_access",
      response_type: "code",
      audience: audience
    }

    query = URI.encode_query(params)
    "https://#{domain}/authorize?#{query}"
  end
end
