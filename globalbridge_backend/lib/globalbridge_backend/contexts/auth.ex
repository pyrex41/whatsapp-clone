defmodule GlobalbridgeBackend.Contexts.Auth do
  @moduledoc """
  Authentication context for user signup, login, and token management.
  """
  import Ecto.Query
  alias GlobalbridgeBackend.Repo
  alias GlobalbridgeBackend.Schemas.User
  alias GlobalbridgeBackend.Auth.Guardian

  @doc """
  Register a new user with username, phone number, and password.
  Optionally accepts public_key for E2EE setup.
  """
  def signup(attrs) do
    attrs_with_hash =
      case Map.get(attrs, "password") do
        nil ->
          attrs

        password ->
          attrs
          |> Map.delete("password")
          |> Map.put("password_hash", hash_password(password))
      end

    %User{}
    |> User.create_changeset(attrs_with_hash)
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        {:ok, tokens} = Guardian.generate_tokens(user)
        {:ok, user, tokens}

      error ->
        error
    end
  end

  @doc """
  Authenticate user with username/phone and password.
  Returns user and JWT tokens on success.
  """
  def login(identifier, password) do
    user =
      from(u in User,
        where: u.username == ^identifier or u.phone_number == ^identifier
      )
      |> Repo.one()

    case user do
      nil ->
        # Run hash to prevent timing attacks
        Bcrypt.no_user_verify()
        {:error, :invalid_credentials}

      user ->
        if verify_password(password, user.password_hash) do
          {:ok, tokens} = Guardian.generate_tokens(user)

          # Update last_seen and online status
          user
          |> User.update_changeset(%{
            last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second),
            is_online: true
          })
          |> Repo.update()

          {:ok, user, tokens}
        else
          {:error, :invalid_credentials}
        end
    end
  end

  @doc """
  Get user by ID.
  """
  def get_user(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Update user's public key for E2EE.
  """
  def update_public_key(user_id, public_key) do
    case get_user(user_id) do
      {:ok, user} ->
        user
        |> User.update_changeset(%{public_key: public_key})
        |> Repo.update()

      error ->
        error
    end
  end

  @doc """
  Get public key for a user (for E2EE key exchange).
  """
  def get_public_key(user_id) do
    case Repo.get(User, user_id) do
      nil -> {:error, :not_found}
      %User{public_key: nil} -> {:error, :no_public_key}
      %User{public_key: public_key} -> {:ok, public_key}
    end
  end

  @doc """
  Update user's online status.
  """
  def update_online_status(user_id, is_online) do
    case get_user(user_id) do
      {:ok, user} ->
        user
        |> User.update_changeset(%{
          is_online: is_online,
          last_seen_at:
            if(is_online,
              do: DateTime.utc_now() |> DateTime.truncate(:second),
              else: user.last_seen_at
            )
        })
        |> Repo.update()

      error ->
        error
    end
  end

  @doc """
  Change user password.
  """
  def change_password(user_id, current_password, new_password) do
    with {:ok, user} <- get_user(user_id),
         true <- verify_password(current_password, user.password_hash) do
      user
      |> User.password_changeset(%{password_hash: hash_password(new_password)})
      |> Repo.update()
    else
      false -> {:error, :invalid_password}
      error -> error
    end
  end

  @doc """
  Verify user credentials without logging in.
  """
  def verify_credentials(identifier, password) do
    case login(identifier, password) do
      {:ok, user, _tokens} -> {:ok, user}
      error -> error
    end
  end

  @doc """
  Search for users by email, username, or display name.
  Excludes the searching user from results.
  """
  def search_users(query, current_user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 20)
    search_pattern = "%#{String.downcase(query)}%"

    from(u in User,
      where: u.id != ^current_user_id,
      where:
        like(fragment("lower(?)", u.email), ^search_pattern) or
          like(fragment("lower(?)", u.username), ^search_pattern) or
          like(fragment("lower(?)", u.display_name), ^search_pattern),
      limit: ^limit,
      order_by: [asc: u.username]
    )
    |> Repo.all()
  end

  # Private functions

  defp hash_password(password) do
    Bcrypt.hash_pwd_salt(password)
  end

  defp verify_password(password, hash) do
    Bcrypt.verify_pass(password, hash)
  end
end
