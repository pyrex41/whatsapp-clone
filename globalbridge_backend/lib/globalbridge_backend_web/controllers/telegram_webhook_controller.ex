defmodule GlobalbridgeBackendWeb.TelegramWebhookController do
  use GlobalbridgeBackendWeb, :controller

  alias GlobalbridgeBackend.Bridges.Registry
  alias GlobalbridgeBackend.Bridges.Telegram.Server, as: TelegramServer

  @doc """
  Handles incoming webhook updates from Telegram.
  """
  def webhook(conn, %{"bridge_id" => bridge_id} = params) do
    # Verify the bridge exists and is active
    case Registry.lookup_bridge(bridge_id) do
      {:ok, server_pid} ->
        # Verify webhook secret and signature if configured
        case verify_webhook_auth(conn, server_pid) do
          :ok ->
            # Process the webhook update
            TelegramServer.process_webhook_update(server_pid, params)

            # Return 200 OK to acknowledge receipt
            json(conn, %{status: "ok"})

          {:error, reason} ->
            Logger.warning(
              "Webhook authentication failed for bridge #{bridge_id}: #{inspect(reason)}"
            )

            conn
            |> put_status(401)
            |> json(%{error: "Authentication failed: #{inspect(reason)}"})
        end

      {:error, :not_found} ->
        Logger.warning("Webhook received for unknown bridge #{bridge_id}")

        conn
        |> put_status(404)
        |> json(%{error: "Bridge not found"})
    end
  end

  @doc """
  Sets up a webhook for a bridge.
  """
  def setup_webhook(conn, %{"bridge_id" => bridge_id, "webhook_url" => webhook_url}) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    case Registry.lookup_bridge(bridge_id) do
      {:ok, server_pid} ->
        # Generate webhook secret
        secret = generate_webhook_secret()

        case TelegramServer.enable_webhook(server_pid, webhook_url, secret) do
          {:ok, result} ->
            json(conn, %{
              status: "webhook_enabled",
              webhook_url: webhook_url,
              secret_token: secret
            })

          {:error, reason} ->
            conn
            |> put_status(500)
            |> json(%{error: "Failed to enable webhook: #{inspect(reason)}"})
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Bridge not found"})
    end
  end

  @doc """
  Disables webhook for a bridge.
  """
  def disable_webhook(conn, %{"bridge_id" => bridge_id}) do
    user = conn.assigns[:current_user] || Guardian.Plug.current_resource(conn)

    case Registry.lookup_bridge(bridge_id) do
      {:ok, server_pid} ->
        case TelegramServer.disable_webhook(server_pid) do
          :ok ->
            json(conn, %{status: "webhook_disabled"})

          {:error, reason} ->
            conn
            |> put_status(500)
            |> json(%{error: "Failed to disable webhook: #{inspect(reason)}"})
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Bridge not found"})
    end
  end

  # Private functions

  defp verify_webhook_auth(conn, server_pid) do
    # Get webhook configuration from server
    case TelegramServer.get_status(server_pid) do
      %{webhook_secret: secret} when not is_nil(secret) ->
        # Verify secret token (primary method)
        secret_token = get_req_header(conn, "x-telegram-bot-api-secret-token")

        if secret_token == [secret] do
          :ok
        else
          # Fallback to signature verification if secret token fails
          verify_signature(conn, secret)
        end

      _ ->
        # No secret configured - allow webhook (less secure)
        Logger.warning("Webhook received without secret token verification")
        :ok
    end
  end

  defp verify_signature(conn, secret) do
    # Telegram webhook signature verification
    # Note: Telegram doesn't actually sign webhooks, but this is prepared for future use
    # or for other webhook providers that do sign requests

    signature = get_req_header(conn, "x-signature")
    timestamp = get_req_header(conn, "x-timestamp")

    case {signature, timestamp} do
      {[sig], [ts]} ->
        # Verify signature (placeholder implementation)
        # In a real implementation, you'd verify the signature against request body
        body = conn.assigns[:raw_body] || ""
        expected_signature = generate_signature(body, ts, secret)

        if sig == expected_signature do
          :ok
        else
          {:error, :invalid_signature}
        end

      _ ->
        {:error, :missing_signature_headers}
    end
  end

  defp generate_signature(body, timestamp, secret) do
    # Generate HMAC signature (placeholder)
    # In production, use proper HMAC-SHA256
    :crypto.hash(:sha256, "#{body}#{timestamp}#{secret}")
    |> Base.encode16(case: :lower)
  end

  defp get_bridge_webhook_secret(server_pid) do
    # Get webhook secret from server state
    # This is a simplified implementation - in production you'd want to store
    # secrets securely and validate them properly
    case TelegramServer.get_status(server_pid) do
      %{webhook_secret: secret} when not is_nil(secret) -> secret
      _ -> nil
    end
  end

  defp generate_webhook_secret do
    # Generate a secure random secret for webhook validation
    :crypto.strong_rand_bytes(32) |> Base.encode64()
  end
end
