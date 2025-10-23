defmodule GlobalbridgeBackend.Auth.Auth0Verifier do
  @moduledoc """
  Auth0 token verification module.
  Verifies JWT tokens issued by Auth0 and manages user creation/lookup.
  """

  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.User
  alias GlobalbridgeBackend.Auth.JWTVerifier
  require Logger

  @doc """
  Verify an Auth0 JWT token and return the associated user.
  Creates a new user if one doesn't exist.
  """
  def verify_and_get_user(token) do
    Logger.info("🔐 [AUTH0] Attempting to verify token: #{String.slice(token, 0, 20)}...")

    with {:ok, claims} <- JWTVerifier.verify_token(token),
         {:ok, user} <- ensure_user_exists(claims) do
      {:ok, user}
    else
      {:error, reason} ->
        Logger.error("❌ [AUTH0] Token verification failed: #{inspect(reason)}")
        {:error, reason}
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
end
