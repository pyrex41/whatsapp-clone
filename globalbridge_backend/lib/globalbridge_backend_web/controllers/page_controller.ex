defmodule GlobalbridgeBackendWeb.PageController do
  use GlobalbridgeBackendWeb, :controller

  def elm_client(conn, _params) do
    conn
    |> put_resp_header("content-type", "text/html; charset=utf-8")
    |> send_file(200, Application.app_dir(:globalbridge_backend, "priv/static/elm/index.html"))
  end
end
