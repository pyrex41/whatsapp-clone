defmodule GlobalbridgeBackendWeb.AppLive do
  use GlobalbridgeBackendWeb, :live_view

  alias GlobalbridgeBackend.{Auth, Contexts}
  alias Phoenix.Socket.Broadcast

  @impl true
  def mount(_params, session, socket) do
    # TODO: Migrate to Auth0 tokens for web sessions
    # Currently using Guardian JWT for LiveView during transition period.
    # Auth0 is used for mobile/API, Guardian for web sessions via OAuth callback.
    # See globalbridge_backend/AUTH_STRATEGY.md for migration plan.
    case session["guardian_token"] do
      nil ->
        {:ok, redirect(socket, to: "/")}

      token ->
        case Auth.Guardian.resource_from_token(token) do
          {:ok, user, _claims} ->
            threads = Contexts.Threads.list_user_threads(user.id)
            {:ok, assign(socket, user: user, threads: threads, current_thread: nil, messages: [])}

          {:error, _reason} ->
            {:ok, redirect(socket, to: "/")}
        end
    end
  end

  @impl true
  def handle_params(%{"thread_id" => thread_id}, _uri, socket) do
    case Contexts.Threads.get_thread(thread_id) do
      {:ok, thread} ->
        messages = Contexts.Messages.list_messages(thread_id)

        # Subscribe to thread channel for real-time updates
        if connected?(socket) do
          GlobalbridgeBackendWeb.Endpoint.subscribe("thread:#{thread_id}")
        end

        {:noreply, assign(socket, current_thread: thread, messages: messages)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Thread not found")}
    end
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_thread", %{"thread_id" => thread_id}, socket) do
    {:noreply, push_patch(socket, to: "/app/threads/#{thread_id}")}
  end

  @impl true
  def handle_event("send_message", %{"content" => content}, socket) do
    %{current_thread: thread, user: user} = socket.assigns

    # Persist message to database first, then broadcast
    case Contexts.Messages.create_message(thread.id, %{
           content: content,
           sender_id: user.id
         }) do
      {:ok, message} ->
        # Broadcast the persisted message to all connected clients
        GlobalbridgeBackendWeb.Endpoint.broadcast("thread:#{thread.id}", "new_message", %{
          id: message.id,
          content: message.content,
          sender_id: message.sender_id,
          thread_id: message.thread_id,
          inserted_at: message.inserted_at
        })

        # Update UI with the real persisted message
        messages = socket.assigns.messages ++ [message]
        {:noreply, assign(socket, messages: messages)}

      {:error, changeset} ->
        # Show error to user if message creation fails
        {:noreply, put_flash(socket, :error, "Failed to send message: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def handle_event("logout", _params, socket) do
    {:noreply, redirect(socket, to: "/auth/logout")}
  end

  @impl true
  def handle_info(
        %Broadcast{topic: "thread:" <> _thread_id, event: "new_message", payload: message},
        socket
      ) do
    # Add new message to the messages list
    messages = socket.assigns.messages ++ [message]
    {:noreply, assign(socket, messages: messages)}
  end

  @impl true
  def handle_info(
        %Broadcast{
          topic: "thread:" <> _thread_id,
          event: "message_edited",
          payload: %{id: message_id, content: new_content}
        },
        socket
      ) do
    # Update the edited message
    messages =
      Enum.map(socket.assigns.messages, fn
        %{id: ^message_id} -> %{id: message_id, content: new_content}
        message -> message
      end)

    {:noreply, assign(socket, messages: messages)}
  end

  @impl true
  def handle_info(
        %Broadcast{
          topic: "thread:" <> _thread_id,
          event: "message_deleted",
          payload: %{id: message_id}
        },
        socket
      ) do
    # Remove the deleted message
    messages = Enum.reject(socket.assigns.messages, &(&1.id == message_id))
    {:noreply, assign(socket, messages: messages)}
  end

  @impl true
  def handle_info(
        %Broadcast{topic: "thread:" <> _thread_id, event: "user_typing", payload: typing_info},
        socket
      ) do
    # Update typing indicators (could add to assigns for display)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="app-container h-screen flex">
      <!-- Sidebar -->
      <div class="w-80 bg-gray-100 border-r border-gray-200 flex flex-col">
        <!-- Header -->
        <div class="p-4 border-b border-gray-200">
          <div class="flex items-center justify-between">
            <h1 class="text-xl font-bold text-gray-900">GlobalBridge</h1>
            <button phx-click="logout" class="text-gray-500 hover:text-gray-700">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"></path>
              </svg>
            </button>
          </div>
        </div>

        <!-- Threads List -->
        <div class="flex-1 overflow-y-auto">
          <div class="p-2">
            <h2 class="text-sm font-medium text-gray-600 mb-2 px-2">Threads</h2>
            <div class="space-y-1">
              <%= for thread <- @threads do %>
                <div
                  phx-click="select_thread"
                  phx-value-thread_id={thread.id}
                  class={"cursor-pointer p-3 rounded-lg hover:bg-gray-200 #{if @current_thread && @current_thread.id == thread.id, do: "bg-blue-100", else: "bg-white"}"}
                >
                  <div class="font-medium text-gray-900"><%= thread.name %></div>
                  <div class="text-sm text-gray-500 truncate">
                    <%= if thread.last_message do %>
                      <%= thread.last_message.content %>
                    <% else %>
                      No messages yet
                    <% end %>
                  </div>
                  <%= if thread.unread_count > 0 do %>
                    <div class="inline-flex items-center justify-center w-5 h-5 text-xs font-medium text-white bg-blue-600 rounded-full">
                      <%= thread.unread_count %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="flex-1 flex flex-col">
        <%= if @current_thread do %>
          <!-- Thread Header -->
          <div class="p-4 border-b border-gray-200">
            <h2 class="text-lg font-semibold text-gray-900"><%= @current_thread.name %></h2>
          </div>

           <!-- Messages -->
           <div class="flex-1 overflow-y-auto p-4 space-y-4">
             <%= for message <- @messages do %>
               <div class={"flex #{if message.sender_id == @user.id, do: "justify-end", else: "justify-start"}"}>
                 <div class={"max-w-xs lg:max-w-md px-4 py-2 rounded-lg #{if message.sender_id == @user.id, do: "bg-blue-600 text-white", else: "bg-gray-200 text-gray-900"}"}>
                   <div class="text-sm"><%= message.content %></div>
                   <div class={"text-xs mt-1 #{if message.sender_id == @user.id, do: "text-blue-200", else: "text-gray-500"}"}>
                     <%= format_timestamp(message[:inserted_at] || message[:created_at] || DateTime.utc_now()) %>
                   </div>
                 </div>
               </div>
             <% end %>
           </div>

          <!-- Message Input -->
          <div class="p-4 border-t border-gray-200">
            <form phx-submit="send_message" class="flex space-x-2">
              <input
                type="text"
                name="content"
                placeholder="Type a message..."
                class="flex-1 px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
                required
              />
              <button
                type="submit"
                class="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                Send
              </button>
            </form>
          </div>
        <% else %>
          <!-- Welcome Screen -->
          <div class="flex-1 flex items-center justify-center">
            <div class="text-center">
              <h2 class="text-2xl font-bold text-gray-900 mb-2">Welcome to GlobalBridge</h2>
              <p class="text-gray-600">Select a thread to start messaging</p>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end
end
