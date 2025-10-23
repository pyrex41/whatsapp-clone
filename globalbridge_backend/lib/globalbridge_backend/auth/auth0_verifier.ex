defmodule GlobalbridgeBackend.Auth.Auth0Verifier do
  @moduledoc """
  Auth0 token verification module.
  Verifies JWT tokens issued by Auth0 and manages user creation/lookup.
  """

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.User
  require Logger

  @doc """
  Verify an Auth0 JWT token and return the associated user.
  Creates a new user if one doesn't exist.
  """
  def verify_and_get_user(token) do
    Logger.info("🔐 [AUTH0] Attempting to verify token")
    Logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    Logger.info("📊 [AUTH0] Token received from iOS:")
    Logger.info("   - First 40 chars: #{String.slice(token, 0, 40)}...")
    Logger.info("   - Last 40 chars: ...#{String.slice(token, -40..-1)}")
    Logger.info("   - Total length: #{String.length(token)} characters")

    # Split by dots to count parts
    parts = String.split(token, ".")
    Logger.info("   - Parts count: #{length(parts)} (JWT=3, JWE=5)")

    # Show first part (header) to see algorithm
    if length(parts) > 0 do
      first_part = Enum.at(parts, 0)
      Logger.info("   - First part (header): #{String.slice(first_part, 0, 50)}...")

      # Try to decode header to see what it says
      case Base.url_decode64(first_part, padding: false) do
        {:ok, decoded_header} ->
          Logger.info("   - Decoded header: #{decoded_header}")

        _ ->
          Logger.info("   - Could not decode header as base64")
      end
    end

    Logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

    with {:ok, claims} <- decode_jwt(token),
         :ok <- verify_auth0_token(claims),
         {:ok, user} <- ensure_user_exists(claims) do
      {:ok, user}
    else
      {:error, reason} ->
        Logger.error("❌ [AUTH0] Token verification failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Decode a JWT token without signature verification (for development).
  In production, use proper JWT library with signature verification.

  NOTE: This function expects standard JWT format (3 parts: header.payload.signature).
  If Auth0 returns JWE (encrypted) tokens (5 parts), this will fail.

  To fix JWE issues:
  1. Go to Auth0 Dashboard > Applications > APIs
  2. Find API with identifier: "globalbridge-api"
  3. Settings > Access Settings > Token Format: Set to "JWT" (not "JWE")
  4. Save changes
  """
  def decode_jwt(token) do
    parts = String.split(token, ".")
    part_count = length(parts)

    case parts do
      [_header, payload, _signature] ->
        Logger.debug("🔍 [AUTH0] Token format: JWT (3 parts) ✅")

        with {:ok, decoded} <- Base.url_decode64(payload, padding: false),
             {:ok, json} <- Jason.decode(decoded) do
          {:ok, json}
        else
          _ -> {:error, :invalid_jwt}
        end

      _ when part_count == 5 ->
        Logger.error(
          "❌ [AUTH0] Token format: JWE (#{part_count} parts) - ENCRYPTED TOKEN DETECTED!"
        )

        Logger.error(
          "   ⚠️  Backend cannot decode JWE tokens. You must configure Auth0 to return JWT tokens."
        )

        Logger.error(
          "   📋 Fix: Auth0 Dashboard > APIs > globalbridge-api > Settings > Token Format: JWT"
        )

        Logger.error("   🔗 Token prefix: #{String.slice(token, 0, 30)}...")
        {:error, :jwe_token_not_supported}

      _ ->
        Logger.error("❌ [AUTH0] Invalid token format: #{part_count} parts (expected 3 for JWT)")
        {:error, :invalid_jwt}
    end
  rescue
    e ->
      Logger.error("❌ [AUTH0] Exception decoding token: #{inspect(e)}")
      {:error, :invalid_jwt}
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

    # Try standard claims first, then custom namespaced claims
    email = claims["email"] || claims["https://globalbridge.com/email"]

    name =
      claims["name"] || claims["https://globalbridge.com/name"] || claims["nickname"] ||
        claims["preferred_username"]

    Logger.info(
      "🔐 [AUTH0] Token claims: sub=#{auth0_id}, email=#{email}, all_keys=#{inspect(Map.keys(claims))}"
    )

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
          # Auth0 users don't need phone numbers - they authenticate via email
          # phone_number field is optional and can be added later if needed
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

        # Update email and display_name if they're missing
        updates = %{}

        updates =
          if is_nil(user.email) and email, do: Map.put(updates, :email, email), else: updates

        updates =
          if is_nil(user.display_name) and name,
            do: Map.put(updates, :display_name, name),
            else: updates

        if map_size(updates) > 0 do
          Logger.info(
            "📝 [AUTH0] Updating user with missing fields: #{inspect(Map.keys(updates))}"
          )

          case User.update_changeset(user, updates) |> Repo.update() do
            {:ok, updated_user} ->
              Logger.info("✅ [AUTH0] User updated successfully")
              {:ok, updated_user}

            {:error, changeset} ->
              Logger.warning(
                "⚠️ [AUTH0] Failed to update user: #{inspect(changeset.errors)}, continuing with existing user"
              )

              {:ok, user}
          end
        else
          {:ok, user}
        end
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
end
