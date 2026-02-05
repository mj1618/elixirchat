defmodule ElixirchatWeb.ChatLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat
  alias Elixirchat.Chat.{Reaction, Mentions, Attachment}
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
      pinned_messages = Chat.list_pinned_messages(conversation_id)

      # Load read receipts for all messages
      message_ids = Enum.map(messages, & &1.id)
      read_receipts = Chat.get_read_receipts_for_messages(message_ids)

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
       socket
       |> allow_upload(:attachments,
         accept: Attachment.allowed_extensions(),
         max_entries: 5,
         max_file_size: Attachment.max_size(),
         auto_upload: false
       )
       |> assign(
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
         replying_to: nil,
         read_receipts: read_receipts,
         show_mentions: false,
         mention_results: [],
         pinned_messages: pinned_messages,
         show_pinned: false
       )}
    else
      {:ok, redirect(socket, to: "/chats") |> put_flash(:error, "Access denied")}
    end
  end

  @impl true
  def handle_event("send_message", %{"message" => content}, socket) do
    content = String.trim(content)
    has_attachments = length(socket.assigns.uploads.attachments.entries) > 0

    # Allow sending if there's content or attachments
    if content != "" or has_attachments do
      # Stop typing when message is sent
      if socket.assigns.is_typing do
        Chat.broadcast_typing_stop(socket.assigns.conversation.id, socket.assigns.current_user.id)
      end

      # Cancel any pending typing timer
      if socket.assigns.typing_timer do
        Process.cancel_timer(socket.assigns.typing_timer)
      end

      # Process uploaded files
      uploaded_files =
        consume_uploaded_entries(socket, :attachments, fn %{path: path}, entry ->
          # Generate unique filename with UUID prefix
          dest_filename = "#{Ecto.UUID.generate()}-#{entry.client_name}"
          dest = Path.join(Chat.uploads_dir(), dest_filename)
          File.cp!(path, dest)

          {:ok, %{
            filename: dest_filename,
            original_filename: entry.client_name,
            content_type: entry.client_type,
            size: entry.client_size
          }}
        end)

      # Include reply_to_id if replying to a message
      opts =
        if socket.assigns.replying_to do
          [reply_to_id: socket.assigns.replying_to.id, attachments: uploaded_files]
        else
          [attachments: uploaded_files]
        end

      # Use a placeholder content if empty but has attachments
      message_content = if content == "" and has_attachments, do: "[Attachment]", else: content

      case Chat.send_message(
        socket.assigns.conversation.id,
        socket.assigns.current_user.id,
        message_content,
        opts
      ) do
        {:ok, _message} ->
          {:noreply, assign(socket, message_input: "", is_typing: false, typing_timer: nil, replying_to: nil)}
        {:error, :invalid_reply_to} ->
          {:noreply,
           socket
           |> put_flash(:error, "Cannot reply to that message")
           |> assign(replying_to: nil)}
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
  def handle_event("cancel_upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  @impl true
  def handle_event("validate_upload", _params, socket) do
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
  # Reply Handlers
  # ===============================

  @impl true
  def handle_event("start_reply", %{"id" => message_id}, socket) do
    message_id = String.to_integer(message_id)
    message = Enum.find(socket.assigns.messages, fn m -> m.id == message_id end)

    # Don't allow replying to deleted messages
    if message && is_nil(message.deleted_at) do
      {:noreply, assign(socket, replying_to: message)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("cancel_reply", _, socket) do
    {:noreply, assign(socket, replying_to: nil)}
  end

  @impl true
  def handle_event("scroll_to_message", %{"message-id" => message_id}, socket) do
    {:noreply, push_event(socket, "scroll_to_message", %{message_id: message_id})}
  end

  # ===============================
  # Mention Handlers
  # ===============================

  @impl true
  def handle_event("mention_search", %{"query" => query}, socket) do
    results =
      if String.length(query) >= 1 do
        Chat.get_mentionable_users(socket.assigns.conversation.id, query)
        |> Enum.reject(fn u -> u.id == socket.assigns.current_user.id end)
      else
        []
      end

    {:noreply,
     assign(socket,
       mention_results: results,
       show_mentions: results != []
     )}
  end

  @impl true
  def handle_event("select_mention", %{"username" => username}, socket) do
    {:noreply,
     socket
     |> assign(show_mentions: false, mention_results: [])
     |> push_event("insert_mention", %{username: username})}
  end

  @impl true
  def handle_event("close_mentions", _, socket) do
    {:noreply, assign(socket, show_mentions: false, mention_results: [])}
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
  def handle_info({:link_previews_fetched, %{message_id: message_id, previews: previews}}, socket) do
    # Update the link previews for this message
    messages =
      Enum.map(socket.assigns.messages, fn msg ->
        if msg.id == message_id do
          Map.put(msg, :link_previews, previews)
        else
          msg
        end
      end)

    {:noreply, assign(socket, messages: messages)}
  end

  # ===============================
  # Message Pinning Handlers
  # ===============================

  @impl true
  def handle_event("pin_message", %{"message-id" => message_id}, socket) do
    message_id = String.to_integer(message_id)

    case Chat.pin_message(
      socket.assigns.conversation.id,
      message_id,
      socket.assigns.current_user.id
    ) do
      {:ok, _pinned} ->
        {:noreply, socket}

      {:error, :pin_limit_reached} ->
        {:noreply, put_flash(socket, :error, "Maximum 5 pinned messages allowed")}

      {:error, :already_pinned} ->
        {:noreply, put_flash(socket, :error, "Message is already pinned")}

      {:error, :message_deleted} ->
        {:noreply, put_flash(socket, :error, "Cannot pin a deleted message")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to pin message")}
    end
  end

  @impl true
  def handle_event("unpin_message", %{"message-id" => message_id}, socket) do
    message_id = String.to_integer(message_id)

    case Chat.unpin_message(message_id, socket.assigns.current_user.id) do
      :ok ->
        {:noreply, socket}

      {:error, :not_authorized} ->
        {:noreply, put_flash(socket, :error, "Only the pinner or message author can unpin")}

      {:error, :not_pinned} ->
        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to unpin message")}
    end
  end

  @impl true
  def handle_event("toggle_pinned", _, socket) do
    {:noreply, assign(socket, show_pinned: !socket.assigns.show_pinned)}
  end

  @impl true
  def handle_event("jump_to_pinned", %{"message-id" => message_id}, socket) do
    {:noreply,
     socket
     |> assign(show_pinned: false)
     |> push_event("scroll_to_message", %{message_id: message_id})}
  end

  @impl true
  def handle_info({:message_pinned, pinned}, socket) do
    {:noreply, update(socket, :pinned_messages, fn pins -> [pinned | pins] end)}
  end

  @impl true
  def handle_info({:message_unpinned, message_id}, socket) do
    {:noreply,
     update(socket, :pinned_messages, fn pins ->
       Enum.reject(pins, fn p -> p.message_id == message_id end)
     end)}
  end

  # ===============================
  # Read Receipt Handlers
  # ===============================

  @impl true
  def handle_event("messages_viewed", %{"message_ids" => message_ids}, socket) do
    # Convert string IDs to integers if needed
    message_ids = Enum.map(message_ids, fn id ->
      if is_binary(id), do: String.to_integer(id), else: id
    end)

    # Only mark messages we didn't send ourselves
    messages_to_mark =
      socket.assigns.messages
      |> Enum.filter(fn msg -> msg.id in message_ids && msg.sender_id != socket.assigns.current_user.id end)
      |> Enum.map(& &1.id)

    if messages_to_mark != [] do
      Chat.mark_messages_read(
        socket.assigns.conversation.id,
        socket.assigns.current_user.id,
        messages_to_mark
      )
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:messages_read, %{user_id: user_id, message_ids: message_ids}}, socket) do
    # Update read_receipts assign with new reads
    updated_receipts =
      Enum.reduce(message_ids, socket.assigns.read_receipts, fn msg_id, acc ->
        current_readers = Map.get(acc, msg_id, [])
        if user_id in current_readers do
          acc
        else
          Map.put(acc, msg_id, [user_id | current_readers])
        end
      end)

    {:noreply, assign(socket, read_receipts: updated_receipts)}
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

      <%!-- Pinned messages section --%>
      <div :if={length(@pinned_messages) > 0} class="bg-base-200 border-b border-base-300">
        <button
          phx-click="toggle_pinned"
          class="w-full px-4 py-2 flex items-center justify-between hover:bg-base-300 transition-colors"
        >
          <div class="flex items-center gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" viewBox="0 0 24 24" class="w-4 h-4 text-warning">
              <path d="M16 12V4h1V2H7v2h1v8l-2 2v2h5.2v6h1.6v-6H18v-2l-2-2z"/>
            </svg>
            <span class="text-sm font-medium">{length(@pinned_messages)} Pinned</span>
          </div>
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class={["w-4 h-4 transition-transform", @show_pinned && "rotate-180"]}>
            <path stroke-linecap="round" stroke-linejoin="round" d="m19.5 8.25-7.5 7.5-7.5-7.5" />
          </svg>
        </button>

        <div :if={@show_pinned} class="px-4 pb-2 space-y-2 max-h-48 overflow-y-auto">
          <div
            :for={pinned <- @pinned_messages}
            class="flex items-start justify-between gap-2 p-2 bg-base-100 rounded hover:bg-base-300 cursor-pointer transition-colors"
            phx-click="jump_to_pinned"
            phx-value-message-id={pinned.message.id}
          >
            <div class="flex-1 min-w-0">
              <div class="text-xs text-base-content/60">
                <span class="font-medium">{pinned.message.sender.username}</span>
                <span> · Pinned by {pinned.pinned_by && pinned.pinned_by.username || "unknown"}</span>
              </div>
              <p class="text-sm truncate">{truncate(pinned.message.content, 80)}</p>
            </div>
            <button
              :if={can_unpin?(@current_user.id, pinned)}
              phx-click="unpin_message"
              phx-value-message-id={pinned.message.id}
              class="btn btn-ghost btn-xs btn-circle flex-shrink-0"
              title="Unpin"
            >
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
              </svg>
            </button>
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
            data-message-id={message.id}
            class={["chat group", get_chat_position(message, @current_user.id)]}
          >
            <div class="chat-image avatar placeholder">
              <div class={[
                "w-10 rounded-full text-white font-bold",
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

            <%!-- Reply preview (shown above message content) --%>
            <div
              :if={message.reply_to}
              phx-click="scroll_to_message"
              phx-value-message-id={message.reply_to_id}
              class="text-xs opacity-70 mb-1 flex items-center gap-1 cursor-pointer hover:opacity-100"
            >
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3 flex-shrink-0">
                <path stroke-linecap="round" stroke-linejoin="round" d="m4.5 19.5 15-15m0 0H8.25m11.25 0v11.25" />
              </svg>
              <span :if={message.reply_to.deleted_at} class="italic">Original message was deleted</span>
              <span :if={is_nil(message.reply_to.deleted_at)} class="truncate">
                <strong>{message.reply_to.sender.username}:</strong> {truncate(message.reply_to.content, 50)}
              </span>
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
                <%!-- Only show text content if it's not just "[Attachment]" --%>
                <span :if={message.content != "[Attachment]"}>
                  <%= raw(Mentions.render_with_mentions(message.content, @conversation.id)) %>
                </span>

                <%!-- Attachment display --%>
                <div :if={length(message.attachments) > 0} class={["mt-2 flex flex-wrap gap-2", message.content == "[Attachment]" && "mt-0"]}>
                  <%= for attachment <- message.attachments do %>
                    <%= if Attachment.image?(attachment) do %>
                      <a href={"/uploads/#{attachment.filename}"} target="_blank" class="block">
                        <img src={"/uploads/#{attachment.filename}"} alt={attachment.original_filename} class="max-w-xs max-h-48 rounded cursor-pointer hover:opacity-90" loading="lazy" />
                      </a>
                    <% else %>
                      <a href={"/uploads/#{attachment.filename}"} download={attachment.original_filename} class="flex items-center gap-2 p-2 bg-base-200 rounded hover:bg-base-300">
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
                        </svg>
                        <span class="text-sm">{attachment.original_filename}</span>
                      </a>
                    <% end %>
                  <% end %>
                </div>
              </div>

              <%!-- Action buttons (visible on hover) --%>
              <div class="absolute -top-2 right-0 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                <%!-- Reply button --%>
                <button
                  phx-click="start_reply"
                  phx-value-id={message.id}
                  class="btn btn-ghost btn-xs btn-circle bg-base-100 shadow-sm"
                  title="Reply"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M9 15 3 9m0 0 6-6M3 9h12a6 6 0 0 1 0 12h-3" />
                  </svg>
                </button>
                <%!-- Pin/Unpin button --%>
                <button
                  phx-click={if is_message_pinned?(message.id, @pinned_messages), do: "unpin_message", else: "pin_message"}
                  phx-value-message-id={message.id}
                  class={["btn btn-ghost btn-xs btn-circle bg-base-100 shadow-sm", is_message_pinned?(message.id, @pinned_messages) && "text-warning"]}
                  title={if is_message_pinned?(message.id, @pinned_messages), do: "Unpin", else: "Pin"}
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill={if is_message_pinned?(message.id, @pinned_messages), do: "currentColor", else: "none"} viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
                    <path d="M16 12V4h1V2H7v2h1v8l-2 2v2h5.2v6h1.6v-6H18v-2l-2-2z"/>
                  </svg>
                </button>
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

            <%!-- Read receipt indicator (only for own sent messages) --%>
            <div :if={message.sender_id == @current_user.id && is_nil(message.deleted_at)} class="chat-footer opacity-50 text-xs flex items-center gap-1 mt-0.5">
              <%!-- Direct chat: show checkmarks --%>
              <%= if @conversation.type == "direct" do %>
                <%= if message_read_by_other?(message.id, @current_user.id, @read_receipts, @conversation) do %>
                  <%!-- Double checkmark (read) --%>
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4 text-primary">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M1.5 12.5l5 5L17 7M7.5 12.5l5 5L23 7"/>
                  </svg>
                  <span class="text-primary">Read</span>
                <% else %>
                  <%!-- Single checkmark (delivered) --%>
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.5l5 5L20 7"/>
                  </svg>
                  <span>Delivered</span>
                <% end %>
              <% else %>
                <%!-- Group chat: show read count --%>
                <% reader_count = get_reader_count(message.id, @current_user.id, @read_receipts) %>
                <% total_members = length(@members) - 1 %>
                <%= if reader_count > 0 do %>
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4 text-primary">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M1.5 12.5l5 5L17 7M7.5 12.5l5 5L23 7"/>
                  </svg>
                  <span class="text-primary cursor-help" title={get_reader_names(message.id, @current_user.id, @read_receipts, @members)}>
                    Read by {reader_count}/{total_members}
                  </span>
                <% else %>
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" class="w-4 h-4">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.5l5 5L20 7"/>
                  </svg>
                  <span>Delivered</span>
                <% end %>
              <% end %>
            </div>
          </div>
        </div>
      </div>

      <div class="bg-base-100 border-t border-base-300 p-4">
        <div class="max-w-2xl mx-auto">
          <%!-- Reply indicator above input --%>
          <div :if={@replying_to} class="bg-base-200 p-2 rounded-t-lg flex justify-between items-center mb-0 -mb-1">
            <div class="text-sm truncate flex-1">
              <span class="opacity-70">Replying to</span>
              <strong class="ml-1">{@replying_to.sender.username}</strong>
              <span class="ml-2 opacity-70">{truncate(@replying_to.content, 40)}</span>
            </div>
            <button phx-click="cancel_reply" class="btn btn-ghost btn-xs btn-circle flex-shrink-0">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
              </svg>
            </button>
          </div>
          <%!-- Upload previews --%>
          <div :if={length(@uploads.attachments.entries) > 0} class="flex flex-wrap gap-2 p-2 bg-base-200 rounded-t-lg mb-0">
            <div :for={entry <- @uploads.attachments.entries} class="relative">
              <.live_img_preview :if={String.starts_with?(entry.client_type, "image/")} entry={entry} class="w-20 h-20 object-cover rounded" />
              <div :if={!String.starts_with?(entry.client_type, "image/")} class="w-20 h-20 bg-base-300 rounded flex items-center justify-center">
                <div class="text-center p-1">
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6 mx-auto">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z" />
                  </svg>
                  <span class="text-xs truncate block w-full">{String.slice(entry.client_name, 0..8)}</span>
                </div>
              </div>
              <button type="button" phx-click="cancel_upload" phx-value-ref={entry.ref} class="absolute -top-2 -right-2 btn btn-circle btn-xs btn-error">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-3 h-3">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
                </svg>
              </button>
              <progress :if={entry.progress > 0 && entry.progress < 100} value={entry.progress} max="100" class="absolute bottom-0 left-0 w-full h-1 progress progress-primary" />
            </div>
            <%!-- Upload errors --%>
            <div :for={err <- upload_errors(@uploads.attachments)} class="text-error text-sm">
              {upload_error_to_string(err)}
            </div>
          </div>

          <div :if={MapSet.size(@typing_users) > 0} class="text-sm text-base-content/60 italic pb-2 h-6">
            <span class="typing-indicator">
              {format_typing_users(@typing_users)}
              <span class="typing-dots">...</span>
            </span>
          </div>
          <div :if={MapSet.size(@typing_users) == 0 && is_nil(@replying_to) && length(@uploads.attachments.entries) == 0} class="h-6 pb-2"></div>
          <div class="relative" id="mention-input-container" phx-hook="MentionInput">
            <%!-- Mention autocomplete dropdown --%>
            <div
              :if={@show_mentions && @mention_results != []}
              class="absolute bottom-full left-0 mb-2 w-64 bg-base-100 border border-base-300 rounded-lg shadow-lg z-20"
            >
              <ul class="menu menu-compact p-2">
                <li :for={user <- @mention_results}>
                  <button
                    type="button"
                    phx-click="select_mention"
                    phx-value-username={user.username}
                    class="flex items-center gap-2"
                  >
                    <div class="avatar placeholder">
                      <div class="bg-neutral text-neutral-content rounded-full w-6">
                        <span class="text-xs">{String.first(user.username) |> String.upcase()}</span>
                      </div>
                    </div>
                    <span>@{user.username}</span>
                  </button>
                </li>
              </ul>
            </div>
            <form phx-submit="send_message" phx-change="validate_upload" class="flex gap-2">
              <%!-- Attachment button --%>
              <label class="btn btn-ghost btn-circle cursor-pointer self-center">
                <.live_file_input upload={@uploads.attachments} class="hidden" />
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                  <path stroke-linecap="round" stroke-linejoin="round" d="m18.375 12.739-7.693 7.693a4.5 4.5 0 0 1-6.364-6.364l10.94-10.94A3 3 0 1 1 19.5 7.372L8.552 18.32m.009-.01-.01.01m5.699-9.941-7.81 7.81a1.5 1.5 0 0 0 2.112 2.13" />
                </svg>
              </label>
              <input
                type="text"
                name="message"
                value={@message_input}
                placeholder="Type a message... (@ to mention)"
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

  defp truncate(text, max_length) when byte_size(text) <= max_length, do: text
  defp truncate(text, max_length) do
    String.slice(text, 0, max_length) <> "..."
  end

  # Read receipt helpers

  # Checks if message is read by the other user in a direct conversation
  defp message_read_by_other?(message_id, sender_id, read_receipts, conversation) do
    readers = Map.get(read_receipts, message_id, [])
    # In direct chat, the "other" user is whoever isn't the sender
    other_member = Enum.find(conversation.members, fn m -> m.user_id != sender_id end)

    if other_member do
      other_member.user_id in readers
    else
      false
    end
  end

  # Gets the count of users who have read a message (excluding the sender)
  defp get_reader_count(message_id, sender_id, read_receipts) do
    readers = Map.get(read_receipts, message_id, [])
    Enum.count(readers, fn reader_id -> reader_id != sender_id end)
  end

  # Gets the names of users who have read a message (for tooltip)
  defp get_reader_names(message_id, sender_id, read_receipts, members) do
    reader_ids = Map.get(read_receipts, message_id, [])

    members
    |> Enum.filter(fn m -> m.id in reader_ids && m.id != sender_id end)
    |> case do
      [] ->
        ""

      readers when length(readers) <= 5 ->
        Enum.map_join(readers, ", ", & &1.username)

      [r1, r2, r3, r4, r5 | rest] ->
        "#{r1.username}, #{r2.username}, #{r3.username}, #{r4.username}, #{r5.username} and #{length(rest)} more"
    end
  end

  # Upload error helpers
  defp upload_error_to_string(:too_large), do: "File too large (max 10MB)"
  defp upload_error_to_string(:too_many_files), do: "Too many files (max 5)"
  defp upload_error_to_string(:not_accepted), do: "File type not allowed"
  defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"

  # Pinning helpers

  # Checks if a message is pinned
  defp is_message_pinned?(message_id, pinned_messages) do
    Enum.any?(pinned_messages, fn p -> p.message_id == message_id end)
  end

  # Checks if user can unpin (is the pinner or message author)
  defp can_unpin?(user_id, pinned) do
    pinned.pinned_by_id == user_id || pinned.message.sender_id == user_id
  end
end
