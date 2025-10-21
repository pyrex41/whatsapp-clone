defmodule GlobalbridgeBackendWeb.AuthJSON do
  @moduledoc """
  JSON rendering for authentication responses.
  """

  @doc """
  Renders authentication success with user and tokens.
  """
  def auth_success(%{user: user, tokens: tokens}) do
    %{
      data: %{
        user: user_data(user),
        tokens: tokens
      }
    }
  end

  @doc """
  Renders user data.
  """
  def user(%{user: user}) do
    %{data: user_data(user)}
  end

  defp user_data(user) do
    %{
      id: user.id,
      username: user.username,
      phone_number: user.phone_number,
      display_name: user.display_name,
      avatar_url: user.avatar_url,
      status_message: user.status_message,
      is_online: user.is_online,
      last_seen_at: user.last_seen_at,
      has_public_key: not is_nil(user.public_key),
      inserted_at: user.inserted_at,
      updated_at: user.updated_at
    }
  end
end
