defmodule GlobalbridgeBackend.Auth.JWTVerifier do
  @moduledoc """
  JWT verification module for Auth0 tokens.

  Verifies JWT signatures using JWKS cache and validates claims.
  """

  alias GlobalbridgeBackend.Auth.JWKSCache
  require Logger

  @expected_issuer_prefix "https://"
  @expected_audience System.get_env("AUTH0_CLIENT_ID")

  @doc """
  Verifies an Auth0 JWT token.

  Returns {:ok, claims} on success or {:error, reason} on failure.
  """
  def verify_token(token) when is_binary(token) do
    with {:ok, header} <- decode_header(token),
         {:ok, kid} <- extract_kid(header),
         {:ok, jwk} <- JWKSCache.get_key(kid),
         {:ok, claims} <- verify_signature(token, jwk),
         :ok <- validate_claims(claims) do
      {:ok, claims}
    else
      {:error, reason} ->
        Logger.warning("JWT verification failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Extracts claims from a verified JWT without full verification.
  Use only for debugging or when you trust the token source.
  """
  def decode_claims(token) do
    case Joken.peek_claims(token) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> {:error, reason}
    end
  end

  # Private Functions

  defp decode_header(token) do
    case Joken.peek_header(token) do
      {:ok, header} -> {:ok, header}
      {:error, reason} -> {:error, {:invalid_header, reason}}
    end
  end

  defp extract_kid(%{"kid" => kid}) when is_binary(kid), do: {:ok, kid}
  defp extract_kid(_), do: {:error, :missing_kid}

  defp verify_signature(token, jwk) do
    signer = Joken.Signer.create("RS256", jwk)

    case Joken.verify(token, signer) do
      {:ok, claims} -> {:ok, claims}
      {:error, reason} -> {:error, {:signature_verification_failed, reason}}
    end
  end

  defp validate_claims(claims) do
    with :ok <- validate_issuer(claims),
         :ok <- validate_audience(claims),
         :ok <- validate_expiration(claims),
         :ok <- validate_not_before(claims),
         :ok <- validate_issued_at(claims) do
      :ok
    end
  end

  defp validate_issuer(%{"iss" => issuer}) do
    auth0_domain = System.get_env("AUTH0_DOMAIN")

    expected_issuer = @expected_issuer_prefix <> auth0_domain <> "/"

    if issuer == expected_issuer do
      :ok
    else
      {:error, {:invalid_issuer, issuer}}
    end
  end

  defp validate_issuer(_), do: {:error, :missing_issuer}

  defp validate_audience(%{"aud" => audience}) do
    cond do
      is_binary(audience) and audience == @expected_audience ->
        :ok

      is_list(audience) and @expected_audience in audience ->
        :ok

      true ->
        {:error, {:invalid_audience, audience}}
    end
  end

  defp validate_audience(_), do: {:error, :missing_audience}

  defp validate_expiration(%{"exp" => exp}) when is_integer(exp) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    if exp > now do
      :ok
    else
      {:error, :token_expired}
    end
  end

  defp validate_expiration(_), do: {:error, :missing_expiration}

  defp validate_not_before(%{"nbf" => nbf}) when is_integer(nbf) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    if nbf <= now do
      :ok
    else
      {:error, :token_not_yet_valid}
    end
  end

  # nbf is optional
  defp validate_not_before(_), do: :ok

  defp validate_issued_at(%{"iat" => iat}) when is_integer(iat) do
    now = DateTime.utc_now() |> DateTime.to_unix()

    # Allow some clock skew (5 minutes)
    if iat <= now + 300 do
      :ok
    else
      {:error, :invalid_issued_at}
    end
  end

  defp validate_issued_at(_), do: {:error, :missing_issued_at}
end
