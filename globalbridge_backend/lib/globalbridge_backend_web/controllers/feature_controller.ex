defmodule GlobalbridgeBackendWeb.FeatureController do
  @moduledoc """
  Controller for feature flag endpoints.
  Provides information about available features for the authenticated user's tier.
  """
  use GlobalbridgeBackendWeb, :controller

  alias GlobalbridgeBackend.Contexts.Accounts.Features
  alias GlobalbridgeBackend.Auth.Guardian

  action_fallback GlobalbridgeBackendWeb.FallbackController

  @doc """
  GET /api/features
  Get all feature flags for the current authenticated user.

  Returns a map of feature names to boolean values indicating availability.
  """
  def index(conn, _params) do
    user = Guardian.Plug.current_resource(conn)
    features = Features.get_user_features(user)

    conn
    |> put_status(:ok)
    |> json(%{
      data: %{
        tier: user.tier,
        features: features,
        limits: Features.tier_limits(String.to_existing_atom(user.tier))
      }
    })
  end

  @doc """
  GET /api/features/:feature
  Check if the current user has access to a specific feature.
  """
  def show(conn, %{"feature" => feature_name}) do
    user = Guardian.Plug.current_resource(conn)

    try do
      feature = String.to_existing_atom(feature_name)
      has_access = Features.has_feature?(user, feature)

      conn
      |> put_status(:ok)
      |> json(%{
        data: %{
          feature: feature_name,
          has_access: has_access,
          tier: user.tier
        }
      })
    rescue
      ArgumentError ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Feature not found: #{feature_name}"})
    end
  end

  @doc """
  PUT /api/features/tier
  Update user's tier (admin only - for now just authenticated users can upgrade).
  """
  def update_tier(conn, %{"tier" => new_tier}) do
    user = Guardian.Plug.current_resource(conn)

    case Features.parse_tier(new_tier) do
      {:ok, tier_atom} ->
        current_tier = if user.tier, do: String.to_existing_atom(user.tier), else: :free

        case Features.validate_tier_upgrade(current_tier, tier_atom) do
          {:ok, _validated_tier} ->
            # In production, this should verify payment/subscription
            # For now, we'll just update the user's tier
            update_user_tier(conn, user, new_tier)

          {:error, :downgrade_not_allowed} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Tier downgrades are not allowed"})

          {:error, :invalid_tier} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{error: "Invalid tier"})
        end

      {:error, :invalid_tier} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Invalid tier. Must be one of: free, pro, enterprise"})
    end
  end

  def update_tier(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Missing tier parameter"})
  end

  # Private helpers

  defp update_user_tier(conn, user, new_tier) do
    alias GlobalbridgeBackend.Repo
    alias GlobalbridgeBackend.Schemas.User

    case user
         |> User.update_changeset(%{tier: new_tier})
         |> Repo.update() do
      {:ok, updated_user} ->
        conn
        |> put_status(:ok)
        |> json(%{
          data: %{
            tier: updated_user.tier,
            features: Features.get_user_features(updated_user),
            message: "Tier updated successfully"
          }
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{errors: translate_errors(changeset)})
    end
  end

  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
