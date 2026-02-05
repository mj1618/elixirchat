defmodule Elixirchat.Chat do
  @moduledoc """
  The Chat context for managing conversations and messages.
  """

  import Ecto.Query, warn: false

  alias Elixirchat.Repo
  alias Elixirchat.Chat.{Conversation, ConversationMember, Message, Reaction, ReadReceipt}
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
  """
  def get_or_create_direct_conversation(user1_id, user2_id) do
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
  """
  def list_user_conversations(user_id) do
    query =
      from c in Conversation,
        join: m in ConversationMember, on: m.conversation_id == c.id,
        where: m.user_id == ^user_id,
        preload: [members: :user],
        order_by: [desc: c.updated_at]

    conversations = Repo.all(query)

    # Fetch last message for each conversation
    Enum.map(conversations, fn conv ->
      last_message = get_last_message(conv.id)
      unread_count = get_unread_count(conv.id, user_id)
      Map.merge(conv, %{last_message: last_message, unread_count: unread_count})
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
  Lists messages in a conversation with reactions and reply_to loaded.
  """
  def list_messages(conversation_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    before_id = Keyword.get(opts, :before_id)

    query =
      from m in Message,
        where: m.conversation_id == ^conversation_id,
        order_by: [asc: m.inserted_at],
        preload: [:sender, reply_to: :sender]

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
  Accepts optional opts with :reply_to_id for replying to a specific message.
  """
  def send_message(conversation_id, sender_id, content, opts \\ []) do
    reply_to_id = Keyword.get(opts, :reply_to_id)

    # Validate reply_to if provided
    if reply_to_id do
      reply_to = Repo.get(Message, reply_to_id)
      if is_nil(reply_to) or reply_to.conversation_id != conversation_id do
        {:error, :invalid_reply_to}
      else
        do_send_message(conversation_id, sender_id, content, reply_to_id)
      end
    else
      do_send_message(conversation_id, sender_id, content, nil)
    end
  end

  defp do_send_message(conversation_id, sender_id, content, reply_to_id) do
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
        # Update conversation's updated_at timestamp
        Repo.get!(Conversation, conversation_id)
        |> Ecto.Changeset.change(%{updated_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)})
        |> Repo.update()

        # Preload sender and reply_to for the response, add empty reactions
        message =
          message
          |> Repo.preload([:sender, reply_to: :sender])
          |> Map.put(:reactions_grouped, %{})

        # Broadcast the message
        broadcast_message(conversation_id, message)

        # Check for @agent mention and process asynchronously
        # Don't process agent messages to avoid infinite loops
        unless Agent.is_agent?(sender_id) do
          maybe_process_agent_mention(conversation_id, content)
        end

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
  """
  def search_users(query, current_user_id) when byte_size(query) > 0 do
    search_term = "%#{query}%"

    from(u in User,
      where: u.id != ^current_user_id,
      where: ilike(u.username, ^search_term),
      limit: 10,
      order_by: u.username
    )
    |> Repo.all()
  end

  def search_users(_, _), do: []

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
      %ConversationMember{}
      |> ConversationMember.changeset(%{conversation_id: conversation_id, user_id: user_id})
      |> Repo.insert()
    else
      {:error, :not_a_group}
    end
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
end
