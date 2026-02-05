defmodule ElixirchatWeb.ChatLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat
  alias Elixirchat.Agent

  @impl true
  def mount(%{"id" => conversation_id}, _session, socket) do
    # current_user is already assigned by on_mount hook
    current_user = socket.assigns.current_user
    conversation_id = String.to_integer(conversation_id)

    if Chat.member?(conversation_id, current_user.id) do
      conversation = Chat.get_conversation!(conversation_id)
      messages = Chat.list_messages(conversation_id)
      members = Chat.list_group_members(conversation_id)

      # Subscribe to real-time updates
      if connected?(socket) do
        Chat.subscribe(conversation_id)
        Chat.mark_conversation_read(conversation_id, current_user.id)
      end

      {:ok,
       assign(socket,
         conversation: conversation,
         messages: messages,
         members: members,
         message_input: "",
         show_members: false,
         typing_users: MapSet.new(),
         is_typing: false,
         typing_timer: nil
       )}
    else
      {:ok, redirect(socket, to: "/chats") |> put_flash(:error, "Access denied")}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => content}, socket) do
    content = String.trim(content)

    if content != "" do
      # Stop typing when message is sent
      if socket.assigns.is_typing do
        Chat.broadcast_typing_stop(socket.assigns.conversation.id, socket.assigns.current_user.id)
      end

      # Cancel any pending typing timer
      if socket.assigns.typing_timer do
        Process.cancel_timer(socket.assigns.typing_timer)
      end

      case Chat.send_message(
        socket.assigns.conversation.id,
        socket.assigns.current_user.id,
        content
      ) do
        {:ok, _message} ->
          {:noreply, assign(socket, message_input: "", is_typing: false, typing_timer: nil)}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => content}, socket) do
    socket = assign(socket, message_input: content)

    # Handle typing indicator logic
    socket =
      if String.trim(content) != "" do
        # Start typing if not already
        if !socket.assigns.is_typing do
          Chat.broadcast_typing_start(socket.assigns.conversation.id, socket.assigns.current_user)
        end

        # Cancel existing timer and set a new one
        if socket.assigns.typing_timer do
          Process.cancel_timer(socket.assigns.typing_timer)
        end

        timer = Process.send_after(self(), :stop_typing, 3000)
        assign(socket, is_typing: true, typing_timer: timer)
      else
        # Input is empty, stop typing immediately
        if socket.assigns.is_typing do
          Chat.broadcast_typing_stop(socket.assigns.conversation.id, socket.assigns.current_user.id)
        end

        if socket.assigns.typing_timer do
          Process.cancel_timer(socket.assigns.typing_timer)
        end

        assign(socket, is_typing: false, typing_timer: nil)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_members", _, socket) do
    {:noreply, assign(socket, show_members: !socket.assigns.show_members)}
  end

  @impl true
  def handle_event("leave_group", _, socket) do
    conversation = socket.assigns.conversation
    current_user = socket.assigns.current_user

    if conversation.type == "group" do
      case Chat.remove_member_from_group(conversation.id, current_user.id) do
        {:ok, _} ->
          {:noreply, push_navigate(socket, to: "/chats") |> put_flash(:info, "You left the group")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Could not leave group")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    # Mark as read if viewing
    Chat.mark_conversation_read(socket.assigns.conversation.id, socket.assigns.current_user.id)

    # Remove sender from typing users when they send a message
    socket =
      update(socket, :typing_users, fn users ->
        MapSet.delete(users, message.sender.username)
      end)

    {:noreply, update(socket, :messages, fn messages -> messages ++ [message] end)}
  end

  @impl true
  def handle_info({:user_typing, %{user_id: user_id, username: username}}, socket) do
    # Don't show your own typing indicator
    if user_id == socket.assigns.current_user.id do
      {:noreply, socket}
    else
      {:noreply, update(socket, :typing_users, &MapSet.put(&1, username))}
    end
  end

  @impl true
  def handle_info({:user_stopped_typing, %{user_id: user_id}}, socket) do
    # Find the username for this user_id from members
    username =
      socket.assigns.members
      |> Enum.find(fn m -> m.id == user_id end)
      |> case do
        nil -> nil
        user -> user.username
      end

    if username do
      {:noreply, update(socket, :typing_users, &MapSet.delete(&1, username))}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:stop_typing, socket) do
    if socket.assigns.is_typing do
      Chat.broadcast_typing_stop(socket.assigns.conversation.id, socket.assigns.current_user.id)
    end

    {:noreply, assign(socket, is_typing: false, typing_timer: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-base-200 flex flex-col">
      <div class="navbar bg-base-100 shadow-sm">
        <div class="flex-none">
          <.link navigate={~p"/chats"} class="btn btn-ghost btn-sm">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" />
            </svg>
          </.link>
        </div>
        <div class="flex-1">
          <div class="flex items-center gap-3">
            <div class="avatar placeholder">
              <div class={[
                "rounded-full w-10",
                @conversation.type == "group" && "bg-secondary text-secondary-content" || "bg-primary text-primary-content"
              ]}>
                <span>{get_conversation_initial(@conversation, @current_user.id)}</span>
              </div>
            </div>
            <div>
              <span class="font-semibold">{get_conversation_name(@conversation, @current_user.id)}</span>
              <span :if={@conversation.type == "group"} class="text-xs text-base-content/70 ml-2">
                {length(@members)} members
              </span>
            </div>
          </div>
        </div>
        <div class="flex-none flex items-center gap-2">
          <div :if={@conversation.type == "group"} class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost btn-sm" phx-click="toggle_members">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z" />
              </svg>
            </div>
            <ul :if={@show_members} tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow">
              <li class="menu-title">Members</li>
              <li :for={member <- @members}>
                <span class={member.id == @current_user.id && "font-bold" || ""}>
                  {member.username}
                  <span :if={member.id == @current_user.id} class="badge badge-xs badge-primary ml-1">you</span>
                </span>
              </li>
              <div class="divider my-1"></div>
              <li>
                <button phx-click="leave_group" class="text-error">
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15m3 0 3-3m0 0-3-3m3 3H9" />
                  </svg>
                  Leave Group
                </button>
              </li>
            </ul>
          </div>
          <span class="text-sm text-base-content/70">{@current_user.username}</span>
        </div>
      </div>

      <div class="flex-1 overflow-y-auto p-4" id="messages-container" phx-hook="ScrollToBottom">
        <div class="max-w-2xl mx-auto space-y-4">
          <div :if={@messages == []} class="text-center py-12 text-base-content/70">
            <p>No messages yet. Say hello!</p>
          </div>

          <div
            :for={message <- @messages}
            class={["chat", get_chat_position(message, @current_user.id)]}
          >
            <div class="chat-image avatar">
              <div class={[
                "w-10 rounded-full flex items-center justify-center text-white font-bold",
                get_avatar_class(message)
              ]}>
                <span class="text-lg">{get_sender_initial(message)}</span>
              </div>
            </div>
            <div class="chat-header">
              <span class={is_agent_message?(message) && "text-secondary font-semibold" || ""}>
                {message.sender.username}
              </span>
              <span :if={is_agent_message?(message)} class="badge badge-secondary badge-xs ml-1">AI</span>
              <time class="text-xs opacity-50 ml-1">{format_time(message.inserted_at)}</time>
            </div>
            <div class={[
              "chat-bubble",
              get_bubble_class(message, @current_user.id)
            ]}>
              {message.content}
            </div>
          </div>
        </div>
      </div>

      <div class="bg-base-100 border-t border-base-300 p-4">
        <div class="max-w-2xl mx-auto">
          <div :if={MapSet.size(@typing_users) > 0} class="text-sm text-base-content/60 italic pb-2 h-6">
            <span class="typing-indicator">
              {format_typing_users(@typing_users)}
              <span class="typing-dots">...</span>
            </span>
          </div>
          <div :if={MapSet.size(@typing_users) == 0} class="h-6 pb-2"></div>
          <form phx-submit="send_message" class="flex gap-2">
            <input
              type="text"
              name="message"
              value={@message_input}
              placeholder="Type a message..."
              class="input input-bordered flex-1"
              autocomplete="off"
              phx-change="update_input"
              phx-debounce="100"
            />
            <button type="submit" class="btn btn-primary">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5" />
              </svg>
            </button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp get_conversation_name(%{type: "direct", members: members}, current_user_id) do
    case Enum.find(members, fn m -> m.user_id != current_user_id end) do
      nil -> "Unknown"
      member -> member.user.username
    end
  end

  defp get_conversation_name(%{name: name}, _) when is_binary(name), do: name
  defp get_conversation_name(_, _), do: "Group Chat"

  defp get_conversation_initial(conv, current_user_id) do
    conv
    |> get_conversation_name(current_user_id)
    |> String.first()
    |> String.upcase()
  end

  defp format_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end

  defp is_agent_message?(message) do
    Agent.is_agent_username?(message.sender.username)
  end

  defp get_chat_position(message, current_user_id) do
    cond do
      is_agent_message?(message) -> "chat-start"
      message.sender_id == current_user_id -> "chat-end"
      true -> "chat-start"
    end
  end

  defp get_bubble_class(message, current_user_id) do
    cond do
      is_agent_message?(message) -> "chat-bubble-secondary"
      message.sender_id == current_user_id -> "chat-bubble-primary"
      true -> ""
    end
  end

  defp get_avatar_class(message) do
    if is_agent_message?(message) do
      "bg-secondary"
    else
      "bg-primary"
    end
  end

  defp get_sender_initial(message) do
    if is_agent_message?(message) do
      "AI"
    else
      message.sender.username
      |> String.first()
      |> String.upcase()
    end
  end

  defp format_typing_users(typing_users) do
    users = MapSet.to_list(typing_users)

    case users do
      [user] ->
        "#{user} is typing"

      [user1, user2] ->
        "#{user1} and #{user2} are typing"

      [user1, user2 | rest] ->
        "#{user1}, #{user2} and #{length(rest)} more are typing"

      [] ->
        ""
    end
  end
end
