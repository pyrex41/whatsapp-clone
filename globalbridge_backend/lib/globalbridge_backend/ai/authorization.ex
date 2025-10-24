defmodule GlobalbridgeBackend.AI.Authorization do
  @moduledoc """
  Authorization module for AI endpoints to prevent unauthorized access to thread data.
  Uses ParticipantCache for high-performance thread access validation.
  """

  require Logger

  alias GlobalbridgeBackend.Cache.ParticipantCache

  @doc """
  Ensures a user has access to a thread by verifying they are a participant.
  Raises UnauthorizedError if the user is not a participant.

  ## Parameters
    - user_id: The ID of the user attempting to access the thread
    - thread_id: The ID of the thread being accessed

  ## Returns
    - :ok if the user is a participant
    - raises GlobalbridgeBackend.AI.UnauthorizedError if not

  ## Examples

      iex> ensure_thread_access!("user-123", "thread-456")
      :ok

      iex> ensure_thread_access!("user-123", "unauthorized-thread")
      ** (GlobalbridgeBackend.AI.UnauthorizedError) You do not have access to this thread
  """
  @spec ensure_thread_access!(String.t(), String.t()) :: :ok
  def ensure_thread_access!(user_id, thread_id) when is_binary(user_id) and is_binary(thread_id) do
    start_time = System.monotonic_time(:microsecond)

    result = ParticipantCache.is_participant?(thread_id, user_id)

    elapsed_time = System.monotonic_time(:microsecond) - start_time

    case result do
      true ->
        Logger.debug("Thread access authorized",
          user_id: user_id,
          thread_id: thread_id,
          elapsed_us: elapsed_time
        )

        :ok

      false ->
        Logger.warning("Unauthorized thread access attempt",
          user_id: user_id,
          thread_id: thread_id,
          elapsed_us: elapsed_time
        )

        raise GlobalbridgeBackend.AI.UnauthorizedError,
          message: "You do not have access to this thread",
          thread_id: thread_id,
          user_id: user_id
    end
  end

  def ensure_thread_access!(nil, thread_id) do
    Logger.warning("Unauthorized thread access attempt with nil user_id",
      thread_id: thread_id
    )

    raise GlobalbridgeBackend.AI.UnauthorizedError,
      message: "Authentication required",
      thread_id: thread_id,
      user_id: nil
  end

  def ensure_thread_access!(user_id, nil) do
    Logger.warning("Thread access attempt with nil thread_id",
      user_id: user_id
    )

    raise GlobalbridgeBackend.AI.UnauthorizedError,
      message: "Thread ID is required",
      thread_id: nil,
      user_id: user_id
  end

  @doc """
  Check if a user has access to a thread without raising an error.
  Returns a boolean indicating whether access is allowed.

  ## Parameters
    - user_id: The ID of the user
    - thread_id: The ID of the thread

  ## Returns
    - true if the user is a participant
    - false otherwise

  ## Examples

      iex> has_thread_access?("user-123", "thread-456")
      true

      iex> has_thread_access?("user-123", "unauthorized-thread")
      false
  """
  @spec has_thread_access?(String.t() | nil, String.t() | nil) :: boolean()
  def has_thread_access?(user_id, thread_id)
      when is_binary(user_id) and is_binary(thread_id) do
    ParticipantCache.is_participant?(thread_id, user_id)
  end

  def has_thread_access?(_user_id, _thread_id), do: false
end
