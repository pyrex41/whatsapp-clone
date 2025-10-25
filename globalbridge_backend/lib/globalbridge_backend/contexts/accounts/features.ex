defmodule GlobalbridgeBackend.Contexts.Accounts.Features do
  @moduledoc """
  Temporary feature-flag stub so downstream controllers can function while the
  real implementation is in progress.
  """

  @tiers ~w(free premium enterprise)a

  def get_user_features(user) do
    tier = if user.tier, do: String.to_existing_atom(user.tier), else: :free

    %{
      messaging: %{enabled: true},
      media_upload: %{enabled: true},
      sync: %{enabled: true},
      bridges: %{
        enabled: true,
        telegram: %{enabled: bridge_enabled?(tier, :telegram)},
        whatsapp: %{enabled: bridge_enabled?(tier, :whatsapp)},
        max_bridges: max_bridges(tier),
        webhook_support: webhook_support?(tier)
      },
      ai_features: %{
        enabled: ai_enabled?(tier),
        translation: %{enabled: ai_enabled?(tier)},
        summarization: %{enabled: ai_enabled?(tier)},
        semantic_search: %{enabled: ai_enabled?(tier)}
      },
      monitoring: %{
        enabled: monitoring_enabled?(tier),
        metrics: %{enabled: monitoring_enabled?(tier)},
        health_checks: %{enabled: true}
      }
    }
  end

  def tier_limits(tier) do
    case tier do
      :free ->
        %{
          max_members_per_thread: 10,
          max_devices: 2,
          max_bridges: 1,
          ai_requests_per_day: 50
        }

      :premium ->
        %{
          max_members_per_thread: 50,
          max_devices: 5,
          max_bridges: 3,
          ai_requests_per_day: 500
        }

      :enterprise ->
        %{
          max_members_per_thread: :infinite,
          max_devices: :infinite,
          max_bridges: :infinite,
          ai_requests_per_day: :infinite
        }
    end
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

  # Bridge feature helpers

  defp bridge_enabled?(tier, bridge_type) do
    case {tier, bridge_type} do
      {:free, :telegram} -> true
      {:free, :whatsapp} -> false
      {:premium, _} -> true
      {:enterprise, _} -> true
      _ -> false
    end
  end

  defp max_bridges(tier) do
    case tier do
      :free -> 1
      :premium -> 3
      :enterprise -> :infinite
    end
  end

  defp webhook_support?(tier) do
    tier in [:premium, :enterprise]
  end

  # AI feature helpers

  defp ai_enabled?(tier) do
    tier != :free
  end

  # Monitoring feature helpers

  defp monitoring_enabled?(tier) do
    tier == :enterprise
  end
end
