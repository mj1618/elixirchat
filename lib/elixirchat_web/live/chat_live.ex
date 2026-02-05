defmodule ElixirchatWeb.ChatLive do
  use ElixirchatWeb, :live_view

  alias Elixirchat.Chat
  alias Elixirchat.Chat.{Reaction, Attachment, Markdown}
  alias Elixirchat.Agent
  alias Elixirchat.Presence
  alias Elixirchat.Accounts

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

      # Load thread reply counts for all messages
      message_ids_for_threads = Enum.map(messages, & &1.id)
      thread_reply_counts = Chat.get_thread_reply_counts(message_ids_for_threads)
      is_conversation_pinned = Chat.is_conversation_pinned?(conversation_id, current_user.id)
      is_muted = Chat.is_muted?(conversation_id, current_user.id)
      is_archived = Chat.is_archived?(conversation_id, current_user.id)
      starred_message_ids = Chat.get_starred_message_ids(current_user.id)
      polls = Chat.list_conversation_polls(conversation_id)
      poll_ids = Enum.map(polls, & &1.id)
      user_poll_votes = Chat.get_user_votes_for_polls(poll_ids, current_user.id)
      current_user_role = Chat.get_member_role(conversation_id, current_user.id)

      # Load read receipts for all messages
      message_ids = Enum.map(messages, & &1.id)
      read_receipts = Chat.get_read_receipts_for_messages(message_ids)

      # Get other user for direct conversations (for status display)
      other_user =
        if conversation.type == "direct" do
          case Enum.find(conversation.members, fn m -> m.user_id != current_user.id end) do
            nil -> nil
            member -> Accounts.get_user(member.user_id)
          end
        else
          nil
        end

      # Track presence and subscribe to updates when connected
      online_user_ids =
        if connected?(socket) do
          Chat.subscribe(conversation_id)
          Chat.mark_conversation_read(conversation_id, current_user.id)
          Presence.track_user(self(), current_user)
          Presence.subscribe()

          # Subscribe to other user's status changes in direct messages
          if other_user do
            Accounts.subscribe_to_user_status(other_user.id)
          end

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
         show_pinned: false,
         show_add_member: false,
         add_member_search_query: "",
         add_member_search_results: [],
         show_leave_confirm: false,
         is_muted: is_muted,
         is_archived: is_archived,
         is_conversation_pinned: is_conversation_pinned,
         show_forward_modal: false,
         forward_message_id: nil,
        forward_search_query: "",
        forward_conversations: [],
        starred_message_ids: starred_message_ids,
        other_user: other_user,
        is_other_user_blocked: other_user && Accounts.is_blocked?(current_user.id, other_user.id),
        polls: polls,
        user_poll_votes: user_poll_votes,
        show_poll_modal: false,
        poll_question: "",
        poll_options: ["", ""],
        show_invite_modal: false,
        invite_link: nil,
        current_user_role: current_user_role,
        show_member_menu: nil,
        show_transfer_confirm: false,
        transfer_target_id: nil,
        show_schedule_modal: false,
        schedule_datetime: nil,
        scheduled_message_count: Chat.get_scheduled_message_count(current_user.id),
        # Thread support
        thread_reply_counts: thread_reply_counts,
        show_thread: false,
        thread_parent_message: nil,
        thread_replies: [],
        thread_input: ""
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
          {:noreply,
           socket
           |> assign(message_input: "", is_typing: false, typing_timer: nil, replying_to: nil)
           |> push_event("clear-input", %{id: "message-input"})}
        {:error, :invalid_reply_to} ->
          {:noreply,
           socket
           |> put_flash(:error, "Cannot reply to that message")
           |> assign(replying_to: nil)}
        {:error, :user_blocked} ->
          {:noreply, put_flash(socket, :error, "You have blocked this user. Unblock them to send messages.")}
        {:error, :blocked_by_user} ->
          {:noreply, put_flash(socket, :error, "You cannot send messages to this user.")}
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
  def handle_event("show_leave_confirm", _, socket) do
    {:noreply, assign(socket, show_leave_confirm: true)}
  end

  @impl true
  def handle_event("cancel_leave", _, socket) do
    {:noreply, assign(socket, show_leave_confirm: false)}
  end

  @impl true
  def handle_event("leave_group", _, socket) do
    conversation_id = socket.assigns.conversation.id
    user_id = socket.assigns.current_user.id

    case Chat.leave_group(conversation_id, user_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "You have left the group")
         |> push_navigate(to: ~p"/chats")}
      {:error, :cannot_leave_general} ->
        {:noreply,
         socket
         |> put_flash(:error, "You cannot leave the General group")
         |> assign(show_leave_confirm: false)}
      {:error, :owner_must_transfer} ->
        {:noreply,
         socket
         |> put_flash(:error, "You must transfer ownership before leaving the group")
         |> assign(show_leave_confirm: false)}
      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not leave the group")
         |> assign(show_leave_confirm: false)}
    end
  end

  # ===============================
  # Group Admin Handlers
  # ===============================

  @impl true
  def handle_event("show_member_menu", %{"user-id" => user_id}, socket) do
    {:noreply, assign(socket, show_member_menu: String.to_integer(user_id))}
  end

  @impl true
  def handle_event("hide_member_menu", _, socket) do
    {:noreply, assign(socket, show_member_menu: nil)}
  end

  @impl true
  def handle_event("kick_member", %{"user-id" => user_id}, socket) do
    target_id = String.to_integer(user_id)
    conversation_id = socket.assigns.conversation.id
    kicker_id = socket.assigns.current_user.id

    case Chat.kick_member(conversation_id, kicker_id, target_id) do
      :ok ->
        {:noreply,
         socket
         |> put_flash(:info, "Member removed from the group")
         |> assign(show_member_menu: nil)}
      {:error, :not_authorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You don't have permission to remove this member")
         |> assign(show_member_menu: nil)}
      {:error, :cannot_kick_owner} ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot remove the group owner")
         |> assign(show_member_menu: nil)}
      {:error, :cannot_kick_admin} ->
        {:noreply,
         socket
         |> put_flash(:error, "Admins cannot remove other admins")
         |> assign(show_member_menu: nil)}
      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not remove member")
         |> assign(show_member_menu: nil)}
    end
  end

  @impl true
  def handle_event("promote_member", %{"user-id" => user_id}, socket) do
    target_id = String.to_integer(user_id)
    conversation_id = socket.assigns.conversation.id
    promoter_id = socket.assigns.current_user.id

    case Chat.promote_to_admin(conversation_id, promoter_id, target_id) do
      {:ok, _} ->
        members = Chat.list_group_members(conversation_id)
        {:noreply,
         socket
         |> put_flash(:info, "Member promoted to admin")
         |> assign(members: members, show_member_menu: nil)}
      {:error, :not_owner} ->
        {:noreply,
         socket
         |> put_flash(:error, "Only the owner can promote members to admin")
         |> assign(show_member_menu: nil)}
      {:error, :already_admin} ->
        {:noreply,
         socket
         |> put_flash(:error, "This member is already an admin")
         |> assign(show_member_menu: nil)}
      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not promote member")
         |> assign(show_member_menu: nil)}
    end
  end

  @impl true
  def handle_event("demote_member", %{"user-id" => user_id}, socket) do
    target_id = String.to_integer(user_id)
    conversation_id = socket.assigns.conversation.id
    demoter_id = socket.assigns.current_user.id

    case Chat.demote_from_admin(conversation_id, demoter_id, target_id) do
      {:ok, _} ->
        members = Chat.list_group_members(conversation_id)
        {:noreply,
         socket
         |> put_flash(:info, "Admin demoted to member")
         |> assign(members: members, show_member_menu: nil)}
      {:error, :not_owner} ->
        {:noreply,
         socket
         |> put_flash(:error, "Only the owner can demote admins")
         |> assign(show_member_menu: nil)}
      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not demote admin")
         |> assign(show_member_menu: nil)}
    end
  end

  @impl true
  def handle_event("show_transfer_confirm", %{"user-id" => user_id}, socket) do
    {:noreply, assign(socket, show_transfer_confirm: true, transfer_target_id: String.to_integer(user_id), show_member_menu: nil)}
  end

  @impl true
  def handle_event("cancel_transfer", _, socket) do
    {:noreply, assign(socket, show_transfer_confirm: false, transfer_target_id: nil)}
  end

  @impl true
  def handle_event("transfer_ownership", _, socket) do
    conversation_id = socket.assigns.conversation.id
    owner_id = socket.assigns.current_user.id
    new_owner_id = socket.assigns.transfer_target_id

    case Chat.transfer_ownership(conversation_id, owner_id, new_owner_id) do
      :ok ->
        members = Chat.list_group_members(conversation_id)
        current_user_role = Chat.get_member_role(conversation_id, owner_id)
        {:noreply,
         socket
         |> put_flash(:info, "Ownership transferred successfully")
         |> assign(members: members, current_user_role: current_user_role, show_transfer_confirm: false, transfer_target_id: nil)}
      {:error, :not_owner} ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not the owner of this group")
         |> assign(show_transfer_confirm: false, transfer_target_id: nil)}
      {:error, _} ->
        {:noreply,
         socket
         |> put_flash(:error, "Could not transfer ownership")
         |> assign(show_transfer_confirm: false, transfer_target_id: nil)}
    end
  end

  # ===============================
  # Mute Conversation Handler
  # ===============================

  @impl true
  def handle_event("toggle_mute", _, socket) do
    conversation_id = socket.assigns.conversation.id
    user_id = socket.assigns.current_user.id

    case Chat.toggle_mute(conversation_id, user_id) do
      {:ok, :muted} ->
        {:noreply,
         socket
         |> assign(is_muted: true)
         |> put_flash(:info, "Conversation muted")}

      {:ok, :unmuted} ->
        {:noreply,
         socket
         |> assign(is_muted: false)
         |> put_flash(:info, "Conversation unmuted")}
    end
  end

  # ===============================
  # Block User Handler (for direct conversations)
  # ===============================

  @impl true
  def handle_event("toggle_block_user", _, socket) do
    conversation = socket.assigns.conversation
    current_user = socket.assigns.current_user
    other_user = socket.assigns.other_user

    if conversation.type == "direct" && other_user do
      if socket.assigns.is_other_user_blocked do
        # Unblock user
        Accounts.unblock_user(current_user.id, other_user.id)
        {:noreply,
         socket
         |> assign(is_other_user_blocked: false)
         |> put_flash(:info, "User unblocked")}
      else
        # Block user
        case Accounts.block_user(current_user.id, other_user.id) do
          {:ok, _} ->
            {:noreply,
             socket
             |> assign(is_other_user_blocked: true)
             |> put_flash(:info, "User blocked")}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not block user")}
        end
      end
    else
      {:noreply, socket}
    end
  end

  # ===============================
  # Archive Conversation Handler
  # ===============================

  @impl true
  def handle_event("toggle_archive", _, socket) do
    conversation_id = socket.assigns.conversation.id
    user_id = socket.assigns.current_user.id

    case Chat.toggle_archive(conversation_id, user_id) do
      {:ok, :archived} ->
        {:noreply,
         socket
         |> assign(is_archived: true)
         |> put_flash(:info, "Conversation archived")}

      {:ok, :unarchived} ->
        {:noreply,
         socket
         |> assign(is_archived: false)
         |> put_flash(:info, "Conversation unarchived")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update archive status")}
    end
  end

  # ===============================
  # Starred Message Handler
  # ===============================

  @impl true
  def handle_event("toggle_star", %{"message-id" => message_id}, socket) do
    message_id = String.to_integer(message_id)
    user_id = socket.assigns.current_user.id

    case Chat.toggle_star(message_id, user_id) do
      {:ok, :starred} ->
        starred_ids = MapSet.put(socket.assigns.starred_message_ids, message_id)
        {:noreply, assign(socket, starred_message_ids: starred_ids)}

      {:ok, :unstarred} ->
        starred_ids = MapSet.delete(socket.assigns.starred_message_ids, message_id)
        {:noreply, assign(socket, starred_message_ids: starred_ids)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not star message")}
    end
  end

  # ===============================
  # Poll Handlers
  # ===============================

  @impl true
  def handle_event("show_poll_modal", _, socket) do
    {:noreply, assign(socket, show_poll_modal: true, poll_question: "", poll_options: ["", ""])}
  end

  @impl true
  def handle_event("close_poll_modal", _, socket) do
    {:noreply, assign(socket, show_poll_modal: false)}
  end

  @impl true
  def handle_event("update_poll_question", %{"value" => question}, socket) do
    {:noreply, assign(socket, poll_question: question)}
  end

  @impl true
  def handle_event("update_poll_option", %{"index" => index, "value" => value}, socket) do
    index = String.to_integer(index)
    options = List.replace_at(socket.assigns.poll_options, index, value)
    {:noreply, assign(socket, poll_options: options)}
  end

  @impl true
  def handle_event("add_poll_option", _, socket) do
    if length(socket.assigns.poll_options) < 10 do
      options = socket.assigns.poll_options ++ [""]
      {:noreply, assign(socket, poll_options: options)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("remove_poll_option", %{"index" => index}, socket) do
    if length(socket.assigns.poll_options) > 2 do
      index = String.to_integer(index)
      options = List.delete_at(socket.assigns.poll_options, index)
      {:noreply, assign(socket, poll_options: options)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("create_poll", %{"question" => question} = params, socket) do
    options =
      params
      |> Map.get("options", %{})
      |> Map.values()
      |> Enum.filter(fn opt -> String.trim(opt) != "" end)

    case Chat.create_poll(
           socket.assigns.conversation.id,
           socket.assigns.current_user.id,
           question,
           options
         ) do
      {:ok, poll} ->
        # Update user_poll_votes map for the new poll (no votes yet)
        user_poll_votes = Map.put(socket.assigns.user_poll_votes, poll.id, MapSet.new())

        {:noreply,
         socket
         |> assign(show_poll_modal: false, user_poll_votes: user_poll_votes)
         |> update(:polls, fn polls -> [poll | polls] end)
         |> put_flash(:info, "Poll created")}

      {:error, :too_few_options} ->
        {:noreply, put_flash(socket, :error, "Poll must have at least 2 options")}

      {:error, :too_many_options} ->
        {:noreply, put_flash(socket, :error, "Poll can have at most 10 options")}

      {:error, :empty_option} ->
        {:noreply, put_flash(socket, :error, "Poll options cannot be empty")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create poll")}
    end
  end

  @impl true
  def handle_event("vote_on_poll", %{"poll-id" => poll_id, "option-id" => option_id}, socket) do
    poll_id = String.to_integer(poll_id)
    option_id = String.to_integer(option_id)

    case Chat.vote_on_poll(poll_id, option_id, socket.assigns.current_user.id) do
      {:ok, poll} ->
        {:noreply, update_poll_in_list(socket, poll)}

      {:error, :poll_closed} ->
        {:noreply, put_flash(socket, :error, "This poll is closed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not vote")}
    end
  end

  @impl true
  def handle_event("close_poll", %{"poll-id" => poll_id}, socket) do
    poll_id = String.to_integer(poll_id)

    case Chat.close_poll(poll_id, socket.assigns.current_user.id) do
      {:ok, poll} ->
        {:noreply,
         socket
         |> update_poll_in_list(poll)
         |> put_flash(:info, "Poll closed")}

      {:error, :not_creator} ->
        {:noreply, put_flash(socket, :error, "Only the poll creator can close it")}

      {:error, :already_closed} ->
        {:noreply, put_flash(socket, :error, "Poll is already closed")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not close poll")}
    end
  end

  defp update_poll_in_list(socket, updated_poll) do
    polls =
      Enum.map(socket.assigns.polls, fn poll ->
        if poll.id == updated_poll.id, do: updated_poll, else: poll
      end)

    # Update user's votes for this poll
    user_votes = Chat.get_user_poll_votes(updated_poll.id, socket.assigns.current_user.id)
    user_poll_votes = Map.put(socket.assigns.user_poll_votes, updated_poll.id, user_votes)

    assign(socket, polls: polls, user_poll_votes: user_poll_votes)
  end

  # ===============================
  # Group Invite Link Handlers
  # ===============================

  @impl true
  def handle_event("show_invite_modal", _, socket) do
    invite = Chat.get_group_invite(socket.assigns.conversation.id)
    invite_link = if invite && Chat.is_invite_valid?(invite) do
      ElixirchatWeb.Endpoint.url() <> "/join/#{invite.token}"
    end

    {:noreply, assign(socket, show_invite_modal: true, invite_link: invite_link)}
  end

  @impl true
  def handle_event("close_invite_modal", _, socket) do
    {:noreply, assign(socket, show_invite_modal: false)}
  end

  @impl true
  def handle_event("create_invite", _, socket) do
    case Chat.create_group_invite(socket.assigns.conversation.id, socket.assigns.current_user.id) do
      {:ok, invite} ->
        invite_link = ElixirchatWeb.Endpoint.url() <> "/join/#{invite.token}"
        {:noreply,
         socket
         |> assign(invite_link: invite_link)
         |> put_flash(:info, "Invite link created")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not create invite")}
    end
  end

  @impl true
  def handle_event("regenerate_invite", _, socket) do
    # Revoke existing and create new
    Chat.revoke_invite(socket.assigns.conversation.id, socket.assigns.current_user.id)

    case Chat.create_group_invite(socket.assigns.conversation.id, socket.assigns.current_user.id) do
      {:ok, invite} ->
        invite_link = ElixirchatWeb.Endpoint.url() <> "/join/#{invite.token}"
        {:noreply,
         socket
         |> assign(invite_link: invite_link)
         |> put_flash(:info, "New invite link generated")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not regenerate invite")}
    end
  end

  @impl true
  def handle_event("show_schedule_modal", _, socket) do
    {:noreply, assign(socket, show_schedule_modal: true)}
  end

  @impl true
  def handle_event("close_schedule_modal", _, socket) do
    {:noreply, assign(socket, show_schedule_modal: false)}
  end

  @impl true
  def handle_event("schedule_message", %{"content" => content, "scheduled_for" => scheduled_for_str}, socket) do
    content = String.trim(content)

    if content == "" do
      {:noreply, put_flash(socket, :error, "Message cannot be empty")}
    else
      # Parse the datetime-local input (which is in local time, we treat as UTC for simplicity)
      case NaiveDateTime.from_iso8601(scheduled_for_str <> ":00") do
        {:ok, naive_dt} ->
          scheduled_for = DateTime.from_naive!(naive_dt, "Etc/UTC")

          # Verify it's at least 1 minute in the future
          if DateTime.compare(scheduled_for, DateTime.add(DateTime.utc_now(), 60, :second)) == :lt do
            {:noreply, put_flash(socket, :error, "Scheduled time must be at least 1 minute in the future")}
          else
            opts =
              if socket.assigns.replying_to do
                [reply_to_id: socket.assigns.replying_to.id]
              else
                []
              end

            case Chat.schedule_message(
              socket.assigns.conversation.id,
              socket.assigns.current_user.id,
              content,
              scheduled_for,
              opts
            ) do
              {:ok, _scheduled_message} ->
                {:noreply,
                 socket
                 |> assign(
                   show_schedule_modal: false,
                   message_input: "",
                   replying_to: nil,
                   scheduled_message_count: socket.assigns.scheduled_message_count + 1
                 )
                 |> push_event("clear-input", %{id: "message-input"})
                 |> put_flash(:info, "Message scheduled successfully")}

              {:error, :not_a_member} ->
                {:noreply, put_flash(socket, :error, "You are not a member of this conversation")}

              {:error, changeset} when is_struct(changeset, Ecto.Changeset) ->
                errors = Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
                error_msg = errors |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end) |> Enum.join("; ")
                {:noreply, put_flash(socket, :error, "Failed to schedule: #{error_msg}")}

              {:error, _} ->
                {:noreply, put_flash(socket, :error, "Failed to schedule message")}
            end
          end

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Invalid date/time format")}
      end
    end
  end

  # ===============================
  # Thread Handlers
  # ===============================

  @impl true
  def handle_event("open_thread", %{"message-id" => message_id}, socket) do
    message_id = String.to_integer(message_id)
    parent_message = Chat.get_thread_parent_message!(message_id)
    replies = Chat.list_thread_replies(message_id)

    # Subscribe to thread updates
    if connected?(socket) do
      Chat.subscribe_to_thread(message_id)
    end

    {:noreply,
     assign(socket,
       show_thread: true,
       thread_parent_message: parent_message,
       thread_replies: replies,
       thread_input: ""
     )}
  end

  @impl true
  def handle_event("close_thread", _, socket) do
    # Unsubscribe from thread updates if we have a parent message
    if socket.assigns.thread_parent_message && connected?(socket) do
      Chat.unsubscribe_from_thread(socket.assigns.thread_parent_message.id)
    end

    {:noreply,
     assign(socket,
       show_thread: false,
       thread_parent_message: nil,
       thread_replies: [],
       thread_input: ""
     )}
  end

  @impl true
  def handle_event("update_thread_input", %{"content" => content}, socket) do
    {:noreply, assign(socket, thread_input: content)}
  end

  @impl true
  def handle_event("send_thread_reply", %{"content" => content} = params, socket) do
    content = String.trim(content)
    also_send = params["also_send_to_channel"] == "true"

    if content != "" and socket.assigns.thread_parent_message do
      case Chat.create_thread_reply(
        socket.assigns.thread_parent_message.id,
        socket.assigns.current_user.id,
        content,
        also_send_to_channel: also_send
      ) do
        {:ok, _reply} ->
          {:noreply, assign(socket, thread_input: "")}

        {:error, :message_deleted} ->
          {:noreply,
           socket
           |> put_flash(:error, "Cannot reply to a deleted message")
           |> assign(show_thread: false)}

        {:error, _} ->
          {:noreply, put_flash(socket, :error, "Failed to send reply")}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("toggle_conversation_pin", _, socket) do
    conversation_id = socket.assigns.conversation.id
    user_id = socket.assigns.current_user.id

    case Chat.toggle_conversation_pin(conversation_id, user_id) do
      {:ok, :pinned} ->
        {:noreply,
         socket
         |> assign(is_conversation_pinned: true)
         |> put_flash(:info, "Conversation pinned")}

      {:ok, :unpinned} ->
        {:noreply,
         socket
         |> assign(is_conversation_pinned: false)
         |> put_flash(:info, "Conversation unpinned")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not update pin status")}
    end
  end

  # ===============================
  # Add Member to Group Handlers
  # ===============================

  @impl true
  def handle_event("toggle_add_member", _, socket) do
    {:noreply, assign(socket,
      show_add_member: !socket.assigns.show_add_member,
      add_member_search_query: "",
      add_member_search_results: []
    )}
  end

  @impl true
  def handle_event("search_members_to_add", %{"query" => query}, socket) do
    results =
      if String.length(query) >= 2 do
        Chat.search_users_not_in_conversation(query, socket.assigns.conversation.id)
      else
        []
      end

    {:noreply, assign(socket,
      add_member_search_query: query,
      add_member_search_results: results
    )}
  end

  @impl true
  def handle_event("add_member_to_group", %{"user-id" => user_id}, socket) do
    conversation_id = socket.assigns.conversation.id
    user_id = String.to_integer(user_id)

    case Chat.add_member_to_group(conversation_id, user_id) do
      {:ok, member} ->
        # Broadcast to all conversation members
        Chat.broadcast_member_added(conversation_id, member)

        {:noreply,
         socket
         |> put_flash(:info, "Member added successfully")
         |> assign(show_add_member: false, add_member_search_results: [], add_member_search_query: "")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not add member")}
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
  # Forward Message Handlers
  # ===============================

  @impl true
  def handle_event("show_forward_modal", %{"message-id" => message_id}, socket) do
    message_id = String.to_integer(message_id)
    message = Enum.find(socket.assigns.messages, fn m -> m.id == message_id end)

    if message && is_nil(message.deleted_at) do
      # Load user's conversations for forwarding
      conversations = Chat.list_user_conversations(socket.assigns.current_user.id)
      |> Enum.reject(fn c -> c.id == socket.assigns.conversation.id end) # Exclude current

      {:noreply, assign(socket,
        show_forward_modal: true,
        forward_message_id: message_id,
        forward_conversations: conversations,
        forward_search_query: ""
      )}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("forward_search", %{"query" => query}, socket) do
    conversations = Chat.list_user_conversations(socket.assigns.current_user.id)
    |> Enum.reject(fn c -> c.id == socket.assigns.conversation.id end)
    |> Enum.filter(fn c ->
      name = get_conversation_name(c, socket.assigns.current_user.id)
      String.contains?(String.downcase(name), String.downcase(query))
    end)

    {:noreply, assign(socket, forward_search_query: query, forward_conversations: conversations)}
  end

  @impl true
  def handle_event("forward_message", %{"conversation-id" => conv_id}, socket) do
    conv_id = String.to_integer(conv_id)
    message_id = socket.assigns.forward_message_id

    case Chat.forward_message(message_id, conv_id, socket.assigns.current_user.id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Message forwarded")
         |> assign(show_forward_modal: false, forward_message_id: nil)}

      {:error, :message_deleted} ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot forward deleted message")
         |> assign(show_forward_modal: false, forward_message_id: nil)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to forward message")}
    end
  end

  @impl true
  def handle_event("close_forward_modal", _, socket) do
    {:noreply, assign(socket, show_forward_modal: false, forward_message_id: nil)}
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
  # Emoji Picker Handlers
  # ===============================

  @impl true
  def handle_event("insert_emoji", %{"emoji" => emoji}, socket) do
    # Insert emoji into message input and send event back to JS to insert at cursor
    {:noreply, push_event(socket, "insert_emoji_at_cursor", %{emoji: emoji})}
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

  @impl true
  def handle_info({:member_added, member}, socket) do
    # Update members list with the new member (include role)
    {:noreply,
     update(socket, :members, fn members ->
       if Enum.any?(members, fn m -> m.id == member.user.id end) do
         members
       else
         new_member = Map.put(member.user, :role, member.role || "member")
         members ++ [new_member]
       end
     end)}
  end

  @impl true
  def handle_info({:member_left, user_id}, socket) do
    if user_id == socket.assigns.current_user.id do
      # Current user left, redirect away
      {:noreply,
       socket
       |> put_flash(:info, "You have left this group")
       |> push_navigate(to: ~p"/chats")}
    else
      # Someone else left, update members list
      {:noreply,
       update(socket, :members, fn members ->
         Enum.reject(members, fn m -> m.id == user_id end)
       end)}
    end
  end

  @impl true
  def handle_info({:member_kicked, %{user_id: user_id}}, socket) do
    if user_id == socket.assigns.current_user.id do
      # Current user was kicked, redirect away
      {:noreply,
       socket
       |> put_flash(:info, "You have been removed from this group")
       |> push_navigate(to: ~p"/chats")}
    else
      # Someone else was kicked, update members list
      {:noreply,
       update(socket, :members, fn members ->
         Enum.reject(members, fn m -> m.id == user_id end)
       end)}
    end
  end

  @impl true
  def handle_info({:role_changed, %{user_id: user_id, new_role: new_role}}, socket) do
    socket =
      if user_id == socket.assigns.current_user.id do
        assign(socket, current_user_role: new_role)
      else
        socket
      end

    {:noreply,
     update(socket, :members, fn members ->
       Enum.map(members, fn m ->
         if m.id == user_id, do: Map.put(m, :role, new_role), else: m
       end)
     end)}
  end

  @impl true
  def handle_info({:ownership_transferred, %{old_owner_id: old_owner_id, new_owner_id: new_owner_id}}, socket) do
    current_user_id = socket.assigns.current_user.id

    current_user_role =
      cond do
        current_user_id == new_owner_id -> "owner"
        current_user_id == old_owner_id -> "admin"
        true -> socket.assigns.current_user_role
      end

    {:noreply,
     socket
     |> assign(current_user_role: current_user_role)
     |> update(:members, fn members ->
       Enum.map(members, fn m ->
         cond do
           m.id == new_owner_id -> Map.put(m, :role, "owner")
           m.id == old_owner_id -> Map.put(m, :role, "admin")
           true -> m
         end
       end)
     end)}
  end

  # ===============================
  # Thread Handlers (handle_info)
  # ===============================

  @impl true
  def handle_info({:new_thread_reply, reply}, socket) do
    # Only update if we're viewing this thread
    if socket.assigns.show_thread &&
       socket.assigns.thread_parent_message &&
       socket.assigns.thread_parent_message.id == reply.parent_message_id do
      {:noreply, update(socket, :thread_replies, fn replies -> replies ++ [reply] end)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:thread_count_updated, %{message_id: message_id, count: count}}, socket) do
    {:noreply,
     update(socket, :thread_reply_counts, fn counts ->
       Map.put(counts, message_id, count)
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

    # Send browser notification if message is from another user and conversation is not muted
    socket =
      if message.sender_id != socket.assigns.current_user.id && !socket.assigns.is_muted do
        push_event(socket, "notify", %{
          sender: message.sender.username,
          message: truncate_for_notification(message.content),
          conversation_id: message.conversation_id,
          conversation_name: get_conversation_name(socket.assigns.conversation, socket.assigns.current_user.id)
        })
      else
        socket
      end

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
  def handle_info({:status_changed, user_id, new_status}, socket) do
    # Update other_user's status in direct messages
    if socket.assigns.other_user && socket.assigns.other_user.id == user_id do
      other_user = %{socket.assigns.other_user | status: new_status}
      {:noreply, assign(socket, other_user: other_user)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:poll_created, poll}, socket) do
    # Add the poll to the list if not already present
    if Enum.any?(socket.assigns.polls, fn p -> p.id == poll.id end) do
      {:noreply, socket}
    else
      user_poll_votes = Map.put(socket.assigns.user_poll_votes, poll.id, MapSet.new())
      {:noreply,
       socket
       |> assign(user_poll_votes: user_poll_votes)
       |> update(:polls, fn polls -> [poll | polls] end)}
    end
  end

  @impl true
  def handle_info({:poll_updated, poll}, socket) do
    {:noreply, update_poll_in_list(socket, poll)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen bg-base-200 flex flex-col overflow-hidden" id="chat-container" phx-hook="BrowserNotification">
      <div class="navbar bg-base-100 shadow-sm flex-shrink-0">
        <div class="flex-none">
          <.link navigate={~p"/chats"} class="btn btn-ghost btn-sm">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M10.5 19.5 3 12m0 0 7.5-7.5M3 12h18" />
            </svg>
          </.link>
        </div>
        <div class="flex-1">
          <div class="flex items-center gap-3">
            <div class="avatar avatar-placeholder">
              <div class={[
                "rounded-full w-10 h-10 flex items-center justify-center",
                !get_conversation_avatar(@conversation, @current_user.id) && (@conversation.type == "group" && "bg-secondary text-secondary-content" || "bg-primary text-primary-content")
              ]}>
                <%= if avatar = get_conversation_avatar(@conversation, @current_user.id) do %>
                  <img src={"/uploads/avatars/#{avatar}"} alt="Avatar" class="rounded-full w-full h-full object-cover" />
                <% else %>
                  <span>{get_conversation_initial(@conversation, @current_user.id)}</span>
                <% end %>
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
              <div :if={@conversation.type == "direct" && @other_user && @other_user.status} class="text-xs text-base-content/60 truncate max-w-48">
                {@other_user.status}
              </div>
              <span :if={@conversation.type == "group"} class="text-xs text-base-content/70">
                {get_online_count(@members, @online_user_ids)}/{length(@members)} online
              </span>
            </div>
          </div>
        </div>
        <div class="flex-none flex items-center gap-2">
          <%!-- Pin conversation button --%>
          <button
            phx-click="toggle_conversation_pin"
            class={["btn btn-ghost btn-sm", @is_conversation_pinned && "text-primary"]}
            title={if @is_conversation_pinned, do: "Unpin conversation", else: "Pin conversation"}
          >
            <svg xmlns="http://www.w3.org/2000/svg" fill={if @is_conversation_pinned, do: "currentColor", else: "none"} viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path d="M16 12V4h1V2H7v2h1v8l-2 2v2h5.2v6h1.6v-6H18v-2l-2-2z"/>
            </svg>
          </button>
          <%!-- Mute button --%>
          <button
            phx-click="toggle_mute"
            class={["btn btn-ghost btn-sm", @is_muted && "text-warning"]}
            title={if @is_muted, do: "Unmute notifications", else: "Mute notifications"}
          >
            <%= if @is_muted do %>
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M17.25 9.75 19.5 12m0 0 2.25 2.25M19.5 12l2.25-2.25M19.5 12l-2.25 2.25m-10.5-6 4.72-4.72a.75.75 0 0 1 1.28.53v15.88a.75.75 0 0 1-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 0 1 2.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75Z" />
              </svg>
            <% else %>
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M19.114 5.636a9 9 0 0 1 0 12.728M16.463 8.288a5.25 5.25 0 0 1 0 7.424M6.75 8.25l4.72-4.72a.75.75 0 0 1 1.28.53v15.88a.75.75 0 0 1-1.28.53L6.75 15.75H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 0 1 2.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75Z" />
              </svg>
            <% end %>
          </button>
          <%!-- Archive button --%>
          <button
            phx-click="toggle_archive"
            class={["btn btn-ghost btn-sm", @is_archived && "text-secondary"]}
            title={if @is_archived, do: "Unarchive conversation", else: "Archive conversation"}
          >
            <%= if @is_archived do %>
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="m20.25 7.5-.625 10.632a2.25 2.25 0 0 1-2.247 2.118H6.622a2.25 2.25 0 0 1-2.247-2.118L3.75 7.5m8.25 3v6.75m0 0 3-3m-3 3-3-3M3.375 7.5h17.25c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125Z" />
              </svg>
            <% else %>
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="m20.25 7.5-.625 10.632a2.25 2.25 0 0 1-2.247 2.118H6.622a2.25 2.25 0 0 1-2.247-2.118L3.75 7.5m8.25 3v6.75m0 0-3-3m3 3 3-3M3.375 7.5h17.25c.621 0 1.125-.504 1.125-1.125v-1.5c0-.621-.504-1.125-1.125-1.125H3.375c-.621 0-1.125.504-1.125 1.125v1.5c0 .621.504 1.125 1.125 1.125Z" />
              </svg>
            <% end %>
          </button>
          <%!-- Block user button (only for direct conversations) --%>
          <button
            :if={@conversation.type == "direct" && @other_user}
            phx-click="toggle_block_user"
            class={["btn btn-ghost btn-sm", @is_other_user_blocked && "text-error"]}
            title={if @is_other_user_blocked, do: "Unblock user", else: "Block user"}
          >
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M18.364 18.364A9 9 0 0 0 5.636 5.636m12.728 12.728A9 9 0 0 1 5.636 5.636m12.728 12.728L5.636 5.636" />
            </svg>
          </button>
          <%!-- Theme toggle --%>
          <ElixirchatWeb.Layouts.theme_toggle />
          <%!-- Search button --%>
          <button phx-click="toggle_search" class="btn btn-ghost btn-sm" title="Search messages">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z" />
            </svg>
          </button>
          <%!-- Invite link button (only for groups that are not General) --%>
          <button
            :if={@conversation.type == "group" && !@conversation.is_general}
            phx-click="show_invite_modal"
            class="btn btn-ghost btn-sm"
            title="Get invite link"
          >
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244" />
            </svg>
          </button>
          <div :if={@conversation.type == "group"} class="dropdown dropdown-end">
            <div tabindex="0" role="button" class="btn btn-ghost btn-sm" phx-click="toggle_members">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                <path stroke-linecap="round" stroke-linejoin="round" d="M15 19.128a9.38 9.38 0 0 0 2.625.372 9.337 9.337 0 0 0 4.121-.952 4.125 4.125 0 0 0-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 0 1 8.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0 1 11.964-3.07M12 6.375a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0Zm8.25 2.25a2.625 2.625 0 1 1-5.25 0 2.625 2.625 0 0 1 5.25 0Z" />
              </svg>
            </div>
            <ul :if={@show_members} tabindex="0" class="dropdown-content menu bg-base-100 rounded-box z-[1] w-72 p-2 shadow">
              <li class="menu-title">Members</li>
              <li :for={member <- @members} class="relative">
                <div class="flex items-center justify-between w-full py-1">
                  <span class={["flex items-center gap-2 flex-1 min-w-0", member.id == @current_user.id && "font-bold" || ""]}>
                    <div class={[
                      "w-2 h-2 rounded-full flex-shrink-0",
                      member.id in @online_user_ids && "bg-success" || "bg-base-content/30"
                    ]}></div>
                    <span class="truncate">{member.username}</span>
                    <span :if={member.id == @current_user.id} class="badge badge-xs badge-primary flex-shrink-0">you</span>
                    <span :if={Map.get(member, :role) == "owner"} class="badge badge-xs badge-warning flex-shrink-0">Owner</span>
                    <span :if={Map.get(member, :role) == "admin"} class="badge badge-xs badge-secondary flex-shrink-0">Admin</span>
                  </span>
                  <%!-- Admin controls dropdown --%>
                  <div :if={@current_user_role in ["owner", "admin"] && member.id != @current_user.id && !@conversation.is_general}>
                    <button
                      phx-click="show_member_menu"
                      phx-value-user-id={member.id}
                      class="btn btn-ghost btn-xs btn-circle"
                    >
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M12 6.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5ZM12 12.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5ZM12 18.75a.75.75 0 1 1 0-1.5.75.75 0 0 1 0 1.5Z" />
                      </svg>
                    </button>
                  </div>
                </div>
                <%!-- Member action menu --%>
                <div :if={@show_member_menu == member.id} class="absolute right-0 top-full z-50 mt-1 w-48 bg-base-200 rounded-box shadow-lg border border-base-300">
                  <ul class="menu menu-sm p-2">
                    <%!-- Kick member (owner can kick anyone, admin can only kick members) --%>
                    <li :if={can_kick_member?(@current_user_role, Map.get(member, :role))}>
                      <button phx-click="kick_member" phx-value-user-id={member.id} class="text-error">
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M22 10.5h-6m-2.25-4.125a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0ZM4 19.235v-.11a6.375 6.375 0 0 1 12.75 0v.109A12.318 12.318 0 0 1 10.374 21c-2.331 0-4.512-.645-6.374-1.766Z" />
                        </svg>
                        Remove from group
                      </button>
                    </li>
                    <%!-- Promote to admin (owner only, for regular members) --%>
                    <li :if={@current_user_role == "owner" && Map.get(member, :role) == "member"}>
                      <button phx-click="promote_member" phx-value-user-id={member.id}>
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                        </svg>
                        Make admin
                      </button>
                    </li>
                    <%!-- Demote from admin (owner only, for admins) --%>
                    <li :if={@current_user_role == "owner" && Map.get(member, :role) == "admin"}>
                      <button phx-click="demote_member" phx-value-user-id={member.id}>
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                          <path stroke-linecap="round" stroke-linejoin="round" d="m9.75 9.75 4.5 4.5m0-4.5-4.5 4.5M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                        </svg>
                        Remove admin
                      </button>
                    </li>
                    <%!-- Transfer ownership (owner only) --%>
                    <li :if={@current_user_role == "owner"}>
                      <button phx-click="show_transfer_confirm" phx-value-user-id={member.id}>
                        <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M7.5 21 3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5" />
                        </svg>
                        Transfer ownership
                      </button>
                    </li>
                  </ul>
                  <button phx-click="hide_member_menu" class="btn btn-ghost btn-xs w-full mt-1">Cancel</button>
                </div>
              </li>
              <%!-- Add Member section --%>
              <div class="divider my-1"></div>
              <div class="p-2">
                <button
                  :if={!@show_add_member}
                  phx-click="toggle_add_member"
                  class="btn btn-sm btn-primary w-full"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 mr-1">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M19 7.5v3m0 0v3m0-3h3m-3 0h-3m-2.25-4.125a3.375 3.375 0 1 1-6.75 0 3.375 3.375 0 0 1 6.75 0ZM4 19.235v-.11a6.375 6.375 0 0 1 12.75 0v.109A12.318 12.318 0 0 1 10.374 21c-2.331 0-4.512-.645-6.374-1.766Z" />
                  </svg>
                  Add Member
                </button>

                <div :if={@show_add_member} class="space-y-2">
                  <form phx-change="search_members_to_add" phx-submit="search_members_to_add">
                    <input
                      type="text"
                      name="query"
                      value={@add_member_search_query}
                      placeholder="Search by username..."
                      class="input input-sm input-bordered w-full"
                      phx-debounce="300"
                      autofocus
                    />
                  </form>

                  <div :if={@add_member_search_results != []} class="max-h-40 overflow-y-auto space-y-1">
                    <div
                      :for={user <- @add_member_search_results}
                      class="flex items-center justify-between p-2 bg-base-200 rounded"
                    >
                      <span class="text-sm font-medium">{user.username}</span>
                      <button
                        phx-click="add_member_to_group"
                        phx-value-user-id={user.id}
                        class="btn btn-xs btn-primary"
                      >
                        Add
                      </button>
                    </div>
                  </div>

                  <p :if={@add_member_search_query != "" && String.length(@add_member_search_query) >= 2 && @add_member_search_results == []} class="text-xs text-base-content/70 text-center py-2">
                    No users found
                  </p>

                  <p :if={@add_member_search_query != "" && String.length(@add_member_search_query) < 2} class="text-xs text-base-content/70 text-center py-2">
                    Enter at least 2 characters
                  </p>

                  <button phx-click="toggle_add_member" class="btn btn-sm btn-ghost w-full">
                    Cancel
                  </button>
                </div>
              </div>
              <%!-- Leave Group section - hidden for General group --%>
              <div :if={!@conversation.is_general} class="p-2 border-t border-base-300">
                <%!-- Owner warning - they must transfer ownership first --%>
                <div :if={@current_user_role == "owner" && !@show_transfer_confirm} class="text-xs text-base-content/60 mb-2">
                  <span class="text-warning">As the owner, you must transfer ownership before leaving.</span>
                </div>

                <button
                  :if={!@show_leave_confirm && @current_user_role != "owner"}
                  phx-click="show_leave_confirm"
                  class="btn btn-sm btn-error btn-outline w-full"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 mr-1">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15m3 0 3-3m0 0-3-3m3 3H9" />
                  </svg>
                  Leave Group
                </button>

                <%!-- Leave confirmation dialog --%>
                <div :if={@show_leave_confirm} class="space-y-2">
                  <p class="text-sm text-warning">Are you sure you want to leave this group?</p>
                  <div class="flex gap-2">
                    <button phx-click="leave_group" class="btn btn-sm btn-error flex-1">
                      Leave
                    </button>
                    <button phx-click="cancel_leave" class="btn btn-sm btn-ghost flex-1">
                      Cancel
                    </button>
                  </div>
                </div>

                <%!-- Transfer ownership confirmation dialog --%>
                <div :if={@show_transfer_confirm} class="space-y-2">
                  <p class="text-sm text-warning">Transfer ownership to this member? You will become an admin.</p>
                  <div class="flex gap-2">
                    <button phx-click="transfer_ownership" class="btn btn-sm btn-warning flex-1">
                      Transfer
                    </button>
                    <button phx-click="cancel_transfer" class="btn btn-sm btn-ghost flex-1">
                      Cancel
                    </button>
                  </div>
                </div>
              </div>
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
      <div :if={length(@pinned_messages) > 0} class="bg-base-200 border-b border-base-300 flex-shrink-0">
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

      <div class="flex-1 overflow-y-auto p-4 relative" id="messages-container" phx-hook="ScrollToBottom">
        <div class="max-w-2xl mx-auto space-y-4">
          <%!-- Active Polls section --%>
          <div :if={length(@polls) > 0} class="space-y-4 mb-6">
            <div :for={poll <- @polls} class="card bg-base-100 shadow-lg border border-base-300">
              <div class="card-body p-4">
                <div class="flex justify-between items-start gap-2">
                  <div class="flex-1">
                    <h3 class="font-bold text-base">{poll.question}</h3>
                    <p class="text-xs text-base-content/60 mt-1">
                      by @{poll.creator.username}
                      <span :if={poll.closed_at} class="badge badge-sm badge-neutral ml-2">Closed</span>
                      <span :if={is_nil(poll.closed_at)} class="ml-2">{poll.total_votes} {if poll.total_votes == 1, do: "vote", else: "votes"}</span>
                    </p>
                  </div>
                  <button
                    :if={poll.creator_id == @current_user.id && is_nil(poll.closed_at)}
                    phx-click="close_poll"
                    phx-value-poll-id={poll.id}
                    class="btn btn-ghost btn-xs"
                    title="Close poll"
                  >
                    Close
                  </button>
                </div>

                <div class="space-y-2 mt-3">
                  <div :for={option <- poll.options} class="relative">
                    <button
                      phx-click="vote_on_poll"
                      phx-value-poll-id={poll.id}
                      phx-value-option-id={option.id}
                      disabled={poll.closed_at != nil}
                      class={[
                        "w-full text-left p-3 rounded-lg border transition-all relative overflow-hidden",
                        user_voted_for_option?(poll.id, option.id, @user_poll_votes) && "border-primary bg-primary/10" || "border-base-300 hover:border-primary",
                        poll.closed_at && "cursor-not-allowed opacity-75" || ""
                      ]}
                    >
                      <%!-- Progress bar background --%>
                      <div
                        class={[
                          "absolute inset-y-0 left-0 transition-all duration-300",
                          user_voted_for_option?(poll.id, option.id, @user_poll_votes) && "bg-primary/20" || "bg-base-200"
                        ]}
                        style={"width: #{option.percentage}%"}
                      />
                      <div class="flex justify-between items-center relative z-10">
                        <span class="font-medium">{option.text}</span>
                        <span class="text-sm font-semibold ml-2">{option.percentage}%</span>
                      </div>
                    </button>
                    <div :if={option.vote_count > 0} class="text-xs text-base-content/60 mt-1 pl-2">
                      {option.vote_count} {if option.vote_count == 1, do: "vote", else: "votes"}
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div :if={@messages == [] && @polls == []} class="text-center py-12 text-base-content/70">
            <p>No messages yet. Say hello!</p>
          </div>

          <div
            :for={message <- @messages}
            id={"message-#{message.id}"}
            data-message-id={message.id}
            class={["chat group", get_chat_position(message, @current_user.id)]}
          >
            <div class="chat-image avatar avatar-placeholder">
              <div class={[
                "w-10 h-10 rounded-full text-white font-bold flex items-center justify-center",
                !message.sender.avatar_filename && get_avatar_class(message)
              ]}>
                <%= if message.sender.avatar_filename do %>
                  <img src={"/uploads/avatars/#{message.sender.avatar_filename}"} alt={message.sender.username} class="rounded-full w-full h-full object-cover" />
                <% else %>
                  <span class="text-lg">{get_sender_initial(message)}</span>
                <% end %>
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

            <%!-- Forwarded message indicator --%>
            <div
              :if={message.forwarded_from_user_id && message.forwarded_from_user}
              class="text-xs opacity-70 mb-1 flex items-center gap-1"
            >
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3 flex-shrink-0">
                <path stroke-linecap="round" stroke-linejoin="round" d="M3 8.689c0-.864.933-1.406 1.683-.977l7.108 4.061a1.125 1.125 0 0 1 0 1.954l-7.108 4.061A1.125 1.125 0 0 1 3 16.811V8.69Z" />
              </svg>
              <span>Forwarded from <strong>@{message.forwarded_from_user.username}</strong></span>
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
                <span :if={message.content != "[Attachment]"} class="markdown-content">
                  <%= raw(format_message_content(message.content, @members)) %>
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

                <%!-- Link previews display --%>
                <div :if={length(Map.get(message, :link_previews, [])) > 0} class="mt-2 space-y-2">
                  <.link_preview_card :for={preview <- message.link_previews} preview={preview} />
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
                <%!-- Reply in thread button --%>
                <button
                  :if={is_nil(message.deleted_at)}
                  phx-click="open_thread"
                  phx-value-message-id={message.id}
                  class="btn btn-ghost btn-xs btn-circle bg-base-100 shadow-sm"
                  title="Reply in thread"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M7.5 8.25h9m-9 3H12m-9.75 1.51c0 1.6 1.123 2.994 2.707 3.227 1.129.166 2.27.293 3.423.379.35.026.67.21.865.501L12 21l2.755-4.133a1.14 1.14 0 0 1 .865-.501 48.172 48.172 0 0 0 3.423-.379c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.394 48.394 0 0 0 12 3c-2.392 0-4.744.175-7.043.513C3.373 3.746 2.25 5.14 2.25 6.741v6.018Z" />
                  </svg>
                </button>
                <%!-- Forward button --%>
                <button
                  phx-click="show_forward_modal"
                  phx-value-message-id={message.id}
                  class="btn btn-ghost btn-xs btn-circle bg-base-100 shadow-sm"
                  title="Forward"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M3 8.689c0-.864.933-1.406 1.683-.977l7.108 4.061a1.125 1.125 0 0 1 0 1.954l-7.108 4.061A1.125 1.125 0 0 1 3 16.811V8.69ZM12.75 8.689c0-.864.933-1.406 1.683-.977l7.108 4.061a1.125 1.125 0 0 1 0 1.954l-7.108 4.061a1.125 1.125 0 0 1-1.683-.977V8.69Z" />
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
                <%!-- Star button --%>
                <button
                  :if={is_nil(message.deleted_at)}
                  phx-click="toggle_star"
                  phx-value-message-id={message.id}
                  class={["btn btn-ghost btn-xs btn-circle bg-base-100 shadow-sm", MapSet.member?(@starred_message_ids, message.id) && "text-warning"]}
                  title={if MapSet.member?(@starred_message_ids, message.id), do: "Unstar", else: "Star"}
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill={if MapSet.member?(@starred_message_ids, message.id), do: "currentColor", else: "none"} viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3 h-3">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M11.48 3.499a.562.562 0 0 1 1.04 0l2.125 5.111a.563.563 0 0 0 .475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 0 0-.182.557l1.285 5.385a.562.562 0 0 1-.84.61l-4.725-2.885a.562.562 0 0 0-.586 0L6.982 20.54a.562.562 0 0 1-.84-.61l1.285-5.386a.562.562 0 0 0-.182-.557l-4.204-3.602a.562.562 0 0 1 .321-.988l5.518-.442a.563.563 0 0 0 .475-.345L11.48 3.5Z" />
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

            <%!-- Thread reply count indicator --%>
            <div :if={Map.get(@thread_reply_counts, message.id, 0) > 0 && is_nil(message.deleted_at)} class="chat-footer mt-1">
              <button
                phx-click="open_thread"
                phx-value-message-id={message.id}
                class="btn btn-ghost btn-xs gap-1 text-primary hover:bg-primary/10"
              >
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-3.5 h-3.5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M7.5 8.25h9m-9 3H12m-9.75 1.51c0 1.6 1.123 2.994 2.707 3.227 1.129.166 2.27.293 3.423.379.35.026.67.21.865.501L12 21l2.755-4.133a1.14 1.14 0 0 1 .865-.501 48.172 48.172 0 0 0 3.423-.379c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.394 48.394 0 0 0 12 3c-2.392 0-4.744.175-7.043.513C3.373 3.746 2.25 5.14 2.25 6.741v6.018Z" />
                </svg>
                <span>{Map.get(@thread_reply_counts, message.id)} {if Map.get(@thread_reply_counts, message.id) == 1, do: "reply", else: "replies"}</span>
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

        <%!-- Scroll to bottom button --%>
        <button
          id="scroll-to-bottom-btn"
          phx-click={JS.dispatch("scroll-to-bottom", to: "#messages-container")}
          class="hidden absolute bottom-4 right-4 btn btn-circle btn-primary shadow-lg"
          title="Scroll to bottom"
        >
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor" class="w-5 h-5">
            <path stroke-linecap="round" stroke-linejoin="round" d="M19.5 13.5 12 21m0 0-7.5-7.5M12 21V3" />
          </svg>
        </button>
      </div>

      <div class="bg-base-100 border-t border-base-300 p-4 flex-shrink-0">
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
                    <div class="avatar avatar-placeholder">
                      <div class={["rounded-full w-6 h-6 flex items-center justify-center", !user.avatar_filename && "bg-neutral text-neutral-content"]}>
                        <%= if user.avatar_filename do %>
                          <img src={"/uploads/avatars/#{user.avatar_filename}"} alt={user.username} class="rounded-full w-full h-full object-cover" />
                        <% else %>
                          <span class="text-xs">{String.first(user.username) |> String.upcase()}</span>
                        <% end %>
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
              <%!-- Create Poll button --%>
              <button
                type="button"
                phx-click="show_poll_modal"
                class="btn btn-ghost btn-circle self-center"
                title="Create poll"
              >
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M3 13.125C3 12.504 3.504 12 4.125 12h2.25c.621 0 1.125.504 1.125 1.125v6.75C7.5 20.496 6.996 21 6.375 21h-2.25A1.125 1.125 0 0 1 3 19.875v-6.75ZM9.75 8.625c0-.621.504-1.125 1.125-1.125h2.25c.621 0 1.125.504 1.125 1.125v11.25c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V8.625ZM16.5 4.125c0-.621.504-1.125 1.125-1.125h2.25C20.496 3 21 3.504 21 4.125v15.75c0 .621-.504 1.125-1.125 1.125h-2.25a1.125 1.125 0 0 1-1.125-1.125V4.125Z" />
                </svg>
              </button>
              <%!-- Emoji picker --%>
              <div id="emoji-picker" phx-hook="EmojiPicker" class="relative self-center">
                <button
                  type="button"
                  data-emoji-toggle
                  class="btn btn-ghost btn-circle"
                  title="Add emoji"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-6 h-6">
                    <path stroke-linecap="round" stroke-linejoin="round" d="M15.182 15.182a4.5 4.5 0 0 1-6.364 0M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0ZM9.75 9.75c0 .414-.168.75-.375.75S9 10.164 9 9.75 9.168 9 9.375 9s.375.336.375.75Zm-.375 0h.008v.015h-.008V9.75Zm5.625 0c0 .414-.168.75-.375.75s-.375-.336-.375-.75.168-.75.375-.75.375.336.375.75Zm-.375 0h.008v.015h-.008V9.75Z" />
                  </svg>
                </button>
                <div data-emoji-picker class="hidden absolute bottom-12 left-0 z-50 bg-base-100 rounded-lg shadow-xl border border-base-300 w-80">
                  <%!-- Search input --%>
                  <div class="p-2 border-b border-base-300">
                    <input
                      type="text"
                      placeholder="Search emojis..."
                      class="input input-sm input-bordered w-full"
                      data-emoji-search
                    />
                  </div>
                  <%!-- Category tabs --%>
                  <div class="flex border-b border-base-300 overflow-x-auto" data-category-tabs>
                  </div>
                  <%!-- Emoji grid --%>
                  <div class="h-64 overflow-y-auto p-2" data-emoji-grid>
                  </div>
                </div>
              </div>
              <input
                type="text"
                id="message-input"
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
              <button type="button" phx-click="show_schedule_modal" class="btn btn-ghost btn-sm" title="Schedule message">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                </svg>
              </button>
            </form>
          </div>
        </div>
      </div>

      <%!-- Forward message modal --%>
      <div :if={@show_forward_modal} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-4">Forward Message</h3>

          <%!-- Search input --%>
          <form phx-change="forward_search" class="mb-4">
            <input
              type="text"
              name="query"
              value={@forward_search_query}
              placeholder="Search conversations..."
              class="input input-bordered w-full"
              autofocus
            />
          </form>

          <%!-- Conversation list --%>
          <div class="max-h-64 overflow-y-auto space-y-2">
            <div :if={@forward_conversations == []} class="text-center py-4 text-base-content/60">
              No conversations to forward to
            </div>

            <div
              :for={conv <- @forward_conversations}
              class="flex items-center justify-between p-3 hover:bg-base-200 rounded-lg"
            >
              <div class="flex items-center gap-3">
                <div class="avatar avatar-placeholder">
                  <div class={[
                    "rounded-full w-10 h-10 flex items-center justify-center",
                    conv.type == "group" && "bg-secondary text-secondary-content" || "bg-primary text-primary-content"
                  ]}>
                    <span>{get_conversation_initial(conv, @current_user.id)}</span>
                  </div>
                </div>
                <div>
                  <div class="font-medium">{get_conversation_name(conv, @current_user.id)}</div>
                  <div class="text-xs text-base-content/60">
                    {if conv.type == "group", do: "Group", else: "Direct message"}
                  </div>
                </div>
              </div>
              <button
                phx-click="forward_message"
                phx-value-conversation-id={conv.id}
                class="btn btn-primary btn-sm"
              >
                Forward
              </button>
            </div>
          </div>

          <div class="modal-action">
            <button phx-click="close_forward_modal" class="btn btn-ghost">Cancel</button>
          </div>
        </div>
        <div class="modal-backdrop bg-base-content/50" phx-click="close_forward_modal"></div>
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

      <%!-- Create Poll modal --%>
      <div :if={@show_poll_modal} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-4">Create Poll</h3>

          <form phx-submit="create_poll">
            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text">Question</span>
              </label>
              <input
                type="text"
                name="question"
                value={@poll_question}
                phx-keyup="update_poll_question"
                phx-debounce="100"
                placeholder="Ask a question..."
                class="input input-bordered w-full"
                required
                maxlength="500"
                autofocus
              />
            </div>

            <div class="form-control mb-4">
              <label class="label">
                <span class="label-text">Options</span>
                <span class="label-text-alt">{length(@poll_options)}/10</span>
              </label>

              <div class="space-y-2">
                <div :for={{option, index} <- Enum.with_index(@poll_options)} class="flex gap-2">
                  <input
                    type="text"
                    name={"options[#{index}]"}
                    value={option}
                    phx-keyup="update_poll_option"
                    phx-value-index={index}
                    phx-debounce="100"
                    placeholder={"Option #{index + 1}"}
                    class="input input-bordered flex-1"
                    required
                    maxlength="200"
                  />
                  <button
                    :if={length(@poll_options) > 2}
                    type="button"
                    phx-click="remove_poll_option"
                    phx-value-index={index}
                    class="btn btn-ghost btn-circle btn-sm self-center"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4">
                      <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
                    </svg>
                  </button>
                </div>
              </div>

              <button
                :if={length(@poll_options) < 10}
                type="button"
                phx-click="add_poll_option"
                class="btn btn-ghost btn-sm mt-2"
              >
                + Add option
              </button>
            </div>

            <div class="modal-action">
              <button type="button" phx-click="close_poll_modal" class="btn btn-ghost">Cancel</button>
              <button type="submit" class="btn btn-primary" disabled={length(@poll_options) < 2 || String.trim(@poll_question) == ""}>
                Create Poll
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop bg-base-content/50" phx-click="close_poll_modal"></div>
      </div>

      <%!-- Invite link modal --%>
      <div :if={@show_invite_modal} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-4">Invite Link</h3>

          <div :if={@invite_link} class="space-y-4">
            <div class="flex gap-2">
              <input
                type="text"
                value={@invite_link}
                readonly
                class="input input-bordered flex-1 font-mono text-sm"
                id="invite-link-input"
              />
              <button
                phx-click={JS.dispatch("phx:copy", to: "#invite-link-input")}
                class="btn btn-primary"
                id="copy-invite-btn"
                phx-hook="CopyToClipboard"
              >
                Copy
              </button>
            </div>

            <p class="text-sm text-base-content/60">
              Share this link with others to invite them to the group.
            </p>

            <button phx-click="regenerate_invite" class="btn btn-ghost btn-sm">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-4 h-4 mr-1">
                <path stroke-linecap="round" stroke-linejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0 3.181 3.183a8.25 8.25 0 0 0 13.803-3.7M4.031 9.865a8.25 8.25 0 0 1 13.803-3.7l3.181 3.182m0-4.991v4.99" />
              </svg>
              Regenerate Link
            </button>
          </div>

          <div :if={!@invite_link}>
            <p class="text-base-content/60 mb-4">No active invite link. Create one to invite others.</p>
            <button phx-click="create_invite" class="btn btn-primary">
              Create Invite Link
            </button>
          </div>

          <div class="modal-action">
            <button phx-click="close_invite_modal" class="btn btn-ghost">Close</button>
          </div>
        </div>
        <div class="modal-backdrop bg-base-content/50" phx-click="close_invite_modal"></div>
      </div>

      <%!-- Schedule message modal --%>
      <div :if={@show_schedule_modal} class="modal modal-open">
        <div class="modal-box">
          <h3 class="font-bold text-lg mb-4">Schedule Message</h3>

          <form phx-submit="schedule_message" class="space-y-4">
            <div>
              <label class="label">
                <span class="label-text">Message</span>
              </label>
              <textarea
                name="content"
                class="textarea textarea-bordered w-full"
                rows="3"
                placeholder="Enter your message..."
                required
              ><%= @message_input %></textarea>
            </div>

            <div>
              <label class="label">
                <span class="label-text">Schedule for</span>
              </label>
              <input
                type="datetime-local"
                name="scheduled_for"
                class="input input-bordered w-full"
                min={get_min_datetime()}
                required
              />
              <label class="label">
                <span class="label-text-alt">Minimum 1 minute from now</span>
              </label>
            </div>

            <div class="modal-action">
              <button type="button" phx-click="close_schedule_modal" class="btn btn-ghost">Cancel</button>
              <button type="submit" class="btn btn-primary">
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5 mr-1">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />
                </svg>
                Schedule
              </button>
            </div>
          </form>
        </div>
        <div class="modal-backdrop bg-base-content/50" phx-click="close_schedule_modal"></div>
      </div>

      <%!-- Thread panel (slides in from right) --%>
      <div :if={@show_thread && @thread_parent_message} class="fixed inset-y-0 right-0 w-full sm:w-96 bg-base-100 shadow-xl z-50 flex flex-col border-l border-base-300">
        <%!-- Thread header --%>
        <div class="flex items-center justify-between p-4 border-b border-base-300">
          <div class="flex items-center gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M7.5 8.25h9m-9 3H12m-9.75 1.51c0 1.6 1.123 2.994 2.707 3.227 1.129.166 2.27.293 3.423.379.35.026.67.21.865.501L12 21l2.755-4.133a1.14 1.14 0 0 1 .865-.501 48.172 48.172 0 0 0 3.423-.379c1.584-.233 2.707-1.626 2.707-3.228V6.741c0-1.602-1.123-2.995-2.707-3.228A48.394 48.394 0 0 0 12 3c-2.392 0-4.744.175-7.043.513C3.373 3.746 2.25 5.14 2.25 6.741v6.018Z" />
            </svg>
            <span class="font-semibold">Thread</span>
            <span class="text-sm text-base-content/60">{length(@thread_replies)} {if length(@thread_replies) == 1, do: "reply", else: "replies"}</span>
          </div>
          <button phx-click="close_thread" class="btn btn-ghost btn-sm btn-circle">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
              <path stroke-linecap="round" stroke-linejoin="round" d="M6 18 18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <%!-- Parent message --%>
        <div class="p-4 border-b border-base-300 bg-base-200/50">
          <div class="flex items-start gap-3">
            <div class="avatar avatar-placeholder flex-shrink-0">
              <div class={[
                "w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-sm",
                !@thread_parent_message.sender.avatar_filename && "bg-primary"
              ]}>
                <%= if @thread_parent_message.sender.avatar_filename do %>
                  <img src={"/uploads/avatars/#{@thread_parent_message.sender.avatar_filename}"} alt={@thread_parent_message.sender.username} class="rounded-full w-full h-full object-cover" />
                <% else %>
                  {String.first(@thread_parent_message.sender.username) |> String.upcase()}
                <% end %>
              </div>
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class="font-semibold text-sm">{@thread_parent_message.sender.username}</span>
                <span class="text-xs text-base-content/50">{format_time(@thread_parent_message.inserted_at)}</span>
              </div>
              <p class="text-sm mt-1 break-words">
                <%= raw(format_message_content(@thread_parent_message.content, @members)) %>
              </p>
            </div>
          </div>
        </div>

        <%!-- Thread replies --%>
        <div class="flex-1 overflow-y-auto p-4 space-y-4" id="thread-replies-container">
          <div :if={@thread_replies == []} class="text-center text-base-content/50 py-8">
            <p>No replies yet. Start the conversation!</p>
          </div>

          <div :for={reply <- @thread_replies} class="flex items-start gap-3">
            <div class="avatar avatar-placeholder flex-shrink-0">
              <div class={[
                "w-8 h-8 rounded-full flex items-center justify-center text-white font-bold text-sm",
                !reply.user.avatar_filename && (reply.user_id == @current_user.id && "bg-secondary" || "bg-primary")
              ]}>
                <%= if reply.user.avatar_filename do %>
                  <img src={"/uploads/avatars/#{reply.user.avatar_filename}"} alt={reply.user.username} class="rounded-full w-full h-full object-cover" />
                <% else %>
                  {String.first(reply.user.username) |> String.upcase()}
                <% end %>
              </div>
            </div>
            <div class="flex-1 min-w-0">
              <div class="flex items-center gap-2">
                <span class={["font-semibold text-sm", reply.user_id == @current_user.id && "text-secondary"]}>
                  {reply.user.username}
                </span>
                <span class="text-xs text-base-content/50">{format_time(reply.inserted_at)}</span>
                <span :if={reply.also_sent_to_channel} class="badge badge-xs badge-ghost">also in chat</span>
              </div>
              <p class="text-sm mt-1 break-words">
                <%= raw(format_message_content(reply.content, @members)) %>
              </p>
            </div>
          </div>
        </div>

        <%!-- Thread reply input --%>
        <div class="p-4 border-t border-base-300">
          <form phx-submit="send_thread_reply" class="space-y-2">
            <div class="flex gap-2">
              <input
                type="text"
                name="content"
                value={@thread_input}
                phx-change="update_thread_input"
                placeholder="Reply in thread..."
                class="input input-bordered flex-1"
                autocomplete="off"
              />
              <button type="submit" class="btn btn-primary" disabled={String.trim(@thread_input) == ""}>
                <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="w-5 h-5">
                  <path stroke-linecap="round" stroke-linejoin="round" d="M6 12 3.269 3.125A59.769 59.769 0 0 1 21.485 12 59.768 59.768 0 0 1 3.27 20.875L5.999 12Zm0 0h7.5" />
                </svg>
              </button>
            </div>
            <label class="flex items-center gap-2 cursor-pointer">
              <input type="checkbox" name="also_send_to_channel" value="true" class="checkbox checkbox-sm" />
              <span class="text-xs text-base-content/70">Also send to channel</span>
            </label>
          </form>
        </div>
      </div>

      <%!-- Thread panel backdrop --%>
      <div :if={@show_thread} class="fixed inset-0 bg-base-content/30 z-40" phx-click="close_thread"></div>
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

  # For direct conversations, returns the other user's avatar filename (if any)
  # For groups, returns nil (groups don't have avatars)
  defp get_conversation_avatar(%{type: "direct", members: members}, current_user_id) do
    case Enum.find(members, fn m -> m.user_id != current_user_id end) do
      nil -> nil
      member -> member.user.avatar_filename
    end
  end

  defp get_conversation_avatar(_, _), do: nil

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
      is_agent_message?(message) -> ""
      message.sender_id == current_user_id -> "chat-bubble-primary"
      true -> ""
    end
  end

  defp get_avatar_class(message) do
    if is_agent_message?(message) do
      "bg-info"
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

  # Truncate message for browser notification
  defp truncate_for_notification(nil), do: "[Attachment]"
  defp truncate_for_notification("[Attachment]"), do: "[Attachment]"
  defp truncate_for_notification(content) when byte_size(content) > 100 do
    String.slice(content, 0, 100) <> "..."
  end
  defp truncate_for_notification(content), do: content

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

  # Checks if kicker can kick the target based on roles
  # Owner can kick anyone (except owner - handled in backend)
  # Admin can only kick regular members
  defp can_kick_member?("owner", _target_role), do: true
  defp can_kick_member?("admin", "member"), do: true
  defp can_kick_member?(_, _), do: false

  # Checks if user has voted for a specific poll option
  defp user_voted_for_option?(poll_id, option_id, user_poll_votes) do
    case Map.get(user_poll_votes, poll_id) do
      nil -> false
      votes -> MapSet.member?(votes, option_id)
    end
  end

  # Link preview card component
  defp link_preview_card(assigns) do
    ~H"""
    <a
      href={@preview.url}
      target="_blank"
      rel="noopener noreferrer"
      class="block max-w-sm border border-base-300 rounded-lg overflow-hidden hover:bg-base-200 transition-colors bg-base-100"
    >
      <img
        :if={@preview.image_url}
        src={@preview.image_url}
        alt=""
        class="w-full h-32 object-cover"
        loading="lazy"
        onerror="this.style.display='none'"
      />
      <div class="p-3">
        <div :if={@preview.site_name} class="text-xs text-base-content/60 mb-1">
          {@preview.site_name}
        </div>
        <div :if={@preview.title} class="font-medium text-sm line-clamp-2">
          {@preview.title}
        </div>
        <div :if={@preview.description} class="text-xs text-base-content/70 mt-1 line-clamp-2">
          {truncate(@preview.description, 150)}
        </div>
      </div>
    </a>
    """
  end

  # Markdown/Mentions formatting helper
  defp format_message_content(content, members) do
    valid_usernames =
      members
      |> Enum.map(fn m -> String.downcase(m.username) end)
      |> MapSet.new()

    Markdown.render_with_mentions(content, valid_usernames)
  end

  # Schedule helpers
  defp get_min_datetime do
    # Return datetime 1 minute from now in ISO format for datetime-local input
    DateTime.utc_now()
    |> DateTime.add(60, :second)
    |> DateTime.to_naive()
    |> NaiveDateTime.truncate(:minute)
    |> NaiveDateTime.to_iso8601()
    |> String.slice(0, 16)  # datetime-local format: YYYY-MM-DDTHH:MM
  end
end
