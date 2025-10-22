defmodule GlobalbridgeBackend.Auth.TokenHandler do
  @moduledoc """
  Handles token expiration, refresh, and error responses.

  This module:
  - Detects expired tokens and suggests refresh
  - Formats helpful error messages for clients
  - Manages token refresh workflows
  - Logs token lifecycle events
  """

  require Logger

  @doc """
  Analyze a token verification error and return a client-friendly response.

  Returns: {:error, error_atom, message}
  """
  def handle_verification_error(:token_expired) do
    Logger.info("⏰ [TOKEN] Token expired, client should refresh")

    {
      :error,
      :token_expired,
      "Your session has expired. Please log in again to refresh your token."
    }
  end

  def handle_verification_error(:invalid_audience) do
    Logger.warning("🔍 [TOKEN] Token has wrong audience")

    {
      :error,
      :invalid_token,
      "This token is not valid for this application."
    }
  end

  def handle_verification_error(:invalid_issuer) do
    Logger.warning("🔍 [TOKEN] Token has wrong issuer")

    {
      :error,
      :invalid_token,
      "This token was not issued by the correct provider."
    }
  end

  def handle_verification_error(:invalid_claims) do
    Logger.warning("🔍 [TOKEN] Token has missing or invalid claims")

    {
      :error,
      :invalid_token,
      "This token is missing required information."
    }
  end

  def handle_verification_error(:invalid_format) do
    Logger.warning("🔍 [TOKEN] Token is not in valid JWT format")

    {
      :error,
      :invalid_token,
      "The token provided is not in a valid format."
    }
  end

  def handle_verification_error(:unsupported_algorithm) do
    Logger.warning("🔍 [TOKEN] Token uses unsupported algorithm")

    {
      :error,
      :invalid_token,
      "The token uses an unsupported signing algorithm."
    }
  end

  def handle_verification_error(reason) do
    Logger.error("❌ [TOKEN] Unexpected verification error: #{inspect(reason)}")

    {
      :error,
      :authentication_failed,
      "Authentication failed. Please try again."
    }
  end

  @doc """
  Get time until token expiration from claims.

  Returns seconds, or nil if no exp claim.
  """
  def get_expiration_seconds(claims) when is_map(claims) do
    case claims["exp"] do
      exp_time when is_integer(exp_time) ->
        max(0, exp_time - System.system_time(:second))

      _ ->
        nil
    end
  end

  @doc """
  Check if token is expiring soon (within X minutes).
  """
  def is_expiring_soon?(claims, minutes \\ 5) when is_map(claims) do
    case get_expiration_seconds(claims) do
      nil ->
        false

      seconds ->
        seconds < minutes * 60
    end
  end

  @doc """
  Log token verification details for debugging.
  """
  def log_verification_details(token, reason) do
    # Try to extract header for algorithm info without verifying signature
    case String.split(token, ".") do
      [header_b64, _payload_b64, _sig] ->
        case Base.url_decode64(header_b64, padding: false) do
          {:ok, header_json} ->
            case Jason.decode(header_json) do
              {:ok, header} ->
                Logger.debug(
                  "🔐 [TOKEN] Verification failed - reason: #{inspect(reason)}, alg: #{header["alg"]}, kid: #{header["kid"]}"
                )

              _ ->
                :ok
            end

          _ ->
            :ok
        end

      _ ->
        :ok
    end
  end

  @doc """
  Format error response for WebSocket or HTTP client.

  Returns: %{error: atom, message: string}
  """
  def format_error_response({:error, error_code, message}) do
    %{
      error: error_code,
      message: message,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Create a suggested refresh token response.

  Tells the client they should refresh their token.
  """
  def suggest_token_refresh(user_id) do
    Logger.info("🔄 [TOKEN] Suggesting refresh for user: #{user_id}")

    %{
      action: "refresh_token",
      message: "Your authentication token is expiring soon. Please refresh it.",
      user_id: user_id,
      suggested_refresh_at: DateTime.add(DateTime.utc_now(), -30, :second)
    }
  end

  @doc """
  Extract user info from token claims for logging/debugging.
  """
  def extract_user_info(claims) when is_map(claims) do
    %{
      user_id: claims["sub"],
      email: claims["email"],
      name: claims["name"] || claims["nickname"],
      expires_in: get_expiration_seconds(claims)
    }
  end
end
