defmodule GlobalbridgeBackend.AI.UnauthorizedError do
  @moduledoc """
  Custom exception for unauthorized access to AI resources.
  """

  defexception [:message, :thread_id, :user_id]

  @type t :: %__MODULE__{
          message: String.t(),
          thread_id: String.t() | nil,
          user_id: String.t() | nil
        }

  @impl true
  def exception(opts) when is_list(opts) do
    message = Keyword.get(opts, :message, "Unauthorized access")
    thread_id = Keyword.get(opts, :thread_id)
    user_id = Keyword.get(opts, :user_id)

    %__MODULE__{
      message: message,
      thread_id: thread_id,
      user_id: user_id
    }
  end

  def exception(message) when is_binary(message) do
    %__MODULE__{message: message, thread_id: nil, user_id: nil}
  end
end
