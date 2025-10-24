defmodule GlobalbridgeBackendWeb.Plugs.ThreadCache do
  @moduledoc """
  Request-scoped caching plug for thread lookups.

  Caches thread records in the process dictionary for the duration of a single request.
  This prevents N+1 queries when the same thread is accessed multiple times within
  a request (e.g., listing messages, marking as read, creating a message).

  The cache is automatically cleaned up when the request process exits, ensuring
  no memory leaks or stale data between requests.

  ## Usage

  Add to a pipeline in your router:

      pipeline :api do
        plug :accepts, ["json"]
        plug ThreadCache
      end

  Then use the helper functions in your context:

      def get_thread_with_shard(thread_id) do
        case ThreadCache.get_cached_thread(thread_id) do
          nil ->
            thread = Repo.get!(Thread, thread_id)
            ThreadCache.cache_thread(thread)
          cached -> cached
        end
      end

  ## Performance Benefits

  - Eliminates N+1 queries for thread lookups within a single request
  - Zero configuration required
  - Automatic cleanup (no memory leaks)
  - Thread-safe (per-process cache)

  ## Implementation Notes

  Uses the process dictionary (`Process.put/get`) for caching. This is safe because:
  1. Each HTTP request runs in its own process
  2. The process dies after the request completes, cleaning up the cache
  3. No shared state between concurrent requests
  """

  @doc """
  Plug initialization callback.

  No options needed for this plug.
  """
  def init(opts), do: opts

  @doc """
  Plug call callback.

  This plug doesn't modify the connection, it just ensures the plug
  is loaded in the pipeline. The actual caching is done via the
  helper functions.
  """
  def call(conn, _opts) do
    # The cache is automatically cleaned up when the request process exits
    # We don't need to do anything here, just pass the connection through
    conn
  end

  @doc """
  Retrieves a cached thread by ID.

  Returns `nil` if the thread hasn't been cached yet in this request.

  ## Examples

      iex> ThreadCache.get_cached_thread("thread-123")
      nil

      iex> ThreadCache.cache_thread(%Thread{id: "thread-123"})
      iex> ThreadCache.get_cached_thread("thread-123")
      %Thread{id: "thread-123"}
  """
  def get_cached_thread(thread_id) when is_binary(thread_id) do
    Process.get({:thread_cache, thread_id})
  end

  @doc """
  Caches a thread for the duration of the request.

  Returns the thread that was cached, for easy chaining.

  ## Examples

      iex> thread = Repo.get!(Thread, "thread-123")
      iex> ThreadCache.cache_thread(thread)
      %Thread{id: "thread-123"}
  """
  def cache_thread(%{id: thread_id} = thread) do
    Process.put({:thread_cache, thread_id}, thread)
    thread
  end

  @doc """
  Clears a specific thread from the cache.

  Useful when a thread is updated during a request and needs to be re-fetched.

  ## Examples

      iex> ThreadCache.clear_thread("thread-123")
      :ok
  """
  def clear_thread(thread_id) when is_binary(thread_id) do
    Process.delete({:thread_cache, thread_id})
    :ok
  end

  @doc """
  Clears the entire thread cache for the current request.

  Rarely needed, but useful for testing or when you need to ensure
  fresh data is fetched.

  ## Examples

      iex> ThreadCache.clear_all()
      :ok
  """
  def clear_all do
    # Get all process dictionary keys
    Process.get_keys()
    |> Enum.filter(fn
      {:thread_cache, _} -> true
      _ -> false
    end)
    |> Enum.each(&Process.delete/1)

    :ok
  end

  @doc """
  Gets the current cache size (number of cached threads).

  Useful for monitoring and debugging.

  ## Examples

      iex> ThreadCache.cache_size()
      0

      iex> ThreadCache.cache_thread(%Thread{id: "thread-123"})
      iex> ThreadCache.cache_size()
      1
  """
  def cache_size do
    Process.get_keys()
    |> Enum.count(fn
      {:thread_cache, _} -> true
      _ -> false
    end)
  end
end
