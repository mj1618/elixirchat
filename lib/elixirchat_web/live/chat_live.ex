defmodule ElixirchatWeb.ChatLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat
  alias Elixirchat.Chat.Reaction
  alias Elixirchat.Agent
  alias Elixirchat.Presence

  @impl true
  def mount(%{"id" => conversation_id}, _session, socket) do
    # current_user is already assigned by on_mount hook
    current_user = socket.assigns.current_user
    conversation_id = String.to_integer(conversation_id)

    if Chat.member?(conversation_id, current_user.id) do
      conversation = Chat.get_conversation!(conversation_id)
      messages = Chat.list_messages(conversation_id)
      members = Chat.list_group_members(conversation_id)

      # Track presence and subscribe to updates when connected
      online_user_ids =
        if connected?(socket) do
          Chat.subscribe(conversation_id)
          Chat.mark_conversation_read(conversation_id, current_user.id)
          Presence.track_user(self(), current_user)
          Presence.subscribe()
          Presence.get_online_user_ids()
        else
          []
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
         typing_timer: nil,
         online_user_ids: online_user_ids,
         show_search: false,
         search_query: "",
         search_results: [],
         editing_message_id: nil,
         edit_content: "",
         show_delete_modal: false,
         delete_message_id: nil,
         reaction_picker_message_id: nil,
         replying_to: nil
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
  def handle_event("toggle_search", _, socket) do
    show_search = !socket.assigns.show_search

    socket =
      if show_search do
        assign(socket, show_search: true)
      else
        assign(socket, show_search: false, search_query: "", search_results: [])
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("search_messages", %{"query" => query}, socket) do
    query = String.trim(query)
    results = Chat.search_messages(socket.assigns.conversation.id, query)
    {:noreply, assign(socket, search_query: query, search_results: results)}
  end

  @impl true
  def handle_event("clear_search", _, socket) do
    {:noreply, assign(socket, search_query: "", search_results: [], show_search: false)}
  end

  @impl true
  def handle_event("jump_to_message", %{"message-id" => message_id}, socket) do
    {:noreply,
     socket
     |> assign(show_search: false, search_query: "", search_results: [])
     |> push_event("scroll_to_message", %{message_id: message_id})}
  end

  # ===============================
  # Message Edit/Delete Handlers
  # ===============================

  @impl true
  def handle_event("start_edit", %{"id" => message_id}, socket) do
    message_id = String.to_integer(message_id)
    message = Enum.find(socket.assigns.messages, fn m -> m.id == message_id end)

    if message do
      {:noreply, assign(socket, editing_message_id: message_id, edit_content: message.content)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_edit", %{"content" => content}, socket) do
    {:noreply, assign(socket, edit_content: content)}
  end

  @impl true
  def handle_event("save_edit", _, socket) do
    message_id = socket.assigns.editing_message_id
    content = String.trim(socket.assigns.edit_content)

    if message_id && content != "" do
      case Chat.edit_message(message_id, socket.assigns.current_user.id, content) do
        {:ok, _message} ->
          {:noreply, assign(socket, editing_message_id: nil, edit_content: "")}

        {:error, :not_owner} ->
          {:noreply, put_flash(socket, :error, "You can only edit your own messages")}

        {:error, :time_expired} ->
          {:noreply,
           socket
           |> put_flash(:error, "You can only edit messages within 15 minutes")
           |> assign(editing_message_id: nil, edit_content: "")}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to edit message")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_edit", _, socket) do
    {:noreply, assign(socket, editing_message_id: nil, edit_content: "")}
  end

  @impl true
  def handle_event("show_delete_modal", %{"id" => message_id}, socket) do
    message_id = String.to_integer(message_id)
    {:noreply, assign(socket, show_delete_modal: true, delete_message_id: message_id)}
  end

  @impl true
  def handle_event("cancel_delete", _, socket) do
    {:noreply, assign(socket, show_delete_modal: false, delete_message_id: nil)}
  end

  @impl true
  def handle_event("confirm_delete", _, socket) do
    message_id = socket.assigns.delete_message_id

    if message_id do
      case Chat.delete_message(message_id, socket.assigns.current_user.id) do
        {:ok, _message} ->
          {:noreply, assign(socket, show_delete_modal: false, delete_message_id: nil)}

        {:error, :not_owner} ->
          {:noreply,
           socket
           |> put_flash(:error, "You can only delete your own messages")
           |> assign(show_delete_modal: false, delete_message_id: nil)}

        {:error, :time_expired} ->
          {:noreply,
           socket
           |> put_flash(:error, "You can only delete messages within 15 minutes")
           |> assign(show_delete_modal: false, delete_message_id: nil)}

        {:error, _} ->
          {:noreply,
           socket
           |> put_flash(:error, "Failed to delete message")
           |> assign(show_delete_modal: false, delete_message_id: nil)}
      end
    else
      {:noreply, socket}
    end
  end

  # ===============================
  # Reaction Handlers
  # ===============================

  @impl true
  def handle_event("show_reaction_picker", %{"message-id" => message_id}, socket) do
    message_id = String.to_integer(message_id)

    # Toggle the picker - if same message, close it
    new_picker_id =
      if socket.assigns.reaction_picker_message_id == message_id do
        nil
      else
        message_id
      end

    {:noreply, assign(socket, reaction_picker_message_id: new_picker_id)}
  end

  @impl true
  def handle_event("close_reaction_picker", _, socket) do
    {:noreply, assign(socket, reaction_picker_message_id: nil)}
  end

  @impl true
  def handle_event("toggle_reaction", %{"message-id" => message_id, "emoji" => emoji}, socket) do
    message_id = String.to_integer(message_id)

    case Chat.toggle_reaction(message_id, socket.assigns.current_user.id, emoji) do
      {:ok, _reactions} ->
        # Close the picker after toggling
        {:noreply, assign(socket, reaction_picker_message_id: nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add reaction")}
    end
  end

  @impl true
  def handle_info({:reaction_updated, %{message_id: message_id, reactions: reactions}}, socket) do
    # Update the reactions for this message
    messages =
      Enum.map(socket.assigns.messages, fn msg ->
        if msg.id == message_id do
          Map.put(msg, :reactions_grouped, reactions)
        else
          msg
        end
      end)

    {:noreply, assign(socket, messages: messages)}
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
  def handle_info({:message_edited, edited_message}, socket) do
    {:noreply,
     update(socket, :messages, fn messages ->
       Enum.map(messages, fn msg ->
         if msg.id == edited_message.id, do: edited_message, else: msg
       end)
     end)}
  end

  @impl true
  def handle_info({:message_deleted, deleted_message}, socket) do
    {:noreply,
     update(socket, :messages, fn messages ->
       Enum.map(messages, fn msg ->
         if msg.id == deleted_message.id, do: deleted_message, else: msg
       end)
     end)}
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
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    # Update online user IDs when presence changes
    {:noreply, assign(socket, online_user_ids: Presence.get_online_user_ids())}
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
              <div class="flex items-center gap-2">
                <span class="font-semibold">{get_conversation_name(@conversation, @current_user.id)}</span>
                <div :if={@conversation.type == "direct"} class="flex items-center gap-1">
                  <div class={[
                    "w-2 h-2 rounded-full",
                    is_other_user_online?(@conversation, @current_user.id, @online_user_ids) && "bg-success" || "bg-base-content/30"
                  ]}></div>
                  <span class="text-xs text-base-content/70">
                    {if is_other_user_online?(@conversation, @current_user.id, @online_user_ids), do: "Online", else: "Offline"}
                  </span>
                </div>
              </div>
              <span :if={@conversation.type == "group"} class="text-xs text-base-content/70">
                {get_online_count(@members, @online_user_ids)}/{length(@members)} online
              </span>
            </div>
          </div>
        </div>
        <div class="flex-none flex items-center gap-2">
          <%!-- Search button --%>
          <button phx-click="toggle_search" class="btn btn-ghost btn-sm" title="Search messages">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z" />
            </svg>
          </button>
          <div :if={@conversation.type == "group"} class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost btn-sm" phx-click="toggle_members">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z" />
              </svg>
            </div>
            <ul :if={@show_members} tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-[1] w-52 p-2 shadow">
              <li class="menu-title">Members</li>
              <li :for={member <- @members}>
                <span class={["flex items-center gap-2", member.id == @current_user.id && "font-bold" || ""]}>
                  <div class={[
                    "w-2 h-2 rounded-full flex-shrink-0",
                    member.id in @online_user_ids && "bg-success" || "bg-base-content/30"
                  ]}></div>
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

      <%!-- Search overlay --%>
      <div :if={@show_search} class="absolute top-16 right-4 z-50">
        <div class="card bg-base-100 shadow-xl w-80">
          <div class="card-body p-4">
            <div class="flex items-center gap-2">
              <input
                type="text"
                placeholder="Search messages..."
                value={@search_query}
                phx-keyup="search_messages"
                phx-debounce="300"
                name="query"
                class="input input-bordered flex-1 input-sm"
                autofocus
                id="search-input"
              />
              <button phx-click="clear_search" class="btn btn-ghost btn-sm btn-circle">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            <div :if={@search_results != []} class="mt-2 max-h-60 overflow-y-auto">
              <div
                :for={msg <- @search_results}
                phx-click="jump_to_message"
                phx-value-message-id={msg.id}
                class="p-2 hover:bg-base-200 rounded cursor-pointer"
              >
                <div class="font-medium text-sm">{msg.sender.username}</div>
                <div class="text-sm truncate">{msg.content}</div>
                <div class="text-xs text-base-content/50">{format_time(msg.inserted_at)}</div>
              </div>
            </div>
            <p :if={@search_query != "" && byte_size(@search_query) >= 2 && @search_results == []} class="text-sm text-base-content/50 mt-2">
              No messages found
            </p>
            <p :if={@search_query != "" && byte_size(@search_query) < 2} class="text-sm text-base-content/50 mt-2">
              Enter at least 2 characters to search
            </p>
          </div>
        </div>
      </div>

      <div class="flex-1 overflow-y-auto p-4" id="messages-container" phx-hook="ScrollToBottom">
        <div class="max-w-2xl mx-auto space-y-4">
          <div :if={@messages == []} class="text-center py-12 text-base-content/70">
            <p>No messages yet. Say hello!</p>
          </div>

          <div
            :for={message <- @messages}
            id={"message-#{message.id}"}
            class={["chat group", get_chat_position(message, @current_user.id)]}
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
              <span :if={message.edited_at && !message.deleted_at} class="text-xs opacity-50 ml-1 italic">(edited)</span>
            </div>

            <%!-- Deleted message placeholder --%>
            <div :if={message.deleted_at} class="chat-bubble bg-base-300 text-base-content/50 italic">
              This message was deleted
            </div>

            <%!-- Edit form --%>
            <div :if={!message.deleted_at && @editing_message_id == message.id} class="chat-bubble-wrapper">
              <form phx-submit="save_edit" class="flex flex-col gap-2">
                <input
                  type="text"
                  name="content"
                  value={@edit_content}
                  phx-change="update_edit"
                  class="input input-bordered input-sm w-full"
                  autofocus
                />
                <div class="flex gap-2 justify-end">
                  <button type="button" phx-click="cancel_edit" class="btn btn-ghost btn-xs">Cancel</button>
                  <button type="submit" class="btn btn-primary btn-xs">Save</button>
                </div>
              </form>
            </div>

            <%!-- Normal message content --%>
            <div :if={!message.deleted_at && @editing_message_id != message.id} class="relative">
              <div class={[
                "chat-bubble",
                get_bubble_class(message, @current_user.id)
              ]}>
                {message.content}
              </div>

              <%!-- Action buttons (visible on hover) --%>
              <div class="absolute -top-2 right-0 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                <%!-- Reaction button --%>
                <button
                  phx-click="show_reaction_picker"
                  phx-value-message-id={message.id}
                  class="btn btn-ghost btn-xs btn-circle bg-base-100 shadow-sm"
                  title="Add reaction"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15.182 15.182a4.5 4.5 0 0 1-6.364 0M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM9.75 9.75c0 .414-.168.75-.375.75S9 10.164 9 9.75 9.168 9 9.375 9s.375.336.375.75Zm-.375 0h.008v.015h-.008V9.75Zm5.625 0c0 .414-.168.75-.375.75s-.375-.336-.375-.75.168-.75.375-.75.375.336.375.75Zm-.375 0h.008v.015h-.008V9.75Z" />
                  </svg>
                </button>
                <%!-- Edit/Delete buttons (only for own messages within time limit) --%>
                <button
                  :if={can_modify_message?(message, @current_user.id)}
                  phx-click="start_edit"
                  phx-value-id={message.id}
                  class="btn btn-ghost btn-xs btn-circle bg-base-100 shadow-sm"
                  title="Edit message"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />
                  </svg>
                </button>
                <button
                  :if={can_modify_message?(message, @current_user.id)}
                  phx-click="show_delete_modal"
                  phx-value-id={message.id}
                  class="btn btn-ghost btn-xs btn-circle bg-base-100 shadow-sm text-error"
                  title="Delete message"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
                    <path stroke-linecap="round" stroke-linejoin="round" d="m14.74 9-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0" />
                  </svg>
                </button>
              </div>

              <%!-- Reaction picker popup --%>
              <div
                :if={@reaction_picker_message_id == message.id}
                class="absolute z-20 bg-base-100 shadow-lg rounded-lg p-2 flex gap-1 border border-base-300 -bottom-12 right-0"
              >
                <button
                  :for={emoji <- Reaction.allowed_emojis()}
                  phx-click="toggle_reaction"
                  phx-value-message-id={message.id}
                  phx-value-emoji={emoji}
                  class="btn btn-ghost btn-sm text-lg hover:scale-125 transition-transform px-1"
                >
                  {emoji}
                </button>
              </div>
            </div>

            <%!-- Reactions display below message --%>
            <div :if={map_size(Map.get(message, :reactions_grouped, %{})) > 0} class="chat-footer flex flex-wrap gap-1 mt-1">
              <button
                :for={{emoji, reactors} <- Map.get(message, :reactions_grouped, %{})}
                phx-click="toggle_reaction"
                phx-value-message-id={message.id}
                phx-value-emoji={emoji}
                class={[
                  "btn btn-xs gap-1",
                  user_has_reacted?(@current_user.id, reactors) && "btn-primary" || "btn-ghost border border-base-300"
                ]}
                title={format_reactor_names(reactors)}
              >
                <span>{emoji}</span>
                <span class="text-xs">{length(reactors)}</span>
              </button>
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

      <%!-- Delete confirmation modal --%>
      <div :if={@show_delete_modal} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg">Delete Message</h3>
          <p class="py-4">Are you sure you want to delete this message? This action cannot be undone.</p>
          <div class="modal-action">
            <button phx-click="cancel_delete" class="btn btn-ghost">Cancel</button>
            <button phx-click="confirm_delete" class="btn btn-error">Delete</button>
          </div>
        </div>
        <div class="modal-backdrop bg-base-content/50" phx-click="cancel_delete"></div>
      </div>
    </div>
    """
  end

  defp can_modify_message?(message, current_user_id) do
    # Check if user owns the message, it's not deleted, not from agent, and within time limit
    message.sender_id == current_user_id &&
      is_nil(message.deleted_at) &&
      !is_agent_message?(message) &&
      within_time_limit?(message)
  end

  defp within_time_limit?(message) do
    # Convert NaiveDateTime to DateTime for comparison
    inserted_at_datetime = DateTime.from_naive!(message.inserted_at, "Etc/UTC")
    minutes_since = DateTime.diff(DateTime.utc_now(), inserted_at_datetime, :minute)
    minutes_since <= Chat.edit_delete_time_limit_minutes()
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

  # Online presence helpers
  defp is_other_user_online?(%{type: "direct", members: members}, current_user_id, online_user_ids) do
    case Enum.find(members, fn m -> m.user_id != current_user_id end) do
      nil -> false
      member -> member.user_id in online_user_ids
    end
  end

  defp is_other_user_online?(_, _, _), do: false

  defp get_online_count(members, online_user_ids) do
    Enum.count(members, fn m -> m.id in online_user_ids end)
  end

  # Reaction helpers
  defp user_has_reacted?(user_id, reactors) do
    Enum.any?(reactors, fn user -> user.id == user_id end)
  end

  defp format_reactor_names(reactors) do
    case reactors do
      [] ->
        ""

      users when length(users) <= 5 ->
        Enum.map_join(users, ", ", & &1.username)

      [u1, u2, u3, u4, u5 | rest] ->
        "#{u1.username}, #{u2.username}, #{u3.username}, #{u4.username}, #{u5.username} and #{length(rest)} more"
    end
  end
end
