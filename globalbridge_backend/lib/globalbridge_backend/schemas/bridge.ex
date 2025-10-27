defmodule GlobalbridgeBackend.Schemas.Bridge do
  @moduledoc """
  Bridge schema for WhatsApp bridge configurations.
  Stored in bridges.db (shared database).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "bridges" do
    field(:user_id, :binary_id)
    # "whatsapp", "telegram", etc.
    field(:bridge_type, :string)
    field(:phone_number, :string)
    # Encrypted session data
    field(:session_data, :map)
    # "connected", "disconnected", "error"
    field(:status, :string)
    field(:last_connected_at, :utc_datetime)
    field(:error_message, :string)
    # For initial connection
    field(:qr_code, :string)
    field(:is_active, :boolean, default: true)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for bridge creation.
  """
  def create_changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:user_id, :bridge_type, :phone_number])
    |> validate_required([:user_id, :bridge_type, :phone_number])
    |> validate_inclusion(:bridge_type, ["whatsapp", "telegram"])
    |> sanitize_phone_number()
    |> validate_phone_number()
    |> put_change(:status, "disconnected")
    |> unique_constraint([:user_id, :bridge_type])
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Changeset for bridge session update.
  """
  def session_changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:session_data, :status, :last_connected_at, :error_message, :qr_code])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["connected", "disconnected", "error", "connecting"])
  end

  @doc """
  Changeset for bridge activation toggle.
  """
  def toggle_changeset(bridge, attrs) do
    bridge
    |> cast(attrs, [:is_active])
    |> validate_required([:is_active])
  end

  # Private helper functions

  @doc false
  defp sanitize_phone_number(changeset) do
    case get_change(changeset, :phone_number) do
      nil ->
        changeset

      phone_number when is_binary(phone_number) ->
        # Sanitize phone number:
        # 1. Trim whitespace
        # 2. Remove all characters except digits and leading +
        # 3. Ensure it starts with +
        # 4. Limit length to prevent DoS
        sanitized =
          phone_number
          |> String.trim()
          # Take only first 20 chars to prevent DoS
          |> String.slice(0, 20)
          # Remove all non-digit characters except + at the start
          |> sanitize_phone_characters()

        put_change(changeset, :phone_number, sanitized)

      _ ->
        # Invalid type, let validation handle it
        changeset
    end
  end

  @doc false
  defp sanitize_phone_characters(phone) do
    # Extract the leading + if present
    {prefix, rest} =
      if String.starts_with?(phone, "+") do
        {"+", String.slice(phone, 1..-1//1)}
      else
        {"", phone}
      end

    # Remove all non-digit characters
    digits = String.replace(rest, ~r/[^\d]/, "")

    # Combine prefix and digits
    prefix <> digits
  end

  @doc false
  defp validate_phone_number(changeset) do
    changeset
    # Validate E.164 format: +[country code][subscriber number]
    # Country code: 1-3 digits
    # Total length: max 15 digits (excluding +)
    |> validate_format(
      :phone_number,
      ~r/^\+[1-9]\d{1,14}$/,
      message: "must be in E.164 format (e.g., +1234567890)"
    )
    # Additional validation: minimum length
    |> validate_length(:phone_number, min: 8, max: 16)
    # Prevent common test/invalid numbers
    |> validate_not_test_number()
  end

  @doc false
  defp validate_not_test_number(changeset) do
    case get_change(changeset, :phone_number) do
      nil ->
        changeset

      phone_number ->
        # Block common test numbers and obviously invalid patterns
        invalid_patterns = [
          ~r/^\+?0+$/,
          # All zeros
          ~r/^\+?1+$/,
          # All ones
          ~r/^\+?1234567/,
          # Sequential test numbers
          ~r/^\+?9999999/,
          # Repeated nines
          ~r/^\+?5555555/
          # Repeated fives
        ]

        is_invalid =
          Enum.any?(invalid_patterns, fn pattern ->
            String.match?(phone_number, pattern)
          end)

        if is_invalid do
          add_error(changeset, :phone_number, "appears to be a test or invalid number")
        else
          changeset
        end
    end
  end
end
