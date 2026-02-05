defmodule ElixirchatWeb.ChatLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat

  @impl true
  def mount(%{"id" => conversation_id}, _session, socket) do
    # current_user is already assigned by on_mount hook
    current_user = socket.assigns.current_user
    conversation_id = String.to_integer(conversation_id)

    if Chat.member?(conversation_id, current_user.id) do
      conversation = Chat.get_conversation!(conversation_id)
      messages = Chat.list_messages(conversation_id)

      # Subscribe to real-time updates
      if connected?(socket) do
        Chat.subscribe(conversation_id)
        Chat.mark_conversation_read(conversation_id, current_user.id)
      end

      {:ok,
       assign(socket,
         conversation: conversation,
         messages: messages,
         message_input: ""
       )}
    else
      {:ok, redirect(socket, to: "/chats") |> put_flash(:error, "Access denied")}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => content}, socket) do
    content = String.trim(content)

    if content != "" do
      case Chat.send_message(
        socket.assigns.conversation.id,
        socket.assigns.current_user.id,
        content
      ) do
        {:ok, _message} ->
          {:noreply, assign(socket, message_input: "")}
        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send message")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_input", %{"message" => content}, socket) do
    {:noreply, assign(socket, message_input: content)}
  end

  @impl true
  def handle_info({:new_message, message}, socket) do
    # Mark as read if viewing
    Chat.mark_conversation_read(socket.assigns.conversation.id, socket.assigns.current_user.id)

    {:noreply, update(socket, :messages, fn messages -> messages ++ [message] end)}
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
              <div class="bg-primary text-primary-content rounded-full w-10">
                <span>{get_conversation_initial(@conversation, @current_user.id)}</span>
              </div>
            </div>
            <span class="font-semibold">{get_conversation_name(@conversation, @current_user.id)}</span>
          </div>
        </div>
        <div class="flex-none">
          <span class="mr-4 text-sm text-base-content/70">{@current_user.username}</span>
        </div>
      </div>

      <div class="flex-1 overflow-y-auto p-4" id="messages-container" phx-hook="ScrollToBottom">
        <div class="max-w-2xl mx-auto space-y-4">
          <div :if={@messages == []} class="text-center py-12 text-base-content/70">
            <p>No messages yet. Say hello!</p>
          </div>

          <div
            :for={message <- @messages}
            class={["chat", message.sender_id == @current_user.id && "chat-end" || "chat-start"]}
          >
            <div class="chat-header">
              {message.sender.username}
              <time class="text-xs opacity-50 ml-1">{format_time(message.inserted_at)}</time>
            </div>
            <div class={[
              "chat-bubble",
              message.sender_id == @current_user.id && "chat-bubble-primary" || ""
            ]}>
              {message.content}
            </div>
          </div>
        </div>
      </div>

      <div class="bg-base-100 border-t border-base-300 p-4">
        <div class="max-w-2xl mx-auto">
          <form phx-submit="send_message" class="flex gap-2">
            <input
              type="text"
              name="message"
              value={@message_input}
              placeholder="Type a message..."
              class="input input-bordered flex-1"
              autocomplete="off"
              phx-change="update_input"
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
end
