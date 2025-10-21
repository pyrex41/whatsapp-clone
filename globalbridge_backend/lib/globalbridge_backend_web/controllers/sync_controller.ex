defmodule GlobalbridgeBackendWeb.SyncController do
  @moduledoc """
  REST controller exposing CDC (Change Data Capture) pull/push endpoints for
  mobile clients. Delegates heavy lifting to `GlobalbridgeBackend.Sync`.
  """

  use GlobalbridgeBackendWeb, :controller

  alias GlobalbridgeBackend.Auth.Guardian
  alias GlobalbridgeBackend.Sync

  action_fallback(GlobalbridgeBackendWeb.FallbackController)

  @doc """
  POST /api/v1/sync/pull

  Fetch CDC logs for the requested `thread_id`. Supports optional cursor
  parameters:

    * `"since"` - ISO8601 timestamp string
    * `"last_sync_cursor"` - legacy cursor value; when provided as a string it
      will be parsed as ISO8601 as well.
  """
  def pull(conn, %{"thread_id" => thread_id} = params) do
    user = Guardian.Plug.current_resource(conn)
    since = parse_since(params)

    require Logger

    Logger.debug(
      "[SYNC] Pull request: thread=#{thread_id}, since_param=#{inspect(params["since"])}, since_parsed=#{inspect(since)}"
    )

    with {:ok, thread} <- Sync.fetch_thread(thread_id),
         :ok <- Sync.authorize_thread_access(user.id, thread) do
      {changes, cursor} = Sync.pull_changes(thread, since: since)

      Logger.debug("[SYNC] Returning #{length(changes)} changes, cursor=#{inspect(cursor)}")

      conn
      |> put_status(:ok)
      |> render(:pull_success, changes: changes, cursor: cursor)
    end
  end

  def pull(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: thread_id"})
  end

  @doc """
  POST /api/v1/sync/push

  Applies CDC changes originating from the client to the server.
  """
  def push(conn, %{"thread_id" => thread_id, "changes" => changes}) when is_list(changes) do
    user = Guardian.Plug.current_resource(conn)

    with {:ok, thread} <- Sync.fetch_thread(thread_id),
         :ok <- Sync.authorize_thread_access(user.id, thread) do
      results = Sync.apply_changes(thread, changes, user.id)

      applied = Enum.count(results, &match?(%{"success" => true}, &1))
      failed = Enum.count(results, &match?(%{"success" => false}, &1))

      conn
      |> put_status(:ok)
      |> render(:push_success, applied: applied, failed: failed, results: results)
    end
  end

  def push(conn, %{"thread_id" => _thread_id}) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameter: changes (must be an array)"})
  end

  def push(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing required parameters: thread_id and changes"})
  end

  # -- Helpers ----------------------------------------------------------------

  defp parse_since(params) do
    params
    |> Map.get("since") ||
      Map.get(params, "last_sync_cursor")
      |> parse_timestamp_param()
  end

  defp parse_timestamp_param(nil), do: nil
  defp parse_timestamp_param(""), do: nil

  defp parse_timestamp_param(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _} ->
        # Truncate to second precision to match database storage
        DateTime.truncate(datetime, :second)

      _ ->
        nil
    end
  end

  defp parse_timestamp_param(_), do: nil
end
