defmodule GlobalbridgeBackend.Contexts.Accounts.Features do
  @moduledoc """
  Temporary feature-flag stub so downstream controllers can function while the
  real implementation is in progress.
  """

  @tiers ~w(free premium enterprise)a

  def get_user_features(_user) do
    %{
      messaging: %{enabled: true},
      media_upload: %{enabled: true},
      sync: %{enabled: true}
    }
  end

  def tier_limits(_tier) do
    %{
      max_members_per_thread: :infinite,
      max_devices: :infinite
    }
  end

  def has_feature?(_user, _feature), do: true

  def parse_tier(tier) when is_binary(tier) do
    tier
    |> String.downcase()
    |> String.to_atom()
    |> ensure_known_tier()
  rescue
    ArgumentError -> {:error, :invalid_tier}
  end

  def validate_tier_upgrade(_current_tier, target) when is_atom(target) do
    ensure_known_tier(target)
  end

  defp ensure_known_tier(tier) do
    if tier in @tiers do
      {:ok, tier}
    else
      {:error, :invalid_tier}
    end
  end
end
