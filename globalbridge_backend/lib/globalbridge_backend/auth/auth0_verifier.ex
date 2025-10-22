defmodule GlobalbridgeBackend.Auth.Auth0Verifier do
  @moduledoc """
  Auth0 token verification module.
  Verifies JWT tokens issued by Auth0 and manages user creation/lookup.
  """

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.User
  require Logger

  # Auth bypass for testing - maps test tokens to usernames
  @test_tokens %{
    "test-token-alice" => "alice",
    "test-token-bob" => "bob",
    "test-token-testuser" => "testuser",
    # Legacy support
    "test-token-for-backend-integration" => "test_user"
  }

  @doc """
  Verify an Auth0 JWT token and return the associated user.
  Creates a new user if one doesn't exist.
  Supports test token bypass for development/testing.
  """
  def verify_and_get_user(token) do
    # Check for test token bypass
    case Map.get(@test_tokens, token) do
      nil ->
        # Not a test token, proceed with normal verification
        Logger.info("🔐 [AUTH0] Attempting to verify token: #{String.slice(token, 0, 20)}...")

        with {:ok, claims} <- decode_jwt(token),
             :ok <- verify_auth0_token(claims),
             {:ok, user} <- ensure_user_exists(claims) do
          {:ok, user}
        else
          {:error, reason} ->
            Logger.error("❌ [AUTH0] Token verification failed: #{inspect(reason)}")
            {:error, reason}
        end

      username ->
        # Test token found
        Logger.warning("⚠️ [AUTH BYPASS] Test token detected for user: #{username}")
        get_test_user_by_username(username)
    end
  end

  @doc """
  Decode a JWT token without signature verification (for development).
  In production, use proper JWT library with signature verification.
  """
  def decode_jwt(token) do
    case String.split(token, ".") do
      [_header, payload, _signature] ->
        with {:ok, decoded} <- Base.url_decode64(payload, padding: false),
             {:ok, json} <- Jason.decode(decoded) do
          {:ok, json}
        else
          _ -> {:error, :invalid_jwt}
        end

      _ ->
        {:error, :invalid_jwt}
    end
  rescue
    _ -> {:error, :invalid_jwt}
  end

  defp verify_auth0_token(claims) do
    # Check if this looks like an Auth0 token
    if Map.has_key?(claims, "sub") and
         (Map.has_key?(claims, "iss") or Map.has_key?(claims, "aud")) do
      # In production, verify:
      # 1. Token signature against Auth0's public keys
      # 2. Issuer (iss) matches your Auth0 domain
      # 3. Audience (aud) matches your API identifier
      # 4. Token hasn't expired (exp)

      # For development, we'll accept it
      :ok
    else
      {:error, :not_auth0_token}
    end
  end

  defp ensure_user_exists(claims) do
    auth0_id = claims["sub"]
    email = claims["email"]
    name = claims["name"] || claims["nickname"] || claims["preferred_username"]

    Logger.info("🔐 [AUTH0] Token claims: sub=#{auth0_id}, email=#{email}")

    # Try to find user by auth0_id
    case Repo.get_by(User, auth0_id: auth0_id) do
      nil ->
        # User doesn't exist, create them
        Logger.info("👤 [AUTH0] Creating new user: auth0_id=#{auth0_id}, email=#{email}")

        username = generate_username(email, name)

        attrs = %{
          auth0_id: auth0_id,
          email: email,
          username: username,
          display_name: name,
          # Placeholder
          phone_number: "+10000000000",
          # Auth0 manages password
          password_hash: "auth0_managed"
        }

        case User.create_changeset(%User{}, attrs) |> Repo.insert() do
          {:ok, user} ->
            Logger.info("✅ [AUTH0] User created: id=#{user.id}, username=#{user.username}")
            {:ok, user}

          {:error, changeset} ->
            Logger.error("❌ [AUTH0] User creation failed: #{inspect(changeset.errors)}")
            {:error, :user_creation_failed}
        end

      user ->
        Logger.info("✅ [AUTH0] Existing user found: id=#{user.id}, username=#{user.username}")
        {:ok, user}
    end
  end

  defp generate_username(email, name) do
    # Generate username from email or name
    base =
      cond do
        email && String.contains?(email, "@") ->
          email |> String.split("@") |> List.first()

        name ->
          name |> String.downcase() |> String.replace(~r/\s+/, "_")

        true ->
          "user"
      end

    # Add timestamp to ensure uniqueness
    "#{base}_#{:os.system_time(:millisecond)}"
  end

  # Get test user by username for auth bypass testing
  defp get_test_user_by_username(username) do
    case Repo.get_by(User, username: username) do
      nil ->
        Logger.error("❌ [AUTH BYPASS] Test user not found: #{username}")
        {:error, :user_not_found}

      user ->
        Logger.info("✅ [AUTH BYPASS] Test user found: id=#{user.id}, username=#{user.username}")
        {:ok, user}
    end
  end
end
