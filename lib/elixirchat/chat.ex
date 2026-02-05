defmodule Elixirchat.Chat do
  @moduledoc """
  The Chat context for managing conversations and messages.
  """

  import Ecto.Query, warn: false

  alias Elixirchat.Repo
  alias Elixirchat.Chat.{Conversation, ConversationMember, Message, Reaction, ReadReceipt, Attachment, Mentions, PinnedMessage, LinkPreview, MessageLinkPreview, UrlExtractor, LinkPreviewFetcher, MutedConversation, StarredMessage, Poll, PollOption, PollVote, GroupInvite}
  alias Elixirchat.Accounts.User
  alias Elixirchat.Agent

  @doc """
  Gets a conversation by id with members preloaded.
  """
  def get_conversation!(id) do
    Conversation
    |> Repo.get!(id)
    |> Repo.preload(members: :user)
  end

  @doc """
  Gets or creates a direct conversation between two users.
  Returns {:error, :user_blocked} if the user has blocked the other person.
  Returns {:error, :blocked_by_user} if the other person has blocked the user.
  """
  def get_or_create_direct_conversation(user1_id, user2_id) do
    alias Elixirchat.Accounts

    # Check for blocks before creating/getting conversation
    case Accounts.check_block_status(user1_id, user2_id) do
      {:error, reason} ->
        {:error, reason}

      :ok ->
        # Find existing direct conversation between these two users
        query =
          from c in Conversation,
            where: c.type == "direct",
            join: m1 in ConversationMember, on: m1.conversation_id == c.id and m1.user_id == ^user1_id,
            join: m2 in ConversationMember, on: m2.conversation_id == c.id and m2.user_id == ^user2_id,
            select: c

        case Repo.one(query) do
          nil -> create_direct_conversation(user1_id, user2_id)
          conversation -> {:ok, conversation}
        end
    end
  end

  @doc """
  Creates a direct conversation between two users.
  """
  def create_direct_conversation(user1_id, user2_id) do
    Repo.transaction(fn ->
      {:ok, conversation} =
        %Conversation{}
        |> Conversation.changeset(%{type: "direct"})
        |> Repo.insert()

      {:ok, _} =
        %ConversationMember{}
        |> ConversationMember.changeset(%{conversation_id: conversation.id, user_id: user1_id})
        |> Repo.insert()

      {:ok, _} =
        %ConversationMember{}
        |> ConversationMember.changeset(%{conversation_id: conversation.id, user_id: user2_id})
        |> Repo.insert()

      conversation
    end)
  end

  @doc """
  Lists all conversations for a user with last message and other member info.
  Pinned conversations appear first (sorted by pinned_at descending), followed by
  unpinned conversations sorted by updated_at descending.
  Archived conversations are excluded by default.

  Options:
    - `:include_archived` - if true, includes archived conversations (default: false)
  """
  def list_user_conversations(user_id, opts \\ []) do
    include_archived = Keyword.get(opts, :include_archived, false)

    query =
      from c in Conversation,
        join: m in ConversationMember, on: m.conversation_id == c.id,
        where: m.user_id == ^user_id,
        preload: [members: :user],
        # Sort by: pinned first (desc nulls last), then by updated_at desc
        order_by: [desc_nulls_last: m.pinned_at, desc: c.updated_at],
        select: {c, m.pinned_at, m.archived_at}

    query =
      if include_archived do
        query
      else
        from [c, m] in query, where: is_nil(m.archived_at)
      end

    results = Repo.all(query)

    # Fetch last message for each conversation and include pinned_at
    Enum.map(results, fn {conv, pinned_at, archived_at} ->
      last_message = get_last_message(conv.id)
      unread_count = get_unread_count(conv.id, user_id)
      Map.merge(conv, %{last_message: last_message, unread_count: unread_count, pinned_at: pinned_at, archived_at: archived_at})
    end)
  end

  @doc """
  Gets the last message in a conversation.
  """
  def get_last_message(conversation_id) do
    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      order_by: [desc: m.inserted_at],
      limit: 1,
      preload: [:sender]
    )
    |> Repo.one()
  end

  @doc """
  Gets unread message count for a user in a conversation.
  """
  def get_unread_count(conversation_id, user_id) do
    member =
      from(m in ConversationMember,
        where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
      )
      |> Repo.one()

    case member do
      nil ->
        0

      %{last_read_at: nil} ->
        from(m in Message,
          where: m.conversation_id == ^conversation_id and m.sender_id != ^user_id
        )
        |> Repo.aggregate(:count)

      %{last_read_at: last_read_at} ->
        from(m in Message,
          where:
            m.conversation_id == ^conversation_id and
              m.sender_id != ^user_id and
              m.inserted_at > ^last_read_at
        )
        |> Repo.aggregate(:count)
    end
  end

  @doc """
  Lists messages in a conversation with reactions, reply_to, forwarded_from_user, and link_previews loaded.
  """
  def list_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before_id)

    query =
      from m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [asc: m.inserted_at],
        preload: [:sender, :attachments, :link_previews, :forwarded_from_user, reply_to: :sender]

    query =
      if before_id do
        from m in query, where: m.id < ^before_id
      else
        query
      end

    messages =
      query
      |> limit(^limit)
      |> Repo.all()

    # Batch load reactions for all messages
    message_ids = Enum.map(messages, & &1.id)
    reactions_map = get_reactions_for_messages(message_ids)

    # Attach reactions to each message
    Enum.map(messages, fn message ->
      Map.put(message, :reactions_grouped, Map.get(reactions_map, message.id, %{}))
    end)
  end

  @doc """
  Sends a message in a conversation.
  Accepts optional opts with :reply_to_id for replying to a specific message,
  and :attachments for file attachments.

  For direct conversations, returns {:error, :user_blocked} if sender has blocked the recipient,
  or {:error, :blocked_by_user} if sender is blocked by the recipient.
  """
  def send_message(conversation_id, sender_id, content, opts \\ []) do
    alias Elixirchat.Accounts

    conversation = get_conversation!(conversation_id)

    # Check for blocks in direct conversations
    with :ok <- check_direct_conversation_block(conversation, sender_id) do
      reply_to_id = Keyword.get(opts, :reply_to_id)
      attachments = Keyword.get(opts, :attachments, [])

      # Validate reply_to if provided
      if reply_to_id do
        reply_to = Repo.get(Message, reply_to_id)
        if is_nil(reply_to) or reply_to.conversation_id != conversation_id do
          {:error, :invalid_reply_to}
        else
          do_send_message(conversation_id, sender_id, content, reply_to_id, attachments)
        end
      else
        do_send_message(conversation_id, sender_id, content, nil, attachments)
      end
    end
  end

  # Checks if the sender is blocked or has blocked the other user in a direct conversation
  defp check_direct_conversation_block(%Conversation{type: "direct"} = conversation, sender_id) do
    alias Elixirchat.Accounts

    other_user = get_other_user(conversation, sender_id)

    if other_user do
      Accounts.check_block_status(sender_id, other_user.id)
    else
      :ok
    end
  end

  defp check_direct_conversation_block(_conversation, _sender_id), do: :ok

  defp do_send_message(conversation_id, sender_id, content, reply_to_id, attachments) do
    attrs = %{
      content: content,
      conversation_id: conversation_id,
      sender_id: sender_id
    }

    attrs = if reply_to_id, do: Map.put(attrs, :reply_to_id, reply_to_id), else: attrs

    result =
      %Message{}
      |> Message.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, message} ->
        # Create attachments if any
        Enum.each(attachments, fn attachment_data ->
          %Attachment{}
          |> Attachment.changeset(Map.put(attachment_data, :message_id, message.id))
          |> Repo.insert!()
        end)

        # Update conversation's updated_at timestamp
        Repo.get!(Conversation, conversation_id)
        |> Ecto.Changeset.change(%{updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)})
        |> Repo.update()

        # Preload sender, reply_to, attachments, and link_previews for the response, add empty reactions
        message =
          message
          |> Repo.preload([:sender, :attachments, :link_previews, reply_to: :sender], force: true)
          |> Map.put(:reactions_grouped, %{})

        # Broadcast the message
        broadcast_message(conversation_id, message)

        # Auto-unarchive for recipients when a new message is sent
        maybe_unarchive_for_recipients(conversation_id, sender_id)

        # Check for @agent mention and process asynchronously
        # Don't process agent messages to avoid infinite loops
        unless Agent.is_agent?(sender_id) do
          maybe_process_agent_mention(conversation_id, content)
        end

        # Trigger async link preview fetching
        maybe_fetch_link_previews(message)

        {:ok, message}

      error ->
        error
    end
  end

  # Spawns an async task to process @agent mentions
  defp maybe_process_agent_mention(conversation_id, content) do
    if Agent.contains_mention?(content) do
      Task.Supervisor.start_child(
        Elixirchat.TaskSupervisor,
        fn -> Agent.process_message(conversation_id, content) end
      )
    end

    :ok
  end

  @doc """
  Forwards a message to another conversation.
  Creates a new message with forwarding attribution.
  """
  def forward_message(message_id, to_conversation_id, sender_id, opts \\ []) do
    original = get_message!(message_id) |> Repo.preload([:attachments])

    cond do
      # Don't forward deleted messages
      original.deleted_at != nil ->
        {:error, :message_deleted}

      # Verify sender is member of target conversation
      !member?(to_conversation_id, sender_id) ->
        {:error, :not_member}

      true ->
        attrs = %{
          content: original.content,
          conversation_id: to_conversation_id,
          sender_id: sender_id,
          forwarded_from_message_id: message_id,
          forwarded_from_user_id: original.sender_id
        }

        result =
          %Message{}
          |> Message.forward_changeset(attrs)
          |> Repo.insert()

        case result do
          {:ok, message} ->
            # Copy attachments if any and opts allow
            if Keyword.get(opts, :include_attachments, true) && length(original.attachments) > 0 do
              copy_attachments(original, message)
            end

            # Update conversation timestamp
            Repo.get!(Conversation, to_conversation_id)
            |> Ecto.Changeset.change(%{updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)})
            |> Repo.update()

            # Preload and broadcast
            message =
              message
              |> Repo.preload([:sender, :attachments, :link_previews, :forwarded_from_user, reply_to: :sender], force: true)
              |> Map.put(:reactions_grouped, %{})

            broadcast_message(to_conversation_id, message)
            {:ok, message}

          error ->
            error
        end
    end
  end

  defp copy_attachments(original_message, new_message) do
    Enum.each(original_message.attachments, fn attachment ->
      %Attachment{}
      |> Attachment.changeset(%{
        message_id: new_message.id,
        filename: attachment.filename,
        original_filename: attachment.original_filename,
        content_type: attachment.content_type,
        size: attachment.size
      })
      |> Repo.insert!()
    end)
  end

  @doc """
  Marks a conversation as read for a user.
  """
  def mark_conversation_read(conversation_id, user_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_found}

      member ->
        member
        |> ConversationMember.changeset(%{last_read_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  @doc """
  Checks if a user is a member of a conversation.
  """
  def member?(conversation_id, user_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
    )
    |> Repo.exists?()
  end

  @doc """
  Gets the other user in a direct conversation.
  """
  def get_other_user(%Conversation{type: "direct", members: members}, current_user_id) do
    members
    |> Enum.find(fn m -> m.user_id != current_user_id end)
    |> case do
      nil -> nil
      member -> member.user
    end
  end

  def get_other_user(_, _), do: nil

  @doc """
  Subscribes to conversation updates.
  """
  def subscribe(conversation_id) do
    Phoenix.PubSub.subscribe(Elixirchat.PubSub, "conversation:#{conversation_id}")
  end

  defp broadcast_message(conversation_id, message) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:new_message, message}
    )
  end

  @doc """
  Broadcasts that a user started typing in a conversation.
  """
  def broadcast_typing_start(conversation_id, user) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:user_typing, %{user_id: user.id, username: user.username}}
    )
  end

  @doc """
  Broadcasts that a user stopped typing in a conversation.
  """
  def broadcast_typing_stop(conversation_id, user_id) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:user_stopped_typing, %{user_id: user_id}}
    )
  end

  @doc """
  Searches users by username (excluding the current user).
  Optionally filters out blocked users and users who have blocked the searcher.
  Options:
    - :exclude_blocked - if true, excludes users involved in any block relationship (default: false)
  """
  def search_users(query, current_user_id, opts \\ [])

  def search_users(query, current_user_id, opts) when byte_size(query) > 0 do
    alias Elixirchat.Accounts

    search_term = "%#{query}%"
    exclude_blocked = Keyword.get(opts, :exclude_blocked, false)

    base_query =
      from(u in User,
        where: u.id != ^current_user_id,
        where: ilike(u.username, ^search_term),
        limit: 10,
        order_by: u.username
      )

    if exclude_blocked do
      # Get users to exclude (blocked by current user or have blocked current user)
      blocked_ids = Accounts.get_blocked_user_ids(current_user_id)
      blocker_ids = Accounts.get_blocker_ids(current_user_id)
      excluded_ids = MapSet.union(blocked_ids, blocker_ids) |> MapSet.to_list()

      from(u in base_query, where: u.id not in ^excluded_ids)
      |> Repo.all()
    else
      base_query
      |> Repo.all()
    end
  end

  def search_users(_, _, _), do: []

  @doc """
  Searches users by username who are NOT already members of a conversation.
  Useful for adding new members to an existing group.
  """
  def search_users_not_in_conversation(query, conversation_id, limit \\ 10) when byte_size(query) > 0 do
    existing_member_ids =
      from(m in ConversationMember,
        where: m.conversation_id == ^conversation_id,
        select: m.user_id
      )
      |> Repo.all()

    search_term = "%#{query}%"

    from(u in User,
      where: ilike(u.username, ^search_term),
      where: u.id not in ^existing_member_ids,
      limit: ^limit,
      order_by: u.username
    )
    |> Repo.all()
  end

  def search_users_not_in_conversation(_, _, _), do: []

  # ===============================
  # Group Chat Functions
  # ===============================

  @doc """
  Creates a group conversation with a name and initial members.
  The creator is automatically added as a member.
  """
  def create_group_conversation(name, member_ids) when is_list(member_ids) and length(member_ids) >= 1 do
    Repo.transaction(fn ->
      # Create the conversation
      {:ok, conversation} =
        %Conversation{}
        |> Conversation.changeset(%{type: "group", name: name})
        |> Repo.insert()

      # Add all members
      Enum.each(member_ids, fn user_id ->
        {:ok, _} =
          %ConversationMember{}
          |> ConversationMember.changeset(%{conversation_id: conversation.id, user_id: user_id})
          |> Repo.insert()
      end)

      conversation |> Repo.preload(members: :user)
    end)
  end

  def create_group_conversation(_, _), do: {:error, :invalid_members}

  @doc """
  Adds a user to an existing group conversation.
  """
  def add_member_to_group(conversation_id, user_id) do
    conversation = Repo.get!(Conversation, conversation_id)

    if conversation.type == "group" do
      result =
        %ConversationMember{}
        |> ConversationMember.changeset(%{conversation_id: conversation_id, user_id: user_id})
        |> Repo.insert()

      case result do
        {:ok, member} ->
          # Preload the user for the broadcast
          member = Repo.preload(member, :user)
          {:ok, member}

        error ->
          error
      end
    else
      {:error, :not_a_group}
    end
  end

  @doc """
  Broadcasts that a new member was added to a conversation.
  """
  def broadcast_member_added(conversation_id, member) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:member_added, member}
    )
  end

  @doc """
  Removes a user from a group conversation (or allows a user to leave).
  """
  def remove_member_from_group(conversation_id, user_id) do
    conversation = Repo.get!(Conversation, conversation_id)

    if conversation.type == "group" do
      from(m in ConversationMember,
        where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
      )
      |> Repo.one()
      |> case do
        nil -> {:error, :not_found}
        member -> Repo.delete(member)
      end
    else
      {:error, :not_a_group}
    end
  end

  @doc """
  Checks if a user can leave a group conversation.
  Returns :ok or {:error, reason}.
  Reasons: :not_a_group, :cannot_leave_general, :not_a_member
  """
  def can_leave_group?(conversation_id, user_id) do
    conversation = Repo.get!(Conversation, conversation_id)

    cond do
      conversation.type != "group" -> {:error, :not_a_group}
      conversation.is_general == true -> {:error, :cannot_leave_general}
      !member?(conversation_id, user_id) -> {:error, :not_a_member}
      true -> :ok
    end
  end

  @doc """
  Allows a user to leave a group conversation.
  Validates the leave is allowed, removes the member, and broadcasts the event.
  Returns :ok or {:error, reason}.
  """
  def leave_group(conversation_id, user_id) do
    case can_leave_group?(conversation_id, user_id) do
      :ok ->
        case remove_member_from_group(conversation_id, user_id) do
          {:ok, _} ->
            broadcast_member_left(conversation_id, user_id)
            :ok
          error ->
            error
        end
      error ->
        error
    end
  end

  @doc """
  Broadcasts that a member left a conversation.
  """
  def broadcast_member_left(conversation_id, user_id) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:member_left, user_id}
    )
  end

  @doc """
  Updates the name of a group conversation.
  """
  def update_group_name(conversation_id, new_name) do
    conversation = Repo.get!(Conversation, conversation_id)

    if conversation.type == "group" do
      conversation
      |> Conversation.changeset(%{name: new_name})
      |> Repo.update()
    else
      {:error, :not_a_group}
    end
  end

  @doc """
  Lists all members of a conversation.
  """
  def list_group_members(conversation_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id,
      preload: [:user]
    )
    |> Repo.all()
    |> Enum.map(& &1.user)
  end

  @doc """
  Gets the member count for a conversation.
  """
  def get_member_count(conversation_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id
    )
    |> Repo.aggregate(:count)
  end

  # ===============================
  # Message Search Functions
  # ===============================

  @doc """
  Searches messages in a conversation by content.
  Requires at least 2 characters for the search query.
  Returns messages with sender info preloaded, ordered by most recent first.
  """
  def search_messages(conversation_id, query) when is_binary(query) and byte_size(query) >= 2 do
    # Escape special characters for ILIKE
    escaped_query = escape_like_query(query)
    search_term = "%#{escaped_query}%"

    from(m in Message,
      where: m.conversation_id == ^conversation_id,
      where: ilike(m.content, ^search_term),
      order_by: [desc: m.inserted_at],
      limit: 20,
      preload: [:sender]
    )
    |> Repo.all()
  end

  def search_messages(_, _), do: []

  # Escapes special characters used in LIKE/ILIKE patterns
  defp escape_like_query(query) do
    query
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  # ===============================
  # Message Edit/Delete Functions
  # ===============================

  @edit_delete_time_limit_minutes 15

  @doc """
  Gets a message by ID with sender preloaded.
  """
  def get_message!(id) do
    Message
    |> Repo.get!(id)
    |> Repo.preload(:sender)
  end

  @doc """
  Checks if a user can modify (edit/delete) a message.
  Returns :ok or {:error, reason}.
  """
  def can_modify_message?(message, user_id) do
    cond do
      message.sender_id != user_id -> {:error, :not_owner}
      message.deleted_at != nil -> {:error, :already_deleted}
      Agent.is_agent?(message.sender_id) -> {:error, :agent_message}
      !within_time_limit?(message) -> {:error, :time_expired}
      true -> :ok
    end
  end

  defp within_time_limit?(message) do
    minutes_since = DateTime.diff(DateTime.utc_now(), message.inserted_at, :minute)
    minutes_since <= @edit_delete_time_limit_minutes
  end

  @doc """
  Edits a message's content. Validates ownership and time limit.
  """
  def edit_message(message_id, user_id, new_content) do
    message = get_message!(message_id)

    case can_modify_message?(message, user_id) do
      :ok ->
        message
        |> Message.edit_changeset(%{content: new_content, edited_at: DateTime.utc_now()})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            updated = Repo.preload(updated, :sender, force: true)
            broadcast_message_edited(message.conversation_id, updated)
            {:ok, updated}
          error ->
            error
        end
      error ->
        error
    end
  end

  @doc """
  Soft deletes a message. Validates ownership and time limit.
  """
  def delete_message(message_id, user_id) do
    message = get_message!(message_id)

    case can_modify_message?(message, user_id) do
      :ok ->
        message
        |> Message.delete_changeset(%{deleted_at: DateTime.utc_now()})
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            updated = Repo.preload(updated, :sender, force: true)
            broadcast_message_deleted(message.conversation_id, updated)
            {:ok, updated}
          error ->
            error
        end
      error ->
        error
    end
  end

  @doc """
  Broadcasts that a message was edited.
  """
  def broadcast_message_edited(conversation_id, message) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:message_edited, message}
    )
  end

  @doc """
  Broadcasts that a message was deleted.
  """
  def broadcast_message_deleted(conversation_id, message) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:message_deleted, message}
    )
  end

  @doc """
  Returns the edit/delete time limit in minutes.
  """
  def edit_delete_time_limit_minutes, do: @edit_delete_time_limit_minutes

  # ===============================
  # Message Reaction Functions
  # ===============================

  @doc """
  Toggles a reaction on a message. If the user already has this reaction,
  it will be removed. Otherwise, it will be added.

  Returns {:ok, reactions_map} where reactions_map is grouped reactions for the message.
  """
  def toggle_reaction(message_id, user_id, emoji) do
    message = Repo.get!(Message, message_id)

    existing =
      from(r in Reaction,
        where: r.message_id == ^message_id and r.user_id == ^user_id and r.emoji == ^emoji
      )
      |> Repo.one()

    result =
      case existing do
        nil ->
          # Add reaction
          %Reaction{}
          |> Reaction.changeset(%{message_id: message_id, user_id: user_id, emoji: emoji})
          |> Repo.insert()

        reaction ->
          # Remove reaction
          Repo.delete(reaction)
      end

    case result do
      {:ok, _} ->
        reactions = list_message_reactions(message_id)
        broadcast_reaction_update(message.conversation_id, %{message_id: message_id, reactions: reactions})
        {:ok, reactions}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Lists all reactions for a message, grouped by emoji.
  Returns a map like %{"👍" => [%User{}, %User{}], "❤️" => [%User{}]}
  """
  def list_message_reactions(message_id) do
    from(r in Reaction,
      where: r.message_id == ^message_id,
      preload: [:user],
      order_by: [asc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.emoji, & &1.user)
  end

  @doc """
  Batch loads reactions for a list of messages.
  Returns a map of message_id => reactions_grouped_by_emoji
  """
  def get_reactions_for_messages(message_ids) when is_list(message_ids) do
    from(r in Reaction,
      where: r.message_id in ^message_ids,
      preload: [:user],
      order_by: [asc: r.inserted_at]
    )
    |> Repo.all()
    |> Enum.group_by(& &1.message_id)
    |> Enum.into(%{}, fn {message_id, reactions} ->
      grouped = Enum.group_by(reactions, & &1.emoji, & &1.user)
      {message_id, grouped}
    end)
  end

  def get_reactions_for_messages(_), do: %{}

  @doc """
  Broadcasts a reaction update to conversation subscribers.
  """
  def broadcast_reaction_update(conversation_id, reaction_data) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:reaction_updated, reaction_data}
    )
  end

  # ===============================
  # Read Receipt Functions
  # ===============================

  @doc """
  Marks messages as read by a user.
  Takes a list of message IDs and creates read receipts for ones not already read.
  Broadcasts the read event to all conversation members.
  """
  def mark_messages_read(conversation_id, user_id, message_ids) when is_list(message_ids) and message_ids != [] do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Get message IDs that user hasn't already read
    existing_read =
      from(r in ReadReceipt,
        where: r.user_id == ^user_id and r.message_id in ^message_ids,
        select: r.message_id
      )
      |> Repo.all()
      |> MapSet.new()

    new_message_ids = Enum.reject(message_ids, &MapSet.member?(existing_read, &1))

    if new_message_ids != [] do
      entries =
        Enum.map(new_message_ids, fn msg_id ->
          %{
            message_id: msg_id,
            user_id: user_id,
            read_at: now,
            inserted_at: now,
            updated_at: now
          }
        end)

      Repo.insert_all(ReadReceipt, entries, on_conflict: :nothing)
      broadcast_messages_read(conversation_id, user_id, new_message_ids)
    end

    :ok
  end

  def mark_messages_read(_, _, _), do: :ok

  @doc """
  Gets read receipts for a list of message IDs.
  Returns a map of message_id => list of user_ids who have read it.
  """
  def get_read_receipts_for_messages(message_ids) when is_list(message_ids) do
    from(r in ReadReceipt,
      where: r.message_id in ^message_ids,
      select: {r.message_id, r.user_id}
    )
    |> Repo.all()
    |> Enum.group_by(fn {msg_id, _} -> msg_id end, fn {_, user_id} -> user_id end)
  end

  def get_read_receipts_for_messages(_), do: %{}

  @doc """
  Gets the list of users who have read a specific message.
  """
  def get_message_readers(message_id) do
    from(r in ReadReceipt,
      where: r.message_id == ^message_id,
      join: u in assoc(r, :user),
      select: u,
      order_by: [asc: r.read_at]
    )
    |> Repo.all()
  end

  @doc """
  Checks if a message has been read by the recipient in a direct conversation.
  Returns true if the other user (not the sender) has read the message.
  """
  def message_read_by_other?(message_id, sender_id) do
    from(r in ReadReceipt,
      where: r.message_id == ^message_id and r.user_id != ^sender_id
    )
    |> Repo.exists?()
  end

  @doc """
  Broadcasts that messages have been read by a user.
  """
  def broadcast_messages_read(conversation_id, user_id, message_ids) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:messages_read, %{user_id: user_id, message_ids: message_ids}}
    )
  end

  # ===============================
  # Mention Functions
  # ===============================

  @doc """
  Gets users that can be mentioned in a conversation.
  Filters by search term and returns matching users.
  """
  defdelegate get_mentionable_users(conversation_id, search_term), to: Mentions

  @doc """
  Renders message content with highlighted mentions.
  """
  defdelegate render_with_mentions(content, conversation_id), to: Mentions

  # ===============================
  # File Attachment Functions
  # ===============================

  @doc """
  Returns the path to the uploads directory.
  Creates the directory if it doesn't exist.
  """
  def uploads_dir do
    dir = Path.join([:code.priv_dir(:elixirchat), "static", "uploads"])
    File.mkdir_p!(dir)
    dir
  end

  @doc """
  Gets an attachment by ID.
  """
  def get_attachment!(id) do
    Repo.get!(Attachment, id)
  end

  # ===============================
  # Link Preview Functions
  # ===============================

  @doc """
  Triggers async link preview fetching for a message.
  Extracts URLs from the message content and fetches previews in the background.
  """
  def maybe_fetch_link_previews(message) do
    urls = UrlExtractor.extract_urls(message.content)

    if urls != [] do
      Task.Supervisor.start_child(
        Elixirchat.TaskSupervisor,
        fn -> fetch_and_attach_previews(message, urls) end
      )
    end

    :ok
  end

  @doc """
  Fetches link previews for URLs and attaches them to a message.
  Called asynchronously from maybe_fetch_link_previews/1.
  """
  def fetch_and_attach_previews(message, urls) do
    previews =
      urls
      |> Enum.map(&get_or_create_preview/1)
      |> Enum.reject(&is_nil/1)

    if previews != [] do
      # Associate previews with message
      Enum.each(previews, fn preview ->
        %MessageLinkPreview{}
        |> MessageLinkPreview.changeset(%{message_id: message.id, link_preview_id: preview.id})
        |> Repo.insert(on_conflict: :nothing)
      end)

      # Broadcast the previews to conversation
      broadcast_link_previews(message.conversation_id, message.id, previews)
    end

    :ok
  end

  @doc """
  Gets an existing link preview from cache or creates a new one by fetching.
  """
  def get_or_create_preview(url) do
    url_hash = LinkPreview.hash_url(url)

    case Repo.get_by(LinkPreview, url_hash: url_hash) do
      nil ->
        # Fetch and create new preview
        case LinkPreviewFetcher.fetch(url) do
          {:ok, metadata} ->
            case create_link_preview(metadata) do
              {:ok, preview} -> preview
              {:error, _} -> nil
            end

          {:error, _} ->
            nil
        end

      preview ->
        preview
    end
  end

  @doc """
  Creates a new link preview record.
  """
  def create_link_preview(attrs) do
    %LinkPreview{}
    |> LinkPreview.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Broadcasts link preview updates to conversation subscribers.
  """
  def broadcast_link_previews(conversation_id, message_id, previews) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:link_previews_fetched, %{message_id: message_id, previews: previews}}
    )
  end

  # ===============================
  # Message Pinning Functions
  # ===============================

  @doc """
  Pins a message in a conversation.
  Returns {:ok, pinned_message} or {:error, reason}.
  Errors: :pin_limit_reached, :invalid_message, :already_pinned, :message_deleted
  """
  def pin_message(conversation_id, message_id, user_id) do
    # Check pin limit
    current_pin_count =
      from(p in PinnedMessage, where: p.conversation_id == ^conversation_id, select: count(p.id))
      |> Repo.one()

    if current_pin_count >= PinnedMessage.max_pins_per_conversation() do
      {:error, :pin_limit_reached}
    else
      # Get and verify the message
      case Repo.get(Message, message_id) do
        nil ->
          {:error, :invalid_message}

        message ->
          cond do
            message.conversation_id != conversation_id ->
              {:error, :invalid_message}

            message.deleted_at != nil ->
              {:error, :message_deleted}

            true ->
              result =
                %PinnedMessage{}
                |> PinnedMessage.changeset(%{
                  message_id: message_id,
                  conversation_id: conversation_id,
                  pinned_by_id: user_id,
                  pinned_at: DateTime.utc_now() |> DateTime.truncate(:second)
                })
                |> Repo.insert()

              case result do
                {:ok, pinned} ->
                  pinned = Repo.preload(pinned, [message: :sender, pinned_by: []])
                  broadcast_pin_update(conversation_id, {:message_pinned, pinned})
                  {:ok, pinned}

                {:error, changeset} ->
                  if changeset.errors[:message_id] do
                    {:error, :already_pinned}
                  else
                    {:error, changeset}
                  end
              end
          end
      end
    end
  end

  @doc """
  Unpins a message. Only the pinner or message author can unpin.
  Returns :ok or {:error, reason}.
  """
  def unpin_message(message_id, user_id) do
    pinned = Repo.get_by(PinnedMessage, message_id: message_id)

    case pinned do
      nil ->
        {:error, :not_pinned}

      pinned ->
        message = Repo.get!(Message, message_id)

        # Only pinner or message author can unpin
        if pinned.pinned_by_id == user_id || message.sender_id == user_id do
          conversation_id = pinned.conversation_id
          {:ok, _} = Repo.delete(pinned)
          broadcast_pin_update(conversation_id, {:message_unpinned, message_id})
          :ok
        else
          {:error, :not_authorized}
        end
    end
  end

  @doc """
  Lists all pinned messages for a conversation, ordered by most recently pinned first.
  """
  def list_pinned_messages(conversation_id) do
    from(p in PinnedMessage,
      where: p.conversation_id == ^conversation_id,
      preload: [message: :sender, pinned_by: []],
      order_by: [desc: p.pinned_at]
    )
    |> Repo.all()
  end

  @doc """
  Checks if a specific message is pinned.
  """
  def is_message_pinned?(message_id) do
    from(p in PinnedMessage, where: p.message_id == ^message_id)
    |> Repo.exists?()
  end

  @doc """
  Gets pinned message IDs for a conversation as a MapSet for fast lookup.
  """
  def get_pinned_message_ids(conversation_id) do
    from(p in PinnedMessage,
      where: p.conversation_id == ^conversation_id,
      select: p.message_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Broadcasts pin/unpin updates to conversation subscribers.
  """
  def broadcast_pin_update(conversation_id, event) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      event
    )
  end

  # ===============================
  # Conversation Pinning Functions
  # ===============================

  @doc """
  Pins a conversation for a user.
  Sets pinned_at to the current timestamp.
  """
  def pin_conversation(conversation_id, user_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_a_member}

      member ->
        member
        |> ConversationMember.pin_changeset(%{pinned_at: DateTime.utc_now() |> DateTime.truncate(:second)})
        |> Repo.update()
    end
  end

  @doc """
  Unpins a conversation for a user.
  Sets pinned_at to nil.
  """
  def unpin_conversation(conversation_id, user_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
    )
    |> Repo.one()
    |> case do
      nil ->
        {:error, :not_a_member}

      member ->
        member
        |> ConversationMember.pin_changeset(%{pinned_at: nil})
        |> Repo.update()
    end
  end

  @doc """
  Checks if a conversation is pinned for a user.
  """
  def is_conversation_pinned?(conversation_id, user_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id and m.user_id == ^user_id,
      where: not is_nil(m.pinned_at)
    )
    |> Repo.exists?()
  end

  @doc """
  Toggles the pin state for a conversation.
  Returns {:ok, :pinned} or {:ok, :unpinned}.
  """
  def toggle_conversation_pin(conversation_id, user_id) do
    if is_conversation_pinned?(conversation_id, user_id) do
      case unpin_conversation(conversation_id, user_id) do
        {:ok, _} -> {:ok, :unpinned}
        error -> error
      end
    else
      case pin_conversation(conversation_id, user_id) do
        {:ok, _} -> {:ok, :pinned}
        error -> error
      end
    end
  end

  # ===============================
  # General Group Functions
  # ===============================

  @doc """
  Gets the General conversation if it exists.
  Returns nil if not found.
  """
  def get_general_conversation do
    from(c in Conversation, where: c.is_general == true)
    |> Repo.one()
  end

  @doc """
  Gets or creates the General group conversation.
  Creates it if it doesn't exist, returns it if it does.
  """
  def get_or_create_general_conversation do
    case get_general_conversation() do
      nil ->
        {:ok, conversation} =
          %Conversation{}
          |> Conversation.changeset(%{type: "group", name: "General", is_general: true})
          |> Repo.insert()

        {:ok, conversation}

      conversation ->
        {:ok, conversation}
    end
  end

  @doc """
  Adds a user to the General group conversation.
  This is idempotent - if the user is already a member, it does nothing.
  Returns :ok on success, or {:error, reason} if the General group doesn't exist.
  """
  def add_user_to_general(user_id) do
    case get_general_conversation() do
      nil ->
        # General group doesn't exist yet, try to create it first
        case get_or_create_general_conversation() do
          {:ok, conversation} ->
            do_add_user_to_general(conversation.id, user_id)

          error ->
            error
        end

      conversation ->
        do_add_user_to_general(conversation.id, user_id)
    end
  end

  defp do_add_user_to_general(conversation_id, user_id) do
    # Check if already a member
    if member?(conversation_id, user_id) do
      :ok
    else
      case add_member_to_group(conversation_id, user_id) do
        {:ok, _} -> :ok
        {:error, _} = error -> error
      end
    end
  end

  # ===============================
  # Muted Conversation Functions
  # ===============================

  @doc """
  Mutes a conversation for a user.
  When a conversation is muted, the user won't receive browser notifications for new messages.
  Returns {:ok, muted_conversation} or {:ok, nil} if already muted (on_conflict: :nothing).
  """
  def mute_conversation(conversation_id, user_id) do
    %MutedConversation{}
    |> MutedConversation.changeset(%{conversation_id: conversation_id, user_id: user_id})
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc """
  Unmutes a conversation for a user.
  Returns :ok whether or not the conversation was previously muted.
  """
  def unmute_conversation(conversation_id, user_id) do
    from(m in MutedConversation,
      where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Checks if a conversation is muted by a user.
  """
  def is_muted?(conversation_id, user_id) do
    from(m in MutedConversation,
      where: m.conversation_id == ^conversation_id and m.user_id == ^user_id
    )
    |> Repo.exists?()
  end

  @doc """
  Lists all conversation IDs that are muted by a user.
  Returns a list of conversation IDs.
  """
  def list_muted_conversation_ids(user_id) do
    from(m in MutedConversation,
      where: m.user_id == ^user_id,
      select: m.conversation_id
    )
    |> Repo.all()
  end

  @doc """
  Toggles the mute status of a conversation for a user.
  Returns {:ok, :muted} or {:ok, :unmuted}.
  """
  def toggle_mute(conversation_id, user_id) do
    if is_muted?(conversation_id, user_id) do
      unmute_conversation(conversation_id, user_id)
      {:ok, :unmuted}
    else
      mute_conversation(conversation_id, user_id)
      {:ok, :muted}
    end
  end

  # ===============================
  # Archived Conversation Functions
  # ===============================

  @doc """
  Archives a conversation for a user.
  Returns {:ok, member} or {:error, :not_a_member}.
  """
  def archive_conversation(conversation_id, user_id) do
    case get_membership(conversation_id, user_id) do
      nil ->
        {:error, :not_a_member}

      member ->
        member
        |> ConversationMember.archive_changeset(%{archived_at: DateTime.utc_now()})
        |> Repo.update()
    end
  end

  @doc """
  Unarchives a conversation for a user.
  Returns {:ok, member} or {:error, :not_a_member}.
  """
  def unarchive_conversation(conversation_id, user_id) do
    case get_membership(conversation_id, user_id) do
      nil ->
        {:error, :not_a_member}

      member ->
        member
        |> ConversationMember.archive_changeset(%{archived_at: nil})
        |> Repo.update()
    end
  end

  @doc """
  Checks if a conversation is archived by a user.
  """
  def is_archived?(conversation_id, user_id) do
    case get_membership(conversation_id, user_id) do
      nil -> false
      member -> member.archived_at != nil
    end
  end

  @doc """
  Lists all archived conversations for a user.
  Returns conversations with last_message, unread_count, and archived_at fields.
  """
  def list_archived_conversations(user_id) do
    query =
      from c in Conversation,
        join: m in ConversationMember, on: m.conversation_id == c.id,
        where: m.user_id == ^user_id,
        where: not is_nil(m.archived_at),
        preload: [members: :user],
        order_by: [desc: m.archived_at],
        select: {c, m.pinned_at, m.archived_at}

    results = Repo.all(query)

    Enum.map(results, fn {conv, pinned_at, archived_at} ->
      last_message = get_last_message(conv.id)
      unread_count = get_unread_count(conv.id, user_id)
      Map.merge(conv, %{last_message: last_message, unread_count: unread_count, pinned_at: pinned_at, archived_at: archived_at})
    end)
  end

  @doc """
  Returns the count of archived conversations for a user.
  """
  def get_archived_count(user_id) do
    from(m in ConversationMember,
      where: m.user_id == ^user_id,
      where: not is_nil(m.archived_at)
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Toggles the archive status of a conversation for a user.
  Returns {:ok, :archived} or {:ok, :unarchived}.
  """
  def toggle_archive(conversation_id, user_id) do
    if is_archived?(conversation_id, user_id) do
      case unarchive_conversation(conversation_id, user_id) do
        {:ok, _} -> {:ok, :unarchived}
        error -> error
      end
    else
      case archive_conversation(conversation_id, user_id) do
        {:ok, _} -> {:ok, :archived}
        error -> error
      end
    end
  end

  @doc """
  Unarchives a conversation for all members except the sender.
  Called when a new message is sent to auto-unarchive for recipients.
  """
  def maybe_unarchive_for_recipients(conversation_id, sender_id) do
    from(m in ConversationMember,
      where: m.conversation_id == ^conversation_id,
      where: m.user_id != ^sender_id,
      where: not is_nil(m.archived_at)
    )
    |> Repo.update_all(set: [archived_at: nil])

    :ok
  end

  defp get_membership(conversation_id, user_id) do
    Repo.get_by(ConversationMember,
      conversation_id: conversation_id,
      user_id: user_id
    )
  end

  # ===============================
  # Starred Message Functions
  # ===============================

  @doc """
  Stars a message for a user.
  Returns {:ok, starred_message} or {:error, reason}.
  The user must be a member of the message's conversation.
  """
  def star_message(message_id, user_id) do
    message = Repo.get!(Message, message_id)

    if member?(message.conversation_id, user_id) do
      %StarredMessage{}
      |> StarredMessage.changeset(%{
        message_id: message_id,
        user_id: user_id,
        starred_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert(on_conflict: :nothing)
    else
      {:error, :not_a_member}
    end
  end

  @doc """
  Unstars a message for a user.
  Returns :ok whether or not the message was starred.
  """
  def unstar_message(message_id, user_id) do
    from(s in StarredMessage,
      where: s.message_id == ^message_id and s.user_id == ^user_id
    )
    |> Repo.delete_all()

    :ok
  end

  @doc """
  Toggles the starred status of a message for a user.
  Returns {:ok, :starred} or {:ok, :unstarred}.
  """
  def toggle_star(message_id, user_id) do
    if is_starred?(message_id, user_id) do
      unstar_message(message_id, user_id)
      {:ok, :unstarred}
    else
      case star_message(message_id, user_id) do
        {:ok, _} -> {:ok, :starred}
        error -> error
      end
    end
  end

  @doc """
  Checks if a message is starred by a user.
  """
  def is_starred?(message_id, user_id) do
    from(s in StarredMessage,
      where: s.message_id == ^message_id and s.user_id == ^user_id
    )
    |> Repo.exists?()
  end

  @doc """
  Lists all starred messages for a user, grouped by conversation.
  Returns a list of starred messages with message, sender, and conversation preloaded.
  """
  def list_starred_messages(user_id) do
    from(s in StarredMessage,
      where: s.user_id == ^user_id,
      join: m in assoc(s, :message),
      join: c in assoc(m, :conversation),
      preload: [message: {m, [sender: [], conversation: {c, [members: :user]}]}],
      order_by: [desc: s.starred_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets starred message IDs for a user as a MapSet for fast lookup.
  """
  def get_starred_message_ids(user_id) do
    from(s in StarredMessage,
      where: s.user_id == ^user_id,
      select: s.message_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  # ===============================
  # Poll Functions
  # ===============================

  @doc """
  Creates a poll in a conversation with the given options.
  Options must be a list of 2-10 strings.
  Returns {:ok, poll} or {:error, reason}.
  """
  def create_poll(conversation_id, creator_id, question, options, attrs \\ %{})
      when is_list(options) do
    cond do
      length(options) < 2 ->
        {:error, :too_few_options}

      length(options) > 10 ->
        {:error, :too_many_options}

      Enum.any?(options, fn opt -> String.trim(opt) == "" end) ->
        {:error, :empty_option}

      true ->
        Repo.transaction(fn ->
          # Create the poll
          poll_attrs =
            Map.merge(attrs, %{
              question: question,
              conversation_id: conversation_id,
              creator_id: creator_id
            })

          {:ok, poll} =
            %Poll{}
            |> Poll.changeset(poll_attrs)
            |> Repo.insert()

          # Create options
          options
          |> Enum.with_index()
          |> Enum.each(fn {text, index} ->
            %PollOption{}
            |> PollOption.changeset(%{
              text: String.trim(text),
              position: index,
              poll_id: poll.id
            })
            |> Repo.insert!()
          end)

          # Return poll with preloaded data and computed results
          poll = get_poll!(poll.id)
          broadcast_poll_created(conversation_id, poll)
          poll
        end)
    end
  end

  @doc """
  Gets a poll by ID with options, votes, and computed results.
  """
  def get_poll!(poll_id) do
    poll =
      Poll
      |> Repo.get!(poll_id)
      |> Repo.preload([:creator, options: :votes])

    compute_poll_results(poll)
  end

  @doc """
  Gets a poll by ID, returning nil if not found.
  """
  def get_poll(poll_id) do
    case Repo.get(Poll, poll_id) do
      nil -> nil
      poll ->
        poll
        |> Repo.preload([:creator, options: :votes])
        |> compute_poll_results()
    end
  end

  defp compute_poll_results(poll) do
    total_votes =
      poll.options
      |> Enum.map(fn opt -> length(opt.votes) end)
      |> Enum.sum()

    options_with_counts =
      Enum.map(poll.options, fn option ->
        vote_count = length(option.votes)
        percentage = if total_votes > 0, do: round(vote_count / total_votes * 100), else: 0
        voter_ids = if poll.anonymous, do: [], else: Enum.map(option.votes, & &1.user_id)

        %{option | vote_count: vote_count, percentage: percentage, voter_ids: voter_ids}
      end)

    %{poll | options: options_with_counts, total_votes: total_votes}
  end

  @doc """
  Casts a vote on a poll option.
  For single-choice polls, removes any existing vote first.
  Returns {:ok, poll} or {:error, reason}.
  """
  def vote_on_poll(poll_id, option_id, user_id) do
    poll = Repo.get!(Poll, poll_id)

    cond do
      poll.closed_at != nil ->
        {:error, :poll_closed}

      not poll.allow_multiple ->
        # Single choice: remove existing vote first
        from(v in PollVote, where: v.poll_id == ^poll_id and v.user_id == ^user_id)
        |> Repo.delete_all()

        insert_vote(poll_id, option_id, user_id)

      true ->
        # Multiple choice: check if already voted for this option
        existing =
          from(v in PollVote,
            where: v.poll_id == ^poll_id and v.poll_option_id == ^option_id and v.user_id == ^user_id
          )
          |> Repo.one()

        if existing do
          # Toggle off - remove vote
          Repo.delete(existing)
          poll = get_poll!(poll_id)
          broadcast_poll_updated(poll)
          {:ok, poll}
        else
          insert_vote(poll_id, option_id, user_id)
        end
    end
  end

  defp insert_vote(poll_id, option_id, user_id) do
    %PollVote{}
    |> PollVote.changeset(%{
      poll_id: poll_id,
      poll_option_id: option_id,
      user_id: user_id
    })
    |> Repo.insert()
    |> case do
      {:ok, _vote} ->
        poll = get_poll!(poll_id)
        broadcast_poll_updated(poll)
        {:ok, poll}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Removes a user's vote from a poll option.
  Returns {:ok, poll} or {:error, reason}.
  """
  def remove_vote(poll_id, option_id, user_id) do
    poll = Repo.get!(Poll, poll_id)

    if poll.closed_at != nil do
      {:error, :poll_closed}
    else
      from(v in PollVote,
        where: v.poll_id == ^poll_id and v.poll_option_id == ^option_id and v.user_id == ^user_id
      )
      |> Repo.delete_all()

      poll = get_poll!(poll_id)
      broadcast_poll_updated(poll)
      {:ok, poll}
    end
  end

  @doc """
  Closes a poll to prevent further voting.
  Only the creator can close a poll.
  Returns {:ok, poll} or {:error, reason}.
  """
  def close_poll(poll_id, user_id) do
    poll = Repo.get!(Poll, poll_id)

    cond do
      poll.creator_id != user_id ->
        {:error, :not_creator}

      poll.closed_at != nil ->
        {:error, :already_closed}

      true ->
        poll
        |> Poll.close_changeset(%{closed_at: DateTime.utc_now() |> DateTime.truncate(:second)})
        |> Repo.update()
        |> case do
          {:ok, _} ->
            poll = get_poll!(poll_id)
            broadcast_poll_updated(poll)
            {:ok, poll}

          error ->
            error
        end
    end
  end

  @doc """
  Lists all polls in a conversation with results computed.
  Returns polls ordered by most recent first.
  """
  def list_conversation_polls(conversation_id) do
    from(p in Poll,
      where: p.conversation_id == ^conversation_id,
      order_by: [desc: p.inserted_at],
      preload: [:creator, options: :votes]
    )
    |> Repo.all()
    |> Enum.map(&compute_poll_results/1)
  end

  @doc """
  Gets the IDs of options a user has voted for in a poll.
  Returns a MapSet of option IDs.
  """
  def get_user_poll_votes(poll_id, user_id) do
    from(v in PollVote,
      where: v.poll_id == ^poll_id and v.user_id == ^user_id,
      select: v.poll_option_id
    )
    |> Repo.all()
    |> MapSet.new()
  end

  @doc """
  Gets a map of poll_id => MapSet of voted option IDs for a user.
  Useful for bulk loading vote status for multiple polls.
  """
  def get_user_votes_for_polls(poll_ids, user_id) when is_list(poll_ids) do
    from(v in PollVote,
      where: v.poll_id in ^poll_ids and v.user_id == ^user_id,
      select: {v.poll_id, v.poll_option_id}
    )
    |> Repo.all()
    |> Enum.group_by(fn {poll_id, _} -> poll_id end, fn {_, option_id} -> option_id end)
    |> Enum.into(%{}, fn {poll_id, option_ids} -> {poll_id, MapSet.new(option_ids)} end)
  end

  def get_user_votes_for_polls(_, _), do: %{}

  defp broadcast_poll_created(conversation_id, poll) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{conversation_id}",
      {:poll_created, poll}
    )
  end

  defp broadcast_poll_updated(poll) do
    Phoenix.PubSub.broadcast(
      Elixirchat.PubSub,
      "conversation:#{poll.conversation_id}",
      {:poll_updated, poll}
    )
  end
end
