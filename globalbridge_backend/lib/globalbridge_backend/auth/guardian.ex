defmodule GlobalbridgeBackend.Auth.Guardian do
  @moduledoc """
  Guardian implementation for JWT token generation and validation.
  """
  use Guardian, otp_app: :globalbridge_backend

  alias GlobalbridgeBackend.Schemas.User
  alias GlobalbridgeBackend.Repo

  @doc """
  Subject for JWT tokens - encodes the user ID.
  """
  def subject_for_token(%User{id: id}, _claims) do
    {:ok, to_string(id)}
  end

  def subject_for_token(_, _) do
    {:error, :invalid_resource}
  end

  @doc """
  Resource from claims - decodes the user ID and fetches the user.
  """
  def resource_from_claims(%{"sub" => id}) do
    case Repo.get(User, id) do
      nil -> {:error, :user_not_found}
      user -> {:ok, user}
    end
  end

  def resource_from_claims(_claims) do
    {:error, :invalid_claims}
  end

  @doc """
  Generate access token for user.
  Default expiration: 24 hours
  """
  def generate_access_token(user) do
    claims = %{
      "typ" => "access",
      "username" => user.username,
      "phone_number" => user.phone_number
    }

    encode_and_sign(user, claims, ttl: {24, :hours})
  end

  @doc """
  Generate refresh token for user.
  Default expiration: 7 days
  """
  def generate_refresh_token(user) do
    claims = %{"typ" => "refresh"}
    encode_and_sign(user, claims, ttl: {7, :days})
  end

  @doc """
  Generate both access and refresh tokens.
  """
  def generate_tokens(user) do
    with {:ok, access_token, _claims} <- generate_access_token(user),
         {:ok, refresh_token, _claims} <- generate_refresh_token(user) do
      {:ok, %{access_token: access_token, refresh_token: refresh_token}}
    end
  end

  @doc """
  Verify and refresh tokens.
  """
  def refresh_tokens(refresh_token) do
    with {:ok, _old_stuff, {_token, claims}} <- refresh(refresh_token),
         {:ok, user} <- resource_from_claims(claims) do
      generate_tokens(user)
    end
  end
end
